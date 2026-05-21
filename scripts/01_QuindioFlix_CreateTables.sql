-- ============================================================================
-- PROYECTO FINAL — BASES DE DATOS II
-- QuindioFlix — Plataforma de Streaming de Contenido Multimedia
-- Universidad del Quindío — 2026-1
-- ----------------------------------------------------------------------------
-- Script:   01_QuindioFlix_CreateTables.sql
-- Propósito: Creación del modelo físico de la base de datos (DDL)
-- Compatible: Oracle Database 12c o superior
-- ============================================================================


-- ============================================================================
-- SECCIÓN 1: TABLAS BASE (sin dependencias)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLA: PLANES
-- Almacena los tres planes de suscripción disponibles
-- ----------------------------------------------------------------------------
CREATE TABLE PLANES (
    id_plan          NUMBER(2)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_plan      VARCHAR2(20)     NOT NULL UNIQUE,
    precio_mensual   NUMBER(8,2)      NOT NULL,
    max_pantallas    NUMBER(1)        NOT NULL,
    calidad_video    VARCHAR2(5)      NOT NULL,
    max_perfiles     NUMBER(1)        NOT NULL,
    CONSTRAINT chk_plan_nombre   CHECK (nombre_plan IN ('Básico','Estándar','Premium')),
    CONSTRAINT chk_plan_calidad  CHECK (calidad_video IN ('SD','HD','4K')),
    CONSTRAINT chk_plan_precio   CHECK (precio_mensual > 0)
);

COMMENT ON TABLE  PLANES IS 'Planes de suscripción disponibles en la plataforma';
COMMENT ON COLUMN PLANES.id_plan IS 'Identificador único del plan';
COMMENT ON COLUMN PLANES.precio_mensual IS 'Precio mensual del plan en pesos colombianos';


-- ----------------------------------------------------------------------------
-- TABLA: CATEGORIAS
-- Tipos principales de contenido multimedia
-- ----------------------------------------------------------------------------
CREATE TABLE CATEGORIAS (
    id_categoria     NUMBER(2)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_categoria VARCHAR2(20)     NOT NULL UNIQUE,
    descripcion      VARCHAR2(200)
);

COMMENT ON TABLE CATEGORIAS IS 'Categorías de contenido: Película, Serie, Documental, Música, Podcast';


-- ----------------------------------------------------------------------------
-- TABLA: GENEROS
-- Géneros cinematográficos o musicales del contenido
-- ----------------------------------------------------------------------------
CREATE TABLE GENEROS (
    id_genero        NUMBER(3)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_genero    VARCHAR2(30)     NOT NULL UNIQUE
);

COMMENT ON TABLE GENEROS IS 'Géneros aplicables al contenido (Acción, Comedia, Drama, etc.)';


-- ----------------------------------------------------------------------------
-- TABLA: DEPARTAMENTOS
-- Áreas organizacionales de la empresa (FK a EMPLEADOS se agrega después)
-- ----------------------------------------------------------------------------
CREATE TABLE DEPARTAMENTOS (
    id_departamento  NUMBER(2)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_dept      VARCHAR2(30)     NOT NULL UNIQUE,
    id_jefe_empleado NUMBER(5),
    CONSTRAINT chk_dept_nombre CHECK (nombre_dept IN ('Tecnología','Contenido','Marketing','Soporte','Finanzas'))
);

COMMENT ON TABLE DEPARTAMENTOS IS 'Departamentos organizacionales de QuindioFlix';
COMMENT ON COLUMN DEPARTAMENTOS.id_jefe_empleado IS 'Empleado que dirige el departamento (FK reflexiva a EMPLEADOS)';


-- ============================================================================
-- SECCIÓN 2: TABLAS CON DEPENDENCIAS DIRECTAS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLA: EMPLEADOS
-- Personal interno con jerarquía de supervisión (relación reflexiva)
-- ----------------------------------------------------------------------------
CREATE TABLE EMPLEADOS (
    id_empleado      NUMBER(5)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_empleado  VARCHAR2(80)     NOT NULL,
    email_empleado   VARCHAR2(100)    NOT NULL UNIQUE,
    cargo            VARCHAR2(50)     NOT NULL,
    fecha_ingreso    DATE             DEFAULT SYSDATE NOT NULL,
    id_departamento  NUMBER(2)        NOT NULL,
    id_supervisor    NUMBER(5),
    CONSTRAINT fk_emp_departamento  FOREIGN KEY (id_departamento) REFERENCES DEPARTAMENTOS(id_departamento),
    CONSTRAINT chk_emp_no_self_super CHECK (id_supervisor <> id_empleado)
);

