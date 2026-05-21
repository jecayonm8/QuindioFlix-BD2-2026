-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   05_QuindioFlix_Nucleo2_PLSQL.sql
-- Propósito: Núcleo Temático 2 — PL/SQL: Procedimientos y Disparadores

-- Este script se divide en Secciones:
--   3.2.1 Cursores              (2 cursores)
--   3.2.2 Procedimientos        (SP_REGISTRAR_USUARIO, SP_CAMBIAR_PLAN,
--                                SP_REPORTE_CONSUMO)
--   3.2.3 Funciones             (FN_CALCULAR_MONTO, FN_CONTENIDO_RECOMENDADO)
--   3.2.4 Excepciones           (integradas en SPs)
--   3.2.5 Disparadores          (4 triggers)

-- Ejecutar: Como quindioflix en QuindioFlixBD

-- Nota:     Aca se recomienda ejecutar sección por sección.
--           Cada bloque termina en / (barra) que indica fin de unidad PL/SQL.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ============================================================================
-- SECCIÓN 3.2.1 — CURSORES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CURSOR 1: Usuarios con suscripción vencida (mora > 30 días)
-- Genera reporte con nombre, email, plan, días mora y monto adeudado
-- ----------------------------------------------------------------------------
DECLARE
    CURSOR c_usuarios_mora IS
        SELECT u.id_usuario,
               u.nombre_usuario,
               u.email_usuario,
               p.nombre_plan,
               p.precio_mensual,
               u.fecha_ultimo_pago,
               TRUNC(SYSDATE - u.fecha_ultimo_pago) AS dias_mora
        FROM   USUARIOS u
        JOIN   PLANES   p ON u.id_plan = p.id_plan
        WHERE  u.estado_cuenta = 'INACTIVO'
          AND  TRUNC(SYSDATE - u.fecha_ultimo_pago) > 30
        ORDER  BY dias_mora DESC;

    v_total_usuarios NUMBER := 0;
    v_total_deuda    NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('╔══════════════════════════════════════════════════════════════╗');
    DBMS_OUTPUT.PUT_LINE('║        REPORTE DE USUARIOS CON MORA — QuindioFlix            ║');
    DBMS_OUTPUT.PUT_LINE('╚══════════════════════════════════════════════════════════════╝');
    DBMS_OUTPUT.PUT_LINE(RPAD('Nombre Usuario', 22)
        || RPAD('Email', 32)
        || RPAD('Plan', 12)
        || RPAD('Días mora', 11)
        || 'Monto adeudado');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));

    FOR reg IN c_usuarios_mora LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(reg.nombre_usuario,  22) ||
            RPAD(reg.email_usuario,   32) ||
            RPAD(reg.nombre_plan,     12) ||
            RPAD(TO_CHAR(reg.dias_mora), 11) ||
            '$' || TO_CHAR(reg.precio_mensual, 'FM999,999,990')
        );
        v_total_usuarios := v_total_usuarios + 1;
        v_total_deuda    := v_total_deuda    + reg.precio_mensual;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
    DBMS_OUTPUT.PUT_LINE('Total cuentas en mora : ' || v_total_usuarios);
    DBMS_OUTPUT.PUT_LINE('Deuda total pendiente : $' || TO_CHAR(v_total_deuda,'FM999,999,990'));
    DBMS_OUTPUT.PUT_LINE('');
END;
/


-- ----------------------------------------------------------------------------
-- CURSOR 2: Actualizar popularidad del catálogo

-- Recorre todo el contenido, cuenta reproducciones completas (>= 90%)
-- y actualiza el campo popularidad de cada registro en CONTENIDO
-- ----------------------------------------------------------------------------
DECLARE
    CURSOR c_catalogo IS
        SELECT c.id_contenido,
               c.titulo,
               cat.nombre_categoria,
               COUNT(CASE WHEN r.porcentaje_avance >= 90 THEN 1 END)
                   AS rep_completas,
               COUNT(r.id_reproduccion) AS total_reproducciones
        FROM   CONTENIDO      c
        JOIN   CATEGORIAS     cat ON c.id_categoria  = cat.id_categoria
        LEFT JOIN REPRODUCCIONES r ON c.id_contenido = r.id_contenido
        GROUP  BY c.id_contenido, c.titulo, cat.nombre_categoria
        ORDER  BY rep_completas DESC;

    v_actualizados NUMBER := 0;
    v_con_data     NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('╔══════════════════════════════════════════════════════════════╗');
    DBMS_OUTPUT.PUT_LINE('║       ACTUALIZACIÓN DE POPULARIDAD — Catálogo QuindioFlix    ║');
    DBMS_OUTPUT.PUT_LINE('╚══════════════════════════════════════════════════════════════╝');
    DBMS_OUTPUT.PUT_LINE(RPAD('Título', 38) || RPAD('Categoría', 15)
        || RPAD('Completas', 11) || 'Total reprod.');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

    FOR reg IN c_catalogo LOOP
        -- Actualizar popularidad con número de reproducciones completas
        UPDATE CONTENIDO
        SET    popularidad = reg.rep_completas
        WHERE  id_contenido = reg.id_contenido;

        v_actualizados := v_actualizados + 1;

        -- Mostrar solo los que tienen reproducciones
        IF reg.total_reproducciones > 0 THEN
            DBMS_OUTPUT.PUT_LINE(
                RPAD(SUBSTR(reg.titulo, 1, 37), 38) ||
                RPAD(reg.nombre_categoria, 15)       ||
                RPAD(TO_CHAR(reg.rep_completas), 11) ||
                TO_CHAR(reg.total_reproducciones)
            );
            v_con_data := v_con_data + 1;
        END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
    DBMS_OUTPUT.PUT_LINE('Contenidos actualizados : ' || v_actualizados);
    DBMS_OUTPUT.PUT_LINE('Contenidos con datos    : ' || v_con_data);
    DBMS_OUTPUT.PUT_LINE('');
