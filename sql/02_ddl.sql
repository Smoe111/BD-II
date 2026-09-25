-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 1
-- Script 02 · DDL del esquema (modelo del equipo, turismouq_modelo_er)
-- =====================================================================

-- Ejecutado por Docker: la sesion conecta AS SYSDBA en CDB$ROOT. Hay que
-- pasar a la PDB de la aplicacion y actuar como turismouq (sin conocer su
-- password) para que las tablas queden en su esquema, no en SYS.
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED

-- ---------------------------------------------------------------------
-- 0. Limpieza del esquema (no toca los tablespaces)
-- ---------------------------------------------------------------------
BEGIN
  FOR j IN (SELECT job_name FROM user_scheduler_jobs) LOOP
    BEGIN
      DBMS_SCHEDULER.DROP_JOB(j.job_name, force => TRUE);
    EXCEPTION WHEN OTHERS THEN
      -- Job de mantenimiento interno de Oracle (p.ej. BSLN_MAINTAIN_STATS_JOB),
      -- no un job propio: no se puede soltar y no hace falta hacerlo.
      NULL;
    END;
  END LOOP;
  FOR m IN (SELECT mview_name FROM user_mviews) LOOP
    EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW ' || m.mview_name;
  END LOOP;
  FOR v IN (SELECT view_name FROM user_views) LOOP
    EXECUTE IMMEDIATE 'DROP VIEW ' || v.view_name;
  END LOOP;
  FOR t IN (SELECT table_name FROM user_tables) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Esquema limpio.');
END;
/

-- ---------------------------------------------------------------------
-- 1. Secuencias, usadas como DEFAULT de la PK. RESERVA_HABITACION y
--    RESERVA_SERVICIO no llevan: su PK es compuesta.
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_tipo_documento   START WITH 1 NOCACHE;
CREATE SEQUENCE seq_municipio        START WITH 1 NOCACHE;
CREATE SEQUENCE seq_tipo_alojamiento START WITH 1 NOCACHE;
CREATE SEQUENCE seq_tipo_habitacion  START WITH 1 NOCACHE;
CREATE SEQUENCE seq_tipo_servicio    START WITH 1 NOCACHE;
CREATE SEQUENCE seq_tarifa           START WITH 1 CACHE 20;
CREATE SEQUENCE seq_temporada        START WITH 1 NOCACHE;
CREATE SEQUENCE seq_alojamiento      START WITH 1 CACHE 20;
CREATE SEQUENCE seq_habitacion       START WITH 1 CACHE 50;
CREATE SEQUENCE seq_cliente          START WITH 1 CACHE 100;
CREATE SEQUENCE seq_usuario_sistema  START WITH 1 CACHE 100;
CREATE SEQUENCE seq_servicio         START WITH 1 NOCACHE;
CREATE SEQUENCE seq_reserva          START WITH 1 CACHE 500;
CREATE SEQUENCE seq_pago             START WITH 1 CACHE 500;
CREATE SEQUENCE seq_resena           START WITH 1 CACHE 100;

-- =====================================================================
-- 2. CATALOGOS  ·  TS_TURISMO_DATOS
-- =====================================================================

CREATE TABLE tipo_documento (
  id_tipo_documento NUMBER       DEFAULT seq_tipo_documento.NEXTVAL,
  nombre            VARCHAR2(60) NOT NULL,
  CONSTRAINT pk_tipo_documento PRIMARY KEY (id_tipo_documento)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_tipo_doc_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx
) TABLESPACE ts_turismo_datos;

CREATE TABLE municipio (
  id_municipio NUMBER       DEFAULT seq_municipio.NEXTVAL,
  nombre       VARCHAR2(60) NOT NULL,
  CONSTRAINT pk_municipio PRIMARY KEY (id_municipio)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_municipio_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx
) TABLESPACE ts_turismo_datos;

-- En el diagrama la PK se llama id_tipo; se nombra igual que la foranea
-- de ALOJAMIENTO para que el join se lea sin ambiguedad.
CREATE TABLE tipo_alojamiento (
  id_tipo_alojamiento NUMBER       DEFAULT seq_tipo_alojamiento.NEXTVAL,
  nombre              VARCHAR2(40) NOT NULL,
  CONSTRAINT pk_tipo_alojamiento PRIMARY KEY (id_tipo_alojamiento)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_tipo_aloj_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx
) TABLESPACE ts_turismo_datos;

