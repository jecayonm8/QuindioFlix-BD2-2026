-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   06_QuindioFlix_Nucleo3_Transacciones.sql
-- Propósito: Núcleo Temático 3 — Transacciones y Concurrencia

-- Secciones:
--   3.3.1-A  Transacción 1: Registro completo (Usuario+Perfil+Pago)
--   3.3.1-B  Transacción 2: Renovación mensual con SAVEPOINT
--   3.3.1-C  Transacción 3: Eliminación de cuenta (todo o nada)
--   3.3.2    Concurrencia: SELECT FOR UPDATE (scripts Sesión A y Sesión B)

-- Ejecutar: Como quindioflix en QuindioFlixBD
-- Nota:     Ejecutar cada BLOQUE por separado

-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ====================================================================
-- ESTADOS DE UNA TRANSACCIÓN EN ORACLE
-- ====================================================================
--  ACTIVA           → Desde el primer DML hasta el COMMIT o ROLLBACK
--  PARCIALMENTE     → Todos los DML ejecutados, pendiente de confirmar
--    CONFIRMADA
--  CONFIRMADA       → Después del COMMIT — cambios permanentes
--  FALLIDA          → Ocurrió un error durante la transacción
--  ABORTADA         → Después del ROLLBACK — cambios deshechos
-- =====================================================================


-- ============================================================================
-- TRANSACCIÓN 1 — REGISTRO COMPLETO

-- Crear Usuario + Perfil + Primer Pago
-- Si falla cualquier paso → ROLLBACK completo (todo o nada)
-- ============================================================================
DECLARE
    -- Variables de entrada
    v_nombre    CONSTANT VARCHAR2(80) := 'Carlos Andrés Mejía';
    v_email     CONSTANT VARCHAR2(100):= 'carlos.mejia.txn1@gmail.com';
    v_telefono  CONSTANT VARCHAR2(20) := '3001234999';
    v_fecha_nac CONSTANT DATE         := DATE '1993-08-15';
    v_ciudad    CONSTANT VARCHAR2(50) := 'Pereira';
    v_id_plan   CONSTANT NUMBER       := 2;  -- Estándar

    -- Variables internas
    v_nuevo_id  NUMBER;
    v_precio    NUMBER;
    v_email_dup NUMBER;

    -- Excepción personalizada
    email_duplicado EXCEPTION;
BEGIN
    -- ──────────────────────────────────────────────────────────
    -- ESTADO: ACTIVA — comienza la transacción con el primer DML
    -- ──────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('TRANSACCIÓN 1: Registro Completo — Estado: ACTIVA');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');

    -- VALIDACIÓN: Email único
    SELECT COUNT(*) INTO v_email_dup
    FROM   USUARIOS WHERE email_usuario = v_email;

    IF v_email_dup > 0 THEN
        RAISE email_duplicado;
    END IF;

    -- Obtener precio del plan
    SELECT precio_mensual INTO v_precio
    FROM   PLANES WHERE id_plan = v_id_plan;

    -- PASO 1: Insertar usuario
    INSERT INTO USUARIOS (
        nombre_usuario, email_usuario, telefono, fecha_nacimiento,
        ciudad, fecha_registro, estado_cuenta, fecha_ultimo_pago,
        id_plan, id_referidor, es_moderador
    ) VALUES (
        v_nombre, v_email, v_telefono, v_fecha_nac,
        v_ciudad, SYSDATE, 'ACTIVO', SYSDATE,
        v_id_plan, NULL, 'N'
    )
    RETURNING id_usuario INTO v_nuevo_id;

    DBMS_OUTPUT.PUT_LINE('  PASO 1 ✓ — Usuario insertado. ID=' || v_nuevo_id);

    -- PASO 2: Crear perfil predeterminado
    INSERT INTO PERFILES (id_usuario, nombre_perfil, avatar, tipo_perfil, fecha_creacion)
    VALUES (v_nuevo_id, v_nombre, 'avatar_default.png', 'adulto', SYSDATE);

    DBMS_OUTPUT.PUT_LINE('  PASO 2 ✓ — Perfil predeterminado creado.');

    -- PASO 3: Registrar primer pago
    INSERT INTO PAGOS (
        id_usuario, fecha_pago, monto, metodo_pago,
        estado_pago, periodo_mes, periodo_anio
    ) VALUES (
        v_nuevo_id, SYSDATE, v_precio, 'PSE', 'EXITOSO',
        EXTRACT(MONTH FROM SYSDATE),
        EXTRACT(YEAR  FROM SYSDATE)
    );

    DBMS_OUTPUT.PUT_LINE('  PASO 3 ✓ — Primer pago ($' || v_precio || ') registrado.');

    -- ─────────────────────────────────────────────────────────────────────
    -- ESTADO: PARCIALMENTE CONFIRMADA — todos los DML ejecutados sin error
    -- ─────────────────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE('  ESTADO: PARCIALMENTE CONFIRMADA — confirming...');

    COMMIT;

    -- ─────────────────────────────────────────────────────────────────────
    -- ESTADO: CONFIRMADA — cambios permanentes en la base de datos
    -- ─────────────────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE('  ESTADO: CONFIRMADA ✓ — COMMIT ejecutado.');
    DBMS_OUTPUT.PUT_LINE('  Nuevo usuario "' || v_nombre || '" registrado con éxito.');
    DBMS_OUTPUT.PUT_LINE('');