END;
/


-- ============================================================================
-- SECCIÓN 3.2.2 — PROCEDIMIENTOS ALMACENADOS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROCEDIMIENTO 1: SP_REGISTRAR_USUARIO
-- Registra un nuevo usuario con validación de email y plan.

-- Crea automáticamente el perfil predeterminado y el primer pago.

-- EXCEPCIONES manejadas (sección 3.2.4):
--   email_duplicado (-20001): el email ya está registrado
--   plan_invalido   (-20002): el id_plan no existe en PLANES
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_USUARIO(
    p_nombre       IN  VARCHAR2,
    p_email        IN  VARCHAR2,
    p_telefono     IN  VARCHAR2,
    p_fecha_nac    IN  DATE,
    p_ciudad       IN  VARCHAR2,
    p_id_plan      IN  NUMBER,
    p_id_referidor IN  NUMBER    DEFAULT NULL,
    p_resultado    OUT VARCHAR2
) AS
    v_count_email  NUMBER;
    v_count_plan   NUMBER;
    v_precio       NUMBER;
    v_nuevo_id     NUMBER;

    -- Declaración de excepciones personalizadas
    email_duplicado EXCEPTION;
    plan_invalido   EXCEPTION;
    PRAGMA EXCEPTION_INIT(email_duplicado, -20001);
    PRAGMA EXCEPTION_INIT(plan_invalido,   -20002);
BEGIN
    -- ── Validación 1: Email único ─────────────────────────────────────
    SELECT COUNT(*) INTO v_count_email
    FROM   USUARIOS
    WHERE  email_usuario = p_email;

    IF v_count_email > 0 THEN
        RAISE email_duplicado;
    END IF;

    -- ── Validación 2: Plan existente ───────────────────────────────────
    SELECT COUNT(*), MAX(precio_mensual)
    INTO   v_count_plan, v_precio
    FROM   PLANES
    WHERE  id_plan = p_id_plan;

    IF v_count_plan = 0 THEN
        RAISE plan_invalido;
    END IF;

    -- ── Paso 1: Insertar usuario ───────────────────────────────────────
    INSERT INTO USUARIOS (
        nombre_usuario, email_usuario, telefono, fecha_nacimiento,
        ciudad, fecha_registro, estado_cuenta, fecha_ultimo_pago,
        id_plan, id_referidor, es_moderador
    ) VALUES (
        p_nombre, p_email, p_telefono, p_fecha_nac,
        p_ciudad, SYSDATE, 'ACTIVO', SYSDATE,
        p_id_plan, p_id_referidor, 'N'
    )
    RETURNING id_usuario INTO v_nuevo_id;

    -- ── Paso 2: Crear perfil predeterminado ───────────────────────────────
    INSERT INTO PERFILES (
        id_usuario, nombre_perfil, avatar, tipo_perfil, fecha_creacion
    ) VALUES (
        v_nuevo_id, p_nombre, 'avatar_default.png', 'adulto', SYSDATE
    );

    -- ── Paso 3: Registrar primer pago ───────────────────────────────────
    INSERT INTO PAGOS (
        id_usuario, fecha_pago, monto, metodo_pago,
        estado_pago, periodo_mes, periodo_anio
    ) VALUES (
        v_nuevo_id, SYSDATE, v_precio, 'PSE', 'EXITOSO',
        EXTRACT(MONTH FROM SYSDATE),
        EXTRACT(YEAR  FROM SYSDATE)
    );

    COMMIT;
    p_resultado := 'OK: Usuario "' || p_nombre || '" registrado. ID=' || v_nuevo_id;

-- ── Manejo de excepciones ────────────────────────────────────────────────
EXCEPTION
    WHEN email_duplicado THEN
        ROLLBACK;
        p_resultado := 'ERROR-20001: El email "' || p_email
                    || '" ya está registrado en el sistema.';
    WHEN plan_invalido THEN
        ROLLBACK;
        p_resultado := 'ERROR-20002: El plan con ID=' || p_id_plan
                    || ' no existe. Use 1=Básico, 2=Estándar, 3=Premium.';
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'ERROR-' || SQLCODE || ': ' || SQLERRM;
END SP_REGISTRAR_USUARIO;
/