CREATE TABLE tipo_habitacion (
  id_tipo_habitacion NUMBER       DEFAULT seq_tipo_habitacion.NEXTVAL,
  nombre             VARCHAR2(40) NOT NULL,
  capacidad_maxima   NUMBER(2)    NOT NULL,
  CONSTRAINT pk_tipo_habitacion PRIMARY KEY (id_tipo_habitacion)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_tipo_hab_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_tipo_hab_capacidad CHECK (capacidad_maxima BETWEEN 1 AND 20)
) TABLESPACE ts_turismo_datos;

CREATE TABLE tipo_servicio (
  id_tipo_servicio NUMBER       DEFAULT seq_tipo_servicio.NEXTVAL,
  nombre           VARCHAR2(40) NOT NULL,
  CONSTRAINT pk_tipo_servicio PRIMARY KEY (id_tipo_servicio)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_tipo_serv_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx
) TABLESPACE ts_turismo_datos;

-- =====================================================================
-- 3. TARIFAS Y TEMPORADAS  ·  TS_TURISMO_DATOS
-- =====================================================================

CREATE TABLE tarifa (
  id_tarifa   NUMBER        DEFAULT seq_tarifa.NEXTVAL,
  nombre      VARCHAR2(100) NOT NULL,
  descripcion VARCHAR2(200),
  valor       NUMBER(12,2)  NOT NULL,
  CONSTRAINT pk_tarifa PRIMARY KEY (id_tarifa)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_tarifa_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_tarifa_valor CHECK (valor > 0)
) TABLESPACE ts_turismo_datos;

CREATE TABLE temporada (
  id_temporada NUMBER        DEFAULT seq_temporada.NEXTVAL,
  nombre       VARCHAR2(40)  NOT NULL,
  descripcion  VARCHAR2(200),
  porcentaje   NUMBER(5,2)   NOT NULL,
  fecha_inicio DATE          NOT NULL,
  fecha_fin    DATE          NOT NULL,
  CONSTRAINT pk_temporada PRIMARY KEY (id_temporada)
             USING INDEX TABLESPACE ts_turismo_idx,
  -- El nombre se repite cada anio; lo que no se repite es el inicio
  CONSTRAINT uq_temporada_inicio UNIQUE (fecha_inicio)
             USING INDEX TABLESPACE ts_turismo_idx,
  -- Negativo = descuento. Nunca puede dejar la noche en cero o menos.
  CONSTRAINT ck_temporada_porcentaje CHECK (porcentaje > -100 AND porcentaje <= 200),
  CONSTRAINT ck_temporada_rango      CHECK (fecha_fin >= fecha_inicio),
  -- Sin hora, para que los rangos sean exactos
  CONSTRAINT ck_temporada_trunc      CHECK (fecha_inicio = TRUNC(fecha_inicio)
                                        AND fecha_fin    = TRUNC(fecha_fin))
) TABLESPACE ts_turismo_datos;

-- =====================================================================
-- 4. OFERTA DE ALOJAMIENTO  ·  TS_TURISMO_DATOS
-- =====================================================================

CREATE TABLE alojamiento (
  id_alojamiento      NUMBER        DEFAULT seq_alojamiento.NEXTVAL,
  id_municipio        NUMBER        NOT NULL,
  id_tipo_alojamiento NUMBER        NOT NULL,
  nombre              VARCHAR2(100) NOT NULL,
  direccion           VARCHAR2(150) NOT NULL,
  calificacion        NUMBER(1)     NOT NULL,   -- clasificacion en estrellas
  activo              CHAR(1)       DEFAULT 'S' NOT NULL,
  CONSTRAINT pk_alojamiento PRIMARY KEY (id_alojamiento)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_aloj_municipio FOREIGN KEY (id_municipio)
             REFERENCES municipio (id_municipio),
  CONSTRAINT fk_aloj_tipo FOREIGN KEY (id_tipo_alojamiento)
             REFERENCES tipo_alojamiento (id_tipo_alojamiento),
  CONSTRAINT uq_aloj_municipio_nombre UNIQUE (id_municipio, nombre)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_aloj_calificacion CHECK (calificacion BETWEEN 1 AND 5),
  CONSTRAINT ck_aloj_activo       CHECK (activo IN ('S','N'))
) TABLESPACE ts_turismo_datos;