-- ─── Manejo de errores ─────────────────────────────────────────────────────
EXCEPTION
    WHEN email_duplicado THEN
        -- ─────────────────────────────────────────────────────────────────
        -- ESTADO: FALLIDA → ABORTADA — error capturado, deshaciendo todo
        -- ─────────────────────────────────────────────────────────────────
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('  ESTADO: FALLIDA → ABORTADA — ROLLBACK ejecutado.');
        DBMS_OUTPUT.PUT_LINE('  CAUSA: El email "' || v_email || '" ya existe.');
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('  ESTADO: FALLIDA → ABORTADA — ROLLBACK ejecutado.');
        DBMS_OUTPUT.PUT_LINE('  CAUSA: ' || SQLERRM);
END;
/

-- Verificar que el usuario fue registrado
SELECT id_usuario, nombre_usuario, ciudad, estado_cuenta
FROM   USUARIOS
WHERE  email_usuario = 'carlos.mejia.txn1@gmail.com';


-- ============================================================================
-- TRANSACCIÓN 2 — RENOVACIÓN MENSUAL CON SAVEPOINT

-- Para cada usuario activo: calcular monto, registrar pago, actualizar estado
-- SAVEPOINT por usuario → si uno falla, los anteriores se conservan
-- ============================================================================
DECLARE
    CURSOR c_usuarios_activos IS
        SELECT u.id_usuario,
               u.nombre_usuario,
               u.email_usuario,
               p.nombre_plan,
               p.precio_mensual
        FROM   USUARIOS u
        JOIN   PLANES   p ON u.id_plan = p.id_plan
        WHERE  u.estado_cuenta = 'ACTIVO'
          AND  u.id_usuario   <= 10   -- Procesar solo primeros 10 para la demo
        ORDER  BY u.id_usuario;

    v_monto          NUMBER;
    v_sp_name        VARCHAR2(30);
    v_procesados     NUMBER := 0;
    v_exitosos       NUMBER := 0;
    v_fallidos       NUMBER := 0;
    v_total_ingresos NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('TRANSACCIÓN 2: Renovación Mensual — Estado: ACTIVA');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('Período: ' || TO_CHAR(SYSDATE, 'Month YYYY'));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));

    FOR reg IN c_usuarios_activos LOOP
        v_procesados := v_procesados + 1;

        -- Crear un SAVEPOINT por usuario (si este falla, rollback solo a él)
        v_sp_name := 'SP_USR_' || reg.id_usuario;
        SAVEPOINT sp_usuario_actual;

        BEGIN
            -- Calcular monto con descuentos usando la función del Núcleo 2
            v_monto := FN_CALCULAR_MONTO(reg.id_usuario);

            -- Verificar que se calculó correctamente
            IF v_monto <= 0 THEN
                RAISE_APPLICATION_ERROR(-20020, 'Monto inválido para usuario ' || reg.id_usuario);
            END IF;

            -- Insertar pago del período actual
            INSERT INTO PAGOS (
                id_usuario, fecha_pago, monto, metodo_pago,
                estado_pago, periodo_mes, periodo_anio
            ) VALUES (
                reg.id_usuario, SYSDATE, v_monto, 'TC', 'EXITOSO',
                EXTRACT(MONTH FROM SYSDATE),
                EXTRACT(YEAR  FROM SYSDATE)
            );

            -- Actualizar fecha del último pago
            UPDATE USUARIOS
            SET    fecha_ultimo_pago = SYSDATE
            WHERE  id_usuario = reg.id_usuario;

            -- SAVEPOINT intermedio confirmado (no hace COMMIT todavía)
            v_exitosos       := v_exitosos + 1;
            v_total_ingresos := v_total_ingresos + v_monto;

            DBMS_OUTPUT.PUT_LINE(
                '  ✓ ID=' || RPAD(reg.id_usuario, 4) ||
                RPAD(reg.nombre_usuario, 22) ||
                RPAD(reg.nombre_plan, 12) ||
                '$' || TO_CHAR(v_monto, 'FM999,999,990')
            );

        EXCEPTION
            WHEN OTHERS THEN
                -- Solo deshace este usuario, los anteriores se conservan
                ROLLBACK TO SAVEPOINT sp_usuario_actual;
                v_fallidos := v_fallidos + 1;
                DBMS_OUTPUT.PUT_LINE(
                    '  ✗ ID=' || reg.id_usuario ||
                    ' ' || reg.nombre_usuario ||
                    ' — REVERTIDO: ' || SQLERRM
                );
        END;

    END LOOP;

    -- ─────────────────────────────────────────────────────────────────────
    -- ESTADO: PARCIALMENTE CONFIRMADA — todos los usuarios procesados
    -- ─────────────────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    DBMS_OUTPUT.PUT_LINE('ESTADO: PARCIALMENTE CONFIRMADA — revisando totales...');
    DBMS_OUTPUT.PUT_LINE('Procesados : ' || v_procesados);
    DBMS_OUTPUT.PUT_LINE('Exitosos   : ' || v_exitosos);
    DBMS_OUTPUT.PUT_LINE('Fallidos   : ' || v_fallidos);
    DBMS_OUTPUT.PUT_LINE('Ingresos   : $' || TO_CHAR(v_total_ingresos, 'FM999,999,990'));

    -- Confirmar todos los pagos exitosos de una vez
    COMMIT;

    -- ─────────────────────────────────────────────────────────────────────
    -- ESTADO: CONFIRMADA — renovación mensual completada
    -- ─────────────────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE('ESTADO: CONFIRMADA ✓ — Renovación mensual completada.');
    DBMS_OUTPUT.PUT_LINE('');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ESTADO: FALLIDA → ABORTADA — Error crítico: ' || SQLERRM);
