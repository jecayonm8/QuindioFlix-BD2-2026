-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II — QuindioFlix
-- Script:  03b_QuindioFlix_Fix_Reproducciones.sql
-- Propósito: Corregir REPRODUCCIONES (0 registros) y CALIFICACIONES (0 registros)
-- Causa:     SYS.ODCINNUMBERLIST no existe en Oracle XE — se reemplaza con
--            TYPE local declarado dentro del bloque PL/SQL
-- Ejecutar:  Como quindioflix en QuindioFlixBD (después del script v2)
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ============================================================================
-- PASO 1: Limpiar las dos tablas vacías para evitar conflictos
-- ============================================================================
DELETE FROM CALIFICACIONES;
DELETE FROM REPRODUCCIONES;
COMMIT;

-- ============================================================================
-- PASO 2: REPRODUCCIONES (200 registros)
-- FIX: Reemplaza SYS.ODCINNUMBERLIST con TYPE declarado localmente
--      que sí existe en Oracle XE 21c
-- ============================================================================
DECLARE
    -- Declaración local del tipo colección (compatible con Oracle XE)
    TYPE t_num_list IS TABLE OF NUMBER;
    TYPE t_str_list IS TABLE OF VARCHAR2(15);

    v_dispositivos t_str_list := t_str_list('celular','tablet','TV','computador');

    -- Lista de perfiles activos para asignar reproducciones
    v_perfiles t_num_list := t_num_list(
        1,2,3,6,8,9,11,13,14,15,16,17,19,20,22,23,
        24,26,29,30,31,32,33,34,36,38,39,40,43,44,
        45,46,47,49,52,54,55,8,9,15,16,32,38,43,1,15,32
    );

    v_id_rep   NUMBER := 1;
    v_perf     NUMBER;
    v_cont     NUMBER;
    v_ep       NUMBER;
    v_fecha    TIMESTAMP;
    v_fin      TIMESTAMP;
    v_disp     VARCHAR2(15);
    v_porc     NUMBER;
    v_dur      NUMBER;
BEGIN
    FOR i IN 1..200 LOOP
        -- Seleccionar perfil (rotativo entre la lista)
        v_perf := v_perfiles(MOD(i - 1, v_perfiles.COUNT) + 1);

        -- Seleccionar contenido (distribuido entre los 40)
        v_cont := MOD(i * 7 + 3, 40) + 1;

        -- Dispositivo rotativo
        v_disp := v_dispositivos(MOD(i, 4) + 1);

        -- Porcentaje de avance variado (mix de completos, mitad, y parciales)
        v_porc := CASE MOD(i, 5)
                    WHEN 0 THEN 100
                    WHEN 1 THEN MOD(i * 3, 20) + 80  -- 80-99%
                    WHEN 2 THEN MOD(i * 3, 30) + 50  -- 50-79%
                    WHEN 3 THEN MOD(i * 3, 30) + 20  -- 20-49%
                    ELSE        MOD(i * 3, 20) + 1   -- 1-20%
                  END;

        -- Fecha distribuida en 3 años (demuestra el particionamiento)
        -- ~60 en 2024 → TS_REPROD_2024
        -- ~80 en 2025 → TS_REPROD_2025
        -- ~60 en 2026 → TS_REPROD_2026
        v_fecha := CASE
            WHEN i <= 60  THEN TIMESTAMP '2024-01-15 08:00:00' + NUMTODSINTERVAL(MOD(i * 73, 330), 'DAY')
            WHEN i <= 140 THEN TIMESTAMP '2025-01-10 09:00:00' + NUMTODSINTERVAL(MOD(i * 59, 350), 'DAY')
            ELSE               TIMESTAMP '2026-01-05 10:00:00' + NUMTODSINTERVAL(MOD(i * 41, 100), 'DAY')
        END;

        -- Calcular fecha_fin basada en duración y porcentaje de avance
        SELECT duracion_min INTO v_dur
        FROM CONTENIDO
        WHERE id_contenido = v_cont;

        v_fin := v_fecha + NUMTODSINTERVAL(ROUND(v_dur * v_porc / 100.0), 'MINUTE');

        -- Asignar episodio solo para series y podcasts que tienen episodios
        v_ep := NULL;
        IF    v_cont = 11 THEN v_ep := MOD(i * 3, 16) + 1;   -- Café Amargo: eps 1-16
        ELSIF v_cont = 12 THEN v_ep := MOD(i * 3, 10) + 17;  -- Los Detectives: eps 17-26
        ELSIF v_cont = 13 THEN v_ep := MOD(i * 3, 12) + 27;  -- Familia Caribe: eps 27-38
        ELSIF v_cont = 15 THEN v_ep := MOD(i * 3,  9) + 39;  -- Amor en Bogotá: eps 39-47
        ELSIF v_cont = 36 THEN v_ep := 48;                    -- Negocios Colombia
        ELSIF v_cont = 37 THEN v_ep := 49;                    -- Ciencia al Día
        ELSIF v_cont = 38 THEN v_ep := 50;                    -- Historia Viva
        END IF;

        INSERT INTO REPRODUCCIONES
        VALUES (v_id_rep, v_perf, v_cont, v_ep, v_fecha, v_fin, v_disp, v_porc);

        v_id_rep := v_id_rep + 1;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('✓ Reproducciones insertadas: ' || (v_id_rep - 1));
