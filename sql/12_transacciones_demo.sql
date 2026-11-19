-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 12 · Demostracion de transacciones: SAVEPOINT, ROLLBACK
--             parcial, ROLLBACK total y transaccion autonoma
-- ---------------------------------------------------------------------
-- EJECUCION MANUAL (no la hace Docker), como turismouq:
--
--   docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 \
--          @/docker-entrypoint-initdb.d/12_transacciones_demo.sql
--
-- Parte A · SAVEPOINT "a mano", sentencia por sentencia, mirando el
--           estado de la transaccion en V$TRANSACTION.
-- Parte B · pkg_transacciones.sp_reservar_y_pagar en sus cuatro
--           desenlaces:
--             B1 todo bien                     -> COMMIT
--             B2 servicio invalido             -> ROLLBACK PARCIAL
--             B3 anticipo insuficiente         -> ROLLBACK TOTAL
--             B4 habitacion ya reservada       -> ROLLBACK TOTAL
-- Parte D · pkg_transacciones.sp_registrar_abono: abonos y pago del
--           saldo de una reserva PENDIENTE (FOR UPDATE + SAVEPOINT).
-- Parte C · Limpieza: borra todo lo que creo la demo, el script se
--           puede repetir las veces que se quiera.
--
-- Las fechas son relativas a hoy (hoy+30 .. hoy+33) y las habitaciones
-- libres se buscan solas: no depende de ids fijos.
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
SET LINESIZE 160
SET PAGESIZE 100
SET VERIFY OFF
COLUMN estado        FORMAT A11
COLUMN resultado     FORMAT A16
COLUMN paso          FORMAT A9
COLUMN mensaje       FORMAT A70 WORD_WRAPPED
COLUMN habitaciones  FORMAT A12
COLUMN metodo_pago   FORMAT A15

ROLLBACK;

-- ---------------------------------------------------------------------
-- Preparacion: punto de partida y datos de la demo
-- ---------------------------------------------------------------------
VARIABLE max_res NUMBER
VARIABLE max_pag NUMBER
VARIABLE max_log NUMBER
VARIABLE h1      NUMBER
VARIABLE h2      NUMBER
VARIABLE h3      NUMBER
VARIABLE cli     NUMBER
VARIABLE res     NUMBER
VARIABLE pag     NUMBER
VARIABLE resul   VARCHAR2(20)
VARIABLE saldo   NUMBER

DECLARE
  v_in  DATE := TRUNC(SYSDATE) + 30;
  v_out DATE := TRUNC(SYSDATE) + 33;
BEGIN
  SELECT NVL(MAX(id_reserva), 0) INTO :max_res FROM reserva;
  SELECT NVL(MAX(id_pago), 0)    INTO :max_pag FROM pago;
  SELECT NVL(MAX(id_log), 0)     INTO :max_log FROM log_transaccion;

  -- Tres habitaciones dobles o mas grandes, activas y libres en el rango
  SELECT MAX(DECODE(rn, 1, id_habitacion)),
         MAX(DECODE(rn, 2, id_habitacion)),
         MAX(DECODE(rn, 3, id_habitacion))
    INTO :h1, :h2, :h3
    FROM (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) rn
            FROM habitacion h
            JOIN alojamiento a      ON a.id_alojamiento = h.id_alojamiento
            JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
           WHERE h.activo = 'S' AND a.activo = 'S' AND th.capacidad_maxima >= 2
             AND NOT EXISTS (SELECT 1
                               FROM reserva_habitacion rh
                               JOIN reserva r ON r.id_reserva = rh.id_reserva
                              WHERE rh.id_habitacion = h.id_habitacion
                                AND r.estado <> 'CANCELADA'
                                AND rh.fecha_checkin  < v_out
                                AND rh.fecha_checkout > v_in))
   WHERE rn <= 3;

  :cli := 1;    -- reserva hecha por recepcion (usuario 1 = recep01)

  DBMS_OUTPUT.PUT_LINE('Fechas de la demo : ' || TO_CHAR(v_in, 'YYYY-MM-DD') ||
                       ' a ' || TO_CHAR(v_out, 'YYYY-MM-DD'));
  DBMS_OUTPUT.PUT_LINE('Habitaciones libres: ' || :h1 || ', ' || :h2 || ', ' || :h3);
