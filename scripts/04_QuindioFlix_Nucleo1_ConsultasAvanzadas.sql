-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   04_QuindioFlix_Nucleo1_ConsultasAvanzadas.sql
-- Propósito: Núcleo Temático 1 — Consultas Avanzadas y Almacenamiento
-- Secciones:
--   3.1.1 Consultas parametrizadas      (mínimo 3)
--   3.1.2 PIVOT y UNPIVOT               (mínimo 2 de cada una)
--   3.1.3 GROUP BY avanzado             (ROLLUP, CUBE, GROUPING, GROUPING SETS)
--   3.1.4 Vistas materializadas         (mínimo 2)
--   3.1.5 Fragmentación (ya implementada en script 02)
-- Ejecutar: Como quindioflix en conexión QuindioFlixBD
-- Nota:     Ejecutar sección por sección con F9, no el script completo con F5
--           (las consultas parametrizadas piden entrada del usuario)
-- ============================================================================


-- ============================================================================
-- SECCIÓN 3.1.1 — CONSULTAS PARAMETRIZADAS (3 consultas)
-- ============================================================================
-- Las variables de sustitución funcionan con & en SQL Developer (F9 por consulta)
-- o con DEFINE para establecer el valor fijo antes de ejecutar.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CONSULTA PARAMETRIZADA 1
-- Top 10 de contenido más reproducido en una ciudad específica
-- Uso: ejecutar con F9, ingresar ciudad cuando SQL Developer la solicite
-- Ejemplo de valor válido: Bogotá | Medellín | Cali | Armenia
-- ----------------------------------------------------------------------------
SELECT *
FROM (
    SELECT
        c.titulo                            AS contenido,
        cat.nombre_categoria                AS categoria,
        COUNT(r.id_reproduccion)            AS total_reproducciones,
        ROUND(AVG(r.porcentaje_avance), 1)  AS avance_promedio_pct,
        COUNT(DISTINCT r.id_perfil)         AS perfiles_distintos
    FROM REPRODUCCIONES r
    JOIN PERFILES     pf  ON r.id_perfil     = pf.id_perfil
    JOIN USUARIOS     u   ON pf.id_usuario   = u.id_usuario
    JOIN CONTENIDO    c   ON r.id_contenido  = c.id_contenido
    JOIN CATEGORIAS   cat ON c.id_categoria  = cat.id_categoria
    WHERE u.ciudad = '&ciudad'
    GROUP BY c.titulo, cat.nombre_categoria
    ORDER BY total_reproducciones DESC
)
WHERE ROWNUM <= 10;


-- ----------------------------------------------------------------------------
-- CONSULTA PARAMETRIZADA 2
-- Ingresos por plan de suscripción en un mes y año específicos
-- Ejemplo de valores válidos: mes=3, anio=2026
-- ----------------------------------------------------------------------------
SELECT
    p.nombre_plan                           AS plan_suscripcion,
    p.precio_mensual                        AS precio_base,
    COUNT(*)                                AS total_pagos,
    COUNT(CASE WHEN pg.estado_pago = 'EXITOSO'    THEN 1 END) AS pagos_exitosos,
    COUNT(CASE WHEN pg.estado_pago = 'FALLIDO'    THEN 1 END) AS pagos_fallidos,
    COUNT(CASE WHEN pg.estado_pago = 'REEMBOLSADO' THEN 1 END) AS reembolsos,
    SUM(CASE WHEN pg.estado_pago = 'EXITOSO'
             THEN pg.monto ELSE 0 END)      AS ingresos_confirmados,
    ROUND(
        SUM(CASE WHEN pg.estado_pago = 'EXITOSO' THEN pg.monto ELSE 0 END)
        / NULLIF(COUNT(CASE WHEN pg.estado_pago = 'EXITOSO' THEN 1 END), 0)
    , 2)                                    AS monto_promedio
FROM PAGOS    pg
JOIN USUARIOS  u  ON pg.id_usuario = u.id_usuario
JOIN PLANES    p  ON u.id_plan     = p.id_plan
WHERE pg.periodo_mes  = &mes
  AND pg.periodo_anio = &anio
GROUP BY p.nombre_plan, p.precio_mensual
ORDER BY ingresos_confirmados DESC;