CREATE TABLE habitacion (
  id_habitacion      NUMBER       DEFAULT seq_habitacion.NEXTVAL,
  id_alojamiento     NUMBER       NOT NULL,
  id_tipo_habitacion NUMBER       NOT NULL,
  id_tarifa          NUMBER       NOT NULL,
  numero_habitacion  VARCHAR2(10) NOT NULL,
  activo             CHAR(1)      DEFAULT 'S' NOT NULL,
  CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_hab_alojamiento FOREIGN KEY (id_alojamiento)
             REFERENCES alojamiento (id_alojamiento),
  CONSTRAINT fk_hab_tipo FOREIGN KEY (id_tipo_habitacion)
             REFERENCES tipo_habitacion (id_tipo_habitacion),
  CONSTRAINT fk_hab_tarifa FOREIGN KEY (id_tarifa)
             REFERENCES tarifa (id_tarifa),
  -- El numero se repite entre alojamientos, no dentro de uno
  CONSTRAINT uq_hab_aloj_numero UNIQUE (id_alojamiento, numero_habitacion)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_hab_activo CHECK (activo IN ('S','N'))
) TABLESPACE ts_turismo_datos;

-- =====================================================================
-- 5. PERSONAS  ·  TS_TURISMO_DATOS
-- =====================================================================

-- No se relaciona con MUNICIPIO: esa tabla son los 12 municipios del
-- Quindio, es decir donde esta el alojamiento, no de donde viene el
-- huesped. La mayoria de turistas no reside en el departamento.
CREATE TABLE cliente (
  id_cliente         NUMBER        DEFAULT seq_cliente.NEXTVAL,
  id_tipo_documento  NUMBER        NOT NULL,
  numero_documento   VARCHAR2(20)  NOT NULL,
  nombres            VARCHAR2(60)  NOT NULL,
  apellidos          VARCHAR2(60)  NOT NULL,
  telefono           VARCHAR2(20),
  correo_electronico VARCHAR2(100) NOT NULL,
  fecha_nacimiento   DATE,
  fecha_registro     DATE          DEFAULT TRUNC(SYSDATE) NOT NULL,
  CONSTRAINT pk_cliente PRIMARY KEY (id_cliente)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_cliente_tipo_doc FOREIGN KEY (id_tipo_documento)
             REFERENCES tipo_documento (id_tipo_documento),
  CONSTRAINT uq_cliente_documento UNIQUE (id_tipo_documento, numero_documento)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_cliente_correo UNIQUE (correo_electronico)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_cliente_correo CHECK (correo_electronico LIKE '%_@_%._%'),
  CONSTRAINT ck_cliente_nacimiento CHECK (fecha_nacimiento IS NULL
                                      OR fecha_nacimiento >= DATE '1900-01-01')
) TABLESPACE ts_turismo_datos;

CREATE TABLE usuario_sistema (
  id_usuario_sistema NUMBER        DEFAULT seq_usuario_sistema.NEXTVAL,
  id_cliente         NUMBER,
  usuario            VARCHAR2(30)  NOT NULL,
  contrasena         VARCHAR2(128) NOT NULL,
  rol                VARCHAR2(20)  NOT NULL,
  activo             CHAR(1)       DEFAULT 'S' NOT NULL,
  fecha_creacion     DATE          DEFAULT TRUNC(SYSDATE) NOT NULL,
  ultimo_acceso      DATE,
  CONSTRAINT pk_usuario_sistema PRIMARY KEY (id_usuario_sistema)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_usuario_cliente FOREIGN KEY (id_cliente)
             REFERENCES cliente (id_cliente),
  CONSTRAINT uq_usuario_usuario UNIQUE (usuario)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT uq_usuario_cliente UNIQUE (id_cliente)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_usuario_rol CHECK (rol IN ('CLIENTE','RECEPCION',
                                           'ADMIN_ALOJAMIENTO','GERENTE','AUDITOR')),
  CONSTRAINT ck_usuario_activo CHECK (activo IN ('S','N')),
  CONSTRAINT ck_usuario_cliente CHECK (
       (rol =  'CLIENTE' AND id_cliente IS NOT NULL)
    OR (rol <> 'CLIENTE' AND id_cliente IS NULL)),
  CONSTRAINT ck_usuario_acceso CHECK (ultimo_acceso IS NULL
                                   OR ultimo_acceso >= fecha_creacion)
) TABLESPACE ts_turismo_datos;