END;
/


-- ============================================================================
-- TRANSACCIÓN 3 — ELIMINACIÓN DE CUENTA (TODO O NADA)

-- Elimina todas las trazas de un usuario en orden correcto de dependencias
-- Un solo error = ROLLBACK de todo = cuenta intacta
-- ==========================================================================
DECLARE
    -- Se usa el usuario creado en la Transacción 1 de este mismo script
    v_id_usuario    NUMBER;
    v_nombre_usr    VARCHAR2(80);

    -- Contadores para el reporte
    v_calif_elim    NUMBER := 0;
    v_fav_elim      NUMBER := 0;
    v_repr_elim     NUMBER := 0;
    v_rep_elim      NUMBER := 0;
    v_perf_elim     NUMBER := 0;
    v_pago_elim     NUMBER := 0;

    usuario_no_encontrado EXCEPTION;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('TRANSACCIÓN 3: Eliminación de Cuenta — Estado: ACTIVA');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');

    -- Localizar el usuario a eliminar (creado en Transacción 1)
    BEGIN
        SELECT id_usuario, nombre_usuario
        INTO   v_id_usuario, v_nombre_usr
        FROM   USUARIOS
        WHERE  email_usuario = 'carlos.mejia.txn1@gmail.com';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE usuario_no_encontrado;
    END;

    DBMS_OUTPUT.PUT_LINE('Eliminando cuenta de: "' || v_nombre_usr
                      || '" (ID=' || v_id_usuario || ')');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 50, '-'));

    -- ─────────────────────────────────────────────────────────────────────
    -- PASO 1: Eliminar CALIFICACIONES de los perfiles del usuario
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM CALIFICACIONES
    WHERE  id_perfil IN (
        SELECT id_perfil FROM PERFILES WHERE id_usuario = v_id_usuario
    );
    v_calif_elim := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('  PASO 1 ✓ — Calificaciones eliminadas : ' || v_calif_elim);

    -- ─────────────────────────────────────────────────────────────────
    -- PASO 2: Eliminar FAVORITOS de los perfiles del usuario
    -- ─────────────────────────────────────────────────────────────────
    DELETE FROM FAVORITOS
    WHERE  id_perfil IN (
        SELECT id_perfil FROM PERFILES WHERE id_usuario = v_id_usuario
    );
    v_fav_elim := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('  PASO 2 ✓ — Favoritos eliminados      : ' || v_fav_elim);

    -- ─────────────────────────────────────────────────────────────────────
    -- PASO 3: Eliminar REPRODUCCIONES de los perfiles del usuario
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM REPRODUCCIONES
    WHERE  id_perfil IN (
        SELECT id_perfil FROM PERFILES WHERE id_usuario = v_id_usuario
    );
    v_repr_elim := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('  PASO 3 ✓ — Reproducciones eliminadas : ' || v_repr_elim);

    -- ─────────────────────────────────────────────────────────────────────
    -- PASO 4: Eliminar REPORTES creados por el usuario
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM REPORTES
    WHERE  id_usuario_reporta = v_id_usuario;
    v_rep_elim := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('  PASO 4 ✓ — Reportes eliminados       : ' || v_rep_elim);

    -- ─────────────────────────────────────────────────────────────────────
    -- PASO 5: Eliminar PERFILES del usuario
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM PERFILES
    WHERE  id_usuario = v_id_usuario;
    v_perf_elim := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('  PASO 5 ✓ — Perfiles eliminados       : ' || v_perf_elim);

    -- ─────────────────────────────────────────────────────────────────────
    -- PASO 6: Eliminar PAGOS del usuario
    -- ─────────────────────────────────────────────────────────────────────
    DELETE FROM PAGOS
    WHERE  id_usuario = v_id_usuario;
    v_pago_elim := SQL%ROWCOUNT;
    DBMS_OUTPUT.PUT_LINE('  PASO 6 ✓ — Pagos eliminados          : ' || v_pago_elim);

    -- ─────────────────────────────────────────────────────────────────────
    -- PASO 7: Eliminar el USUARIO (anular FK de referidor en otros usuarios)
    -- ─────────────────────────────────────────────────────────────────────
    UPDATE USUARIOS SET id_referidor = NULL
    WHERE  id_referidor = v_id_usuario;

    DELETE FROM USUARIOS
    WHERE  id_usuario = v_id_usuario;

    DBMS_OUTPUT.PUT_LINE('  PASO 7 ✓ — Usuario eliminado del sistema.');

    -- ─────────────────────────────────────────────────────────────────────
    -- ESTADO: PARCIALMENTE CONFIRMADA — todos los DELETE ejecutados
    -- ─────────────────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 50, '-'));
    DBMS_OUTPUT.PUT_LINE('ESTADO: PARCIALMENTE CONFIRMADA — confirmando...');

    COMMIT;

    -- ──────────────────────────────────────────────────────────────────
    -- ESTADO: CONFIRMADA — cuenta eliminada permanentemente
    -- ──────────────────────────────────────────────────────────────────
    DBMS_OUTPUT.PUT_LINE('ESTADO: CONFIRMADA ✓ — Cuenta eliminada definitivamente.');
    DBMS_OUTPUT.PUT_LINE('Total registros eliminados: '
        || (v_calif_elim + v_fav_elim + v_repr_elim
            + v_rep_elim + v_perf_elim + v_pago_elim + 1));
    DBMS_OUTPUT.PUT_LINE('');

