-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   02_QuindioFlix_Tablespaces.sql
-- Propósito del script: Creación de Tablespaces, Datafiles y Fragmentación de
--  REPRODUCCIONES
-- Núcleo:   NT1 — Sección 3.1.5 (Fragmentación de tablas)
-- Plantilla: Sección 3 — Esquema de Almacenamiento

-- ANTES DE EJECUTAR se debe:
--   1. Ejecutar la consulta de diagnóstico en QuindioFlixBD o la conexion utilizada:
--      SELECT name FROM v$datafile FETCH FIRST 1 ROWS ONLY;
--   2. Se Reemplaza la variable RUTA_BASE en la PARTE A con la ruta obtenida
--      Ejemplo para macOS/Docker : /opt/oracle/oradata/XE/
-- ============================================================================


-- ============================================================================
-- PARTE A — CREAR TABLESPACES (ejecutar como system en NeonatosBD)

-- Nota: Tener en cuenta que la NeonatosBD, esta en localhost de puerto 1521
--  con SID: xe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TS_QUINDIOFLIX: Tablas maestras y catálogos del sistema.

-- Justificación: Agrupa las tablas de referencia que cambian poco y tienen
-- lecturas frecuentes. Separar del tablespace por defecto (USERS) permitiria
-- administrar mejor el espacio y aplicar políticas de backup independientes.
-- ----------------------------------------------------------------------------
CREATE TABLESPACE TS_QUINDIOFLIX
    DATAFILE '/opt/oracle/oradata/XE/ts_quindioflix01.dbf'
    SIZE 50M
    AUTOEXTEND ON NEXT 10M MAXSIZE 200M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

-- ----------------------------------------------------------------------------
-- TS_CONTENIDO: Catálogo de contenido multimedia.

-- Justificación: El catálogo crece constantemente con nuevas películas, series
-- y podcasts. Aislarlo permite hacer consultas analíticas sin afectar las
-- tablas transaccionales de usuarios y pagos.
-- ----------------------------------------------------------------------------
CREATE TABLESPACE TS_CONTENIDO
    DATAFILE '/opt/oracle/oradata/XE/ts_contenido01.dbf'
    SIZE 30M
    AUTOEXTEND ON NEXT 10M MAXSIZE 150M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

-- ----------------------------------------------------------------------------
-- TS_TRANSACCIONES: Pagos, calificaciones, favoritos y reportes.

-- Justificación: Tablas con alta frecuencia de INSERT. Separarlas mejora el
-- rendimiento de escritura y simplifica el mantenimiento de backups diarios
-- de datos transaccionales críticos (especialmente PAGOS).
-- ----------------------------------------------------------------------------
CREATE TABLESPACE TS_TRANSACCIONES
    DATAFILE '/opt/oracle/oradata/XE/ts_transacciones01.dbf'
    SIZE 30M
    AUTOEXTEND ON NEXT 10M MAXSIZE 150M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

-- ----------------------------------------------------------------------------
-- TS_REPROD_2024, TS_REPROD_2025, TS_REPROD_2026: Particiones de REPRODUCCIONES

-- Justificación: REPRODUCCIONES es la tabla con mayor crecimiento (cada vez
-- que alguien reproduce algo se inserta un registro). Con un aprox de 200+ usuarios y
-- múltiples reproducciones diarias puede alcanzar millones de filas en meses.
-- La fragmentación o particion por año permite:
--   - Consultar solo el año relevante sin escanear toda la tabla
--   - Archivar o eliminar años antiguos sin afectar los datos actuales
--   - Balancear la carga de I/O en diferentes datafiles físicos
-- ----------------------------------------------------------------------------
CREATE TABLESPACE TS_REPROD_2024
    DATAFILE '/opt/oracle/oradata/XE/ts_reprod_2024.dbf'
    SIZE 50M
    AUTOEXTEND ON NEXT 20M MAXSIZE 500M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

CREATE TABLESPACE TS_REPROD_2025
    DATAFILE '/opt/oracle/oradata/XE/ts_reprod_2025.dbf'
    SIZE 50M
    AUTOEXTEND ON NEXT 20M MAXSIZE 500M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

CREATE TABLESPACE TS_REPROD_2026
    DATAFILE '/opt/oracle/oradata/XE/ts_reprod_2026.dbf'
    SIZE 50M
    AUTOEXTEND ON NEXT 20M MAXSIZE 500M
    EXTENT MANAGEMENT LOCAL
    SEGMENT SPACE MANAGEMENT AUTO;