END;
/

-- ============================================================================
-- PASO 3: CALIFICACIONES (hasta 60 registros)
-- Solo para contenido con >= 50% de avance (Regla de Negocio RN-05)
-- FIX: Subquery con DISTINCT garantiza pares únicos (id_perfil, id_contenido)
--      para evitar ORA-00001 en el UNIQUE constraint de CALIFICACIONES
-- ============================================================================
DECLARE
    TYPE t_str_list IS TABLE OF VARCHAR2(200);

    v_cal_id    NUMBER := 1;
    v_estrellas NUMBER;
    v_resenas   t_str_list := t_str_list(
        'Excelente producción colombiana, muy recomendada.',
        'Buena historia pero el final me decepcionó un poco.',
        'Increíble trabajo del elenco, me encantó cada episodio.',
        'Entretenida pero predecible en algunos momentos.',
        'Una joya del cine colombiano, hay que verla.',
        'Me pareció regular, esperaba más de esta producción.',
        'Perfecta para ver en familia los domingos.',
        'La fotografía es espectacular, muy bien hecha.',
        NULL,
        NULL
    );
BEGIN
    -- Subquery con DISTINCT garantiza combinaciones únicas (perfil, contenido)
    -- GROUP BY evita que el mismo perfil califique el mismo contenido dos veces
    FOR r IN (
        SELECT id_perfil,
               id_contenido,
               ROW_NUMBER() OVER (ORDER BY id_perfil, id_contenido) AS rn
        FROM (
            SELECT DISTINCT id_perfil, id_contenido
            FROM   REPRODUCCIONES
            WHERE  porcentaje_avance >= 50
              AND  id_perfil NOT IN (4, 5, 27, 28, 51)  -- excluye perfiles de cuentas INACTIVAS
        )
        FETCH FIRST 60 ROWS ONLY
    )
    LOOP
        v_estrellas := MOD(r.rn, 5) + 1;  -- estrellas 1-5 rotativas

        INSERT INTO CALIFICACIONES
        VALUES (
            v_cal_id,
            r.id_perfil,
            r.id_contenido,
            v_estrellas,
            v_resenas(MOD(r.rn - 1, v_resenas.COUNT) + 1),
            SYSDATE - MOD(r.rn * 7, 90)
        );
        v_cal_id := v_cal_id + 1;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('✓ Calificaciones insertadas: ' || (v_cal_id - 1));
END;
/

-- ============================================================================
-- PASO 4: Actualizar estadísticas de particiones de REPRODUCCIONES
-- (para que NUM_ROWS muestre valores reales en user_tab_partitions)
-- ============================================================================
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER, 'REPRODUCCIONES');
    DBMS_OUTPUT.PUT_LINE('✓ Estadísticas actualizadas.');
END;
/

-- ============================================================================
-- VERIFICACIÓN FINAL
-- ============================================================================

-- Conteo de las tablas que faltaban
SELECT 'REPRODUCCIONES' AS tabla, COUNT(*) AS registros FROM REPRODUCCIONES
UNION ALL
SELECT 'CALIFICACIONES', COUNT(*) FROM CALIFICACIONES;

-- Distribución de reproducciones por año (demuestra particionamiento)
SELECT
    partition_name                                   AS particion,
    num_rows                                         AS reproducciones,
    CASE partition_name
        WHEN 'P_REPROD_2024'  THEN 'Tablespace TS_REPROD_2024'
        WHEN 'P_REPROD_2025'  THEN 'Tablespace TS_REPROD_2025'
        WHEN 'P_REPROD_2026'  THEN 'Tablespace TS_REPROD_2026'
        ELSE                       'Tablespace TS_REPROD_2026 (futuro)'
    END AS tablespace_fisico
FROM user_tab_partitions
WHERE table_name = 'REPRODUCCIONES'
ORDER BY partition_position;

-- Distribución de calificaciones por estrellas
SELECT estrellas, COUNT(*) AS cantidad
FROM CALIFICACIONES
GROUP BY estrellas
ORDER BY estrellas;

-- Reproducciones por dispositivo y año
SELECT
    dispositivo,
    EXTRACT(YEAR FROM fecha_inicio) AS anio,
    COUNT(*) AS total
FROM REPRODUCCIONES
GROUP BY dispositivo, EXTRACT(YEAR FROM fecha_inicio)
ORDER BY dispositivo, anio;

-- ============================================================================
-- FIN DEL SCRIPT DE CORRECCIÓN
-- ============================================================================