END;
/

-- =====================================================================
-- PARTE A · SAVEPOINT paso a paso
-- ---------------------------------------------------------------------
-- Un recepcionista registra una reserva y su pago. Luego descubre que el
-- pago se digito mal: quiere deshacer SOLO el pago y conservar la
-- reserva. Eso es ROLLBACK TO SAVEPOINT.
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT  PARTE A. SAVEPOINT paso a paso
PROMPT =====================================================================

PROMPT
PROMPT --- A1. Reserva creada SIN confirmar (p_confirmar => FALSE)
BEGIN
  pkg_turismo.sp_crear_reserva(:cli, 1, TRUNC(SYSDATE) + 30, TRUNC(SYSDATE) + 33,
                               2, TO_CHAR(:h1), :res, p_confirmar => FALSE);
END;
/
PRINT res

PROMPT --- Estado de la transaccion: ACTIVA, con registros de UNDO
SELECT t.status, t.used_urec AS registros_undo
  FROM v$transaction t
  JOIN v$session s ON s.taddr = t.addr
 WHERE s.sid = SYS_CONTEXT('USERENV', 'SID');

PROMPT
PROMPT --- A2. SAVEPOINT sp_reserva_ok
SAVEPOINT sp_reserva_ok;

PROMPT --- A3. Pago y actualizacion de la reserva (valor mal digitado)
INSERT INTO pago (id_reserva, valor, fecha_pago, metodo_pago, estado)
VALUES (:res, 1000, SYSDATE, 'PSE', 'APROBADO');

UPDATE reserva
   SET valor_pagado = valor_pagado + 1000,
       estado       = 'CONFIRMADA'
 WHERE id_reserva = :res;

PROMPT --- A4. Dentro de la transaccion se ve todo
SELECT r.id_reserva, r.estado, r.valor_total, r.valor_pagado,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagos
  FROM reserva r
 WHERE r.id_reserva = :res;

SELECT t.used_urec AS registros_undo
  FROM v$transaction t
  JOIN v$session s ON s.taddr = t.addr
 WHERE s.sid = SYS_CONTEXT('USERENV', 'SID');

PROMPT
PROMPT --- A5. ROLLBACK TO sp_reserva_ok: se deshace SOLO el pago
ROLLBACK TO sp_reserva_ok;

SELECT r.id_reserva, r.estado, r.valor_total, r.valor_pagado,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagos
  FROM reserva r
 WHERE r.id_reserva = :res;

PROMPT (la reserva sigue ahi, PENDIENTE y sin pago; la transaccion sigue
PROMPT  ACTIVA y el UNDO volvio al tamano que tenia en el savepoint)
SELECT t.status, t.used_urec AS registros_undo
  FROM v$transaction t
  JOIN v$session s ON s.taddr = t.addr
 WHERE s.sid = SYS_CONTEXT('USERENV', 'SID');

PROMPT
PROMPT --- A6. ROLLBACK completo: nunca se confirmo nada
ROLLBACK;

SELECT COUNT(*) AS reserva_existe FROM reserva WHERE id_reserva = :res;

PROMPT (sin transaccion activa: la consulta a V$TRANSACTION no devuelve filas)
SELECT t.status
  FROM v$transaction t
  JOIN v$session s ON s.taddr = t.addr
 WHERE s.sid = SYS_CONTEXT('USERENV', 'SID');

-- =====================================================================
-- PARTE B · sp_reservar_y_pagar
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT  PARTE B. pkg_transacciones.sp_reservar_y_pagar
PROMPT =====================================================================

-- ---------------------------------------------------------------------
PROMPT
PROMPT --- B1. Todo bien: reserva + 2 servicios + pago del 60 % del hospedaje -> COMMIT
-- El anticipo se calcula con el mismo valor que cobrara el paquete
DECLARE
  v_hosp NUMBER := pkg_turismo.fn_valor_estadia(:h1, TRUNC(SYSDATE) + 30,
                                                TRUNC(SYSDATE) + 33);