-- ----------------------------------------------------------------------------
-- PROCEDIMIENTO 2: SP_CAMBIAR_PLAN
-- Cambia el plan de suscripción de un usuario.

-- Valida que si es degradación, el usuario no tenga más perfiles
-- de los que permite el nuevo plan.

-- EXCEPCIÓN manejada (sección 3.2.4):
--   perfiles_excedidos (-20003): tiene más perfiles de los permitidos
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_CAMBIAR_PLAN(
    p_id_usuario    IN  NUMBER,
    p_id_plan_nuevo IN  NUMBER,
    p_resultado     OUT VARCHAR2
) AS
    v_plan_actual    NUMBER;
    v_max_perf_nuevo NUMBER;
    v_perf_actuales  NUMBER;
    v_nombre_plan    VARCHAR2(20);
    v_precio_nuevo   NUMBER;

    perfiles_excedidos EXCEPTION;
    PRAGMA EXCEPTION_INIT(perfiles_excedidos, -20003);
BEGIN
    -- ── Obtener plan actual del usuario ───────────────────────────────
    SELECT id_plan INTO v_plan_actual
    FROM   USUARIOS
    WHERE  id_usuario = p_id_usuario;

    -- ── Obtener datos del nuevo plan ──────────────────────────────────
    SELECT max_perfiles, nombre_plan, precio_mensual
    INTO   v_max_perf_nuevo, v_nombre_plan, v_precio_nuevo
    FROM   PLANES
    WHERE  id_plan = p_id_plan_nuevo;

    -- ── Contar perfiles actuales del usuario ─────────────────────────
    SELECT COUNT(*) INTO v_perf_actuales
    FROM   PERFILES
    WHERE  id_usuario = p_id_usuario;

    -- ── Validación: no puede degradar si tiene más perfiles de los permitidos
    IF v_perf_actuales > v_max_perf_nuevo THEN
        RAISE perfiles_excedidos;
    END IF;

    -- ── Actualizar plan ──────────────────────────────────────────
    UPDATE USUARIOS
    SET    id_plan = p_id_plan_nuevo
    WHERE  id_usuario = p_id_usuario;

    -- ── Registrar el próximo pago pendiente con el nuevo precio ──────────
    INSERT INTO PAGOS (
        id_usuario, fecha_pago, monto, metodo_pago,
        estado_pago, periodo_mes, periodo_anio
    ) VALUES (
        p_id_usuario, SYSDATE, v_precio_nuevo, 'TC', 'PENDIENTE',
        EXTRACT(MONTH FROM ADD_MONTHS(SYSDATE, 1)),
        EXTRACT(YEAR  FROM ADD_MONTHS(SYSDATE, 1))
    );

    COMMIT;
    p_resultado := 'OK: Plan cambiado a "' || v_nombre_plan
               || '" para usuario ID=' || p_id_usuario
               || '. Próximo pago: $' || v_precio_nuevo;

-- ── Manejo de excepciones ─────────────────────────────────────────
EXCEPTION
    WHEN perfiles_excedidos THEN
        ROLLBACK;
        p_resultado := 'ERROR-20003: El usuario tiene ' || v_perf_actuales
                    || ' perfil(es) activos, pero el plan "' || v_nombre_plan
                    || '" solo permite ' || v_max_perf_nuevo
                    || '. Elimine ' || (v_perf_actuales - v_max_perf_nuevo)
                    || ' perfil(es) antes de degradar.';
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        p_resultado := 'ERROR: Usuario ID=' || p_id_usuario
                    || ' o Plan ID=' || p_id_plan_nuevo || ' no encontrado.';
    WHEN OTHERS THEN
        ROLLBACK;
        p_resultado := 'ERROR-' || SQLCODE || ': ' || SQLERRM;
END SP_CAMBIAR_PLAN;
/


-- ----------------------------------------------------------------------------
-- PROCEDIMIENTO 3: SP_REPORTE_CONSUMO

-- Genera reporte de reproducciones de cada perfil de un usuario
-- en un rango de fechas, agrupadas por categoría con tiempo total
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REPORTE_CONSUMO(
    p_id_usuario   IN NUMBER,
    p_fecha_inicio IN DATE,
    p_fecha_fin    IN DATE
) AS
    v_nombre_usuario VARCHAR2(80);
    v_plan           VARCHAR2(20);
    v_total_min      NUMBER := 0;
    v_total_rep      NUMBER := 0;

    CURSOR c_consumo IS
        SELECT pf.nombre_perfil,
               pf.tipo_perfil,
               cat.nombre_categoria,
               COUNT(r.id_reproduccion)
                   AS reproducciones,
               ROUND(SUM(c.duracion_min * r.porcentaje_avance / 100))
                   AS minutos_consumidos,
               ROUND(AVG(r.porcentaje_avance), 1)
                   AS avance_promedio
        FROM   PERFILES       pf
        JOIN   REPRODUCCIONES r   ON pf.id_perfil    = r.id_perfil
        JOIN   CONTENIDO      c   ON r.id_contenido  = c.id_contenido
        JOIN   CATEGORIAS     cat ON c.id_categoria  = cat.id_categoria
        WHERE  pf.id_usuario = p_id_usuario
          AND  TRUNC(r.fecha_inicio) BETWEEN p_fecha_inicio AND p_fecha_fin
        GROUP  BY pf.nombre_perfil, pf.tipo_perfil, cat.nombre_categoria
        ORDER  BY pf.nombre_perfil, minutos_consumidos DESC;
