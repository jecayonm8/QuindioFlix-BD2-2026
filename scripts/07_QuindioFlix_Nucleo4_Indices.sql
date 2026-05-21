-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   07_QuindioFlix_Nucleo4_Indices.sql
-- Propósito: Núcleo Temático 4 — Índices y Análisis de Rendimiento

-- Este script de divide en secciones:
--   3.4.1  Creación de 4 índices con justificación
--   3.4.2  Análisis EXPLAIN PLAN antes y después de índice

-- Ejecutar: Como quindioflix en QuindioFlixBD

--           Las capturas del EXPLAIN PLAN son obligatorias para el documento
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- =========================================================================
-- PASO PREVIO: Actualizar estadísticas del optimizador
-- Oracle usa estadísticas para decidir qué plan de ejecución usar.
-- Sin estadísticas actualizadas el EXPLAIN PLAN puede ser impreciso.
-- =========================================================================
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'REPRODUCCIONES');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'USUARIOS');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'CONTENIDO');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'CALIFICACIONES');
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGOS');
    DBMS_OUTPUT.PUT_LINE('Estadísticas actualizadas correctamente.');
END;
/


-- ============================================================================
-- SECCIÓN 3.4.1 — CREACIÓN DE ÍNDICES
-- ============================================================================


-- ----------------------------------------------------------------------------
-- ÍNDICE 1: REPRODUCCIONES(id_perfil, fecha_inicio)
-- ----------------------------------------------------------------------------
-- JUSTIFICACIÓN:
-- Esta es la consulta más frecuente del sistema: "mostrar el historial de
-- reproducciones de un perfil específico ordenado por fecha".
-- Se ejecuta cada vez que un usuario abre su perfil en la plataforma.
--
-- Sin índice: Oracle hace FULL SCAN de 200 registros distribuidos en 3
--             particiones (2024, 2025, 2026) buscando los de id_perfil=X
--
-- Con índice: Oracle va directo a los registros de ese perfil usando el
--             índice, sin escanear las particiones completas.
--
-- TIPO: B-Tree compuesto LOCAL (una partición de índice por cada partición
--       de la tabla REPRODUCCIONES → sincronizado con el particionamiento)
-- ----------------------------------------------------------------------------

-- Eliminar si ya existe (para re-ejecuciones limpias)
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_reprod_perfil_fecha';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE INDEX idx_reprod_perfil_fecha
    ON REPRODUCCIONES(id_perfil, fecha_inicio)
    LOCAL   -- índice particionado, una partición por cada tablespace de datos
    TABLESPACE TS_REPROD_2024;  -- tablespace base del índice

COMMENT ON INDEX idx_reprod_perfil_fecha
    IS 'Índice compuesto LOCAL para historial de reproducciones por perfil y fecha';

-- Verificar que se creó correctamente
SELECT index_name, index_type, status, partitioned
FROM   user_indexes
WHERE  index_name = 'IDX_REPROD_PERFIL_FECHA';

-- ----------------------------------------------------------------------------
-- ÍNDICE 2: USUARIOS(email_usuario)
-- ----------------------------------------------------------------------------
-- JUSTIFICACIÓN:
-- El campo email_usuario ya tiene un índice ÚNICO creado automáticamente por
-- Oracle al definir la constraint UNIQUE en el CREATE TABLE.
-- Este índice es CRÍTICO para dos operaciones de alta frecuencia:
--   a) LOGIN: cada inicio de sesión busca por email → sin índice = full scan
--             de 30 usuarios (en producción serían millones)
--   b) VALIDACIÓN DE DUPLICADOS: SP_REGISTRAR_USUARIO verifica unicidad
--             del email antes de insertar → búsqueda por exacta coincidencia
--
-- Oracle crea índice UNIQUE automáticamente para constraints UNIQUE y PK.
-- Lo verificamos a continuación:
-- ----------------------------------------------------------------------------