BEGIN
  pkg_transacciones.sp_reservar_y_pagar(
    p_id_cliente         => :cli,
    p_id_usuario_sistema => 1,
    p_checkin            => TRUNC(SYSDATE) + 30,
    p_checkout           => TRUNC(SYSDATE) + 33,
    p_num_huespedes      => 2,
    p_habitaciones       => TO_CHAR(:h1),
    p_servicios          => '2:2,16:2',          -- Cocora x2, desayuno x2
    p_valor_pago         => ROUND(v_hosp * 0.6, -2),
    p_metodo_pago        => 'TARJETA_CREDITO',
    p_id_reserva         => :res,
    p_id_pago            => :pag,
    p_resultado          => :resul);
END;
/
PRINT resul

SELECT r.id_reserva, r.estado, r.valor_total, r.valor_pagado, r.valor_pendiente,
       (SELECT COUNT(*) FROM reserva_servicio s WHERE s.id_reserva = r.id_reserva) AS servicios,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagos
  FROM reserva r
 WHERE r.id_reserva = :res;

-- ---------------------------------------------------------------------
PROMPT
PROMPT --- B2. Servicio 999 no existe -> ROLLBACK TO sp_servicios (PARCIAL)
PROMPT     La reserva y el pago se guardan; los servicios se descartan todos.
DECLARE
  v_hosp NUMBER := pkg_turismo.fn_valor_estadia(:h2, TRUNC(SYSDATE) + 30,
                                                TRUNC(SYSDATE) + 33);
BEGIN
  pkg_transacciones.sp_reservar_y_pagar(
    :cli, 1, TRUNC(SYSDATE) + 30, TRUNC(SYSDATE) + 33, 2, TO_CHAR(:h2),
    '3:2,999:1',                 -- el 3 existe, el 999 no
    ROUND(v_hosp * 0.5, -2), 'PSE',
    :res, :pag, :resul);
END;
/
PRINT resul

PROMPT (servicios = 0: tambien se deshizo la linea del servicio 3, que si existia,
PROMPT  y el valor_total volvio a ser solo el hospedaje)
SELECT r.id_reserva, r.estado, r.valor_total, r.valor_pagado,
       (SELECT COUNT(*) FROM reserva_servicio s WHERE s.id_reserva = r.id_reserva) AS servicios,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagos
  FROM reserva r
 WHERE r.id_reserva = :res;

-- ---------------------------------------------------------------------
PROMPT
PROMPT --- B3. Anticipo de 1.000 pesos (< 30 %) -> ROLLBACK TO sp_inicio (TOTAL)
BEGIN
  pkg_transacciones.sp_reservar_y_pagar(
    :cli, 1, TRUNC(SYSDATE) + 30, TRUNC(SYSDATE) + 33, 2, TO_CHAR(:h3),
    '7:2', 1000, 'EFECTIVO',
    :res, :pag, :resul);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error recibido por el llamador: ' || SQLERRM);
END;
/

PROMPT (no quedo ninguna reserva sobre la habitacion h3: todo o nada)
SELECT COUNT(*) AS reservas_en_h3
  FROM reserva_habitacion
 WHERE id_habitacion = :h3
   AND id_reserva > :max_res;

-- ---------------------------------------------------------------------
PROMPT
PROMPT --- B4. Reservar otra vez la habitacion de B1 -> -20047, ROLLBACK TOTAL
BEGIN
  pkg_transacciones.sp_reservar_y_pagar(
    2, 1, TRUNC(SYSDATE) + 31, TRUNC(SYSDATE) + 32, 1, TO_CHAR(:h1),
    NULL, 500000, 'PSE',
    :res, :pag, :resul);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error recibido por el llamador: ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
PROMPT
PROMPT --- Bitacora: los intentos fallidos SIGUEN registrados aunque su
PROMPT --- transaccion hizo ROLLBACK (PRAGMA AUTONOMOUS_TRANSACTION)
SELECT id_log, habitaciones, id_reserva, id_pago, resultado, paso,
       codigo_error, mensaje
  FROM log_transaccion
 WHERE id_log > :max_log
 ORDER BY id_log;

PROMPT
PROMPT --- Lo que quedo confirmado en la base
SELECT r.id_reserva, rh.id_habitacion, r.estado, r.valor_total, r.valor_pagado,
       p.id_pago, p.metodo_pago, p.valor AS valor_pago
  FROM reserva r
  JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
  LEFT JOIN pago p           ON p.id_reserva  = r.id_reserva
 WHERE r.id_reserva > :max_res
 ORDER BY r.id_reserva;