COMMENT ON TABLE  EMPLEADOS IS 'Empleados de QuindioFlix con jerarquía interna';
COMMENT ON COLUMN EMPLEADOS.id_supervisor IS 'Supervisor directo del empleado (FK reflexiva)';


-- ----------------------------------------------------------------------------
-- TABLA: USUARIOS
-- Suscriptores de la plataforma con sistema de referidos (relación reflexiva)
-- ----------------------------------------------------------------------------
CREATE TABLE USUARIOS (
    id_usuario       NUMBER(8)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_usuario   VARCHAR2(80)     NOT NULL,
    email_usuario    VARCHAR2(100)    NOT NULL UNIQUE,
    telefono         VARCHAR2(20),
    fecha_nacimiento DATE             NOT NULL,
    ciudad           VARCHAR2(50)     NOT NULL,
    fecha_registro   DATE             DEFAULT SYSDATE NOT NULL,
    estado_cuenta    VARCHAR2(10)     DEFAULT 'ACTIVO' NOT NULL,
    fecha_ultimo_pago DATE,
    id_plan          NUMBER(2)        NOT NULL,
    id_referidor     NUMBER(8),
    es_moderador     CHAR(1)          DEFAULT 'N' NOT NULL,
    CONSTRAINT fk_usu_plan          FOREIGN KEY (id_plan) REFERENCES PLANES(id_plan),
    CONSTRAINT chk_usu_estado       CHECK (estado_cuenta IN ('ACTIVO','INACTIVO','SUSPENDIDO')),
    CONSTRAINT chk_usu_email        CHECK (email_usuario LIKE '%_@_%._%'),
    CONSTRAINT chk_usu_moderador    CHECK (es_moderador IN ('S','N')),
    CONSTRAINT chk_usu_no_self_ref  CHECK (id_referidor <> id_usuario)
);

COMMENT ON TABLE  USUARIOS IS 'Usuarios suscriptores de la plataforma';
COMMENT ON COLUMN USUARIOS.id_referidor IS 'Usuario que refirió a este (FK reflexiva)';
COMMENT ON COLUMN USUARIOS.es_moderador IS 'Indica si el usuario tiene rol de moderador (S/N)';


-- ----------------------------------------------------------------------------
-- TABLA: CONTENIDO
-- Catálogo principal de la plataforma
-- ----------------------------------------------------------------------------
CREATE TABLE CONTENIDO (
    id_contenido     NUMBER(8)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    titulo           VARCHAR2(150)    NOT NULL,
    anio_lanzamiento NUMBER(4)        NOT NULL,
    duracion_min     NUMBER(5)        NOT NULL,
    sinopsis         VARCHAR2(1000),
    clasificacion_edad VARCHAR2(3)    NOT NULL,
    fecha_agregado   DATE             DEFAULT SYSDATE NOT NULL,
    es_original      CHAR(1)          DEFAULT 'N' NOT NULL,
    popularidad      NUMBER(8)        DEFAULT 0,
    id_categoria     NUMBER(2)        NOT NULL,
    id_empleado_resp NUMBER(5)        NOT NULL,
    CONSTRAINT fk_cont_categoria FOREIGN KEY (id_categoria) REFERENCES CATEGORIAS(id_categoria),
    CONSTRAINT fk_cont_empleado  FOREIGN KEY (id_empleado_resp) REFERENCES EMPLEADOS(id_empleado),
    CONSTRAINT chk_cont_clasif   CHECK (clasificacion_edad IN ('TP','+7','+13','+16','+18')),
    CONSTRAINT chk_cont_anio     CHECK (anio_lanzamiento BETWEEN 1900 AND 2100),
    CONSTRAINT chk_cont_duracion CHECK (duracion_min > 0),
    CONSTRAINT chk_cont_original CHECK (es_original IN ('S','N'))
);

COMMENT ON TABLE  CONTENIDO IS 'Catálogo de contenido multimedia de QuindioFlix';
COMMENT ON COLUMN CONTENIDO.es_original IS 'Indica si es producción original de QuindioFlix (S/N)';
COMMENT ON COLUMN CONTENIDO.popularidad IS 'Contador de reproducciones completas, actualizado por trigger';