BEGIN
    -- Obtener datos del usuario
    SELECT u.nombre_usuario, p.nombre_plan
    INTO   v_nombre_usuario, v_plan
    FROM   USUARIOS u
    JOIN   PLANES   p ON u.id_plan = p.id_plan
    WHERE  u.id_usuario = p_id_usuario;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('╔═══════════════════════════════════════════════════════════╗');
    DBMS_OUTPUT.PUT_LINE('║           REPORTE DE CONSUMO — QuindioFlix                ║');
    DBMS_OUTPUT.PUT_LINE('╚═══════════════════════════════════════════════════════════╝');
    DBMS_OUTPUT.PUT_LINE('Usuario : ' || v_nombre_usuario || ' (ID=' || p_id_usuario || ')');
    DBMS_OUTPUT.PUT_LINE('Plan    : ' || v_plan);
    DBMS_OUTPUT.PUT_LINE('Período : ' || TO_CHAR(p_fecha_inicio,'DD/MM/YYYY')
                      || ' al '    || TO_CHAR(p_fecha_fin,  'DD/MM/YYYY'));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 72, '-'));
    DBMS_OUTPUT.PUT_LINE(
        RPAD('Perfil',    16) ||
        RPAD('Tipo',      10) ||
        RPAD('Categoría', 16) ||
        RPAD('Reproduc.', 11) ||
        RPAD('Minutos',   10) ||
        'Avance%'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 72, '-'));

    FOR reg IN c_consumo LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(reg.nombre_perfil,    16) ||
            RPAD(reg.tipo_perfil,      10) ||
            RPAD(reg.nombre_categoria, 16) ||
            RPAD(TO_CHAR(reg.reproducciones),    11) ||
            RPAD(TO_CHAR(reg.minutos_consumidos), 10) ||
            reg.avance_promedio || '%'
        );
        v_total_min := v_total_min + NVL(reg.minutos_consumidos, 0);
        v_total_rep := v_total_rep + reg.reproducciones;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 72, '-'));
    DBMS_OUTPUT.PUT_LINE('Total reproducciones  : ' || v_total_rep);
    DBMS_OUTPUT.PUT_LINE('Total tiempo consumido: ' || v_total_min
        || ' min (' || ROUND(v_total_min / 60, 1) || ' horas)');
    DBMS_OUTPUT.PUT_LINE('');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Usuario con ID=' || p_id_usuario || ' no encontrado.');
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END SP_REPORTE_CONSUMO;
/


-- ============================================================================
-- SECCIÓN 3.2.3 — FUNCIONES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- FUNCIÓN 1: FN_CALCULAR_MONTO

-- Calcula el monto a cobrar en el próximo mes aplicando descuentos:
--   · Antigüedad > 24 meses → 15% descuento
--   · Antigüedad > 12 meses → 10% descuento
--   · Tiene referido activo → 5% descuento adicional (si no llega al 10%)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_CALCULAR_MONTO(
    p_id_usuario IN NUMBER
) RETURN NUMBER AS
    v_precio_base   NUMBER;
    v_meses         NUMBER;
    v_nombre_plan   VARCHAR2(20);
    v_tiene_referido NUMBER;
    v_descuento     NUMBER := 0;
    v_monto_final   NUMBER;
BEGIN
    -- Obtener precio del plan y antigüedad en meses
    SELECT p.precio_mensual,
           p.nombre_plan,
           MONTHS_BETWEEN(SYSDATE, u.fecha_registro)
    INTO   v_precio_base, v_nombre_plan, v_meses
    FROM   USUARIOS u
    JOIN   PLANES   p ON u.id_plan = p.id_plan
    WHERE  u.id_usuario = p_id_usuario;

    -- Calcular descuento por antigüedad (Regla de Negocio RN-07)
    IF v_meses > 24 THEN
        v_descuento := 0.15;  -- 15% para >24 meses
    ELSIF v_meses > 12 THEN
        v_descuento := 0.10;  -- 10% para >12 meses
    END IF;

    -- Descuento adicional por referido activo (Regla de Negocio RN-06)
    SELECT COUNT(*) INTO v_tiene_referido
    FROM   USUARIOS
    WHERE  id_referidor  = p_id_usuario
      AND  estado_cuenta = 'ACTIVO';

    IF v_tiene_referido > 0 AND v_descuento < 0.10 THEN
        v_descuento := v_descuento + 0.05;
    END IF;

    v_monto_final := ROUND(v_precio_base * (1 - v_descuento), 0);

    -- Log informativo
    DBMS_OUTPUT.PUT_LINE(
        'Plan: '      || v_nombre_plan       ||
        ' | Base: $'  || v_precio_base       ||
        ' | Meses: '  || ROUND(v_meses)      ||
        ' | Desc: '   || (v_descuento * 100) || '%' ||
        ' | Final: $' || v_monto_final
    );

    RETURN v_monto_final;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('ERROR FN_CALCULAR_MONTO: usuario ' || p_id_usuario || ' no existe.');
        RETURN -1;