-- ----------------------------------------------------------------------------
-- CONSULTA PARAMETRIZADA 3
-- Calificación promedio por categoría para un género específico
-- Ejemplo de valores válidos: Drama | Acción | Suspenso | Romance | Terror
-- ----------------------------------------------------------------------------
SELECT
    cat.nombre_categoria                    AS categoria,
    g.nombre_genero                         AS genero,
    COUNT(DISTINCT c.id_contenido)          AS titulos_en_genero,
    COUNT(cal.id_calificacion)              AS total_calificaciones,
    ROUND(AVG(cal.estrellas), 2)            AS promedio_estrellas,
    MIN(cal.estrellas)                      AS minimo_estrellas,
    MAX(cal.estrellas)                      AS maximo_estrellas,
    COUNT(CASE WHEN cal.estrellas >= 4 THEN 1 END) AS calificaciones_altas
FROM CALIFICACIONES   cal
JOIN CONTENIDO        c   ON cal.id_contenido = c.id_contenido
JOIN CATEGORIAS       cat ON c.id_categoria   = cat.id_categoria
JOIN CONTENIDO_GENERO cg  ON c.id_contenido   = cg.id_contenido
JOIN GENEROS          g   ON cg.id_genero     = g.id_genero
WHERE g.nombre_genero = '&genero'
GROUP BY cat.nombre_categoria, g.nombre_genero
ORDER BY promedio_estrellas DESC;


-- ============================================================================
-- SECCIÓN 3.1.2 — TABLAS DE REFERENCIAS CRUZADAS: PIVOT y UNPIVOT
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PIVOT 1
-- Usuarios ACTIVOS por ciudad (filas) y plan de suscripción (columnas)
-- Evidencia la distribución asimétrica de suscriptores
-- ----------------------------------------------------------------------------
SELECT ciudad,
       BASICO      AS "Plan Básico",
       ESTANDAR    AS "Plan Estándar",
       PREMIUM     AS "Plan Premium",
       NVL(BASICO,0) + NVL(ESTANDAR,0) + NVL(PREMIUM,0) AS total_ciudad
FROM (
    SELECT u.ciudad, p.nombre_plan, u.id_usuario
    FROM USUARIOS u
    JOIN PLANES p ON u.id_plan = p.id_plan
    WHERE u.estado_cuenta = 'ACTIVO'
)
PIVOT (
    COUNT(id_usuario)
    FOR nombre_plan IN (
        'Básico'   AS BASICO,
        'Estándar' AS ESTANDAR,
        'Premium'  AS PREMIUM
    )
)
ORDER BY ciudad;


-- ----------------------------------------------------------------------------
-- PIVOT 2
-- Total de reproducciones por categoría (filas) y dispositivo (columnas)
-- Muestra desde qué dispositivo se consume cada tipo de contenido
-- ----------------------------------------------------------------------------
SELECT nombre_categoria                    AS categoria,
       NVL(CELULAR, 0)                     AS celular,
       NVL(TABLET, 0)                      AS tablet,
       NVL(TV, 0)                          AS television,
       NVL(COMPUTADOR, 0)                  AS computador,
       NVL(CELULAR,0) + NVL(TABLET,0)
           + NVL(TV,0) + NVL(COMPUTADOR,0) AS total_categoria
FROM (
    SELECT cat.nombre_categoria, r.dispositivo, r.id_reproduccion
    FROM REPRODUCCIONES r
    JOIN CONTENIDO  c   ON r.id_contenido  = c.id_contenido
    JOIN CATEGORIAS cat ON c.id_categoria  = cat.id_categoria
)
PIVOT (
    COUNT(id_reproduccion)
    FOR dispositivo IN (
        'celular'    AS CELULAR,
        'tablet'     AS TABLET,
        'TV'         AS TV,
        'computador' AS COMPUTADOR
    )
)
ORDER BY nombre_categoria;


-- ----------------------------------------------------------------------------
-- UNPIVOT 1
-- Convierte el PIVOT de usuarios por ciudad/plan de vuelta a formato de filas
-- Útil para análisis detallado por combinación ciudad-plan
-- ----------------------------------------------------------------------------
SELECT ciudad,
       plan_suscripcion,
       usuarios_activos