-- Verificar que Oracle ya creó el índice automáticamente
SELECT index_name, index_type, uniqueness, status
FROM   user_indexes
WHERE  table_name  = 'USUARIOS'
  AND  index_name LIKE '%EMAIL%'
   OR  (table_name = 'USUARIOS'
        AND EXISTS (
            SELECT 1 FROM user_ind_columns uic
            WHERE  uic.index_name  = user_indexes.index_name
              AND  uic.column_name = 'EMAIL_USUARIO'
        ));

-- Si no aparece con el nombre esperado, buscar de otra forma
SELECT ui.index_name,
       uic.column_name,
       ui.uniqueness,
       ui.status
FROM   user_indexes     ui
JOIN   user_ind_columns uic ON ui.index_name = uic.index_name
WHERE  ui.table_name = 'USUARIOS'
ORDER  BY ui.index_name, uic.column_position;

-- El índice de email ya existe como UNIQUE por la constraint.
-- Creamos un índice adicional para búsquedas por ciudad + plan
-- (útil para los reportes PIVOT de usuarios por ciudad y plan):

BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_usuarios_ciudad_plan';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE INDEX idx_usuarios_ciudad_plan
    ON USUARIOS(ciudad, id_plan, estado_cuenta);

COMMENT ON INDEX idx_usuarios_ciudad_plan
    IS 'Índice para reportes de usuarios activos por ciudad y plan de suscripción';


-- ----------------------------------------------------------------------------
-- ÍNDICE 3: CONTENIDO(id_categoria, anio_lanzamiento)
-- ----------------------------------------------------------------------------
-- JUSTIFICACIÓN:
-- Las consultas analíticas de la gerencia filtran frecuentemente el catálogo
-- por categoría (Película, Serie, etc.) y año de lanzamiento:
--   - "¿Cuántas series nuevas se agregaron en 2024?"
--   - "Top documentales de los últimos 2 años"
--   - Reporte de catálogo por categoría para el equipo de Contenido
--
-- Sin índice: Scan completo de los 40 contenidos filtrando por categoría y año.
-- Con índice: Acceso directo a los registros que cumplen ambos criterios.
-- En producción el catálogo puede tener miles de títulos → el índice es clave.
--
-- TIPO: B-Tree compuesto (columna selectiva primero: id_categoria tiene solo
--       5 valores distintos, anio_lanzamiento mejora la selectividad combinada)
-- ----------------------------------------------------------------------------

BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_contenido_cat_anio';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE INDEX idx_contenido_cat_anio
    ON CONTENIDO(id_categoria, anio_lanzamiento)
    TABLESPACE TS_CONTENIDO;

COMMENT ON INDEX idx_contenido_cat_anio
    IS 'Índice para búsquedas y reportes de catálogo por categoría y año';

-- Verificar
SELECT index_name, index_type, status, tablespace_name
FROM   user_indexes
WHERE  index_name = 'IDX_CONTENIDO_CAT_ANIO';


-- ----------------------------------------------------------------------------
-- ÍNDICE 4 (elección del estudiante): PAGOS(id_usuario, estado_pago)
-- ----------------------------------------------------------------------------
-- JUSTIFICACIÓN:
-- Este índice fue elegido analizando las consultas más frecuentes del sistema:
--
--   1. TRG_ACTIVAR_CUENTA_PAGO: busca pagos EXITOSOS del día actual por usuario
--      → WHERE id_usuario = X AND estado_pago = 'EXITOSO' AND fecha_pago = hoy
--
--   2. Cursor de mora: filtra pagos por usuario y estado para calcular deuda
--      → WHERE id_usuario = X AND estado_pago = 'FALLIDO'
--
--   3. MV_INGRESOS_MENSUALES: agrupa pagos por usuario y estado para reportes
--      financieros → GROUP BY que se beneficia del índice en ambas columnas
--
--   4. SP_CAMBIAR_PLAN: verifica historial de pagos del usuario antes de cambio
--
-- Sin índice: cada consulta de pagos de un usuario escanea todos los 80 pagos.
-- Con índice: acceso directo a los pagos de ese usuario filtrados por estado.
-- En producción con millones de pagos históricos, este índice es fundamental.
--
-- TIPO: B-Tree compuesto. id_usuario primero (alta cardinalidad),
--       estado_pago segundo (filtra dentro del subconjunto del usuario)
-- ----------------------------------------------------------------------------

BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_pagos_usuario_estado';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE INDEX idx_pagos_usuario_estado
    ON PAGOS(id_usuario, estado_pago, periodo_anio)
    TABLESPACE TS_TRANSACCIONES;

COMMENT ON INDEX idx_pagos_usuario_estado
    IS 'Índice para consultas de historial de pagos por usuario, estado y año';


-- ============================================================================
-- RESUMEN DE ÍNDICES CREADOS
-- ============================================================================
SELECT
    ui.index_name                           AS indice,
    ui.table_name                           AS tabla,
    LISTAGG(uic.column_name, ', ')
        WITHIN GROUP (ORDER BY uic.column_position)
                                            AS columnas,
    ui.index_type                           AS tipo,
    ui.uniqueness                           AS unicidad,
    ui.status                               AS estado,
    ui.partitioned                          AS particionado
FROM   user_indexes     ui
JOIN   user_ind_columns uic ON ui.index_name = uic.index_name
WHERE  ui.index_name IN (
    'IDX_REPROD_PERFIL_FECHA',
    'IDX_USUARIOS_CIUDAD_PLAN',
    'IDX_CONTENIDO_CAT_ANIO',
    'IDX_PAGOS_USUARIO_ESTADO'
)
GROUP BY ui.index_name, ui.table_name, ui.index_type,
         ui.uniqueness, ui.status, ui.partitioned
ORDER BY ui.table_name;


-- ============================================================================
-- SECCIÓN 3.4.2 — ANÁLISIS DE RENDIMIENTO: EXPLAIN PLAN
-- ============================================================================
-- Demostración del impacto del índice IDX_REPROD_PERFIL_FECHA
-- Consulta elegida: historial de reproducciones de un perfil específico
-- Esta consulta se ejecuta miles de veces al día en la plataforma real
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- ANÁLISIS 1 — PLAN DE EJECUCIÓN SIN EL ÍNDICE COMPUESTO
-- Primero deshabilitamos el índice para simular el escenario "antes"
-- ─────────────────────────────────────────────────────────────────────────────

-- Deshabilitar el índice para ver el plan sin él
ALTER INDEX idx_reprod_perfil_fecha UNUSABLE;

-- (muestra el plan CON el índice — costo más alto)
EXPLAIN PLAN
    SET STATEMENT_ID = 'SIN_INDICE'
    FOR
    SELECT
        r.id_reproduccion,
        r.id_contenido,
        c.titulo,
        cat.nombre_categoria,
        r.dispositivo,
        r.porcentaje_avance,
        r.fecha_inicio,
        r.fecha_fin
    FROM   REPRODUCCIONES r
    JOIN   CONTENIDO  c   ON r.id_contenido = c.id_contenido
    JOIN   CATEGORIAS cat ON c.id_categoria = cat.id_categoria
    WHERE  r.id_perfil  = 15
    ORDER  BY r.fecha_inicio DESC;

-- Ver el plan de ejecución detallado SIN índice
SELECT *
FROM   TABLE(DBMS_XPLAN.DISPLAY(
    statement_id => 'SIN_INDICE',
    format       => 'ALL'
));


-- ─────────────────────────────────────────────────────────────────────────────
-- ANÁLISIS 2 — PLAN DE EJECUCIÓN CON EL ÍNDICE ACTIVO
-- Rehabilitamos el índice y ejecutamos la misma consulta
-- ─────────────────────────────────────────────────────────────────────────────

-- Rehabilitar el índice
ALTER INDEX idx_reprod_perfil_fecha REBUILD;