-- ============================================================================
-- SECCIÓN 3: TABLAS DEPENDIENTES Y RELACIONES N:M
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABLA: PERFILES
-- Perfiles de consumo dentro de cada cuenta de usuario
-- ----------------------------------------------------------------------------
CREATE TABLE PERFILES (
    id_perfil        NUMBER(8)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario       NUMBER(8)        NOT NULL,
    nombre_perfil    VARCHAR2(50)     NOT NULL,
    avatar           VARCHAR2(100),
    tipo_perfil      VARCHAR2(10)     NOT NULL,
    fecha_creacion   DATE             DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_perf_usuario FOREIGN KEY (id_usuario) REFERENCES USUARIOS(id_usuario) ON DELETE CASCADE,
    CONSTRAINT chk_perf_tipo   CHECK (tipo_perfil IN ('adulto','infantil')),
    CONSTRAINT uq_perf_usuario_nombre UNIQUE (id_usuario, nombre_perfil)
);

COMMENT ON TABLE PERFILES IS 'Perfiles de consumo dentro de cada cuenta';


-- ----------------------------------------------------------------------------
-- TABLA: CONTENIDO_GENERO  (relación N:M)
-- Un contenido puede tener varios géneros
-- ----------------------------------------------------------------------------
CREATE TABLE CONTENIDO_GENERO (
    id_contenido     NUMBER(8)        NOT NULL,
    id_genero        NUMBER(3)        NOT NULL,
    CONSTRAINT pk_cont_gen     PRIMARY KEY (id_contenido, id_genero),
    CONSTRAINT fk_cg_contenido FOREIGN KEY (id_contenido) REFERENCES CONTENIDO(id_contenido) ON DELETE CASCADE,
    CONSTRAINT fk_cg_genero    FOREIGN KEY (id_genero)    REFERENCES GENEROS(id_genero)
);

COMMENT ON TABLE CONTENIDO_GENERO IS 'Tabla intermedia N:M entre contenido y géneros';


-- ----------------------------------------------------------------------------
-- TABLA: CONTENIDO_RELACIONADO  (relación N:M reflexiva)
-- Asocia contenidos entre sí: secuelas, precuelas, spin-offs, etc.
-- ----------------------------------------------------------------------------
CREATE TABLE CONTENIDO_RELACIONADO (
    id_contenido_origen  NUMBER(8)    NOT NULL,
    id_contenido_destino NUMBER(8)    NOT NULL,
    tipo_relacion        VARCHAR2(20) NOT NULL,
    descripcion          VARCHAR2(200),
    CONSTRAINT pk_cont_rel       PRIMARY KEY (id_contenido_origen, id_contenido_destino),
    CONSTRAINT fk_cr_origen      FOREIGN KEY (id_contenido_origen)  REFERENCES CONTENIDO(id_contenido) ON DELETE CASCADE,
    CONSTRAINT fk_cr_destino     FOREIGN KEY (id_contenido_destino) REFERENCES CONTENIDO(id_contenido),
    CONSTRAINT chk_cr_tipo       CHECK (tipo_relacion IN ('secuela','precuela','remake','spin-off','version_extendida','relacionado')),
    CONSTRAINT chk_cr_no_self    CHECK (id_contenido_origen <> id_contenido_destino)
);

COMMENT ON TABLE CONTENIDO_RELACIONADO IS 'Relación N:M reflexiva entre contenidos (secuelas, spin-offs, etc.)';


-- ----------------------------------------------------------------------------
-- TABLA: TEMPORADAS
-- Solo aplica a series y podcasts
-- ----------------------------------------------------------------------------
CREATE TABLE TEMPORADAS (
    id_temporada     NUMBER(6)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_contenido     NUMBER(8)        NOT NULL,
    numero_temporada NUMBER(2)        NOT NULL,
    titulo_temporada VARCHAR2(100),
    anio_temporada   NUMBER(4),
    CONSTRAINT fk_temp_contenido FOREIGN KEY (id_contenido) REFERENCES CONTENIDO(id_contenido) ON DELETE CASCADE,
    CONSTRAINT uq_temp_cont_num  UNIQUE (id_contenido, numero_temporada),
    CONSTRAINT chk_temp_numero   CHECK (numero_temporada > 0)
);