FROM (
    -- Subconsulta con el PIVOT
    SELECT ciudad, BASICO, ESTANDAR, PREMIUM
    FROM (
        SELECT u.ciudad, p.nombre_plan, u.id_usuario
        FROM USUARIOS u
        JOIN PLANES p ON u.id_plan = p.id_plan
        WHERE u.estado_cuenta = 'ACTIVO'
    )
    PIVOT (
        COUNT(id_usuario)
        FOR nombre_plan IN (
            'Básico'   AS BASICO,
            'Estándar' AS ESTANDAR,
            'Premium'  AS PREMIUM
        )
    )
)
UNPIVOT (
    usuarios_activos
    FOR plan_suscripcion IN (BASICO, ESTANDAR, PREMIUM)
)
WHERE usuarios_activos > 0
ORDER BY ciudad, plan_suscripcion;


-- ----------------------------------------------------------------------------
-- UNPIVOT 2
-- Convierte tabla de resumen mensual de ingresos (columnas = meses)
-- a formato de filas individuales para análisis detallado por mes
-- ----------------------------------------------------------------------------
WITH resumen_pivot AS (
    -- Paso 1: Crear tabla con un mes por columna (usando PIVOT)
    SELECT *
    FROM (
        SELECT p.nombre_plan, pg.periodo_mes, pg.monto
        FROM PAGOS pg
        JOIN USUARIOS u ON pg.id_usuario = u.id_usuario
        JOIN PLANES   p ON u.id_plan     = p.id_plan
        WHERE pg.estado_pago = 'EXITOSO'
          AND pg.periodo_anio = 2026
    )
    PIVOT (
        SUM(monto)
        FOR periodo_mes IN (
            1 AS MES_ENE,
            2 AS MES_FEB,
            3 AS MES_MAR
        )
    )
)
-- Paso 2: UNPIVOT para convertir columnas de meses en filas
SELECT
    nombre_plan                             AS plan,
    CASE mes_col
        WHEN 'MES_ENE' THEN 'Enero 2026'
        WHEN 'MES_FEB' THEN 'Febrero 2026'
        WHEN 'MES_MAR' THEN 'Marzo 2026'
    END                                     AS periodo,
    NVL(ingresos_mes, 0)                    AS ingresos
FROM resumen_pivot
UNPIVOT INCLUDE NULLS (
    ingresos_mes
    FOR mes_col IN (MES_ENE, MES_FEB, MES_MAR)
)
ORDER BY nombre_plan, mes_col;


-- ============================================================================
-- SECCIÓN 3.1.3 — FUNCIONES AVANZADAS DEL GROUP BY
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ROLLUP
-- Ingresos por ciudad y plan de suscripción con subtotales por ciudad
-- y gran total general — ideal para reporte financiero de la gerencia
-- GROUPING() reemplaza los NULLs por etiquetas legibles
-- ----------------------------------------------------------------------------
SELECT
    CASE GROUPING(u.ciudad)
        WHEN 1 THEN '=== GRAN TOTAL ==='
        ELSE u.ciudad
    END                                     AS ciudad,
    CASE GROUPING(p.nombre_plan)
        WHEN 1 THEN '-- Subtotal ciudad --'
        ELSE p.nombre_plan
    END                                     AS plan,
    COUNT(*)                                AS total_pagos,
    COUNT(CASE WHEN pg.estado_pago = 'EXITOSO'
               THEN 1 END)                  AS pagos_exitosos,
    SUM(CASE WHEN pg.estado_pago = 'EXITOSO'
             THEN pg.monto ELSE 0 END)      AS ingresos_totales,
    GROUPING(u.ciudad)                      AS nivel_ciudad,
    GROUPING(p.nombre_plan)                 AS nivel_plan
FROM PAGOS    pg
JOIN USUARIOS  u ON pg.id_usuario = u.id_usuario
JOIN PLANES    p ON u.id_plan     = p.id_plan
GROUP BY ROLLUP(u.ciudad, p.nombre_plan)
ORDER BY
    GROUPING(u.ciudad),
    u.ciudad NULLS LAST,
    GROUPING(p.nombre_plan),
    p.nombre_plan NULLS LAST;


-- ----------------------------------------------------------------------------
-- CUBE
-- Reproducciones por categoría de contenido y dispositivo
-- con TODAS las combinaciones posibles de subtotales:
-- (categoría, dispositivo), (categoría, todos), (todos, dispositivo), (total)
-- ----------------------------------------------------------------------------
SELECT
    CASE GROUPING(cat.nombre_categoria)
        WHEN 1 THEN 'TODAS LAS CATEGORÍAS'
        ELSE cat.nombre_categoria
    END                                     AS categoria,
    CASE GROUPING(r.dispositivo)
        WHEN 1 THEN 'TODOS LOS DISPOSITIVOS'
        ELSE r.dispositivo
    END                                     AS dispositivo,
    COUNT(*)                                AS total_reproducciones,
    ROUND(AVG(r.porcentaje_avance), 1)      AS avance_promedio,
    COUNT(CASE WHEN r.porcentaje_avance = 100
               THEN 1 END)                  AS reproducciones_completas,
    GROUPING(cat.nombre_categoria)          AS grp_cat,
    GROUPING(r.dispositivo)                 AS grp_disp
