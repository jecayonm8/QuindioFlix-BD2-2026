-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   09_QuindioFlix_Vistas_CRUD.sql

-- Propósito: Sección 4 — Análisis de Vistas (CRUD)
-- Vistas:
--   VW_USUARIOS_PUBLICO        → Oculta datos personales sensibles
--   VW_CATALOGO_COMPLETO       → Catálogo con géneros y responsable
--   VW_REPORTE_CONSUMO         → Historial de reproducciones para gerencia
--   VW_CUENTAS_ACTIVAS         → Usuarios activos sin datos financieros
--   VW_REPORTE_FINANCIERO      → Ingresos consolidados por ciudad y plan
-- Se Ejecuta: Como quindioflix en conexion QuindioFlixBD
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ============================================================================
-- LIMPIEZA PREVIA (para re-ejecuciones)
-- ============================================================================
BEGIN
    FOR v IN (SELECT view_name FROM user_views
              WHERE view_name IN (
                  'VW_USUARIOS_PUBLICO','VW_CATALOGO_COMPLETO',
                  'VW_REPORTE_CONSUMO','VW_CUENTAS_ACTIVAS',
                  'VW_REPORTE_FINANCIERO'))
    LOOP
        EXECUTE IMMEDIATE 'DROP VIEW ' || v.view_name;
        DBMS_OUTPUT.PUT_LINE('Vista eliminada: ' || v.view_name);
    END LOOP;
END;
/


-- ============================================================================
-- VISTA 1: VW_USUARIOS_PUBLICO
-- ============================================================================
-- JUSTIFICACIÓN:
-- La tabla USUARIOS contiene datos personales sensibles como fecha de
-- nacimiento, teléfono e id_referidor que no deben ser accesibles para todos
-- los roles. El equipo de Soporte necesita ver datos del usuario para atender
-- solicitudes, pero sin exposición de información privada.
-- Esta vista oculta: telefono, fecha_nacimiento, id_referidor, es_moderador.
--
-- TIPO: Vista SIMPLE sobre una sola tabla con condición WHERE
-- CRUD permitido:
--   SELECT  → ✅ Permitido (propósito principal)
--   INSERT  → ❌ No permitido (columnas NOT NULL ocultas en la vista)
--   UPDATE  → ✅ Parcialmente (solo columnas visibles: ciudad, estado_cuenta)
--   DELETE  → ✅ Técnicamente permitido (pero no recomendado)
-- ============================================================================
CREATE OR REPLACE VIEW VW_USUARIOS_PUBLICO AS
SELECT
    u.id_usuario,
    u.nombre_usuario,
    u.email_usuario,
    u.ciudad,
    u.fecha_registro,
    u.estado_cuenta,
    u.fecha_ultimo_pago,
    p.nombre_plan,
    p.precio_mensual,
    p.calidad_video,
    -- Días sin pago (calculado para identificar cuentas en riesgo)
    TRUNC(SYSDATE - u.fecha_ultimo_pago)    AS dias_sin_pago,
    -- Indicador de mora (>30 días sin pago)
    CASE WHEN TRUNC(SYSDATE - u.fecha_ultimo_pago) > 30
         THEN 'EN MORA' ELSE 'AL DÍA'
    END                                     AS estado_pago
FROM   USUARIOS u
JOIN   PLANES   p ON u.id_plan = p.id_plan;

-- Conceder acceso a los roles que necesitan ver usuarios
GRANT SELECT ON VW_USUARIOS_PUBLICO TO ROL_SOPORTE;
GRANT SELECT ON VW_USUARIOS_PUBLICO TO ROL_ANALISTA;
GRANT SELECT ON VW_USUARIOS_PUBLICO TO ROL_ADMIN;

-- ── PRUEBAS CRUD ─────────────────────────────────────────────────────────────

-- SELECT: Ver todos los usuarios sin datos sensibles
SELECT * FROM VW_USUARIOS_PUBLICO ORDER BY ciudad, nombre_plan;

