-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 05 · Estructuras de apoyo de la capa PL/SQL
-- ---------------------------------------------------------------------
-- Se ejecuta despues de 01-04 (en Docker corre solo, en orden alfabetico).
--
--   1. Temporadas de 2027: la carga cubre 2024-2026 y fn_valor_estadia
--      se niega a valorar noches sin temporada. Sin estas filas nadie
--      podria reservar a partir del 1 de enero de 2027.
--   2. AUDITORIA_TARIFA   -> la llena el trigger trg_tarifa_auditoria.
--
-- El enunciado permite agregar tablas ("pueden agregar las que necesiten,
-- no quitar"): el modelo pasa de 17 a 19 tablas, sin tocar ninguna.
-- =====================================================================

ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED

-- ---------------------------------------------------------------------
-- 0. Limpieza (permite volver a correr el script)
-- ---------------------------------------------------------------------
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('AUDITORIA_TARIFA')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE "' || t.table_name || '" CASCADE CONSTRAINTS PURGE';
  END LOOP;
  FOR s IN (SELECT sequence_name FROM user_sequences
             WHERE sequence_name IN ('SEQ_AUDITORIA_TARIFA', 'SEQ_AUDITORIA_SENTENCIA')) LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE ' || s.sequence_name;
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- 1. Temporadas 2027 (mismo calendario que 2024-2026)
--    Semana Santa 2027: Domingo de Ramos 21/03 a Resurreccion 28/03.
-- ---------------------------------------------------------------------
DECLARE
  PROCEDURE ins(p_nombre VARCHAR2, p_desc VARCHAR2, p_pct NUMBER,
                p_ini DATE, p_fin DATE) IS
  BEGIN
    INSERT INTO temporada (nombre, descripcion, porcentaje, fecha_inicio, fecha_fin)
    SELECT p_nombre, p_desc, p_pct, p_ini, p_fin FROM dual
     WHERE NOT EXISTS (SELECT 1 FROM temporada WHERE fecha_inicio = p_ini);
  END;
BEGIN
  ins('Vacaciones de enero',  'Cierre de las vacaciones escolares 2027', 35, DATE '2027-01-01', DATE '2027-01-15');
  ins('Temporada baja',       'Enero a marzo 2027',                       0, DATE '2027-01-16', DATE '2027-03-20');
  ins('Semana Santa',         'Domingo de Ramos a Resurreccion 2027',    40, DATE '2027-03-21', DATE '2027-03-28');
  ins('Temporada baja',       'Abril a junio 2027',                       0, DATE '2027-03-29', DATE '2027-06-14');
  ins('Vacaciones de mitad',  'Receso escolar de junio y julio 2027',    30, DATE '2027-06-15', DATE '2027-07-31');
  ins('Temporada baja',       'Agosto y septiembre 2027',                 0, DATE '2027-08-01', DATE '2027-10-04');
  ins('Receso de octubre',    'Semana de receso escolar 2027',           15, DATE '2027-10-05', DATE '2027-10-18');
  ins('Temporada baja',       'Octubre a diciembre 2027',                 0, DATE '2027-10-19', DATE '2027-12-14');
  ins('Temporada decembrina', 'Navidad y fin de anio 2027',              45, DATE '2027-12-15', DATE '2027-12-31');
  COMMIT;
END;
/

-- ---------------------------------------------------------------------
-- 2. Secuencias
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_auditoria_tarifa     START WITH 1 CACHE 20;
CREATE SEQUENCE seq_auditoria_sentencia  START WITH 1 CACHE 20;

-- ---------------------------------------------------------------------
-- 3. AUDITORIA_TARIFA
--    Una fila por tarifa afectada. id_sentencia agrupa las filas que
--    cambio UNA misma sentencia (un UPDATE masivo = un id_sentencia).
-- ---------------------------------------------------------------------
CREATE TABLE auditoria_tarifa (
  id_auditoria   NUMBER        DEFAULT seq_auditoria_tarifa.NEXTVAL,
  id_sentencia   NUMBER        NOT NULL,
  id_tarifa      NUMBER        NOT NULL,   -- sin FK: debe sobrevivir al DELETE
  operacion      VARCHAR2(6)   NOT NULL,
  usuario_bd     VARCHAR2(30)  NOT NULL,   -- quien: usuario de la sesion Oracle
  usuario_app    VARCHAR2(64),             -- quien: usuario de la aplicacion
  fecha_cambio   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,   -- cuando
  valor_anterior NUMBER(12,2),
  valor_nuevo    NUMBER(12,2),
  CONSTRAINT pk_auditoria_tarifa PRIMARY KEY (id_auditoria)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_audtar_operacion CHECK (operacion IN ('INSERT','UPDATE','DELETE'))
) TABLESPACE ts_turismo_hist;

CREATE INDEX ix_audtar_tarifa ON auditoria_tarifa (id_tarifa, fecha_cambio)
  TABLESPACE ts_turismo_idx;

COMMENT ON TABLE auditoria_tarifa IS 'Bitacora de cambios sobre TARIFA (trigger trg_tarifa_auditoria)';