-- =====================================================================
-- 6. SERVICIOS  ·  TS_TURISMO_DATOS
-- =====================================================================

CREATE TABLE servicio (
  id_servicio      NUMBER       DEFAULT seq_servicio.NEXTVAL,
  id_tipo_servicio NUMBER       NOT NULL,
  nombre           VARCHAR2(80) NOT NULL,
  valor_servicio   NUMBER(12,2) NOT NULL,
  CONSTRAINT pk_servicio PRIMARY KEY (id_servicio)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_servicio_tipo FOREIGN KEY (id_tipo_servicio)
             REFERENCES tipo_servicio (id_tipo_servicio),
  CONSTRAINT uq_servicio_nombre UNIQUE (nombre)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_servicio_valor CHECK (valor_servicio > 0)
) TABLESPACE ts_turismo_datos;

-- =====================================================================
-- 7. RESERVAS  ·  TS_TURISMO_HIST
-- =====================================================================

CREATE TABLE reserva (
  id_reserva         NUMBER        DEFAULT seq_reserva.NEXTVAL,
  id_cliente         NUMBER        NOT NULL,
  id_usuario_sistema NUMBER        NOT NULL,
  fecha_creacion     DATE          DEFAULT SYSDATE NOT NULL,
  fecha_checkin      DATE          NOT NULL,
  fecha_checkout     DATE          NOT NULL,
  estado             VARCHAR2(12)  DEFAULT 'PENDIENTE' NOT NULL,
  num_huespedes      NUMBER(3)     NOT NULL,
  valor_total        NUMBER(14,2)  NOT NULL,
  valor_pagado       NUMBER(14,2)  DEFAULT 0 NOT NULL,
  valor_pendiente    NUMBER(14,2)  GENERATED ALWAYS AS (valor_total - valor_pagado) VIRTUAL,
  CONSTRAINT pk_reserva PRIMARY KEY (id_reserva)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_reserva_cliente FOREIGN KEY (id_cliente)
             REFERENCES cliente (id_cliente),
  CONSTRAINT fk_reserva_usuario FOREIGN KEY (id_usuario_sistema)
             REFERENCES usuario_sistema (id_usuario_sistema),
  CONSTRAINT ck_reserva_fechas    CHECK (fecha_checkout > fecha_checkin),
  CONSTRAINT ck_reserva_anticipo  CHECK (fecha_checkin >= TRUNC(fecha_creacion)),
  CONSTRAINT ck_reserva_trunc     CHECK (fecha_checkin  = TRUNC(fecha_checkin)
                                     AND fecha_checkout = TRUNC(fecha_checkout)),
  CONSTRAINT ck_reserva_estado    CHECK (estado IN ('PENDIENTE','CONFIRMADA',
                                                    'EN_CURSO','FINALIZADA',
                                                    'CANCELADA')),
  CONSTRAINT ck_reserva_huespedes CHECK (num_huespedes BETWEEN 1 AND 60),
  CONSTRAINT ck_reserva_total     CHECK (valor_total >= 0),
  CONSTRAINT ck_reserva_pagado    CHECK (valor_pagado BETWEEN 0 AND valor_total)
) TABLESPACE ts_turismo_hist;

CREATE TABLE reserva_habitacion (
  id_reserva     NUMBER       NOT NULL,
  id_habitacion  NUMBER       NOT NULL,
  fecha_checkin  DATE         NOT NULL,
  fecha_checkout DATE         NOT NULL,
  valor_previo   NUMBER(12,2) NOT NULL,
  valor_reserva  NUMBER(12,2) NOT NULL,
  CONSTRAINT pk_reserva_habitacion PRIMARY KEY (id_reserva, id_habitacion)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_rh_reserva FOREIGN KEY (id_reserva)
             REFERENCES reserva (id_reserva) ON DELETE CASCADE,
  CONSTRAINT fk_rh_habitacion FOREIGN KEY (id_habitacion)
             REFERENCES habitacion (id_habitacion),
  CONSTRAINT ck_rh_fechas CHECK (fecha_checkout > fecha_checkin),
  CONSTRAINT ck_rh_valor  CHECK (valor_previo >= 0 AND valor_reserva >= 0)
) TABLESPACE ts_turismo_hist;

