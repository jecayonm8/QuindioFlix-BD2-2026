-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   08_QuindioFlix_Nucleo5_RolesPrivilegios.sql
-- Propósito: Núcleo Temático 5 — Administración de Acceso a BD

-- Secciones:
--   3.5.1  Creación de 4 roles con privilegios diferenciados
--   3.5.2a Creación de 1 usuario Oracle por rol
--   3.5.2b GRANT de privilegios a cada rol
--   3.5.2c Demostración de restricciones por rol
--   3.5.2d Creación de PROFILE con límites de recursos

-- Ejecutar: Como quindioflix en QuindioFlixBD (tiene DBA role)

-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;

-- ============================================================================
-- LIMPIEZA PREVIA (para re-ejecuciones limpias)
-- Elimina usuarios, roles y perfil si ya existen de ejecuciones anteriores
-- ============================================================================
BEGIN
    -- Eliminar usuarios
    FOR u IN (SELECT username FROM dba_users
              WHERE username IN ('USR_ADMIN','USR_ANALISTA','USR_SOPORTE','USR_CONTENIDO'))
    LOOP
        EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
        DBMS_OUTPUT.PUT_LINE('Usuario eliminado: ' || u.username);
    END LOOP;

    -- Eliminar roles
    FOR r IN (SELECT role FROM dba_roles
              WHERE role IN ('ROL_ADMIN','ROL_ANALISTA','ROL_SOPORTE','ROL_CONTENIDO'))
    LOOP
        EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
        DBMS_OUTPUT.PUT_LINE('Rol eliminado: ' || r.role);
    END LOOP;

    -- Eliminar perfil
    BEGIN
        EXECUTE IMMEDIATE 'DROP PROFILE PERFIL_QUINDIOFLIX CASCADE';
        DBMS_OUTPUT.PUT_LINE('Perfil eliminado: PERFIL_QUINDIOFLIX');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END;
/


-- ============================================================================
-- SECCIÓN 3.5.2d — PERFIL DE RECURSOS (PROFILE)
-- Se crea primero para asignarlo a los usuarios al momento de crearlos
-- ============================================================================
-- JUSTIFICACIÓN DE CADA LÍMITE:
--   SESSIONS_PER_USER  3  → Máximo 3 sesiones simultáneas por usuario
--                            Evita abuso de conexiones y protege recursos del servidor
--   IDLE_TIME         20  → Desconectar sesión inactiva tras 20 minutos
--                            Libera conexiones de usuarios que olvidaron cerrar sesión
--   CONNECT_TIME     480  → Máximo 8 horas de conexión continua por sesión
--                            Garantiza rotación de sesiones durante la jornada laboral
--   FAILED_LOGIN_ATTEMPTS 5 → Bloquear cuenta tras 5 intentos fallidos de login
--                            Protección contra ataques de fuerza bruta
--   PASSWORD_LOCK_TIME 1/24 → Bloqueo de 1 hora al exceder intentos de login
--   PASSWORD_LIFE_TIME  90  → Contraseña válida por 90 días (3 meses)
--   PASSWORD_GRACE_TIME  7  → 7 días de gracia para cambiar contraseña al vencer
-- ============================================================================
CREATE PROFILE PERFIL_QUINDIOFLIX LIMIT
    SESSIONS_PER_USER       3
    IDLE_TIME              20
    CONNECT_TIME          480
    FAILED_LOGIN_ATTEMPTS   5
    PASSWORD_LOCK_TIME   1/24
    PASSWORD_LIFE_TIME     90
    PASSWORD_GRACE_TIME     7
    CPU_PER_SESSION   UNLIMITED
    LOGICAL_READS_PER_SESSION UNLIMITED;

-- Verificar que el perfil fue creado
SELECT profile, resource_name, limit
FROM   dba_profiles
WHERE  profile = 'PERFIL_QUINDIOFLIX'
ORDER  BY resource_name;


-- ===========================================================================
-- SECCIÓN 3.5.1 — CREACIÓN DE ROLES
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- ROL 1: ROL_ADMIN — Administrador de la plataforma