COMMENT ON TABLE TEMPORADAS IS 'Temporadas de series y podcasts';


-- ----------------------------------------------------------------------------
-- TABLA: EPISODIOS
-- Episodios individuales dentro de cada temporada
-- ----------------------------------------------------------------------------
CREATE TABLE EPISODIOS (
    id_episodio      NUMBER(8)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_temporada     NUMBER(6)        NOT NULL,
    numero_episodio  NUMBER(3)        NOT NULL,
    titulo_episodio  VARCHAR2(150)    NOT NULL,
    duracion_min     NUMBER(4)        NOT NULL,
    sinopsis_ep      VARCHAR2(500),
    CONSTRAINT fk_ep_temporada FOREIGN KEY (id_temporada) REFERENCES TEMPORADAS(id_temporada) ON DELETE CASCADE,
    CONSTRAINT uq_ep_temp_num  UNIQUE (id_temporada, numero_episodio),
    CONSTRAINT chk_ep_duracion CHECK (duracion_min > 0)
);

COMMENT ON TABLE EPISODIOS IS 'Episodios pertenecientes a temporadas';


-- ----------------------------------------------------------------------------
-- TABLA: REPRODUCCIONES
-- Registro de cada reproducción de contenido por un perfil
-- ----------------------------------------------------------------------------
CREATE TABLE REPRODUCCIONES (
    id_reproduccion  NUMBER(10)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_perfil        NUMBER(8)        NOT NULL,
    id_contenido     NUMBER(8)        NOT NULL,
    id_episodio      NUMBER(8),
    fecha_inicio     TIMESTAMP        DEFAULT SYSTIMESTAMP NOT NULL,
    fecha_fin        TIMESTAMP,
    dispositivo      VARCHAR2(15)     NOT NULL,
    porcentaje_avance NUMBER(5,2)     DEFAULT 0,
    CONSTRAINT fk_rep_perfil    FOREIGN KEY (id_perfil)    REFERENCES PERFILES(id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_rep_contenido FOREIGN KEY (id_contenido) REFERENCES CONTENIDO(id_contenido),
    CONSTRAINT fk_rep_episodio  FOREIGN KEY (id_episodio)  REFERENCES EPISODIOS(id_episodio),
    CONSTRAINT chk_rep_disp     CHECK (dispositivo IN ('celular','tablet','TV','computador')),
    CONSTRAINT chk_rep_porc     CHECK (porcentaje_avance BETWEEN 0 AND 100)
);

COMMENT ON TABLE REPRODUCCIONES IS 'Historial de reproducciones de cada perfil';


-- ----------------------------------------------------------------------------
-- TABLA: FAVORITOS  (relación N:M)
-- Lista personal de contenido favorito por perfil
-- ----------------------------------------------------------------------------
CREATE TABLE FAVORITOS (
    id_perfil        NUMBER(8)        NOT NULL,
    id_contenido     NUMBER(8)        NOT NULL,
    fecha_agregado   DATE             DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_favoritos     PRIMARY KEY (id_perfil, id_contenido),
    CONSTRAINT fk_fav_perfil    FOREIGN KEY (id_perfil)    REFERENCES PERFILES(id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_fav_contenido FOREIGN KEY (id_contenido) REFERENCES CONTENIDO(id_contenido) ON DELETE CASCADE
);

COMMENT ON TABLE FAVORITOS IS 'Lista de favoritos por perfil (N:M)';


-- ----------------------------------------------------------------------------
-- TABLA: CALIFICACIONES
-- Valoraciones del contenido por parte de los perfiles
-- ----------------------------------------------------------------------------
CREATE TABLE CALIFICACIONES (
    id_calificacion  NUMBER(10)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_perfil        NUMBER(8)        NOT NULL,
    id_contenido     NUMBER(8)        NOT NULL,
    estrellas        NUMBER(1)        NOT NULL,
    resena           VARCHAR2(1000),
    fecha_calif      DATE             DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_cal_perfil    FOREIGN KEY (id_perfil)    REFERENCES PERFILES(id_perfil) ON DELETE CASCADE,
    CONSTRAINT fk_cal_contenido FOREIGN KEY (id_contenido) REFERENCES CONTENIDO(id_contenido) ON DELETE CASCADE,
    CONSTRAINT uq_cal_perf_cont UNIQUE (id_perfil, id_contenido),
    CONSTRAINT chk_cal_estrellas CHECK (estrellas BETWEEN 1 AND 5)
);

COMMENT ON TABLE CALIFICACIONES IS 'Calificaciones con estrellas y reseñas';


-- ----------------------------------------------------------------------------
-- TABLA: REPORTES
-- Reportes de contenido inapropiado, gestionados por moderadores
-- ----------------------------------------------------------------------------
CREATE TABLE REPORTES (
    id_reporte       NUMBER(8)        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario_reporta NUMBER(8)      NOT NULL,
    id_contenido     NUMBER(8)        NOT NULL,
    motivo           VARCHAR2(500)    NOT NULL,
    fecha_reporte    DATE             DEFAULT SYSDATE NOT NULL,
    estado_reporte   VARCHAR2(15)     DEFAULT 'PENDIENTE' NOT NULL,
    id_moderador     NUMBER(8),
    fecha_resolucion DATE,
    observacion_mod  VARCHAR2(500),
    CONSTRAINT fk_rep_usuario   FOREIGN KEY (id_usuario_reporta) REFERENCES USUARIOS(id_usuario),
    CONSTRAINT fk_rep_contenido2 FOREIGN KEY (id_contenido)      REFERENCES CONTENIDO(id_contenido),
    CONSTRAINT fk_rep_moderador FOREIGN KEY (id_moderador)       REFERENCES USUARIOS(id_usuario),
    CONSTRAINT chk_rep_estado   CHECK (estado_reporte IN ('PENDIENTE','EN_REVISION','RESUELTO','DESCARTADO'))
);

COMMENT ON TABLE  REPORTES IS 'Reportes de contenido inapropiado';
COMMENT ON COLUMN REPORTES.id_moderador IS 'Usuario moderador que resolvió el reporte';


-- ----------------------------------------------------------------------------
-- TABLA: PAGOS
-- Historial de pagos mensuales de suscripción
-- ----------------------------------------------------------------------------
CREATE TABLE PAGOS (
    id_pago          NUMBER(10)       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_usuario       NUMBER(8)        NOT NULL,
    fecha_pago       DATE             DEFAULT SYSDATE NOT NULL,
    monto            NUMBER(8,2)      NOT NULL,
    metodo_pago      VARCHAR2(20)     NOT NULL,
    estado_pago      VARCHAR2(15)     DEFAULT 'PENDIENTE' NOT NULL,
    periodo_mes      NUMBER(2)        NOT NULL,
    periodo_anio     NUMBER(4)        NOT NULL,
    CONSTRAINT fk_pag_usuario  FOREIGN KEY (id_usuario) REFERENCES USUARIOS(id_usuario),
    CONSTRAINT chk_pag_metodo  CHECK (metodo_pago IN ('TC','TD','PSE','Nequi','Daviplata')),
    CONSTRAINT chk_pag_estado  CHECK (estado_pago IN ('EXITOSO','FALLIDO','PENDIENTE','REEMBOLSADO')),
    CONSTRAINT chk_pag_mes     CHECK (periodo_mes BETWEEN 1 AND 12),
    CONSTRAINT chk_pag_monto   CHECK (monto >= 0)
);

COMMENT ON TABLE PAGOS IS 'Historial de pagos de suscripción';


-- ============================================================================
-- SECCIÓN 4: RELACIONES REFLEXIVAS Y CIRCULARES
-- (Se agregan al final para evitar problemas de referencias circulares)
-- ============================================================================

-- DEPARTAMENTOS.id_jefe_empleado → EMPLEADOS.id_empleado
ALTER TABLE DEPARTAMENTOS ADD CONSTRAINT fk_dept_jefe
    FOREIGN KEY (id_jefe_empleado) REFERENCES EMPLEADOS(id_empleado);

-- EMPLEADOS.id_supervisor → EMPLEADOS.id_empleado (REFLEXIVA)
ALTER TABLE EMPLEADOS ADD CONSTRAINT fk_emp_supervisor
    FOREIGN KEY (id_supervisor) REFERENCES EMPLEADOS(id_empleado);

-- USUARIOS.id_referidor → USUARIOS.id_usuario (REFLEXIVA)
ALTER TABLE USUARIOS ADD CONSTRAINT fk_usu_referidor
    FOREIGN KEY (id_referidor) REFERENCES USUARIOS(id_usuario);


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