CREATE TABLE reserva_servicio (
  id_reserva     NUMBER       NOT NULL,
  id_servicio    NUMBER       NOT NULL,
  fecha_servicio DATE         NOT NULL,
  cantidad       NUMBER(4)    DEFAULT 1 NOT NULL,
  valor_previo   NUMBER(12,2) NOT NULL,
  valor_servicio NUMBER(12,2) NOT NULL,
  CONSTRAINT pk_reserva_servicio PRIMARY KEY (id_reserva, id_servicio)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_rs_reserva FOREIGN KEY (id_reserva)
             REFERENCES reserva (id_reserva) ON DELETE CASCADE,
  CONSTRAINT fk_rs_servicio FOREIGN KEY (id_servicio)
             REFERENCES servicio (id_servicio),
  CONSTRAINT ck_rs_cantidad CHECK (cantidad > 0),
  CONSTRAINT ck_rs_valor    CHECK (valor_previo > 0 AND valor_servicio > 0)
) TABLESPACE ts_turismo_hist;

CREATE TABLE pago (
  id_pago     NUMBER       DEFAULT seq_pago.NEXTVAL,
  id_reserva  NUMBER       NOT NULL,
  valor       NUMBER(14,2) NOT NULL,
  fecha_pago  DATE         DEFAULT SYSDATE NOT NULL,
  metodo_pago VARCHAR2(16) NOT NULL,
  estado      VARCHAR2(12) DEFAULT 'PENDIENTE' NOT NULL,
  CONSTRAINT pk_pago PRIMARY KEY (id_pago)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_pago_reserva FOREIGN KEY (id_reserva)
             REFERENCES reserva (id_reserva),
  CONSTRAINT ck_pago_valor  CHECK (valor > 0),
  CONSTRAINT ck_pago_metodo CHECK (metodo_pago IN ('EFECTIVO','TARJETA_CREDITO',
                                                   'TARJETA_DEBITO','PSE',
                                                   'TRANSFERENCIA')),
  CONSTRAINT ck_pago_estado CHECK (estado IN ('PENDIENTE','APROBADO',
                                              'RECHAZADO','REEMBOLSADO'))
) TABLESPACE ts_turismo_hist;

CREATE TABLE resena (
  id_resena    NUMBER        DEFAULT seq_resena.NEXTVAL,
  id_reserva   NUMBER        NOT NULL,
  calificacion NUMBER(1)     NOT NULL,
  comentario   VARCHAR2(500),
  fecha        DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_resena PRIMARY KEY (id_resena)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_resena_reserva FOREIGN KEY (id_reserva)
             REFERENCES reserva (id_reserva),
  -- Una sola resena por reserva
  CONSTRAINT uq_resena_reserva UNIQUE (id_reserva)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_resena_calificacion CHECK (calificacion BETWEEN 1 AND 5)
) TABLESPACE ts_turismo_hist;

-- =====================================================================
-- 8. Indices sobre llaves foraneas
-- =====================================================================
CREATE INDEX ix_aloj_tipo         ON alojamiento (id_tipo_alojamiento)  TABLESPACE ts_turismo_idx;
CREATE INDEX ix_hab_tipo          ON habitacion (id_tipo_habitacion)    TABLESPACE ts_turismo_idx;
CREATE INDEX ix_hab_tarifa        ON habitacion (id_tarifa)             TABLESPACE ts_turismo_idx;
CREATE INDEX ix_servicio_tipo     ON servicio (id_tipo_servicio)        TABLESPACE ts_turismo_idx;
CREATE INDEX ix_reserva_cliente   ON reserva (id_cliente)               TABLESPACE ts_turismo_idx;
CREATE INDEX ix_reserva_usuario   ON reserva (id_usuario_sistema)       TABLESPACE ts_turismo_idx;
CREATE INDEX ix_rh_habitacion     ON reserva_habitacion (id_habitacion) TABLESPACE ts_turismo_idx;
CREATE INDEX ix_rs_servicio       ON reserva_servicio (id_servicio)     TABLESPACE ts_turismo_idx;
CREATE INDEX ix_pago_reserva      ON pago (id_reserva)                  TABLESPACE ts_turismo_idx;