END FN_CALCULAR_MONTO;
/


-- ----------------------------------------------------------------------------
-- FUNCIÓN 2: FN_CONTENIDO_RECOMENDADO
-- Recibe un id de perfil y retorna el título del contenido más afín
-- basado en el género que más ha reproducido ese perfil,
-- excluyendo contenido ya visto por el perfil
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_CONTENIDO_RECOMENDADO(
    p_id_perfil IN NUMBER
) RETURN VARCHAR2 AS
    v_titulo        VARCHAR2(150);
    v_genero_top    NUMBER;
    v_nombre_genero VARCHAR2(30);
    v_tipo_perfil   VARCHAR2(10);
BEGIN
    -- Verificar tipo de perfil (infantil solo ve TP,+7,+13)
    SELECT tipo_perfil INTO v_tipo_perfil
    FROM   PERFILES
    WHERE  id_perfil = p_id_perfil;

    -- Encontrar el género más reproducido por el perfil
    SELECT cg.id_genero INTO v_genero_top
    FROM   REPRODUCCIONES    r
    JOIN   CONTENIDO_GENERO  cg ON r.id_contenido = cg.id_contenido
    WHERE  r.id_perfil = p_id_perfil
    GROUP  BY cg.id_genero
    ORDER  BY COUNT(*) DESC
    FETCH  FIRST 1 ROWS ONLY;

    SELECT nombre_genero INTO v_nombre_genero
    FROM   GENEROS WHERE id_genero = v_genero_top;

    -- Recomendar el contenido mejor calificado de ese género
    -- que el perfil aún no haya visto
    SELECT c.titulo INTO v_titulo
    FROM   CONTENIDO        c
    JOIN   CONTENIDO_GENERO cg ON c.id_contenido = cg.id_contenido
    WHERE  cg.id_genero = v_genero_top
    -- Filtro de clasificación para perfiles infantiles
    AND (
        v_tipo_perfil = 'adulto'
        OR (v_tipo_perfil = 'infantil'
            AND c.clasificacion_edad IN ('TP', '+7', '+13'))
    )
    -- Excluir contenido ya visto por el perfil
    AND c.id_contenido NOT IN (
        SELECT r2.id_contenido
        FROM   REPRODUCCIONES r2
        WHERE  r2.id_perfil = p_id_perfil
    )
    -- Ordenar por calificación promedio (mejor primero)
    ORDER BY (
        SELECT NVL(AVG(cal.estrellas), 0)
        FROM   CALIFICACIONES cal
        WHERE  cal.id_contenido = c.id_contenido
    ) DESC NULLS LAST, c.titulo
    FETCH FIRST 1 ROWS ONLY;

    DBMS_OUTPUT.PUT_LINE('Perfil ' || p_id_perfil
        || ' | Género favorito: ' || v_nombre_genero
        || ' | Recomendado: "' || v_titulo || '"');

    RETURN v_titulo;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'No hay recomendaciones disponibles para este perfil';
    WHEN OTHERS THEN
        RETURN 'Error al generar recomendación: ' || SQLERRM;
END FN_CONTENIDO_RECOMENDADO;
/


-- ============================================================================
-- SECCIÓN 3.2.5 — DISPARADORES (TRIGGERS)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TRIGGER 1: TRG_VALIDAR_CUENTA_ACTIVA
-- Nivel de FILA — BEFORE INSERT en REPRODUCCIONES

-- Verifica que el usuario dueño del perfil tenga cuenta ACTIVA
-- Si la cuenta está INACTIVA → rechaza la inserción
-- Aca se utiliza la Regla de Negocio: RN-14
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VALIDAR_CUENTA_ACTIVA
BEFORE INSERT ON REPRODUCCIONES
FOR EACH ROW
DECLARE
    v_estado_cuenta VARCHAR2(10);
    v_id_usuario    NUMBER;
    v_nombre_usr    VARCHAR2(80);
BEGIN
    -- Obtener el usuario dueño del perfil
    SELECT p.id_usuario INTO v_id_usuario
    FROM   PERFILES p
    WHERE  p.id_perfil = :NEW.id_perfil;

    -- Verificar estado de la cuenta
    SELECT estado_cuenta, nombre_usuario
    INTO   v_estado_cuenta, v_nombre_usr
    FROM   USUARIOS
    WHERE  id_usuario = v_id_usuario;

    IF v_estado_cuenta != 'ACTIVO' THEN
        RAISE_APPLICATION_ERROR(-20010,
            'TRG_VALIDAR_CUENTA_ACTIVA: La cuenta del usuario "'
            || v_nombre_usr || '" está ' || v_estado_cuenta
            || '. Solo las cuentas ACTIVAS pueden reproducir contenido. (RN-14)');
    END IF;