-- Acceso total: CRUD en todas las tablas + ejecutar todos los procedimientos
-- Usado por: equipo de Tecnología (DBA interno de QuindioFlix)
-- ---------------------------------------------------------------------------
CREATE ROLE ROL_ADMIN;

-- Privilegios de sistema
GRANT CREATE SESSION TO ROL_ADMIN;

-- CRUD completo en todas las tablas del esquema quindioflix
GRANT SELECT, INSERT, UPDATE, DELETE ON PLANES              TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON CATEGORIAS          TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON GENEROS             TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON DEPARTAMENTOS       TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON EMPLEADOS           TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON USUARIOS            TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON PERFILES            TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON CONTENIDO           TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON CONTENIDO_GENERO    TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON CONTENIDO_RELACIONADO TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON TEMPORADAS          TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON EPISODIOS           TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON REPRODUCCIONES      TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON FAVORITOS           TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON CALIFICACIONES      TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON REPORTES            TO ROL_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON PAGOS               TO ROL_ADMIN;

-- Acceso a vistas materializadas
GRANT SELECT ON MV_CONTENIDO_POPULAR   TO ROL_ADMIN;
GRANT SELECT ON MV_INGRESOS_MENSUALES  TO ROL_ADMIN;

-- Ejecución de todos los procedimientos y funciones
GRANT EXECUTE ON SP_REGISTRAR_USUARIO  TO ROL_ADMIN;
GRANT EXECUTE ON SP_CAMBIAR_PLAN       TO ROL_ADMIN;
GRANT EXECUTE ON SP_REPORTE_CONSUMO    TO ROL_ADMIN;
GRANT EXECUTE ON FN_CALCULAR_MONTO     TO ROL_ADMIN;
GRANT EXECUTE ON FN_CONTENIDO_RECOMENDADO TO ROL_ADMIN;


-- ----------------------------------------------------------------------------
-- ROL 2: ROL_ANALISTA — Analista de datos / Gerencia

-- Solo lectura en todas las tablas + acceso a reportes y vistas materializadas
-- Usado por: equipo de gerencia para reportes de negocio
-- ----------------------------------------------------------------------------
CREATE ROLE ROL_ANALISTA;

GRANT CREATE SESSION TO ROL_ANALISTA;

-- SELECT en todas las tablas (solo lectura, sin modificar datos)
GRANT SELECT ON PLANES              TO ROL_ANALISTA;
GRANT SELECT ON CATEGORIAS          TO ROL_ANALISTA;
GRANT SELECT ON GENEROS             TO ROL_ANALISTA;
GRANT SELECT ON DEPARTAMENTOS       TO ROL_ANALISTA;
GRANT SELECT ON EMPLEADOS           TO ROL_ANALISTA;
GRANT SELECT ON USUARIOS            TO ROL_ANALISTA;
GRANT SELECT ON PERFILES            TO ROL_ANALISTA;
GRANT SELECT ON CONTENIDO           TO ROL_ANALISTA;
GRANT SELECT ON CONTENIDO_GENERO    TO ROL_ANALISTA;
GRANT SELECT ON CONTENIDO_RELACIONADO TO ROL_ANALISTA;
GRANT SELECT ON TEMPORADAS          TO ROL_ANALISTA;
GRANT SELECT ON EPISODIOS           TO ROL_ANALISTA;
GRANT SELECT ON REPRODUCCIONES      TO ROL_ANALISTA;
GRANT SELECT ON FAVORITOS           TO ROL_ANALISTA;
GRANT SELECT ON CALIFICACIONES      TO ROL_ANALISTA;
GRANT SELECT ON REPORTES            TO ROL_ANALISTA;
GRANT SELECT ON PAGOS               TO ROL_ANALISTA;

-- Acceso a vistas materializadas (base de los reportes financieros)
GRANT SELECT ON MV_CONTENIDO_POPULAR  TO ROL_ANALISTA;
GRANT SELECT ON MV_INGRESOS_MENSUALES TO ROL_ANALISTA;