FROM REPRODUCCIONES r
JOIN CONTENIDO  c   ON r.id_contenido = c.id_contenido
JOIN CATEGORIAS cat ON c.id_categoria = cat.id_categoria
GROUP BY CUBE(cat.nombre_categoria, r.dispositivo)
ORDER BY
    GROUPING(cat.nombre_categoria),
    cat.nombre_categoria NULLS LAST,
    GROUPING(r.dispositivo),
    r.dispositivo NULLS LAST;


-- ----------------------------------------------------------------------------
-- GROUPING() con ROLLUP — etiquetas legibles para NULLs
-- Reporte de contenido más popular con subtotales por categoría
-- Demuestra el uso de GROUPING() para distinguir NULL real vs NULL de rollup
-- ----------------------------------------------------------------------------
SELECT
    CASE GROUPING(cat.nombre_categoria)
        WHEN 1 THEN '>> TOTAL GENERAL'
        ELSE cat.nombre_categoria
    END                                     AS categoria,
    CASE GROUPING(c.titulo)
        WHEN 1 THEN '  > Subtotal categoría'
        ELSE c.titulo
    END                                     AS titulo,
    COUNT(r.id_reproduccion)                AS reproducciones,
    ROUND(AVG(cal.estrellas), 2)            AS promedio_estrellas,
    GROUPING_ID(cat.nombre_categoria,
                c.titulo)                   AS nivel_agrupacion
    -- 0 = detalle | 1 = subtotal categoría | 3 = gran total
FROM CONTENIDO      c
JOIN CATEGORIAS     cat ON c.id_categoria  = cat.id_categoria
LEFT JOIN REPRODUCCIONES r   ON c.id_contenido = r.id_contenido
LEFT JOIN CALIFICACIONES cal ON c.id_contenido = cal.id_contenido
GROUP BY ROLLUP(cat.nombre_categoria, c.titulo)
HAVING COUNT(r.id_reproduccion) > 0
    OR GROUPING(c.titulo) = 1
ORDER BY
    GROUPING(cat.nombre_categoria),
    cat.nombre_categoria NULLS LAST,
    GROUPING(c.titulo),
    COUNT(r.id_reproduccion) DESC NULLS LAST;


-- ----------------------------------------------------------------------------
-- GROUPING SETS
-- Muestra SOLO los totales por categoría y por ciudad
-- SIN el detalle cruzado entre ambos — más eficiente que CUBE
-- Útil cuando se necesitan exactamente ciertos niveles de agregación
-- ----------------------------------------------------------------------------
SELECT
    cat.nombre_categoria                    AS categoria,
    u.ciudad                                AS ciudad,
    COUNT(r.id_reproduccion)                AS total_reproducciones,
    COUNT(DISTINCT r.id_perfil)             AS perfiles_activos,
    ROUND(AVG(r.porcentaje_avance), 1)      AS avance_promedio
FROM REPRODUCCIONES r
JOIN PERFILES   pf  ON r.id_perfil     = pf.id_perfil
JOIN USUARIOS   u   ON pf.id_usuario   = u.id_usuario
JOIN CONTENIDO  c   ON r.id_contenido  = c.id_contenido
JOIN CATEGORIAS cat ON c.id_categoria  = cat.id_categoria
GROUP BY GROUPING SETS (
    (cat.nombre_categoria),    -- total de reproducciones por categoría
    (u.ciudad)                 -- total de reproducciones por ciudad
)
ORDER BY
    CASE WHEN cat.nombre_categoria IS NOT NULL THEN 0 ELSE 1 END,
    cat.nombre_categoria,
    u.ciudad;


-- ============================================================================
-- SECCIÓN 3.1.4 — VISTAS MATERIALIZADAS
-- ============================================================================
-- Las vistas materializadas pre-calculan y almacenan resultados físicamente.
-- A diferencia de una vista normal (que recalcula cada vez que se consulta),
-- una vista materializada ya tiene los datos guardados → consultas más rápidas.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- VISTA MATERIALIZADA 1: MV_CONTENIDO_POPULAR
-- Pre-calcula total de reproducciones y calificación promedio por contenido
-- Base del reporte "Contenido Más Popular" de la gerencia
-- ----------------------------------------------------------------------------