END TRG_VALIDAR_CUENTA_ACTIVA;
/


-- ----------------------------------------------------------------------------
-- TRIGGER 2: TRG_LIMITE_PERFILES
-- Nivel de FILA — BEFORE INSERT en PERFILES

-- Verifica que el usuario no exceda el máximo de perfiles de su plan
-- Básico: máx 2 | Estándar: máx 3 | Premium: máx 5
-- Si excede → rechaza la inserción
-- Aca se utiliza la Regla de Negocio: RN-02
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_LIMITE_PERFILES
BEFORE INSERT ON PERFILES
FOR EACH ROW
DECLARE
    v_max_perfiles  NUMBER;
    v_perf_actuales NUMBER;
    v_nombre_plan   VARCHAR2(20);
BEGIN
    -- Obtener máximo de perfiles del plan del usuario
    SELECT pl.max_perfiles, pl.nombre_plan
    INTO   v_max_perfiles, v_nombre_plan
    FROM   USUARIOS  u
    JOIN   PLANES    pl ON u.id_plan = pl.id_plan
    WHERE  u.id_usuario = :NEW.id_usuario;

    -- Contar perfiles actuales (excluyendo el que se está insertando)
    SELECT COUNT(*) INTO v_perf_actuales
    FROM   PERFILES
    WHERE  id_usuario = :NEW.id_usuario;

    IF v_perf_actuales >= v_max_perfiles THEN
        RAISE_APPLICATION_ERROR(-20011,
            'TRG_LIMITE_PERFILES: El plan "' || v_nombre_plan
            || '" permite máximo ' || v_max_perfiles || ' perfil(es). '
            || 'El usuario ya tiene ' || v_perf_actuales
            || '. No se puede agregar más. (RN-02)');
    END IF;
END TRG_LIMITE_PERFILES;
/


-- ----------------------------------------------------------------------------
-- TRIGGER 3: TRG_VALIDAR_CALIFICACION
-- Nivel de FILA — BEFORE INSERT en CALIFICACIONES

-- Verifica que el perfil haya reproducido al menos el 50% del contenido
-- antes de permitir una calificación
-- Si no cumple → rechaza la inserción
-- Aca se aplica la Regla de Negocio: RN-05
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VALIDAR_CALIFICACION
BEFORE INSERT ON CALIFICACIONES
FOR EACH ROW
DECLARE
    v_max_avance NUMBER;
    v_titulo     VARCHAR2(150);
BEGIN
    -- Buscar el máximo porcentaje de avance del perfil en ese contenido
    SELECT MAX(r.porcentaje_avance)
    INTO   v_max_avance
    FROM   REPRODUCCIONES r
    WHERE  r.id_perfil    = :NEW.id_perfil
      AND  r.id_contenido = :NEW.id_contenido;

    -- Obtener título del contenido para el mensaje de error
    SELECT titulo INTO v_titulo
    FROM   CONTENIDO WHERE id_contenido = :NEW.id_contenido;

    IF v_max_avance IS NULL OR v_max_avance < 50 THEN
        RAISE_APPLICATION_ERROR(-20012,
            'TRG_VALIDAR_CALIFICACION: El perfil ID=' || :NEW.id_perfil
            || ' debe haber reproducido al menos el 50% de "'
            || v_titulo || '" para calificarlo. '
            || 'Avance máximo registrado: '
            || NVL(TO_CHAR(v_max_avance), '0') || '%. (RN-05)');
    END IF;
END TRG_VALIDAR_CALIFICACION;
/


-- ----------------------------------------------------------------------------
-- TRIGGER 4: TRG_ACTIVAR_CUENTA_PAGO
-- Nivel de SENTENCIA — AFTER INSERT en PAGOS

-- Después de insertar un pago, actualiza estado_cuenta='ACTIVO'
-- y fecha_ultimo_pago para todos los usuarios que tengan
-- un pago EXITOSO recién insertado y su cuenta no esté ACTIVA
-- Aca se aplica la Regla de Negocio: RN-04 (reactivación de cuentas)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_ACTIVAR_CUENTA_PAGO
AFTER INSERT ON PAGOS
BEGIN
    -- Reactivar cuentas de usuarios que tienen pago EXITOSO de hoy
    UPDATE USUARIOS u
    SET    u.estado_cuenta     = 'ACTIVO',
           u.fecha_ultimo_pago = SYSDATE
    WHERE  u.estado_cuenta    != 'ACTIVO'
      AND  EXISTS (
              SELECT 1 FROM PAGOS pg
              WHERE  pg.id_usuario  = u.id_usuario
                AND  pg.estado_pago = 'EXITOSO'
                AND  TRUNC(pg.fecha_pago) = TRUNC(SYSDATE)
           );

    IF SQL%ROWCOUNT > 0 THEN
        DBMS_OUTPUT.PUT_LINE('TRG_ACTIVAR_CUENTA_PAGO: '
            || SQL%ROWCOUNT || ' cuenta(s) reactivadas correctamente.');
    END IF;
END TRG_ACTIVAR_CUENTA_PAGO;
/