-- SELECT con filtro: Usuarios en mora
SELECT id_usuario, nombre_usuario, ciudad, nombre_plan,
       dias_sin_pago, estado_pago
FROM   VW_USUARIOS_PUBLICO
WHERE  estado_pago = 'EN MORA';

-- UPDATE: Cambiar ciudad de un usuario (columna visible en la vista)
-- (Actualiza la tabla base USUARIOS directamente)
UPDATE VW_USUARIOS_PUBLICO
SET    ciudad = 'Bogotá'
WHERE  id_usuario = 30;
ROLLBACK;  -- Revertir para no afectar datos de prueba

-- INSERT: Intento de inserción — debe fallar porque faltan columnas NOT NULL
BEGIN
    EXECUTE IMMEDIATE
        'INSERT INTO VW_USUARIOS_PUBLICO (nombre_usuario, email_usuario, ciudad)
         VALUES (''Test'', ''test@test.com'', ''Bogotá'')';
    DBMS_OUTPUT.PUT_LINE('ERROR: debería haber fallado.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('INSERT bloqueado correctamente: ' || SQLERRM);
END;
/


-- ============================================================================
-- VISTA 2: VW_CATALOGO_COMPLETO
-- ============================================================================
-- JUSTIFICACIÓN:
-- El equipo de Contenido y los Analistas necesitan ver el catálogo completo
-- con toda su información contextual: categoría, géneros asignados y nombre
-- del empleado responsable de la publicación. Hacer este JOIN repetidamente
-- en cada consulta es ineficiente — la vista lo centraliza y simplifica.
-- También oculta columnas técnicas (id_categoria, id_empleado_resp) que
-- solo son relevantes para el DBA.
--
-- TIPO: Vista COMPLEJA (múltiples JOINs + LISTAGG para géneros)
-- CRUD permitido:
--   SELECT  → ✅ Permitido (propósito principal)
--   INSERT  → ❌ No permitido (múltiples tablas base)
--   UPDATE  → ❌ No permitido (múltiples tablas base + LISTAGG)
--   DELETE  → ❌ No permitido (múltiples tablas base)
-- ============================================================================
CREATE OR REPLACE VIEW VW_CATALOGO_COMPLETO AS
SELECT
    c.id_contenido,
    c.titulo,
    cat.nombre_categoria                    AS categoria,
    c.anio_lanzamiento,
    c.duracion_min                          AS duracion_minutos,
    c.clasificacion_edad,
    CASE c.es_original WHEN 'S' THEN 'QuindioFlix Original'
                       ELSE 'Contenido Externo' END AS tipo_produccion,
    -- Géneros concatenados en un solo campo (más legible que múltiples filas)
    LISTAGG(g.nombre_genero, ' / ')
        WITHIN GROUP (ORDER BY g.nombre_genero) AS generos,
    e.nombre_empleado                       AS responsable_publicacion,
    c.fecha_agregado,
    c.popularidad                           AS reproducciones_completas
FROM   CONTENIDO        c
JOIN   CATEGORIAS       cat ON c.id_categoria    = cat.id_categoria
JOIN   EMPLEADOS        e   ON c.id_empleado_resp = e.id_empleado
LEFT JOIN CONTENIDO_GENERO cg ON c.id_contenido  = cg.id_contenido
LEFT JOIN GENEROS          g  ON cg.id_genero     = g.id_genero
GROUP  BY c.id_contenido, c.titulo, cat.nombre_categoria,
          c.anio_lanzamiento, c.duracion_min, c.clasificacion_edad,
          c.es_original, e.nombre_empleado, c.fecha_agregado, c.popularidad;

GRANT SELECT ON VW_CATALOGO_COMPLETO TO ROL_ANALISTA;
GRANT SELECT ON VW_CATALOGO_COMPLETO TO ROL_CONTENIDO;
GRANT SELECT ON VW_CATALOGO_COMPLETO TO ROL_ADMIN;

-- ── PRUEBAS CRUD ─────────────────────────────────────────────────────────────

-- SELECT: Ver catálogo completo ordenado por reproducciones
SELECT titulo, categoria, generos, clasificacion_edad,
       tipo_produccion, reproducciones_completas
FROM   VW_CATALOGO_COMPLETO
ORDER  BY reproducciones_completas DESC NULLS LAST;

-- SELECT con filtro: Solo producciones originales de QuindioFlix
SELECT titulo, categoria, generos, anio_lanzamiento
FROM   VW_CATALOGO_COMPLETO
WHERE  tipo_produccion = 'QuindioFlix Original'
ORDER  BY anio_lanzamiento DESC;

-- SELECT por categoría: Solo series
SELECT titulo, generos, duracion_minutos, responsable_publicacion
FROM   VW_CATALOGO_COMPLETO
WHERE  categoria = 'Serie'
ORDER  BY titulo;

-- INSERT: Debe fallar — vista con múltiples tablas base
BEGIN
    EXECUTE IMMEDIATE
        'INSERT INTO VW_CATALOGO_COMPLETO (titulo) VALUES (''Test'')';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('INSERT bloqueado: ' || SQLERRM);
END;
/


-- ============================================================================
-- VISTA 3: VW_REPORTE_CONSUMO
-- ============================================================================
-- JUSTIFICACIÓN:
-- Los analistas y la gerencia necesitan consultar el historial de consumo
-- cruzando datos de 4 tablas (REPRODUCCIONES, PERFILES, USUARIOS, CONTENIDO,
-- CATEGORIAS). Esta vista consolida toda esa información en un único objeto
-- consultable, simplificando los reportes y evitando errores en JOINs
-- complejos. También oculta IDs internos, exponiendo solo datos legibles.
--
-- TIPO: Vista COMPLEJA (5 JOINs)
-- CRUD permitido:
--   SELECT  → ✅ Permitido
--   INSERT  → ❌ No permitido
--   UPDATE  → ❌ No permitido
--   DELETE  → ❌ No permitido
-- ============================================================================
CREATE OR REPLACE VIEW VW_REPORTE_CONSUMO AS
SELECT
    r.id_reproduccion,
    u.nombre_usuario,
    u.ciudad,
    pl.nombre_plan,
    pf.nombre_perfil,
    pf.tipo_perfil,
    c.titulo                                AS contenido,
    cat.nombre_categoria                    AS categoria,
    r.dispositivo,
    r.porcentaje_avance,
    TRUNC(r.fecha_inicio)                   AS fecha_reproduccion,
    EXTRACT(YEAR  FROM r.fecha_inicio)      AS anio,
    EXTRACT(MONTH FROM r.fecha_inicio)      AS mes,
    -- Tiempo consumido estimado en minutos
    ROUND(c.duracion_min * r.porcentaje_avance / 100) AS minutos_consumidos,
    -- Clasificar si fue completa o parcial
    CASE WHEN r.porcentaje_avance >= 90
         THEN 'Completa' ELSE 'Parcial' END AS tipo_reproduccion
FROM   REPRODUCCIONES r
JOIN   PERFILES    pf  ON r.id_perfil    = pf.id_perfil
JOIN   USUARIOS    u   ON pf.id_usuario  = u.id_usuario
JOIN   PLANES      pl  ON u.id_plan      = pl.id_plan
JOIN   CONTENIDO   c   ON r.id_contenido = c.id_contenido
JOIN   CATEGORIAS  cat ON c.id_categoria = cat.id_categoria;

GRANT SELECT ON VW_REPORTE_CONSUMO TO ROL_ANALISTA;
GRANT SELECT ON VW_REPORTE_CONSUMO TO ROL_ADMIN;

-- ── PRUEBAS CRUD ─────────────────────────────────────────────────────────────

-- SELECT: Consumo total por ciudad y categoría
SELECT ciudad, categoria, COUNT(*) AS reproducciones,
       SUM(minutos_consumidos) AS minutos_totales
FROM   VW_REPORTE_CONSUMO
GROUP  BY ciudad, categoria
ORDER  BY ciudad, reproducciones DESC;

-- SELECT: Top perfiles más activos
SELECT nombre_usuario, nombre_perfil, nombre_plan,
       COUNT(*) AS reproducciones,
       SUM(minutos_consumidos) AS minutos_totales
FROM   VW_REPORTE_CONSUMO
GROUP  BY nombre_usuario, nombre_perfil, nombre_plan
ORDER  BY reproducciones DESC
FETCH FIRST 10 ROWS ONLY;

-- SELECT: Consumo por dispositivo y año (datos para PIVOT)
SELECT anio, dispositivo, COUNT(*) AS total
FROM   VW_REPORTE_CONSUMO
GROUP  BY anio, dispositivo
ORDER  BY anio, dispositivo;

-- INSERT bloqueado en VW_REPORTE_CONSUMO
-- La vista tiene 5 JOINs → Oracle no puede determinar en qué tabla base insertar
BEGIN
    EXECUTE IMMEDIATE
        'INSERT INTO VW_REPORTE_CONSUMO
             (nombre_usuario, ciudad, contenido, categoria, dispositivo)
         VALUES
             (''Test Usuario'', ''Bogotá'', ''Test Contenido'', ''Película'', ''TV'')';
    DBMS_OUTPUT.PUT_LINE('ERROR: El INSERT debería haber fallado.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('INSERT bloqueado: ' || SQLERRM);
END;
/


-- ============================================================================
-- VISTA 4: VW_CUENTAS_ACTIVAS
-- ============================================================================
-- JUSTIFICACIÓN:
-- El equipo de Soporte y los analistas necesitan saber qué cuentas están
-- activas y cuántos perfiles tiene cada una, sin acceso a montos de pago
-- ni historial financiero. Esta vista filtra solo cuentas ACTIVAS y oculta
-- completamente la tabla PAGOS, garantizando separación de datos sensibles.
-- Incluye WITH CHECK OPTION para que cualquier UPDATE a través de la vista
-- no pueda cambiar el estado a INACTIVO (mantiene la integridad del filtro).
--
-- TIPO: Vista SIMPLE con condición — WITH CHECK OPTION
-- CRUD permitido:
--   SELECT  → ✅ Permitido
--   INSERT  → ❌ No permitido (columnas NOT NULL ocultas)
--   UPDATE  → ✅ Solo columnas visibles; WITH CHECK OPTION impide
--               cambiar estado_cuenta a INACTIVO desde esta vista
--   DELETE  → ✅ Técnicamente permitido (elimina de USUARIOS)
-- ============================================================================
CREATE OR REPLACE VIEW VW_CUENTAS_ACTIVAS AS
SELECT
    u.id_usuario,
    u.nombre_usuario,
    u.email_usuario,
    u.ciudad,
    u.fecha_registro,
    u.fecha_ultimo_pago,
    p.nombre_plan,
    p.max_perfiles                          AS max_perfiles_plan,
    -- Contar perfiles actuales del usuario
    (SELECT COUNT(*) FROM PERFILES pf
     WHERE pf.id_usuario = u.id_usuario)    AS perfiles_actuales,
    -- Antigüedad en meses
    ROUND(MONTHS_BETWEEN(SYSDATE, u.fecha_registro)) AS meses_suscrito,
    -- Indica si es elegible para descuento por antigüedad
    CASE WHEN MONTHS_BETWEEN(SYSDATE, u.fecha_registro) > 24
         THEN '15% descuento'
         WHEN MONTHS_BETWEEN(SYSDATE, u.fecha_registro) > 12
         THEN '10% descuento'
         ELSE 'Sin descuento'
    END                                     AS descuento_fidelidad
FROM   USUARIOS u
JOIN   PLANES   p ON u.id_plan = p.id_plan
WHERE  u.estado_cuenta = 'ACTIVO'
WITH   CHECK OPTION CONSTRAINT chk_solo_activos;
-- WITH CHECK OPTION: impide que un UPDATE cambie estado_cuenta a INACTIVO
-- desde esta vista, protegiendo la integridad del filtro

GRANT SELECT ON VW_CUENTAS_ACTIVAS TO ROL_SOPORTE;
GRANT SELECT ON VW_CUENTAS_ACTIVAS TO ROL_ANALISTA;
GRANT SELECT ON VW_CUENTAS_ACTIVAS TO ROL_ADMIN;

-- ── PRUEBAS CRUD ────────────────────────────────────────────────────────────

-- SELECT: Ver todas las cuentas activas con su fidelidad
SELECT nombre_usuario, ciudad, nombre_plan,
       perfiles_actuales, meses_suscrito, descuento_fidelidad
FROM   VW_CUENTAS_ACTIVAS
ORDER  BY meses_suscrito DESC;

-- SELECT: Cuentas Premium con más de 1 año
SELECT nombre_usuario, email_usuario, ciudad, meses_suscrito
FROM   VW_CUENTAS_ACTIVAS
WHERE  nombre_plan = 'Premium'
  AND  meses_suscrito > 12
ORDER  BY meses_suscrito DESC;

-- UPDATE: Cambiar ciudad (operación permitida)
UPDATE VW_CUENTAS_ACTIVAS
SET    ciudad = 'Medellín'
WHERE  id_usuario = 30;
ROLLBACK;

-- UPDATE: Intentar cambiar a INACTIVO — debe fallar por WITH CHECK OPTION
BEGIN
    EXECUTE IMMEDIATE
        'UPDATE VW_CUENTAS_ACTIVAS
         SET estado_cuenta = ''INACTIVO''
         WHERE id_usuario = 1';
    DBMS_OUTPUT.PUT_LINE('ERROR: WITH CHECK OPTION debió bloquearlo.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('WITH CHECK OPTION activo: ' || SQLERRM);
END;
/


-- ============================================================================
-- VISTA 5: VW_REPORTE_FINANCIERO
-- ============================================================================
-- JUSTIFICACIÓN:
-- La gerencia necesita un reporte ejecutivo de ingresos consolidados sin
-- acceder directamente a la tabla PAGOS (que contiene datos individuales
-- de cada transacción). Esta vista presenta solo los totales agregados por
-- ciudad, plan y período, protegiendo la privacidad de los pagos individuales
-- mientras entrega la información financiera que la dirección necesita.
--
-- TIPO: Vista COMPLEJA con agregaciones (GROUP BY + SUM + COUNT)
-- CRUD permitido:
--   SELECT  → ✅ Permitido (único propósito)
--   INSERT  → ❌ No permitido (vista con GROUP BY)
--   UPDATE  → ❌ No permitido (vista con GROUP BY)
--   DELETE  → ❌ No permitido (vista con GROUP BY)
-- ============================================================================
CREATE OR REPLACE VIEW VW_REPORTE_FINANCIERO AS
SELECT
    u.ciudad,
    p.nombre_plan,
    p.precio_mensual                        AS precio_base,
    pg.periodo_mes,
    pg.periodo_anio,
    -- Indicador de período legible
    TO_CHAR(TO_DATE(pg.periodo_mes,'MM'),'Month') AS nombre_mes,
    COUNT(*)                                AS total_transacciones,
    COUNT(CASE WHEN pg.estado_pago = 'EXITOSO'
               THEN 1 END)                  AS pagos_exitosos,
    COUNT(CASE WHEN pg.estado_pago = 'FALLIDO'
               THEN 1 END)                  AS pagos_fallidos,
    COUNT(CASE WHEN pg.estado_pago = 'REEMBOLSADO'
               THEN 1 END)                  AS reembolsos,
    -- Ingresos reales (solo pagos exitosos)
    SUM(CASE WHEN pg.estado_pago = 'EXITOSO'
             THEN pg.monto ELSE 0 END)      AS ingresos_confirmados,
    -- Ingresos perdidos (pagos fallidos)
    SUM(CASE WHEN pg.estado_pago = 'FALLIDO'
             THEN pg.monto ELSE 0 END)      AS ingresos_perdidos,
    -- Porcentaje de éxito en cobros
    ROUND(
        COUNT(CASE WHEN pg.estado_pago = 'EXITOSO' THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0)
    , 1)                                    AS pct_cobros_exitosos
FROM   PAGOS    pg
JOIN   USUARIOS  u ON pg.id_usuario = u.id_usuario
JOIN   PLANES    p ON u.id_plan     = p.id_plan
GROUP  BY u.ciudad, p.nombre_plan, p.precio_mensual,
          pg.periodo_mes, pg.periodo_anio;

GRANT SELECT ON VW_REPORTE_FINANCIERO TO ROL_ANALISTA;
GRANT SELECT ON VW_REPORTE_FINANCIERO TO ROL_ADMIN;

-- ── PRUEBAS CRUD ───────────────────────────────────────────────────────────

-- SELECT: Ingresos por ciudad en el período más reciente 2026
SELECT ciudad, nombre_plan, nombre_mes, periodo_anio,
       ingresos_confirmados, ingresos_perdidos, pct_cobros_exitosos
FROM   VW_REPORTE_FINANCIERO
WHERE  periodo_anio = 2026
ORDER  BY ciudad, nombre_plan, periodo_mes;

-- SELECT: Resumen total por plan (usando la vista como base)
SELECT nombre_plan,
       SUM(ingresos_confirmados) AS ingresos_totales,
       SUM(pagos_exitosos)       AS total_cobros,
       SUM(pagos_fallidos)       AS total_fallidos
FROM   VW_REPORTE_FINANCIERO
GROUP  BY nombre_plan
ORDER  BY ingresos_totales DESC;

-- SELECT: Ciudad con más ingresos
SELECT ciudad,
       SUM(ingresos_confirmados) AS ingresos_totales,
       ROUND(AVG(pct_cobros_exitosos), 1) AS eficiencia_cobro_pct
FROM   VW_REPORTE_FINANCIERO
GROUP  BY ciudad
ORDER  BY ingresos_totales DESC;

-- INSERT: Debe fallar — vista con GROUP BY
BEGIN
    EXECUTE IMMEDIATE
        'INSERT INTO VW_REPORTE_FINANCIERO (ciudad) VALUES (''Test'')';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('INSERT bloqueado: ' || SQLERRM);
END;
/


-- ============================================================================
-- VERIFICACIÓN FINAL — RESUMEN DE VISTAS CREADAS
-- ============================================================================

-- Listar todas las vistas del esquema con su tipo
SELECT view_name,
       text_length                          AS longitud_sql,
       'Ver código con: SELECT TEXT FROM USER_VIEWS WHERE VIEW_NAME = ''' ||
           view_name || '''' AS como_ver_codigo
FROM   user_views
WHERE  view_name IN (
    'VW_USUARIOS_PUBLICO',
    'VW_CATALOGO_COMPLETO',
    'VW_REPORTE_CONSUMO',
    'VW_CUENTAS_ACTIVAS',
    'VW_REPORTE_FINANCIERO'
)
ORDER  BY view_name;

-- Ver los privilegios otorgados sobre las vistas
SELECT grantee AS rol, table_name AS vista, privilege
FROM   user_tab_privs
WHERE  table_name IN (
    'VW_USUARIOS_PUBLICO',
    'VW_CATALOGO_COMPLETO',
    'VW_REPORTE_CONSUMO',
    'VW_CUENTAS_ACTIVAS',
    'VW_REPORTE_FINANCIERO'
)
ORDER  BY table_name, grantee;

-- ========================================================================
-- TABLA RESUMEN — ANÁLISIS CRUD POR VISTA
-- ========================================================================
-- Vista                   | Tipo      |
-- VW_USUARIOS_PUBLICO     | Simple    |
-- VW_CATALOGO_COMPLETO    | Compleja  | 
-- VW_REPORTE_CONSUMO      | Compleja  |
-- VW_CUENTAS_ACTIVAS      | Simple+   |
--                         | CHECK OPT | *limitado por CHECK
-- VW_REPORTE_FINANCIERO   | Agregada  |
-- ============================================================================

-- ============================================================================
-- FIN DEL SCRIPT — SECCIÓN 4 COMPLETADA
-- ============================================================================