-- Solo puede ejecutar el procedimiento de reportes (no modificación)
GRANT EXECUTE ON SP_REPORTE_CONSUMO    TO ROL_ANALISTA;
GRANT EXECUTE ON FN_CALCULAR_MONTO     TO ROL_ANALISTA;
GRANT EXECUTE ON FN_CONTENIDO_RECOMENDADO TO ROL_ANALISTA;


-- ----------------------------------------------------------------------------
-- ROL 3: ROL_SOPORTE — Soporte al cliente
-- Puede ver datos de usuarios/pagos y registrar pagos + cambiar planes
-- Usado por: equipo de Soporte al Cliente y agentes de facturación
-- ----------------------------------------------------------------------------
CREATE ROLE ROL_SOPORTE;

GRANT CREATE SESSION TO ROL_SOPORTE;

-- Solo lectura en tablas de clientes
GRANT SELECT ON USUARIOS    TO ROL_SOPORTE;
GRANT SELECT ON PERFILES    TO ROL_SOPORTE;
GRANT SELECT ON PLANES      TO ROL_SOPORTE;
GRANT SELECT ON PAGOS       TO ROL_SOPORTE;
GRANT SELECT ON REPORTES    TO ROL_SOPORTE;

-- Puede insertar y actualizar pagos (registrar pagos manuales o correcciones)
GRANT INSERT, UPDATE ON PAGOS TO ROL_SOPORTE;

-- Puede ejecutar SP_CAMBIAR_PLAN (cambio de plan a solicitud del cliente)
GRANT EXECUTE ON SP_CAMBIAR_PLAN   TO ROL_SOPORTE;
GRANT EXECUTE ON FN_CALCULAR_MONTO TO ROL_SOPORTE;


-- ----------------------------------------------------------------------------
-- ROL 4: ROL_CONTENIDO — Gestor de catálogo multimedia
-- CRUD en tablas del catálogo + lectura de consumo y calificaciones
-- Usado por: equipo de Contenido (agrega/edita películas, series, etc.)
-- ----------------------------------------------------------------------------
CREATE ROLE ROL_CONTENIDO;

GRANT CREATE SESSION TO ROL_CONTENIDO;

-- CRUD completo en el catálogo de contenido
GRANT SELECT, INSERT, UPDATE, DELETE ON CONTENIDO            TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON CONTENIDO_GENERO     TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON CONTENIDO_RELACIONADO TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON TEMPORADAS           TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON EPISODIOS            TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON GENEROS              TO ROL_CONTENIDO;
GRANT SELECT, INSERT, UPDATE, DELETE ON CATEGORIAS           TO ROL_CONTENIDO;

-- Solo lectura en consumo y calificaciones (para analizar qué contenido funciona)
GRANT SELECT ON REPRODUCCIONES TO ROL_CONTENIDO;
GRANT SELECT ON CALIFICACIONES TO ROL_CONTENIDO;
GRANT SELECT ON FAVORITOS      TO ROL_CONTENIDO;
GRANT SELECT ON MV_CONTENIDO_POPULAR TO ROL_CONTENIDO;

-- Puede ejecutar procedimiento de recomendaciones
GRANT EXECUTE ON FN_CONTENIDO_RECOMENDADO TO ROL_CONTENIDO;


-- ==========================================================================
-- SECCIÓN 3.5.2a/b — CREAR USUARIOS Y ASIGNAR ROLES
-- ==========================================================================

-- Usuario administrador
CREATE USER usr_admin
    IDENTIFIED BY "Admin2026#"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_QUINDIOFLIX
    QUOTA UNLIMITED ON USERS;

GRANT ROL_ADMIN TO usr_admin;

-- Usuario analista de datos / gerencia
CREATE USER usr_analista
    IDENTIFIED BY "Analista2026#"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_QUINDIOFLIX
    QUOTA UNLIMITED ON USERS;

GRANT ROL_ANALISTA TO usr_analista;

-- Usuario de soporte al cliente
CREATE USER usr_soporte
    IDENTIFIED BY "Soporte2026#"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_QUINDIOFLIX
    QUOTA UNLIMITED ON USERS;

GRANT ROL_SOPORTE TO usr_soporte;