-- Limpiar si ya existe
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_CONTENIDO_POPULAR';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE MATERIALIZED VIEW MV_CONTENIDO_POPULAR
    BUILD IMMEDIATE          -- Carga datos inmediatamente al crear
    REFRESH COMPLETE         -- Recalcula todo en cada refresh
    ON DEMAND                -- Se refresca manualmente, no automáticamente
COMMENT ON TABLE MV_CONTENIDO_POPULAR IS 'Vista materializada: popularidad del catálogo QuindioFlix'
AS
SELECT
    c.id_contenido,
    c.titulo,
    cat.nombre_categoria                            AS categoria,
    c.clasificacion_edad,
    c.es_original,
    COUNT(r.id_reproduccion)                        AS total_reproducciones,
    COUNT(DISTINCT r.id_perfil)                     AS perfiles_unicos,
    COUNT(CASE WHEN r.porcentaje_avance >= 90
               THEN 1 END)                          AS reproducciones_completas,
    ROUND(
        COUNT(CASE WHEN r.porcentaje_avance >= 90 THEN 1 END)
        * 100.0 / NULLIF(COUNT(r.id_reproduccion), 0)
    , 1)                                            AS pct_completadas,
    ROUND(AVG(cal.estrellas), 2)                    AS calificacion_promedio,
    COUNT(DISTINCT cal.id_calificacion)             AS total_calificaciones,
    COUNT(DISTINCT f.id_perfil)                     AS veces_en_favoritos,
    SYSDATE                                         AS fecha_calculo
FROM CONTENIDO c
JOIN CATEGORIAS cat ON c.id_categoria = cat.id_categoria
LEFT JOIN REPRODUCCIONES r   ON c.id_contenido = r.id_contenido
LEFT JOIN CALIFICACIONES cal ON c.id_contenido = cal.id_contenido
LEFT JOIN FAVORITOS      f   ON c.id_contenido = f.id_contenido
GROUP BY
    c.id_contenido, c.titulo, cat.nombre_categoria,
    c.clasificacion_edad, c.es_original;

-- Consultar el top 10 de contenido más popular
SELECT titulo, categoria, total_reproducciones,
       calificacion_promedio, pct_completadas
FROM MV_CONTENIDO_POPULAR
WHERE total_reproducciones > 0
ORDER BY total_reproducciones DESC, calificacion_promedio DESC
FETCH FIRST 10 ROWS ONLY;


-- ----------------------------------------------------------------------------
-- VISTA MATERIALIZADA 2: MV_INGRESOS_MENSUALES
-- Pre-calcula ingresos por ciudad, plan y período
-- Base del reporte financiero mensual de la gerencia
-- ----------------------------------------------------------------------------

-- Limpiar si ya existe
BEGIN
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW MV_INGRESOS_MENSUALES';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE MATERIALIZED VIEW MV_INGRESOS_MENSUALES
    BUILD IMMEDIATE
    REFRESH COMPLETE
    ON DEMAND
AS
SELECT
    u.ciudad,
    p.nombre_plan,
    p.precio_mensual                                AS precio_base_plan,
    pg.periodo_mes,
    pg.periodo_anio,
    TO_CHAR(TO_DATE(pg.periodo_mes, 'MM'), 'Month') AS nombre_mes,
    COUNT(*)                                        AS total_pagos,
    COUNT(CASE WHEN pg.estado_pago = 'EXITOSO'
               THEN 1 END)                          AS pagos_exitosos,
    COUNT(CASE WHEN pg.estado_pago = 'FALLIDO'
               THEN 1 END)                          AS pagos_fallidos,
    COUNT(CASE WHEN pg.estado_pago = 'REEMBOLSADO'
               THEN 1 END)                          AS reembolsos,
    SUM(CASE WHEN pg.estado_pago = 'EXITOSO'
             THEN pg.monto ELSE 0 END)              AS ingresos_confirmados,
    SUM(CASE WHEN pg.estado_pago = 'FALLIDO'
             THEN pg.monto ELSE 0 END)              AS ingresos_perdidos,
    ROUND(
        SUM(CASE WHEN pg.estado_pago = 'EXITOSO' THEN pg.monto ELSE 0 END)
        / NULLIF(COUNT(CASE WHEN pg.estado_pago = 'EXITOSO' THEN 1 END), 0)
    , 2)                                            AS ticket_promedio,
    SYSDATE                                         AS fecha_calculo
