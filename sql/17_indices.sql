-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 17 · Indices: 3 consultas lentas, plan antes y despues,
--             medicion, y un caso donde el indice NO ayuda
-- ---------------------------------------------------------------------
-- EJECUCION MANUAL, como turismouq (tarda ~1 minuto):
--
--   docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 \
--          @/docker-entrypoint-initdb.d/17_indices.sql
--
-- Es idempotente: borra los indices del experimento al empezar, mide sin
-- ellos, los crea y vuelve a medir. Al terminar los indices quedan creados.
--
-- Como se mide (para cada consulta y cada fase):
--   a) EXPLAIN PLAN + costo del optimizador        (estimado)
--   b) 200 ejecuciones reales: lecturas logicas (buffers) y milisegundos
--      por ejecucion, leidos de V$MYSTAT            (medido)
--   c) DBMS_XPLAN.DISPLAY_CURSOR 'ALLSTATS LAST': el plan que de verdad
--      se ejecuto, con filas reales (A-Rows) y buffers por paso.
-- Las lecturas logicas son la medida principal: no dependen de si el
-- bloque estaba en cache ni de la carga del portatil; los milisegundos
-- si, y con este volumen son pequenos en los dos casos.
--
--   Q1  Llegadas de la semana (recepcion)      -> indice COMPUESTO
--       reserva (estado, fecha_checkin)
--   Q2  Cierre de caja de un dia               -> indice BASADO EN FUNCION
--       pago (TRUNC(fecha_pago))
--       (y antes, la prueba de que un indice normal sobre fecha_pago
--        no sirve porque la consulta aplica TRUNC a la columna)
--   Q3  Agenda de servicios de un dia          -> indice COMPUESTO que
--       reserva_servicio (fecha_servicio, id_servicio, cantidad)  CUBRE
--   Q4  Total de reservas FINALIZADAS          -> el indice NO ayuda
--       (mismo indice de Q1; 82 % de la tabla cumple el filtro)
-- =====================================================================

-- Si Docker lo corre al crear el contenedor (como SYS en CDB$ROOT) se
-- detiene aqui sin tocar nada.
WHENEVER SQLERROR EXIT
BEGIN
  IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
    RAISE_APPLICATION_ERROR(-20999,
      'Script de ejecucion manual: conectese como turismouq a XEPDB1.');
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 180
SET PAGESIZE 200
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMSPOOL ON
COLUMN consulta   FORMAT A4
COLUMN fase       FORMAT A16
COLUMN acceso     FORMAT A62 WORD_WRAPPED
COLUMN plan_table_output FORMAT A160

-- =====================================================================
-- 0. Punto de partida limpio
-- =====================================================================
PROMPT
PROMPT === 0. Limpieza, estadisticas y tabla de resultados ===
BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
             WHERE index_name IN ('IX_RESERVA_ESTADO_CHECKIN', 'IX_PAGO_FECHA',
                                  'IX_PAGO_DIA', 'IX_RS_FECHA_SERVICIO')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
  END LOOP;
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name = 'MEDICION_INDICE') LOOP
    EXECUTE IMMEDIATE 'DROP TABLE medicion_indice PURGE';
  END LOOP;
END;
/

-- Estadisticas frescas. ESTADO lleva histograma: sus 5 valores estan muy
-- desbalanceados (82 % FINALIZADA, 7 % CONFIRMADA) y sin histograma el
-- optimizador supondria 20 % para cada uno.
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA',
    method_opt => 'FOR ALL COLUMNS SIZE 1 FOR COLUMNS SIZE 254 ESTADO', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO',             cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_SERVICIO', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'CLIENTE',          cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'SERVICIO',         cascade => TRUE);
END;
/

CREATE TABLE medicion_indice (
  orden        NUMBER,
  consulta     VARCHAR2(4),
  fase         VARCHAR2(16),
  costo        NUMBER,
  filas        NUMBER,
  buffers      NUMBER(10,1),    -- lecturas logicas por ejecucion
  ms           NUMBER(10,3),    -- milisegundos por ejecucion
  acceso       VARCHAR2(400)    -- operaciones de acceso del plan
) TABLESPACE ts_turismo_datos;