-- Usuario gestor de contenido
CREATE USER usr_contenido
    IDENTIFIED BY "Contenido2026#"
    DEFAULT TABLESPACE USERS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_QUINDIOFLIX
    QUOTA UNLIMITED ON USERS;

GRANT ROL_CONTENIDO TO usr_contenido;

DBMS_OUTPUT.PUT_LINE('Usuarios y roles creados correctamente.');


-- ========================================================================
-- VERIFICACIONES: Ver que todo quedó bien configurado
-- ========================================================================

-- Verificar usuarios creados con su perfil
SELECT username,
       account_status,
       profile,
       default_tablespace
FROM   dba_users
WHERE  username IN ('USR_ADMIN','USR_ANALISTA','USR_SOPORTE','USR_CONTENIDO')
ORDER  BY username;

-- Verificar roles asignados a cada usuario
SELECT grantee    AS usuario,
       granted_role AS rol_asignado,
       admin_option,
       default_role
FROM   dba_role_privs
WHERE  grantee IN ('USR_ADMIN','USR_ANALISTA','USR_SOPORTE','USR_CONTENIDO')
ORDER  BY grantee;

-- Verificar privilegios de cada rol sobre las tablas
SELECT grantee    AS rol,
       privilege  AS permiso,
       table_name AS tabla,
       grantable
FROM   dba_tab_privs
WHERE  grantee IN ('ROL_ADMIN','ROL_ANALISTA','ROL_SOPORTE','ROL_CONTENIDO')
ORDER  BY grantee, table_name, privilege;

-----------------------------------------------------------------------------
-- Verificar qué roles ROL_% existen en el Oracle
SELECT role FROM dba_roles WHERE role LIKE 'ROL%' ORDER BY role;

-- Asignar el rol correcto a USR_ADMIN
GRANT ROL_ADMIN TO USR_ADMIN;

-- Quitar el rol del otro proyecto (si quieres dejarlo limpio)
REVOKE ROL_ADMINISTRATIVO FROM USR_ADMIN;

-- Verificar que quedó correcto
SELECT grantee AS usuario, granted_role AS rol_asignado
FROM   dba_role_privs
WHERE  grantee IN ('USR_ADMIN','USR_ANALISTA','USR_SOPORTE','USR_CONTENIDO')
ORDER BY grantee;