-- ─── Manejo de errores — si algo falla, nada se elimina ───────────────────
EXCEPTION
    WHEN usuario_no_encontrado THEN
        -- No hay nada que revertir (no hubo DMLs)
        DBMS_OUTPUT.PUT_LINE('ESTADO: FALLIDA — Usuario no encontrado. Sin cambios.');
    WHEN OTHERS THEN
        -- ─────────────────────────────────────────────────────────────────
        -- ESTADO: FALLIDA → ABORTADA — error en medio de la eliminación
        -- La cuenta queda intacta gracias al ROLLBACK
        -- ─────────────────────────────────────────────────────────────────
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('ESTADO: FALLIDA → ABORTADA — ROLLBACK ejecutado.');
        DBMS_OUTPUT.PUT_LINE('CAUSA: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('La cuenta del usuario permanece intacta.');
END;
/

-- Verificar que el usuario fue eliminado
SELECT COUNT(*) AS usuario_aun_existe
FROM   USUARIOS
WHERE  email_usuario = 'carlos.mejia.txn1@gmail.com';


-- ============================================================================
-- SECCIÓN 3.3.2 — CONCURRENCIA DE DATOS: SELECT FOR UPDATE
-- ============================================================================
-- ESCENARIO: Dos sesiones intentan cambiar el plan del mismo usuario
--            simultáneamente (usuario ID=8, Daniel Cardona, Premium)
--
-- INSTRUCCIONES DE EJECUCIÓN:
--   1. Abrir DOS ventanas de SQL Developer conectadas a QuindioFlixBD
--   2. Ejecutar los pasos en el ORDEN indicado, alternando entre ventanas
--   3. Observar cómo Oracle gestiona el bloqueo automáticamente
-- ============================================================================

SELECT SYS_CONTEXT('USERENV','SID') AS mi_sesion_id FROM DUAL;
-- ════════════════════════════════════════════════════════════════════
-- SCRIPT SESIÓN A (ejecutar en la PRIMERA ventana de SQL Developer)
-- ════════════════════════════════════════════════════════════════════

-- PASO A1: Sesión A bloquea el registro del usuario 8
-- Ejecutar en Ventana 1
/*
SELECT id_usuario, nombre_usuario, id_plan, estado_cuenta
FROM   USUARIOS
WHERE  id_usuario = 8
FOR UPDATE;                          -- Bloqueo exclusivo sobre esta fila

-- En este momento la Sesión A tiene el lock sobre usuario 8.
-- La Sesión B intentará acceder y quedará ESPERANDO.
--
*/


-- ════════════════════════════════════════════════════════════════════
-- SCRIPT SESIÓN B (ejecutar en la SEGUNDA ventana de SQL Developer)
-- ════════════════════════════════════════════════════════════════════

-- PASO B1: Sesión B intenta bloquear el mismo usuario 8
-- Ejecutar en Ventana 2 DESPUÉS de que Sesión A ejecutó el FOR UPDATE
/*
SELECT id_usuario, nombre_usuario, id_plan
FROM   USUARIOS
WHERE  id_usuario = 8
FOR UPDATE;                          -- Sesión B QUEDA BLOQUEADA aquí
                                     -- Oracle la pone en cola de espera
                                     -- El cursor "gira" sin retornar
*/


-- ═════════════════════════════════════════════════════════════════
-- DE VUELTA A SESIÓN A — Completar la transacción
-- ═════════════════════════════════════════════════════════════════

-- PASO A2: Sesión A realiza el cambio y libera el lock con COMMIT
-- Ejecutar en Ventana 1 DESPUÉS de que Sesión B está esperando
/*
UPDATE USUARIOS
SET    id_plan = 2              -- Cambia de Premium (3) a Estándar (2)
WHERE  id_usuario = 8;

COMMIT;                        -- Libera el lock → Sesión B se desbloquea
*/

-- ════════════════════════════════════════════════════════════════════
-- RESULTADO ESPERADO en Sesión B
-- ════════════════════════════════════════════════════════════════════
-- Una vez que Sesión A hace COMMIT, la Sesión B obtiene el lock
-- y puede leer la fila (ya con id_plan=2)
-- Sesión B puede hacer su propio UPDATE o ROLLBACK


-- ════════════════════════════════════════════════════════════════════
-- DEMOSTRACIÓN: FOR UPDATE con NOWAIT

-- Versión que falla inmediatamente si el registro está bloqueado
-- En lugar de esperar indefinidamente
-- ════════════════════════════════════════════════════════════════════
DECLARE
    v_id_plan   NUMBER;
    v_nombre    VARCHAR2(80);
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('VARIANTE: SELECT FOR UPDATE NOWAIT');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('Si el registro ya está bloqueado por otra sesión,');
    DBMS_OUTPUT.PUT_LINE('NOWAIT falla inmediatamente con ORA-00054 en lugar');
    DBMS_OUTPUT.PUT_LINE('de quedar esperando indefinidamente.');
    DBMS_OUTPUT.PUT_LINE('');

    -- En escenario real, si Sesión B llega tarde, NOWAIT lanza error
    SELECT id_plan, nombre_usuario
    INTO   v_id_plan, v_nombre
    FROM   USUARIOS
    WHERE  id_usuario = 8
    FOR UPDATE NOWAIT;  -- Si hay lock → ORA-00054 inmediatamente

    DBMS_OUTPUT.PUT_LINE('Lock obtenido para "' || v_nombre || '" — Plan: ' || v_id_plan);
    DBMS_OUTPUT.PUT_LINE('Sesión puede proceder con el UPDATE.');

    ROLLBACK;  -- Liberar sin cambios para la demo

EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -54 THEN  -- ORA-00054: resource busy
            DBMS_OUTPUT.PUT_LINE('ORA-00054: Recurso ocupado — otra sesión tiene el lock.');
            DBMS_OUTPUT.PUT_LINE('NOWAIT rechazó la solicitud inmediatamente.');
            DBMS_OUTPUT.PUT_LINE('Aplicación puede manejar el error sin bloquear al usuario.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Error inesperado: ' || SQLERRM);
        END IF;
END;
/


-- ════════════════════════════════════════════════════════════════════
-- DEMOSTRACIÓN: FOR UPDATE con WAIT n
-- Espera máximo n segundos antes de lanzar error
-- ════════════════════════════════════════════════════════════════════
DECLARE
    v_id_plan   NUMBER;
    v_nombre    VARCHAR2(80);
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');
    DBMS_OUTPUT.PUT_LINE('VARIANTE: SELECT FOR UPDATE WAIT 5');
    DBMS_OUTPUT.PUT_LINE('═══════════════════════════════════════════════════');

    SELECT id_plan, nombre_usuario
    INTO   v_id_plan, v_nombre
    FROM   USUARIOS
    WHERE  id_usuario = 8
    FOR UPDATE WAIT 5;  -- Espera máximo 5 segundos, luego ORA-30006

    DBMS_OUTPUT.PUT_LINE('Lock obtenido para "' || v_nombre
        || '" en menos de 5 segundos.');

    ROLLBACK;

EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -30006 THEN  -- ORA-30006: resource busy, WAIT timeout
            DBMS_OUTPUT.PUT_LINE('ORA-30006: Timeout — lock no obtenido en 5 seg.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        END IF;
END;
/


-- ════════════════════════════════════════════════════════════════════
-- CONSULTA DIAGNÓSTICO: Ver bloqueos activos en el sistema
-- Útil para verificar en tiempo real quién tiene qué locked
-- ════════════════════════════════════════════════════════════════════
SELECT
    s.sid                           AS sesion_id,
    s.serial#                       AS serial,
    s.username                      AS usuario_oracle,
    s.status                        AS estado_sesion,
    l.type                          AS tipo_lock,
    DECODE(l.lmode,
        0,'Sin lock',
        1,'Nulo',
        2,'Row-S (SS)',
        3,'Row-X (SX)',
        4,'Compartido (S)',
        5,'S/Row-X (SSX)',
        6,'Exclusivo (X)'
    )                               AS modo_lock,
    l.request                       AS solicitando,
    o.object_name                   AS objeto_bloqueado
FROM   v$session s
JOIN   v$lock    l ON s.sid = l.sid
LEFT JOIN all_objects o ON l.id1 = o.object_id
WHERE  s.username = UPPER('quindioflix')
  AND  l.type IN ('TM','TX')
ORDER  BY s.sid;


-- ============================================================================
-- VERIFICACIÓN FINAL — NÚCLEO 3
-- ============================================================================

-- Resumen de pagos generados por la renovación mensual (Transacción 2)
SELECT
    p.nombre_plan,
    COUNT(*)                        AS pagos_renovacion,
    SUM(pg.monto)                   AS ingresos_generados
FROM   PAGOS    pg
JOIN   USUARIOS  u ON pg.id_usuario = u.id_usuario
JOIN   PLANES    p ON u.id_plan     = p.id_plan
WHERE  TRUNC(pg.fecha_pago) = TRUNC(SYSDATE)
  AND  pg.estado_pago       = 'EXITOSO'
GROUP  BY p.nombre_plan
ORDER  BY ingresos_generados DESC;

-- ====================================================================
-- FIN DEL SCRIPT — NÚCLEO 3 COMPLETADO
-- ====================================================================