-- =====================================================================
-- 9. Comentarios (los muestra SQL Developer y los toma Data Modeler)
-- =====================================================================
COMMENT ON TABLE tipo_documento     IS 'Catalogo de documentos de identidad';
COMMENT ON TABLE municipio          IS 'Los 12 municipios del Quindio';
COMMENT ON TABLE tipo_alojamiento   IS 'Finca cafetera, hotel, glamping, hostal, ecohotel';
COMMENT ON TABLE tipo_habitacion    IS 'Tipos de habitacion con su capacidad maxima';
COMMENT ON TABLE tipo_servicio      IS 'Categorias de servicios complementarios';
COMMENT ON TABLE tarifa             IS 'Precio base por noche, compartido por varias habitaciones';
COMMENT ON TABLE temporada          IS 'Rango de fechas con porcentaje de ajuste sobre la tarifa base';
COMMENT ON TABLE alojamiento        IS 'Establecimientos de la plataforma';
COMMENT ON TABLE habitacion         IS 'Unidades reservables de cada alojamiento';
COMMENT ON TABLE cliente            IS 'Huespedes que reservan';
COMMENT ON TABLE usuario_sistema    IS 'Cuentas de acceso: clientes y personal de la plataforma';
COMMENT ON TABLE servicio           IS 'Catalogo de servicios complementarios';
COMMENT ON TABLE reserva            IS 'Cabecera de la reserva, con la foto de lo cobrado';
COMMENT ON TABLE reserva_habitacion IS 'Habitaciones de cada reserva (decision de diseno 1)';
COMMENT ON TABLE reserva_servicio   IS 'Servicios consumidos en una reserva';
COMMENT ON TABLE pago               IS 'Pagos de una reserva: anticipo, saldo o reembolso';
COMMENT ON TABLE resena             IS 'Calificacion del huesped al terminar la estadia';

COMMENT ON COLUMN reserva.valor_pendiente       IS 'Columna virtual: valor_total - valor_pagado';
COMMENT ON COLUMN reserva.id_usuario_sistema    IS 'Cuenta que registro la reserva';
COMMENT ON COLUMN temporada.porcentaje          IS 'Ajuste sobre la tarifa base: 40 = +40 %, 0 = sin ajuste';
COMMENT ON COLUMN alojamiento.calificacion      IS 'Clasificacion en estrellas, 1 a 5';
COMMENT ON COLUMN reserva_habitacion.valor_previo IS 'Noches x tarifa base, sin ajuste de temporada';
COMMENT ON COLUMN usuario_sistema.contrasena    IS 'Hash SHA-256 en hexadecimal';

-- =====================================================================
-- 10. Verificacion
-- =====================================================================
SET LINESIZE 150
SET PAGESIZE 100
COLUMN tabla           FORMAT A20
COLUMN tablespace_name FORMAT A18
COLUMN tipo            FORMAT A30

PROMPT
PROMPT === Tablas y su tablespace ===
SELECT table_name AS tabla, tablespace_name
  FROM user_tables
 ORDER BY tablespace_name, table_name;

PROMPT
PROMPT === Restricciones por tipo ===
SELECT DECODE(constraint_type, 'P', 'P  primaria',
                               'R', 'R  foranea',
                               'U', 'U  unica',
                               'C', 'C  check y not null') AS tipo,
       COUNT(*) AS cantidad
  FROM user_constraints
 WHERE table_name NOT LIKE 'BIN$%'
 GROUP BY constraint_type
 ORDER BY constraint_type;

PROMPT
PROMPT === Indices fuera de TS_TURISMO_IDX (debe salir vacio) ===
SELECT index_name, tablespace_name
  FROM user_indexes
 WHERE tablespace_name <> 'TS_TURISMO_IDX';

PROMPT
PROMPT === Foraneas sin indice (debe salir vacio) ===
SELECT c.table_name, c.constraint_name, cc.column_name
  FROM user_constraints c
  JOIN user_cons_columns cc ON cc.constraint_name = c.constraint_name
 WHERE c.constraint_type = 'R'
   AND NOT EXISTS (SELECT 1
                     FROM user_ind_columns ic
                    WHERE ic.table_name      = cc.table_name
                      AND ic.column_name     = cc.column_name
                      AND ic.column_position = 1)
 ORDER BY c.table_name;