-- ============================================================================
-- SECCIÓN 3.5.2c — DEMOSTRACIÓN DE RESTRICCIONES POR ROL
-- ============================================================================
-- Las siguientes pruebas deben ejecutarse conectado como cada usuario.
-- En SQL Developer: crear una nueva conexión con las credenciales de cada
-- usuario y ejecutar los bloques correspondientes.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PRUEBA ROL_ANALISTA (usr_analista / Analista2026#)
-- Puede hacer SELECT pero NO puede INSERT, UPDATE ni DELETE
-- ─────────────────────────────────────────────────────────────────────────────

-- PERMITIDO: SELECT en cualquier tabla
SELECT * FROM quindioflix.USUARIOS FETCH FIRST 5 ROWS ONLY;
-- SELECT * FROM quindioflix.MV_CONTENIDO_POPULAR ORDER BY total_reproducciones DESC;

-- ❌ BLOQUEADO: INSERT en CONTENIDO → debe fallar con ORA-01031
-- INSERT INTO quindioflix.CONTENIDO VALUES (...);

-- ─────────────────────────────────────────────────────────────────────────────
-- PRUEBA ROL_SOPORTE (usr_soporte / Soporte2026#)
-- Puede ver usuarios/pagos e insertar pagos, pero NO puede tocar contenido
-- ─────────────────────────────────────────────────────────────────────────────

-- ✅ PERMITIDO: Ver usuarios y planes
-- SELECT u.nombre_usuario, p.nombre_plan FROM quindioflix.USUARIOS u
-- JOIN quindioflix.PLANES p ON u.id_plan = p.id_plan;

-- ✅ PERMITIDO: Registrar un pago manualmente
-- INSERT INTO quindioflix.PAGOS (id_usuario,fecha_pago,monto,metodo_pago,
--     estado_pago,periodo_mes,periodo_anio)
-- VALUES (3, SYSDATE, 14900, 'PSE', 'EXITOSO', 5, 2026);

-- ❌ BLOQUEADO: Acceder al catálogo → debe fallar con ORA-01031
-- SELECT * FROM quindioflix.CONTENIDO;

-- ─────────────────────────────────────────────────────────────────────────────
-- PRUEBA ROL_CONTENIDO (usr_contenido / Contenido2026#)
-- Puede editar el catálogo pero NO puede ver pagos ni datos financieros
-- ─────────────────────────────────────────────────────────────────────────────

-- ✅ PERMITIDO: Editar el catálogo
-- UPDATE quindioflix.CONTENIDO SET sinopsis = 'Sinopsis actualizada'
-- WHERE id_contenido = 1;

-- ✅ PERMITIDO: Ver reproducciones y calificaciones
-- SELECT * FROM quindioflix.REPRODUCCIONES FETCH FIRST 5 ROWS ONLY;

-- ❌ BLOQUEADO: Ver pagos → debe fallar con ORA-01031
-- SELECT * FROM quindioflix.PAGOS;

-- ─────────────────────────────────────────────────────────────────────────────
-- DEMOSTRACIÓN EJECUTABLE: Verificar restricciones usando CURRENT_USER
-- Ejecutar estos bloques conectado como cada usuario en SQL Developer
-- ─────────────────────────────────────────────────────────────────────────────

-- Para generar el error ORA-01031 documentable, ejecuta en la conexión de
-- usr_analista:
--
-- BEGIN
--     EXECUTE IMMEDIATE 'INSERT INTO quindioflix.PAGOS
--         (id_usuario, fecha_pago, monto, metodo_pago, estado_pago,
--          periodo_mes, periodo_anio)
--         VALUES (1, SYSDATE, 14900, ''PSE'', ''EXITOSO'', 5, 2026)';
--     DBMS_OUTPUT.PUT_LINE('ERROR: La inserción debió bloquearse.');
-- EXCEPTION
--     WHEN OTHERS THEN
--         DBMS_OUTPUT.PUT_LINE('RESTRICCIÓN CORRECTA — ' || SQLERRM);
-- END;
-- /


-- ============================================================================
-- VERIFICACIÓN FINAL: MATRIZ COMPLETA DE PRIVILEGIOS
-- ============================================================================

-- Matriz de privilegios por rol y tabla
SELECT
    t.grantee                               AS rol,
    t.table_name                            AS tabla,
    MAX(CASE WHEN t.privilege='SELECT' THEN '✓' ELSE '' END) AS sel,
    MAX(CASE WHEN t.privilege='INSERT' THEN '✓' ELSE '' END) AS ins,
    MAX(CASE WHEN t.privilege='UPDATE' THEN '✓' ELSE '' END) AS upd,
    MAX(CASE WHEN t.privilege='DELETE' THEN '✓' ELSE '' END) AS del
FROM   dba_tab_privs t
WHERE  t.grantee IN ('ROL_ADMIN','ROL_ANALISTA','ROL_SOPORTE','ROL_CONTENIDO')
  AND  t.table_name IN (
           'USUARIOS','PERFILES','PLANES','PAGOS',
           'CONTENIDO','TEMPORADAS','EPISODIOS','GENEROS',
           'REPRODUCCIONES','CALIFICACIONES','REPORTES')
GROUP  BY t.grantee, t.table_name
ORDER  BY t.grantee, t.table_name;

-- Ver privilegios de sistema de los roles
SELECT grantee AS rol, privilege AS privilegio_sistema
FROM   dba_sys_privs
WHERE  grantee IN ('ROL_ADMIN','ROL_ANALISTA','ROL_SOPORTE','ROL_CONTENIDO')
ORDER  BY grantee;

-- Resumen del perfil de recursos
SELECT resource_name, limit
FROM   dba_profiles
WHERE  profile = 'PERFIL_QUINDIOFLIX'
  AND  limit  != 'DEFAULT'
ORDER  BY resource_name;

-- ============================================================================
-- FIN DEL SCRIPT — NÚCLEO 5 COMPLETADO
-- ============================================================================