FROM PAGOS    pg
JOIN USUARIOS  u ON pg.id_usuario = u.id_usuario
JOIN PLANES    p ON u.id_plan     = p.id_plan
GROUP BY
    u.ciudad, p.nombre_plan, p.precio_mensual,
    pg.periodo_mes, pg.periodo_anio;

-- Consultar los ingresos mensuales consolidados (útil para la gerencia)
SELECT ciudad, nombre_plan, nombre_mes, periodo_anio,
       ingresos_confirmados, ingresos_perdidos, pagos_exitosos
FROM MV_INGRESOS_MENSUALES
ORDER BY periodo_anio, periodo_mes, ciudad, nombre_plan;

-- Reporte financiero por ciudad usando la vista materializada + ROLLUP
SELECT
    CASE GROUPING(ciudad)
        WHEN 1 THEN '=== TOTAL GENERAL ==='
        ELSE ciudad
    END                                     AS ciudad,
    CASE GROUPING(nombre_plan)
        WHEN 1 THEN '  Subtotal'
        ELSE nombre_plan
    END                                     AS plan,
    SUM(ingresos_confirmados)               AS ingresos_totales,
    SUM(pagos_exitosos)                     AS pagos_ok,
    SUM(pagos_fallidos)                     AS pagos_fallidos
FROM MV_INGRESOS_MENSUALES
GROUP BY ROLLUP(ciudad, nombre_plan)
ORDER BY
    GROUPING(ciudad),
    ciudad NULLS LAST,
    GROUPING(nombre_plan),
    nombre_plan NULLS LAST;


-- Refrescar manualmente las vistas cuando los datos cambien:
-- BEGIN
--     DBMS_MVIEW.REFRESH('MV_CONTENIDO_POPULAR', 'C');
--     DBMS_MVIEW.REFRESH('MV_INGRESOS_MENSUALES', 'C');
-- END;
-- /


-- ============================================================================
-- SECCIÓN 3.1.5 — FRAGMENTACIÓN (ya implementada en script 02)
-- ============================================================================
-- La tabla REPRODUCCIONES fue fragmentada por rango de fechas en el script 02.
-- A continuación se muestra la consulta de verificación del particionamiento.
-- ============================================================================

-- Verificar distribución de datos en cada partición física
SELECT
    tp.partition_name                       AS particion,
    tp.tablespace_name                      AS tablespace_fisico,
    tp.num_rows                             AS filas_en_particion,
    tp.high_value                           AS limite_superior
FROM user_tab_partitions tp
WHERE tp.table_name = 'REPRODUCCIONES'
ORDER BY tp.partition_position;

-- Demostrar partition pruning: Oracle solo lee la partición de 2025
EXPLAIN PLAN FOR
SELECT COUNT(*)
FROM REPRODUCCIONES
WHERE fecha_inicio >= TIMESTAMP '2025-01-01 00:00:00'
  AND fecha_inicio <  TIMESTAMP '2026-01-01 00:00:00';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Consulta de reproducciones por año (demuestra uso de cada partición)
SELECT
    EXTRACT(YEAR FROM fecha_inicio)         AS anio,
    dispositivo,
    COUNT(*)                                AS reproducciones,
    ROUND(AVG(porcentaje_avance), 1)        AS avance_promedio
FROM REPRODUCCIONES
GROUP BY EXTRACT(YEAR FROM fecha_inicio), dispositivo
ORDER BY anio, dispositivo;


-- ============================================================================
-- VERIFICACIÓN GENERAL — NÚCLEO 1 COMPLETO
-- ============================================================================
SELECT 'MV_CONTENIDO_POPULAR'  AS vista_materializada,
       COUNT(*)                AS registros,
       MAX(fecha_calculo)      AS ultimo_calculo
FROM MV_CONTENIDO_POPULAR
UNION ALL
SELECT 'MV_INGRESOS_MENSUALES',
       COUNT(*),
       MAX(fecha_calculo)
FROM MV_INGRESOS_MENSUALES;

-- ============================================================================
-- FIN DEL SCRIPT — NÚCLEO 1 COMPLETADO
-- ============================================================================