-- =====================================================================
-- PARTE D · sp_registrar_abono
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT  PARTE D. pkg_transacciones.sp_registrar_abono
PROMPT =====================================================================
PROMPT --- D0. Reserva PENDIENTE, sin pagos, sobre la habitacion h3 (libre tras B3)
BEGIN
  pkg_turismo.sp_crear_reserva(:cli, 1, TRUNC(SYSDATE) + 30, TRUNC(SYSDATE) + 33,
                               2, TO_CHAR(:h3), :res);
END;
/
SELECT id_reserva, estado, valor_total, valor_pagado, valor_pendiente
  FROM reserva WHERE id_reserva = :res;

PROMPT
PROMPT --- D1. Abono de 1.000 a una reserva PENDIENTE -> -20053 (no cubre el 30 %)
BEGIN
  pkg_transacciones.sp_registrar_abono(:res, 1000, 'EFECTIVO', :pag, :saldo);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error recibido: ' || SQLERRM);
END;
/

PROMPT
PROMPT --- D2. Metodo de pago invalido -> -20051
BEGIN
  pkg_transacciones.sp_registrar_abono(:res, 100000, 'BITCOIN', :pag, :saldo);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error recibido: ' || SQLERRM);
END;
/

PROMPT
PROMPT --- D3. Abono del 40 % -> COMMIT, la reserva pasa a CONFIRMADA
DECLARE
  v_total NUMBER;
BEGIN
  SELECT valor_total INTO v_total FROM reserva WHERE id_reserva = :res;
  pkg_transacciones.sp_registrar_abono(:res, ROUND(v_total * 0.4, -2), 'PSE', :pag, :saldo);
END;
/

PROMPT
PROMPT --- D4. Abonar mas que el saldo -> -20050 (no se cobra de mas)
BEGIN
  pkg_transacciones.sp_registrar_abono(:res, 999999999, 'EFECTIVO', :pag, :saldo);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error recibido: ' || SQLERRM);
END;
/

PROMPT
PROMPT --- D5. Pago del saldo completo -> saldo 0
DECLARE
  v_saldo NUMBER;
BEGIN
  SELECT valor_pendiente INTO v_saldo FROM reserva WHERE id_reserva = :res;
  pkg_transacciones.sp_registrar_abono(:res, v_saldo, 'TARJETA_DEBITO', :pag, :saldo);
END;
/
SELECT r.id_reserva, r.estado, r.valor_total, r.valor_pagado, r.valor_pendiente,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagos
  FROM reserva r WHERE r.id_reserva = :res;

PROMPT
PROMPT --- D6. Reserva que no existe -> -20054 ; reserva cancelada -> -20055
BEGIN
  pkg_transacciones.sp_registrar_abono(-1, 1000, 'EFECTIVO', :pag, :saldo);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error recibido: ' || SQLERRM);
END;
/
DECLARE
  v_cancelada NUMBER;
BEGIN
  SELECT MIN(id_reserva) INTO v_cancelada FROM reserva WHERE estado = 'CANCELADA';
  pkg_transacciones.sp_registrar_abono(v_cancelada, 1000, 'EFECTIVO', :pag, :saldo);
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error recibido: ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- Concurrencia (manual, dos sesiones): en la sesion 1 bloquee la reserva
--   SELECT * FROM reserva WHERE id_reserva = <id> FOR UPDATE;   -- sin COMMIT
-- y en la sesion 2 ejecute sp_registrar_abono sobre la misma reserva: se
-- queda esperando (enq: TX - row lock contention, visible en
-- 16_concurrencia_monitor.sql). Al hacer COMMIT en la sesion 1, la sesion 2
-- continua y valida contra el saldo ya actualizado.
-- ---------------------------------------------------------------------

-- =====================================================================
-- PARTE C · Limpieza (comentar este bloque para conservar los datos)
-- =====================================================================
PROMPT
PROMPT =====================================================================
PROMPT  PARTE C. Limpieza
PROMPT =====================================================================
BEGIN
  DELETE FROM pago            WHERE id_reserva > :max_res;
  DELETE FROM reserva         WHERE id_reserva > :max_res;   -- cascada a rh y rs
  DELETE FROM log_transaccion WHERE id_log     > :max_log;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Datos de la demostracion eliminados.');
END;
/
