-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 1
-- Script 01 · Tablespaces y permisos
-- ---------------------------------------------------------------------
-- Se ejecuta automaticamente al crear el contenedor por primera vez
-- (ver docker-compose.yml: ./sql -> /docker-entrypoint-initdb.d, conexion
-- AS SYSDBA). Crea los tablespaces que usa 02_ddl.sql y le da cuota
-- ilimitada al usuario de la aplicacion (turismouq).
--
-- gvenzl/oracle-xe corre TODOS los scripts de /docker-entrypoint-initdb.d
-- conectado a la raiz (CDB$ROOT), sin importar la subcarpeta. Como la
-- aplicacion y el usuario turismouq viven en la PDB XEPDB1, hay que
-- cambiar de contenedor explicitamente antes de crear nada, o los
-- tablespaces quedarian en CDB$ROOT (donde nadie los puede usar).
--
-- Tamanos pensados para un contenedor de curso (XE 21c, datos de
-- practica). Ajustar SIZE/MAXSIZE si la carga de 03_carga.sql crece.
-- =====================================================================

ALTER SESSION SET CONTAINER = XEPDB1;

CREATE TABLESPACE ts_turismo_datos
  DATAFILE '/opt/oracle/oradata/XE/XEPDB1/ts_turismo_datos01.dbf'
  SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

CREATE TABLESPACE ts_turismo_idx
  DATAFILE '/opt/oracle/oradata/XE/XEPDB1/ts_turismo_idx01.dbf'
  SIZE 50M AUTOEXTEND ON NEXT 25M MAXSIZE 1G;

CREATE TABLESPACE ts_turismo_hist
  DATAFILE '/opt/oracle/oradata/XE/XEPDB1/ts_turismo_hist01.dbf'
  SIZE 100M AUTOEXTEND ON NEXT 50M MAXSIZE 2G;

ALTER USER turismouq QUOTA UNLIMITED ON ts_turismo_datos;
ALTER USER turismouq QUOTA UNLIMITED ON ts_turismo_idx;
ALTER USER turismouq QUOTA UNLIMITED ON ts_turismo_hist;

PROMPT Tablespaces creados y cuotas asignadas a turismouq.
