-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 05 · Tabla de la liquidacion mensual por alojamiento
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq, despues de 02_ddl.sql
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @05_liquidacion_tabla.sql
--
-- No estaba en el modelo de la Entrega 1 porque es un artefacto de
-- proceso, no del dominio de reservas: la llena pkg_turismo.sp_liquidar_mes
-- (06_pkg_turismo.sql).
--
-- La UNIQUE (id_alojamiento, anio, mes) es la que hace el proceso
-- idempotente: volver a liquidar un mes actualiza la fila en vez de
-- duplicarla. Un proceso masivo que no se puede repetir sin ensuciar los
-- datos es inutilizable: siempre hay que volver a correrlo.
-- =====================================================================

-- Ejecutado por Docker: la sesion conecta AS SYSDBA en CDB$ROOT (ver
-- 02_ddl.sql). Corriendo a mano como turismouq las dos lineas no tienen
-- efecto: ya se esta en la PDB y en el esquema correctos.
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED

-- ---------------------------------------------------------------------
-- 0. Limpieza: el script se puede volver a correr. La primera vez no
--    hay nada que borrar (ORA-00942 / ORA-02289) y se ignora.
-- ---------------------------------------------------------------------
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE liquidacion_mensual CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_liquidacion';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE <> -2289 THEN RAISE; END IF;
END;
/

-- ---------------------------------------------------------------------
-- 1. Secuencia como DEFAULT de la PK, igual que el resto del esquema
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_liquidacion START WITH 1 CACHE 100;

-- ---------------------------------------------------------------------
-- 2. Tabla  ·  TS_TURISMO_HIST (crece un corte por mes, como RESERVA)
-- ---------------------------------------------------------------------
CREATE TABLE liquidacion_mensual (
  id_liquidacion    NUMBER       DEFAULT seq_liquidacion.NEXTVAL,
  id_alojamiento    NUMBER       NOT NULL,
  anio              NUMBER(4)    NOT NULL,
  mes               NUMBER(2)    NOT NULL,
  reservas          NUMBER(6)    DEFAULT 0 NOT NULL,
  noches_vendidas   NUMBER(8)    DEFAULT 0 NOT NULL,   -- noches-habitacion
  ingreso_hospedaje NUMBER(14,2) DEFAULT 0 NOT NULL,   -- devengado en el mes
  ingreso_servicios NUMBER(14,2) DEFAULT 0 NOT NULL,   -- de la plataforma
  recaudo_caja      NUMBER(14,2) DEFAULT 0 NOT NULL,   -- pagos aprobados del mes
  pct_comision      NUMBER(5,2)  NOT NULL,
  valor_comision    NUMBER(14,2) NOT NULL,
  neto_alojamiento  NUMBER(14,2) NOT NULL,
  fecha_proceso     DATE         DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_liquidacion PRIMARY KEY (id_liquidacion)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT fk_liq_alojamiento FOREIGN KEY (id_alojamiento)
             REFERENCES alojamiento (id_alojamiento),
  -- Idempotencia del proceso. Ademas, al empezar por id_alojamiento,
  -- sirve de indice para la foranea.
  CONSTRAINT uq_liq_aloj_periodo UNIQUE (id_alojamiento, anio, mes)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_liq_mes      CHECK (mes BETWEEN 1 AND 12),
  CONSTRAINT ck_liq_conteos  CHECK (reservas >= 0 AND noches_vendidas >= 0),
  CONSTRAINT ck_liq_valores  CHECK (ingreso_hospedaje >= 0
                                AND ingreso_servicios >= 0
                                AND recaudo_caja      >= 0
                                AND valor_comision    >= 0),
  CONSTRAINT ck_liq_comision CHECK (pct_comision BETWEEN 0 AND 100),
  -- El neto no es un dato libre: si no cuadra, el proceso tiene un error
  CONSTRAINT ck_liq_neto     CHECK (neto_alojamiento = ingreso_hospedaje - valor_comision)
) TABLESPACE ts_turismo_hist;

-- Consultas por periodo (todos los alojamientos de un mes)
CREATE INDEX ix_liq_periodo ON liquidacion_mensual (anio, mes) TABLESPACE ts_turismo_idx;

-- ---------------------------------------------------------------------
-- 3. Comentarios
-- ---------------------------------------------------------------------
COMMENT ON TABLE liquidacion_mensual IS
  'Corte mensual por alojamiento: devengado, comision y neto a transferir';
COMMENT ON COLUMN liquidacion_mensual.noches_vendidas IS
  'Noches-habitacion ocupadas dentro del mes';
COMMENT ON COLUMN liquidacion_mensual.ingreso_hospedaje IS
  'Devengado noche por noche dentro del mes, prorrateado sobre lo cobrado (valor_reserva)';
COMMENT ON COLUMN liquidacion_mensual.ingreso_servicios IS
  'Servicios consumidos en el mes; son de la plataforma, no entran a la comision';
COMMENT ON COLUMN liquidacion_mensual.recaudo_caja IS
  'Pagos aprobados en el mes; se informa, no se liquida sobre el';
COMMENT ON COLUMN liquidacion_mensual.pct_comision IS
  'Porcentaje vigente al liquidar; se guarda para que un cambio futuro no altere cortes pasados';

PROMPT Tabla LIQUIDACION_MENSUAL creada. Continue con 06_pkg_turismo.sql