-- (muestra el plan CON el índice — costo más bajo)
EXPLAIN PLAN
    SET STATEMENT_ID = 'CON_INDICE'
    FOR
    SELECT
        r.id_reproduccion,
        r.id_contenido,
        c.titulo,
        cat.nombre_categoria,
        r.dispositivo,
        r.porcentaje_avance,
        r.fecha_inicio,
        r.fecha_fin
    FROM   REPRODUCCIONES r
    JOIN   CONTENIDO  c   ON r.id_contenido = c.id_contenido
    JOIN   CATEGORIAS cat ON c.id_categoria = cat.id_categoria
    WHERE  r.id_perfil  = 15
    ORDER  BY r.fecha_inicio DESC;

-- Ver el plan de ejecución detallado CON índice
SELECT *
FROM   TABLE(DBMS_XPLAN.DISPLAY(
    statement_id => 'CON_INDICE',
    format       => 'ALL'
));

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPARACIÓN DIRECTA DE COSTOS — ANTES vs DESPUÉS
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    p.statement_id                          AS escenario,
    p.operation || ' ' || p.options         AS operacion,
    p.object_name                           AS objeto,
    p.cost                                  AS costo_estimado,
    p.cardinality                           AS filas_estimadas,
    p.bytes                                 AS bytes_estimados,
    p.partition_start                       AS particion_inicio,
    p.partition_stop                        AS particion_fin
FROM   plan_table p
WHERE  p.statement_id IN ('SIN_INDICE', 'CON_INDICE')
ORDER  BY p.statement_id, p.id;


-- ─────────────────────────────────────────────────────────────────────────────
-- ANÁLISIS ADICIONAL: EXPLAIN PLAN para consulta de PIVOT (Núcleo 1)
-- Muestra cómo el índice idx_usuarios_ciudad_plan mejora el PIVOT
-- ─────────────────────────────────────────────────────────────────────────────
EXPLAIN PLAN
    SET STATEMENT_ID = 'PIVOT_CON_INDICE'
    FOR
    SELECT ciudad, BASICO, ESTANDAR, PREMIUM
    FROM (
        SELECT u.ciudad, p.nombre_plan, u.id_usuario
        FROM   USUARIOS u
        JOIN   PLANES   p ON u.id_plan = p.id_plan
        WHERE  u.estado_cuenta = 'ACTIVO'
    )
    PIVOT (
        COUNT(id_usuario)
        FOR nombre_plan IN (
            'Básico'   AS BASICO,
            'Estándar' AS ESTANDAR,
            'Premium'  AS PREMIUM
        )
    );

SELECT operation, options, object_name, cost, cardinality
FROM   plan_table
WHERE  statement_id = 'PIVOT_CON_INDICE'
ORDER  BY id;


-- ==========================================================================
-- VERIFICACIÓN FINAL — ÍNDICES OPERATIVOS
-- ==========================================================================

-- Ver todos los índices del esquema quindioflix
SELECT
    ui.index_name,
    ui.table_name,
    ui.status,
    ui.index_type,
    ui.uniqueness,
    NVL(ui.tablespace_name, 'PARTICIONADO') AS tablespace_name,
    ui.last_analyzed
FROM   user_indexes ui
ORDER  BY ui.table_name, ui.index_name;

-- Ver columnas de cada índice creado en este script
SELECT
    uic.index_name,
    uic.column_position AS pos,
    uic.column_name,
    uic.descend
FROM   user_ind_columns uic
WHERE  uic.index_name IN (
    'IDX_REPROD_PERFIL_FECHA',
    'IDX_USUARIOS_CIUDAD_PLAN',
    'IDX_CONTENIDO_CAT_ANIO',
    'IDX_PAGOS_USUARIO_ESTADO'
)
ORDER  BY uic.index_name, uic.column_position;

-- ======================================================================
-- FIN DEL SCRIPT — NÚCLEO 4 COMPLETO
-- ======================================================================