-- =========================================================================
-- SECCIÓN DE PRUEBAS — Verificar que todo funciona correctamente
-- =========================================================================

-- ── PRUEBA CURSORES ──────────────────────────────────────────────────────
-- (Aca ya se ejecutaron arriba al declarar los bloques DECLARE...BEGIN...END)
-- Para re-ejecutarlos, copiar el bloque y ejecutar con F5


-- ── PRUEBA SP_REGISTRAR_USUARIO (procedimiento almacenado) ──────────────────

-- CASO 1: Registro exitoso de usuario nuevo
DECLARE
    v_resultado VARCHAR2(500);
BEGIN
    SP_REGISTRAR_USUARIO(
        p_nombre       => 'Prueba Nuevo Usuario',
        p_email        => 'nuevo.usuario@test.com',
        p_telefono     => '3001112233',
        p_fecha_nac    => DATE '1998-03-20',
        p_ciudad       => 'Armenia',
        p_id_plan      => 2,       -- Indica el Plan Estándar
        p_id_referidor => 1,       -- Referido por usuario 1
        p_resultado    => v_resultado
    );
    DBMS_OUTPUT.PUT_LINE('CASO 1 — ' || v_resultado);
END;
/

-- CASO 2: Email duplicado → debe fallar con ERROR-20001
DECLARE
    v_resultado VARCHAR2(500);
BEGIN
    SP_REGISTRAR_USUARIO(
        p_nombre    => 'Intento Duplicado',
        p_email     => 'juliana.ospina@gmail.com',  -- email ya existe (Es el email del usuario 1)
        p_telefono  => '3009999999',
        p_fecha_nac => DATE '1990-01-01',
        p_ciudad    => 'Bogotá',
        p_id_plan   => 1,
        p_resultado => v_resultado
    );
    DBMS_OUTPUT.PUT_LINE('CASO 2 — ' || v_resultado);
END;
/

-- CASO 3: Plan inválido → debe fallar con ERROR-20002
DECLARE
    v_resultado VARCHAR2(500);
BEGIN
    SP_REGISTRAR_USUARIO(
        p_nombre    => 'Usuario Plan Malo',
        p_email     => 'plan.malo@test.com',
        p_telefono  => '3008888888',
        p_fecha_nac => DATE '1995-06-15',
        p_ciudad    => 'Cali',
        p_id_plan   => 99,         -- plan inexistente
        p_resultado => v_resultado
    );
    DBMS_OUTPUT.PUT_LINE('CASO 3 — ' || v_resultado);
END;
/


-- ── PRUEBA SP_CAMBIAR_PLAN ────────────────────────────────────────────────

-- CASO 1: Cambio exitoso — usuario 1 (Básico, 2 perfiles) sube a Premium
DECLARE
    v_resultado VARCHAR2(500);
BEGIN
    SP_CAMBIAR_PLAN(
        p_id_usuario    => 1,
        p_id_plan_nuevo => 3,    -- cambio a Premium
        p_resultado     => v_resultado
    );
    DBMS_OUTPUT.PUT_LINE('CAMBIO PLAN OK — ' || v_resultado);
    -- Revertir para no afectar otros tests
    UPDATE USUARIOS SET id_plan = 1 WHERE id_usuario = 1;
    COMMIT;
END;
/

-- CASO 2: Degradación bloqueada — usuario 18 (Premium, 5 perfiles) baja a Básico
-- Debe fallar ERROR-20003 porque tiene 5 perfiles y Básico solo permite 2
DECLARE
    v_resultado VARCHAR2(500);
BEGIN
    SP_CAMBIAR_PLAN(
        p_id_usuario    => 18,
        p_id_plan_nuevo => 1,    -- Básico (max 2 perfiles)
        p_resultado     => v_resultado
    );
    DBMS_OUTPUT.PUT_LINE('CAMBIO PLAN BLOQUEADO — ' || v_resultado);
END;
/


-- ── PRUEBA SP_REPORTE_CONSUMO ─────────────────────────────────────────────

-- Reporte de usuario 8 (Daniel Cardona, Premium, Bogotá) — rango amplio
BEGIN
    SP_REPORTE_CONSUMO(
        p_id_usuario   => 8,
        p_fecha_inicio => DATE '2024-01-01',
        p_fecha_fin    => DATE '2026-12-31'
    );
END;
/


-- ── PRUEBA FN_CALCULAR_MONTO ─────────────────────────────────────────────

-- Calcular montos para varios usuarios (distintas antigüedades y planes)
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== CÁLCULO DE MONTOS PRÓXIMO MES ===');
    DBMS_OUTPUT.PUT_LINE('Usuario 1  (Básico):   $' || FN_CALCULAR_MONTO(1));
    DBMS_OUTPUT.PUT_LINE('Usuario 5  (Estándar): $' || FN_CALCULAR_MONTO(5));
    DBMS_OUTPUT.PUT_LINE('Usuario 8  (Premium):  $' || FN_CALCULAR_MONTO(8));
    DBMS_OUTPUT.PUT_LINE('Usuario 18 (Premium):  $' || FN_CALCULAR_MONTO(18));
    DBMS_OUTPUT.PUT_LINE('Usuario 30 (Premium):  $' || FN_CALCULAR_MONTO(30));