-- PRUEBA: Verificar que los tablespaces fueron creados correctamente
SELECT
    t.tablespace_name,
    t.status,
    t.contents,
    ROUND(d.bytes     / 1024 / 1024, 2) AS tamanio_actual_mb,
    ROUND(d.user_bytes/ 1024 / 1024, 2) AS disponible_mb,
    d.autoextensible                     AS autoextend
FROM dba_tablespaces t
JOIN dba_data_files d
  ON t.tablespace_name = d.tablespace_name
WHERE t.tablespace_name LIKE 'TS_%'
ORDER BY t.tablespace_name;


-- ============================================================================
-- PARTE B — FRAGMENTAR TABLA Y MOVER TABLAS (se ejecuta como quindioflix)

-- Nota: Tener en cuenta que la QuindioFlixBD, esta en localhost de puerto 1521
--  con SID: xe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PASO B1: Se elimina la tabla REPRODUCCIONES original
-- (fue creada sin particiones en el script 01, se reemplaza con versión
-- particionada. No hay datos todavía, por eso es seguro hacer DROP)
-- ----------------------------------------------------------------------------
DROP TABLE REPRODUCCIONES;

-- ----------------------------------------------------------------------------
-- PASO B2: Aca se va a recrear REPRODUCCIONES como tabla PARTICIONADA por rango de fechas
-- Tipo de particionamiento: RANGE sobre fecha_inicio
-- Cada partición vive en su propio tablespace con datafile independiente
-- ----------------------------------------------------------------------------
CREATE TABLE REPRODUCCIONES (
    id_reproduccion   NUMBER(10)      GENERATED ALWAYS AS IDENTITY,
    id_perfil         NUMBER(8)       NOT NULL,
    id_contenido      NUMBER(8)       NOT NULL,
    id_episodio       NUMBER(8),
    fecha_inicio      TIMESTAMP       DEFAULT SYSTIMESTAMP NOT NULL,
    fecha_fin         TIMESTAMP,
    dispositivo       VARCHAR2(15)    NOT NULL,
    porcentaje_avance NUMBER(5,2)     DEFAULT 0,
    -- Restricciones de integridad
    CONSTRAINT pk_reproducciones    PRIMARY KEY (id_reproduccion, fecha_inicio),
    CONSTRAINT fk_rep_perfil        FOREIGN KEY (id_perfil)
                                    REFERENCES PERFILES(id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_rep_contenido     FOREIGN KEY (id_contenido)
                                    REFERENCES CONTENIDO(id_contenido),
    CONSTRAINT fk_rep_episodio      FOREIGN KEY (id_episodio)
                                    REFERENCES EPISODIOS(id_episodio),
    CONSTRAINT chk_rep_dispositivo  CHECK (dispositivo IN ('celular','tablet','TV','computador')),
    CONSTRAINT chk_rep_porcentaje   CHECK (porcentaje_avance BETWEEN 0 AND 100)
)
-- Particionamiento por rango de fecha de inicio
PARTITION BY RANGE (fecha_inicio) (
    -- Reproducciones del año 2024 → tablespace dedicado 2024
    PARTITION p_reprod_2024
        VALUES LESS THAN (TIMESTAMP '2025-01-01 00:00:00')
        TABLESPACE TS_REPROD_2024,
    -- Reproducciones del año 2025 → tablespace dedicado 2025
    PARTITION p_reprod_2025
        VALUES LESS THAN (TIMESTAMP '2026-01-01 00:00:00')
        TABLESPACE TS_REPROD_2025,
    -- Reproducciones del año 2026 → tablespace dedicado 2026
    PARTITION p_reprod_2026
        VALUES LESS THAN (TIMESTAMP '2027-01-01 00:00:00')
        TABLESPACE TS_REPROD_2026,
    -- Partición para fechas futuras (safety net)
    PARTITION p_reprod_futuro
        VALUES LESS THAN (MAXVALUE)
        TABLESPACE TS_REPROD_2026
);

COMMENT ON TABLE  REPRODUCCIONES IS 'Historial de reproducciones — tabla fragmentada por año de fecha_inicio';
COMMENT ON COLUMN REPRODUCCIONES.fecha_inicio IS 'Clave de particionamiento — determina en qué tablespace físico se almacena el registro';

-- ----------------------------------------------------------------------------
-- PASO B3: Mover tablas maestras al tablespace TS_QUINDIOFLIX
-- ----------------------------------------------------------------------------
ALTER TABLE PLANES        MOVE TABLESPACE TS_QUINDIOFLIX;
ALTER TABLE USUARIOS      MOVE TABLESPACE TS_QUINDIOFLIX;
ALTER TABLE PERFILES      MOVE TABLESPACE TS_QUINDIOFLIX;
ALTER TABLE EMPLEADOS     MOVE TABLESPACE TS_QUINDIOFLIX;
ALTER TABLE DEPARTAMENTOS MOVE TABLESPACE TS_QUINDIOFLIX;

-- ----------------------------------------------------------------------------
-- PASO B4: Mover tablas de contenido al tablespace TS_CONTENIDO
-- ----------------------------------------------------------------------------
ALTER TABLE CATEGORIAS            MOVE TABLESPACE TS_CONTENIDO;
ALTER TABLE GENEROS               MOVE TABLESPACE TS_CONTENIDO;
ALTER TABLE CONTENIDO             MOVE TABLESPACE TS_CONTENIDO;
ALTER TABLE CONTENIDO_GENERO      MOVE TABLESPACE TS_CONTENIDO;
ALTER TABLE CONTENIDO_RELACIONADO MOVE TABLESPACE TS_CONTENIDO;
ALTER TABLE TEMPORADAS            MOVE TABLESPACE TS_CONTENIDO;
ALTER TABLE EPISODIOS             MOVE TABLESPACE TS_CONTENIDO;

-- ----------------------------------------------------------------------------
-- PASO B5: Mover tablas transaccionales al tablespace TS_TRANSACCIONES
-- ----------------------------------------------------------------------------
ALTER TABLE PAGOS          MOVE TABLESPACE TS_TRANSACCIONES;
ALTER TABLE CALIFICACIONES MOVE TABLESPACE TS_TRANSACCIONES;
ALTER TABLE FAVORITOS      MOVE TABLESPACE TS_TRANSACCIONES;
ALTER TABLE REPORTES       MOVE TABLESPACE TS_TRANSACCIONES;

-- ----------------------------------------------------------------------------
-- PASO B6: Reconstruir TODOS los índices

-- OBLIGATORIO: ALTER TABLE MOVE invalida los índices automáticamente.
-- Sin este paso, las consultas fallarian con ORA-01502 (índice inutilizable).
-- ----------------------------------------------------------------------------
BEGIN
    FOR idx IN (
        SELECT index_name
        FROM user_indexes
        WHERE status = 'UNUSABLE'
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER INDEX ' || idx.index_name || ' REBUILD';
            DBMS_OUTPUT.PUT_LINE('Reconstruido: ' || idx.index_name);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Error en: ' || idx.index_name || ' — ' || SQLERRM);
        END;
    END LOOP;
END;
/


-- =========================================================================
-- PRUEBA: VERIFICACIONES FINALES de que este todo correcto.
-- =========================================================================

-- 1. Verificar que todas las tablas están en el tablespace correcto
SELECT table_name, tablespace_name
FROM user_tables
ORDER BY tablespace_name, table_name;

-- 2. Verificar las particiones de REPRODUCCIONES
SELECT partition_name,
       tablespace_name,
       high_value,
       num_rows
FROM user_tab_partitions
WHERE table_name = 'REPRODUCCIONES'
ORDER BY partition_position;

-- 3. Verificar que no hay índices UNUSABLE
SELECT index_name, status
FROM user_indexes
WHERE status != 'VALID'
ORDER BY index_name;

-- 4. Ver propiedades de los tablespaces creados
SELECT
    t.tablespace_name,
    t.status,
    ROUND(d.bytes / 1024 / 1024, 2)     AS tamanio_mb,
    ROUND(d.maxbytes / 1024 / 1024, 2)  AS maximo_mb,
    d.autoextensible                     AS autoextend
FROM dba_tablespaces t
JOIN dba_data_files d ON t.tablespace_name = d.tablespace_name
WHERE t.tablespace_name LIKE 'TS_%'
ORDER BY t.tablespace_name;

-- ===================
-- FIN DEL SCRIPT 02
-- ===================