-- ---------------------------------------------------------------------
-- Procedimiento de medicion (local al script, se borra al final)
--   EXPLAIN PLAN -> costo y operaciones de acceso
--   p_n ejecuciones con DBMS_SQL, leyendo todas las filas
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE tmp_medir (p_consulta VARCHAR2, p_fase VARCHAR2,
                                       p_sql VARCHAR2, p_n PLS_INTEGER DEFAULT 200)
IS
  v_cur    INTEGER;
  v_ign    INTEGER;
  v_filas  NUMBER := 0;
  v_lr0    NUMBER;
  v_lr1    NUMBER;
  v_t0     TIMESTAMP;
  v_t1     TIMESTAMP;
  v_costo  NUMBER;
  v_acceso VARCHAR2(400);
  v_id     VARCHAR2(30) := p_consulta || '_' || SUBSTR(p_fase, 1, 10);

  FUNCTION lecturas RETURN NUMBER IS
    v NUMBER;
  BEGIN
    SELECT m.value INTO v
      FROM v$mystat m JOIN v$statname n ON n.statistic# = m.statistic#
     WHERE n.name = 'session logical reads';
    RETURN v;
  END;
BEGIN
  DELETE FROM plan_table WHERE statement_id = v_id;
  EXECUTE IMMEDIATE 'EXPLAIN PLAN SET STATEMENT_ID = ''' || v_id || ''' FOR ' || p_sql;

  SELECT MAX(CASE WHEN id = 0 THEN cost END),
         LISTAGG(CASE WHEN object_name IS NOT NULL
                      THEN operation || ' ' || options || ' ' || object_name END,
                 ' / ') WITHIN GROUP (ORDER BY id)
    INTO v_costo, v_acceso
    FROM plan_table
   WHERE statement_id = v_id;

  v_cur := DBMS_SQL.OPEN_CURSOR;
  DBMS_SQL.PARSE(v_cur, p_sql, DBMS_SQL.NATIVE);

  v_ign := DBMS_SQL.EXECUTE(v_cur);                 -- calentamiento
  WHILE DBMS_SQL.FETCH_ROWS(v_cur) > 0 LOOP NULL; END LOOP;

  v_lr0 := lecturas;
  v_t0  := SYSTIMESTAMP;
  FOR i IN 1 .. p_n LOOP
    v_ign := DBMS_SQL.EXECUTE(v_cur);
    WHILE DBMS_SQL.FETCH_ROWS(v_cur) > 0 LOOP
      v_filas := v_filas + 1;
    END LOOP;
  END LOOP;
  v_t1  := SYSTIMESTAMP;
  v_lr1 := lecturas;
  DBMS_SQL.CLOSE_CURSOR(v_cur);

  INSERT INTO medicion_indice
  VALUES ((SELECT COUNT(*) + 1 FROM medicion_indice), p_consulta, p_fase,
          v_costo, v_filas / p_n,
          (v_lr1 - v_lr0) / p_n,
          (EXTRACT(SECOND FROM (v_t1 - v_t0)) + 60 * EXTRACT(MINUTE FROM (v_t1 - v_t0)))
            * 1000 / p_n,
          v_acceso);
  COMMIT;
END tmp_medir;
/

-- Muestra la ultima medicion
CREATE OR REPLACE VIEW tmp_ultima AS
SELECT consulta, fase, costo, filas, buffers, ms, acceso
  FROM medicion_indice
 WHERE orden = (SELECT MAX(orden) FROM medicion_indice);


-- =====================================================================
-- Q1 · Llegadas del dia  ->  INDICE COMPUESTO
-- ---------------------------------------------------------------------
-- Recepcion abre cada manana la lista de reservas CONFIRMADAS que llegan
-- ese dia (nombre y telefono del huesped). Sin indice: TABLE ACCESS FULL
-- de RESERVA (25.000 filas, ~250 bloques) para devolver ~50. Se mide con
-- el 18 de diciembre de 2026, un dia pico de temporada decembrina.
--
-- Indice (estado, fecha_checkin), en ese orden:
--   * Las dos columnas del filtro quedan en el ACCESS del RANGE SCAN:
--     el indice llega directo a las ~50 entradas (CONFIRMADA, 18-dic) en
--     2 bloques; ninguna fila se lee para descartarla despues.
--   * estado va primero: con "=" en estado y un RANGO de fechas (la
--     lista de toda la semana) las entradas siguen contiguas, porque
--     dentro de CONFIRMADA estan ordenadas por fecha. Al reves
--     (fecha_checkin, estado) el rango recorreria las reservas de la
--     semana de TODOS los estados y filtraria el estado despues.
--   * Sirve tambien para "WHERE estado = ..." solo (columna lider), pero
--     NO para "WHERE fecha_checkin = ..." solo.
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT Q1. Llegadas del dia (estado = CONFIRMADA, check-in 2026-12-18)
PROMPT =====================================================================

PROMPT --- ANTES
BEGIN
  tmp_medir('Q1', '1 antes',
    q'[SELECT r.id_reserva, r.num_huespedes, c.nombres, c.apellidos, c.telefono FROM reserva r JOIN cliente c ON c.id_cliente = r.id_cliente WHERE r.estado = 'CONFIRMADA' AND r.fecha_checkin = DATE '2026-12-18']');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ r.id_reserva, r.num_huespedes, c.nombres, c.apellidos, c.telefono FROM reserva r JOIN cliente c ON c.id_cliente = r.id_cliente WHERE r.estado = 'CONFIRMADA' AND r.fecha_checkin = DATE '2026-12-18';
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

PROMPT --- CREATE INDEX ix_reserva_estado_checkin ON reserva (estado, fecha_checkin)
CREATE INDEX ix_reserva_estado_checkin ON reserva (estado, fecha_checkin)
  TABLESPACE ts_turismo_idx;

PROMPT --- DESPUES
BEGIN
  tmp_medir('Q1', '2 despues',
    q'[SELECT r.id_reserva, r.num_huespedes, c.nombres, c.apellidos, c.telefono FROM reserva r JOIN cliente c ON c.id_cliente = r.id_cliente WHERE r.estado = 'CONFIRMADA' AND r.fecha_checkin = DATE '2026-12-18']');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ r.id_reserva, r.num_huespedes, c.nombres, c.apellidos, c.telefono FROM reserva r JOIN cliente c ON c.id_cliente = r.id_cliente WHERE r.estado = 'CONFIRMADA' AND r.fecha_checkin = DATE '2026-12-18';
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
SET SERVEROUTPUT ON


-- =====================================================================
-- Q2 · Cierre de caja de un dia  ->  INDICE BASADO EN FUNCION
-- ---------------------------------------------------------------------
-- Al final del dia se cuadran los pagos aprobados por metodo de pago.
-- FECHA_PAGO guarda hora (los pagos nuevos se registran con SYSDATE),
-- asi que la forma natural de pedir "los del dia" es TRUNC(fecha_pago).
--
-- Un indice normal sobre fecha_pago NO sirve: el indice esta ordenado
-- por fecha_pago, no por TRUNC(fecha_pago), y al aplicar una funcion a
-- la columna el optimizador ya no puede usarlo para buscar. Se
-- demuestra primero; luego se crea el indice sobre la EXPRESION.
-- (La alternativa seria reescribir el filtro como rango:
--  fecha_pago >= :dia AND fecha_pago < :dia + 1; el FBI permite dejar
--  la consulta como la escriben los usuarios.)
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT Q2. Cierre de caja del 2025-12-20 (TRUNC(fecha_pago) = dia)
PROMPT =====================================================================

PROMPT --- ANTES
BEGIN
  tmp_medir('Q2', '1 antes',
    q'[SELECT metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total FROM pago WHERE TRUNC(fecha_pago) = DATE '2025-12-20' AND estado = 'APROBADO' GROUP BY metodo_pago ORDER BY metodo_pago]');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total FROM pago WHERE TRUNC(fecha_pago) = DATE '2025-12-20' AND estado = 'APROBADO' GROUP BY metodo_pago ORDER BY metodo_pago;
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
SET SERVEROUTPUT ON

PROMPT --- Intento con un indice NORMAL sobre fecha_pago (no se usa)
CREATE INDEX ix_pago_fecha ON pago (fecha_pago) TABLESPACE ts_turismo_idx;
BEGIN
  tmp_medir('Q2', '1b indice normal',
    q'[SELECT metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total FROM pago WHERE TRUNC(fecha_pago) = DATE '2025-12-20' AND estado = 'APROBADO' GROUP BY metodo_pago ORDER BY metodo_pago]');
END;
/
SELECT * FROM tmp_ultima;
DROP INDEX ix_pago_fecha;

PROMPT --- CREATE INDEX ix_pago_dia ON pago (TRUNC(fecha_pago))
CREATE INDEX ix_pago_dia ON pago (TRUNC(fecha_pago)) TABLESPACE ts_turismo_idx;
-- El FBI crea una columna virtual oculta: necesita estadisticas propias
-- para que el optimizador sepa cuantas filas trae un dia.
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO', method_opt => 'FOR ALL HIDDEN COLUMNS SIZE 1', cascade => TRUE)

PROMPT --- DESPUES
BEGIN
  tmp_medir('Q2', '2 despues',
    q'[SELECT metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total FROM pago WHERE TRUNC(fecha_pago) = DATE '2025-12-20' AND estado = 'APROBADO' GROUP BY metodo_pago ORDER BY metodo_pago]');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total FROM pago WHERE TRUNC(fecha_pago) = DATE '2025-12-20' AND estado = 'APROBADO' GROUP BY metodo_pago ORDER BY metodo_pago;
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
SET SERVEROUTPUT ON


-- =====================================================================
-- Q3 · Agenda de servicios de un dia  ->  INDICE COMPUESTO QUE CUBRE
-- ---------------------------------------------------------------------
-- Operaciones necesita saber cada dia cuantos cupos programar de cada
-- servicio (tours, traslados, spa). RESERVA_SERVICIO tiene ~47.000
-- lineas y hoy se recorre entera para sacar las ~90 de un dia.
--
-- Indice (fecha_servicio, id_servicio, cantidad):
--   * fecha_servicio primero: es el filtro.
--   * id_servicio y cantidad son lo unico mas que la consulta lee de la
--     tabla: con ellos en el indice, Oracle responde SIN ir a la tabla
--     (no aparece TABLE ACCESS BY INDEX ROWID). Es un indice "que cubre".
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT Q3. Agenda de servicios del 2025-12-20
PROMPT =====================================================================

PROMPT --- ANTES
BEGIN
  tmp_medir('Q3', '1 antes',
    q'[SELECT s.nombre AS servicio, SUM(rs.cantidad) AS cupos, COUNT(*) AS reservas FROM reserva_servicio rs JOIN servicio s ON s.id_servicio = rs.id_servicio WHERE rs.fecha_servicio = DATE '2025-12-20' GROUP BY s.nombre ORDER BY cupos DESC]');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ s.nombre AS servicio, SUM(rs.cantidad) AS cupos, COUNT(*) AS reservas FROM reserva_servicio rs JOIN servicio s ON s.id_servicio = rs.id_servicio WHERE rs.fecha_servicio = DATE '2025-12-20' GROUP BY s.nombre ORDER BY cupos DESC;
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

PROMPT --- CREATE INDEX ix_rs_fecha_servicio ON reserva_servicio (fecha_servicio, id_servicio, cantidad)
CREATE INDEX ix_rs_fecha_servicio ON reserva_servicio (fecha_servicio, id_servicio, cantidad)
  TABLESPACE ts_turismo_idx;

PROMPT --- DESPUES
SET SERVEROUTPUT ON
BEGIN
  tmp_medir('Q3', '2 despues',
    q'[SELECT s.nombre AS servicio, SUM(rs.cantidad) AS cupos, COUNT(*) AS reservas FROM reserva_servicio rs JOIN servicio s ON s.id_servicio = rs.id_servicio WHERE rs.fecha_servicio = DATE '2025-12-20' GROUP BY s.nombre ORDER BY cupos DESC]');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS */ s.nombre AS servicio, SUM(rs.cantidad) AS cupos, COUNT(*) AS reservas FROM reserva_servicio rs JOIN servicio s ON s.id_servicio = rs.id_servicio WHERE rs.fecha_servicio = DATE '2025-12-20' GROUP BY s.nombre ORDER BY cupos DESC;
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
SET SERVEROUTPUT ON


-- =====================================================================
-- Q4 · Caso donde el indice NO ayuda
-- ---------------------------------------------------------------------
-- Gerencia pide el total facturado de las reservas FINALIZADAS. La
-- columna estado ya esta indexada (es la lider de ix_reserva_estado_checkin,
-- el indice de Q1), pero 20.417 de 25.000 reservas (82 %) son FINALIZADA.
--
-- Por que el optimizador lo ignora (y hace bien):
--   * Seleccion baja: el indice no "descarta" casi nada.
--   * Con el indice, por cada una de las ~20.000 entradas hay que ir a la
--     tabla por ROWID a leer valor_total: un acceso de UN bloque por
--     fila. Las reservas FINALIZADAS estan regadas por todos los bloques
--     de la tabla (clustering factor alto), asi que se leen los mismos
--     bloques una y otra vez: decenas de miles de lecturas.
--   * El FULL SCAN lee los ~250 bloques de la tabla una sola vez, y en
--     lecturas de varios bloques (multiblock read).
-- Se fuerza el indice con un hint para medir lo que costaria usarlo.
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT Q4. Total de reservas FINALIZADAS: el indice no ayuda
PROMPT =====================================================================

PROMPT --- Plan elegido por el optimizador (con el indice disponible)
BEGIN
  tmp_medir('Q4', '1 optimizador',
    q'[SELECT COUNT(*) AS reservas, SUM(valor_total) AS facturado FROM reserva r WHERE r.estado = 'FINALIZADA']');
END;
/
SELECT * FROM tmp_ultima;

PROMPT --- Forzando el indice con /*+ INDEX */
BEGIN
  tmp_medir('Q4', '2 indice forzado',
    q'[SELECT /*+ INDEX(r ix_reserva_estado_checkin) */ COUNT(*) AS reservas, SUM(valor_total) AS facturado FROM reserva r WHERE r.estado = 'FINALIZADA']');
END;
/
SELECT * FROM tmp_ultima;

SET SERVEROUTPUT OFF
SET TERMOUT OFF
SELECT /*+ GATHER_PLAN_STATISTICS INDEX(r ix_reserva_estado_checkin) */ COUNT(*) AS reservas, SUM(valor_total) AS facturado FROM reserva r WHERE r.estado = 'FINALIZADA';
SET TERMOUT ON
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
SET SERVEROUTPUT ON

PROMPT --- Seleccion y clustering factor del indice
COLUMN index_name FORMAT A26
SELECT i.index_name, i.clustering_factor, t.blocks AS bloques_tabla,
       t.num_rows AS filas_tabla,
       ROUND(100 * (SELECT COUNT(*) FROM reserva WHERE estado = 'FINALIZADA')
                 / t.num_rows, 1) AS pct_finalizada
  FROM user_indexes i
  JOIN user_tables t ON t.table_name = i.table_name
 WHERE i.index_name = 'IX_RESERVA_ESTADO_CHECKIN';


-- =====================================================================
-- Resumen
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT RESUMEN (buffers = lecturas logicas por ejecucion; ms por ejecucion)
PROMPT =====================================================================
SELECT consulta, fase, costo, filas, buffers, ms, acceso
  FROM medicion_indice
 ORDER BY orden;

PROMPT
PROMPT --- Mejora en lecturas logicas (antes / despues)
SELECT a.consulta,
       a.buffers AS buffers_antes,
       d.buffers AS buffers_despues,
       ROUND(a.buffers / NULLIF(d.buffers, 0), 1) AS veces_menos,
       a.ms AS ms_antes,
       d.ms AS ms_despues
  FROM medicion_indice a
  JOIN medicion_indice d ON d.consulta = a.consulta
 WHERE a.fase = '1 antes' AND d.fase = '2 despues'
 ORDER BY a.consulta;

PROMPT
PROMPT --- Indices de la Entrega 3
COLUMN columnas FORMAT A60
SELECT i.index_name, i.index_type, i.tablespace_name,
       LISTAGG(c.column_name, ', ')
         WITHIN GROUP (ORDER BY c.column_position) AS columnas
  FROM user_indexes i
  JOIN user_ind_columns c ON c.index_name = i.index_name
 WHERE i.index_name IN ('IX_RESERVA_ESTADO_CHECKIN', 'IX_PAGO_DIA', 'IX_RS_FECHA_SERVICIO')
 GROUP BY i.index_name, i.index_type, i.tablespace_name
 ORDER BY i.index_name;

PROMPT (la columna SYS_NC... de IX_PAGO_DIA es la expresion:)
COLUMN column_expression FORMAT A40
SELECT index_name, column_expression
  FROM user_ind_expressions
 WHERE index_name = 'IX_PAGO_DIA';

-- Limpieza de los auxiliares (la tabla de mediciones se conserva)
DROP VIEW tmp_ultima;
DROP PROCEDURE tmp_medir;
DELETE FROM plan_table;
COMMIT;

PROMPT
PROMPT Script 17 terminado. Los indices quedan creados; MEDICION_INDICE
PROMPT guarda los numeros.