END;
/


-- ── PRUEBA FN_CONTENIDO_RECOMENDADO ──────────────────────────────────────

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== RECOMENDACIONES PERSONALIZADAS ===');
    DBMS_OUTPUT.PUT_LINE('Perfil  1 (Juliana):  ' || FN_CONTENIDO_RECOMENDADO(1));
    DBMS_OUTPUT.PUT_LINE('Perfil 15 (Daniel):   ' || FN_CONTENIDO_RECOMENDADO(15));
    DBMS_OUTPUT.PUT_LINE('Perfil 32 (Isabella): ' || FN_CONTENIDO_RECOMENDADO(32));
    DBMS_OUTPUT.PUT_LINE('Perfil 38 (Santiago): ' || FN_CONTENIDO_RECOMENDADO(38));
END;
/


-- ── PRUEBA TRG_VALIDAR_CUENTA_ACTIVA ─────────────────────────────────────────
-- Usuario 3 (Fernanda Niño) está INACTIVO → su perfil 4 no puede reproducir

-- Debe fallar con TRG_VALIDAR_CUENTA_ACTIVA
BEGIN
    INSERT INTO REPRODUCCIONES
    VALUES (201, 4, 5, NULL,
            TIMESTAMP '2026-05-01 10:00:00',
            TIMESTAMP '2026-05-01 11:00:00',
            'celular', 60);
    DBMS_OUTPUT.PUT_LINE('ERROR: El trigger debería haber bloqueado esto.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TRIGGER OK — Reproducción bloqueada: ' || SQLERRM);
END;
/


-- ── PRUEBA TRG_LIMITE_PERFILES ────────────────────────────────────────────────
-- Usuario 3 (Básico, max 2) ya tiene 2 perfiles → no puede agregar más

BEGIN
    INSERT INTO PERFILES (id_usuario, nombre_perfil, avatar, tipo_perfil, fecha_creacion)
    VALUES (3, 'PerfilExtra', 'av_test.png', 'adulto', SYSDATE);
    DBMS_OUTPUT.PUT_LINE('ERROR: El trigger debería haber bloqueado esto.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TRIGGER OK — Perfil extra bloqueado: ' || SQLERRM);
END;
/


-- ── PRUEBA TRG_VALIDAR_CALIFICACION ──────────────────────────────────────────
-- Perfil 55 (Hernán-Docs, usuario 24) no tiene ninguna reproducción
-- → no puede calificar ningún contenido

BEGIN
    INSERT INTO CALIFICACIONES (id_perfil, id_contenido, estrellas, resena, fecha_calif)
    VALUES (55, 30, 5, 'Excelente sin haberla visto', SYSDATE);
    DBMS_OUTPUT.PUT_LINE('ERROR: El trigger debería haber bloqueado esto.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('TRIGGER OK — Calificación bloqueada: ' || SQLERRM);
END;
/


-- ── PRUEBA TRG_ACTIVAR_CUENTA_PAGO ───────────────────────────────────────────
-- Usuario 13 (Tatiana Mesa, Medellín) está INACTIVO
-- Al insertar un pago EXITOSO, el trigger debe reactivar la cuenta

-- Estado ANTES
SELECT id_usuario, nombre_usuario, estado_cuenta, fecha_ultimo_pago
FROM   USUARIOS
WHERE  id_usuario = 13;

-- Insertar pago EXITOSO para usuario INACTIVO
INSERT INTO PAGOS (id_usuario, fecha_pago, monto, metodo_pago, estado_pago, periodo_mes, periodo_anio)
VALUES (13, SYSDATE, 14900, 'Nequi', 'EXITOSO',
        EXTRACT(MONTH FROM SYSDATE), EXTRACT(YEAR FROM SYSDATE));
COMMIT;

-- Estado DESPUÉS — debe mostrar ACTIVO
SELECT id_usuario, nombre_usuario, estado_cuenta, fecha_ultimo_pago
FROM   USUARIOS
WHERE  id_usuario = 13;


-- ── VERIFICACIÓN FINAL: Triggers compilados correctamente ───────────
SELECT trigger_name, status, trigger_type, triggering_event
FROM   user_triggers
WHERE  trigger_name IN (
    'TRG_VALIDAR_CUENTA_ACTIVA',
    'TRG_LIMITE_PERFILES',
    'TRG_VALIDAR_CALIFICACION',
    'TRG_ACTIVAR_CUENTA_PAGO'
)
ORDER BY trigger_name;

-- Verificación: procedimientos y funciones compilados
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN (
    'SP_REGISTRAR_USUARIO',
    'SP_CAMBIAR_PLAN',
    'SP_REPORTE_CONSUMO',
    'FN_CALCULAR_MONTO',
    'FN_CONTENIDO_RECOMENDADO'
)
ORDER BY object_type, object_name;

-- =====================================================================
-- FIN DEL SCRIPT — NÚCLEO 2 COMPLETO
-- =====================================================================
