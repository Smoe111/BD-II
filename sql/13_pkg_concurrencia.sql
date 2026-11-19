-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 13 · Concurrencia: dos sesiones reservando la misma habitacion
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq (en Docker corre solo al crear el contenedor)
--
-- Crea lo necesario para el experimento; los pasos estan en
--   14_concurrencia_preparar.sql   limpia y fija el escenario (1..4)
--   15_concurrencia_sesion.sql     lo que corre cada sesion (A y B)
--   16_concurrencia_monitor.sql    tercera sesion: quien bloquea a quien
-- y la guia completa con los resultados en ENTREGA3.md.
--
-- El problema: reservar es LEER-VERIFICAR-ESCRIBIR.
--   1. leer   : ¿hay otra reserva activa que se cruce?   (SELECT COUNT)
--   2. pensar : el usuario confirma, la pasarela responde (segundos)
--   3. escribir: INSERT de la reserva y COMMIT
-- En READ COMMITTED (el nivel por defecto de Oracle) la sesion B no ve
-- lo que A todavia no confirmo; si las dos leen antes de que la otra
-- confirme, las dos concluyen "libre" y las dos escriben: DOBLE RESERVA.
-- Ninguna constraint lo impide (son dos filas distintas de
-- RESERVA_HABITACION, con PK distinta).
--
-- Procedimientos (DBMS_SESSION.SLEEP simula el paso 2 para que el
-- cruce de las dos sesiones sea reproducible a mano):
--   sp_reservar_sin_control  paso 1 con un SELECT normal: ANTES
--   sp_reservar_con_bloqueo  paso 1 precedido de SELECT ... FOR UPDATE
--                            sobre la fila de HABITACION: DESPUES
--                            p_modo: 'ESPERAR' | 'NOWAIT' | 'WAIT'
--
-- Codigos de error:
--   -20047  habitacion no disponible (mismo codigo que sp_crear_reserva)
--   -20060  la habitacion la esta reservando otra sesion (NOWAIT / WAIT)
-- =====================================================================

ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED

-- =====================================================================
-- 1. Vista de monitoreo: sesiones de turismouq y quien las bloquea
--    (usa los permisos de diagnostico de 01_tablespaces.sql)
-- =====================================================================
CREATE OR REPLACE VIEW v_monitor_bloqueos AS
SELECT s.sid,
       s.serial#,
       s.username,
       s.status,
       s.client_info                       AS sesion,      -- 'A' / 'B'
       s.blocking_session                  AS bloqueada_por,
       s.event                             AS evento,
       s.seconds_in_wait                   AS seg_esperando,
       s.row_wait_obj#                     AS objeto_esperado,
       (SELECT o.object_name
          FROM user_objects o
         WHERE o.object_id = s.row_wait_obj#) AS tabla_esperada,
       s.sql_id
  FROM v$session s
 WHERE s.username = 'TURISMOUQ'
   AND s.type     = 'USER';

COMMENT ON TABLE v_monitor_bloqueos IS
  'Sesiones de TURISMOUQ: la columna BLOQUEADA_POR dice que SID tiene la fila';

-- =====================================================================
-- 2. Especificacion
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_concurrencia AS

  -- Datos fijos del experimento: Semana Santa 2027 (40 % de recargo), una
  -- habitacion doble del primer alojamiento. La carga llega hasta enero
  -- de 2027, asi que esas noches estan libres.
  c_habitacion CONSTANT NUMBER := 2;
  c_checkin    CONSTANT DATE   := DATE '2027-03-24';
  c_checkout   CONSTANT DATE   := DATE '2027-03-27';
  c_usuario    CONSTANT NUMBER := 1;          -- recep01

  -- ANTES: verificar con un SELECT comun y luego insertar
  PROCEDURE sp_reservar_sin_control (p_sesion     IN VARCHAR2,
                                     p_id_cliente IN NUMBER,
                                     p_pausa      IN NUMBER DEFAULT 10);

  -- DESPUES: bloquear la habitacion con SELECT ... FOR UPDATE, verificar
  -- e insertar. p_modo:
  --   ESPERAR  FOR UPDATE          espera lo que haga falta
  --   NOWAIT   FOR UPDATE NOWAIT   si esta tomada, falla al instante
  --   WAIT     FOR UPDATE WAIT 5   espera maximo 5 segundos
  PROCEDURE sp_reservar_con_bloqueo (p_sesion     IN VARCHAR2,
                                     p_id_cliente IN NUMBER,
                                     p_modo       IN VARCHAR2 DEFAULT 'ESPERAR',
                                     p_pausa      IN NUMBER   DEFAULT 10);

  -- Borra las reservas del experimento y deja el trigger de solape
  -- ENABLED o DISABLED segun el escenario
  PROCEDURE sp_preparar (p_trigger_activo IN BOOLEAN);

  -- Reservas activas de la habitacion del experimento
  PROCEDURE sp_resultado;

END pkg_concurrencia;
/

-- =====================================================================
-- 3. Cuerpo
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_concurrencia AS

  -- Hora con decimas de segundo y la sesion que habla
  PROCEDURE msg (p_sesion VARCHAR2, p_texto VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('[' || p_sesion || ' ' ||
                         TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS.FF1') || '] ' || p_texto);
  END msg;

  -- Paso 1 de las dos versiones: ¿la habitacion esta libre?
  FUNCTION ocupadas RETURN NUMBER IS
    v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n
      FROM reserva_habitacion rh
      JOIN reserva r ON r.id_reserva = rh.id_reserva
     WHERE rh.id_habitacion  = c_habitacion
       AND r.estado         <> 'CANCELADA'
       AND rh.fecha_checkin  < c_checkout
       AND rh.fecha_checkout > c_checkin;
    RETURN v_n;
  END ocupadas;

  -- Paso 3 de las dos versiones: insertar la reserva
  PROCEDURE insertar (p_sesion VARCHAR2, p_id_cliente NUMBER) IS
    v_valor NUMBER;
    v_id    NUMBER;
  BEGIN
    v_valor := pkg_turismo.fn_valor_estadia(c_habitacion, c_checkin, c_checkout);

    INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_checkin,
                         fecha_checkout, estado, num_huespedes,
                         valor_total, valor_pagado)
    VALUES (p_id_cliente, c_usuario, c_checkin, c_checkout, 'CONFIRMADA', 2,
            v_valor, 0)
    RETURNING id_reserva INTO v_id;

    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                    fecha_checkout, valor_previo, valor_reserva)
    SELECT v_id, c_habitacion, c_checkin, c_checkout,
           (c_checkout - c_checkin) * t.valor, v_valor
      FROM habitacion h
      JOIN tarifa t ON t.id_tarifa = h.id_tarifa
     WHERE h.id_habitacion = c_habitacion;

    COMMIT;
    msg(p_sesion, 'COMMIT. Reserva ' || v_id || ' guardada para el cliente ' ||
                  p_id_cliente);
  END insertar;

  -- -------------------------------------------------------------------
  -- ANTES: sin control de concurrencia
  -- -------------------------------------------------------------------
  PROCEDURE sp_reservar_sin_control (p_sesion     IN VARCHAR2,
                                     p_id_cliente IN NUMBER,
                                     p_pausa      IN NUMBER DEFAULT 10)
  IS
    v_n NUMBER;
  BEGIN
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(p_sesion);
    msg(p_sesion, 'Inicio SIN control. Consulto disponibilidad de la habitacion ' ||
                  c_habitacion);

    v_n := ocupadas;                       -- 1. leer (sin bloquear nada)
    IF v_n > 0 THEN
      RAISE_APPLICATION_ERROR(-20047,
        'La habitacion ' || c_habitacion || ' no esta disponible.');
    END IF;
    msg(p_sesion, 'La veo LIBRE. Confirmando con el cliente (' || p_pausa || ' s)...');

    DBMS_SESSION.SLEEP(p_pausa);           -- 2. pensar

    insertar(p_sesion, p_id_cliente);      -- 3. escribir
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      msg(p_sesion, 'RECHAZADA: ' || SQLERRM);
  END sp_reservar_sin_control;

  -- -------------------------------------------------------------------
  -- DESPUES: SELECT ... FOR UPDATE (bloqueo pesimista)
  -- La fila de HABITACION hace de "candado" de la habitacion: quien la
  -- tiene bloqueada es el unico que puede verificar y escribir reservas
  -- de ella. La segunda sesion se detiene EN EL FOR UPDATE (antes de
  -- leer); cuando la primera hace COMMIT el bloqueo se libera, la
  -- segunda continua y su SELECT, que empieza despues de ese COMMIT, ya
  -- ve la reserva nueva.
  -- -------------------------------------------------------------------
  PROCEDURE sp_reservar_con_bloqueo (p_sesion     IN VARCHAR2,
                                     p_id_cliente IN NUMBER,
                                     p_modo       IN VARCHAR2 DEFAULT 'ESPERAR',
                                     p_pausa      IN NUMBER   DEFAULT 10)
  IS
    v_num    habitacion.numero_habitacion%TYPE;
    v_n      NUMBER;
    v_t0     TIMESTAMP := SYSTIMESTAMP;
    e_ocupado  EXCEPTION;                  -- ORA-00054 (NOWAIT)
    e_timeout  EXCEPTION;                  -- ORA-30006 (WAIT n)
    PRAGMA EXCEPTION_INIT(e_ocupado, -54);
    PRAGMA EXCEPTION_INIT(e_timeout, -30006);
  BEGIN
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(p_sesion);
    msg(p_sesion, 'Inicio CON bloqueo (' || UPPER(p_modo) ||
                  '). Pido la fila de la habitacion ' || c_habitacion);

    -- FOR UPDATE WAIT necesita un literal: una sentencia por modo
    CASE UPPER(p_modo)
      WHEN 'NOWAIT' THEN
        SELECT numero_habitacion INTO v_num FROM habitacion
         WHERE id_habitacion = c_habitacion
           FOR UPDATE NOWAIT;
      WHEN 'WAIT' THEN
        SELECT numero_habitacion INTO v_num FROM habitacion
         WHERE id_habitacion = c_habitacion
           FOR UPDATE WAIT 5;
      ELSE
        SELECT numero_habitacion INTO v_num FROM habitacion
         WHERE id_habitacion = c_habitacion
           FOR UPDATE;
    END CASE;

    msg(p_sesion, 'Bloqueo OBTENIDO tras ' ||
                  TO_CHAR(EXTRACT(SECOND FROM (SYSTIMESTAMP - v_t0))
                          + 60 * EXTRACT(MINUTE FROM (SYSTIMESTAMP - v_t0)),
                          'FM990.0') || ' s de espera');

    v_n := ocupadas;                       -- 1. leer, ya con el candado
    IF v_n > 0 THEN
      RAISE_APPLICATION_ERROR(-20047,
        'La habitacion ' || c_habitacion || ' (No. ' || v_num ||
        ') no esta disponible: otra sesion la reservo primero.');
    END IF;
    msg(p_sesion, 'La veo LIBRE. Confirmando con el cliente (' || p_pausa || ' s)...');

    DBMS_SESSION.SLEEP(p_pausa);           -- 2. pensar (con la fila bloqueada)

    insertar(p_sesion, p_id_cliente);      -- 3. escribir; el COMMIT suelta el bloqueo
  EXCEPTION
    WHEN e_ocupado OR e_timeout THEN
      ROLLBACK;
      msg(p_sesion, 'RECHAZADA: ' || SQLERRM);
      msg(p_sesion, '-20060 la habitacion la esta reservando otra sesion; ' ||
                    'intente en unos segundos.');
    WHEN OTHERS THEN
      ROLLBACK;                            -- tambien libera el bloqueo
      msg(p_sesion, 'RECHAZADA: ' || SQLERRM);
  END sp_reservar_con_bloqueo;

  -- -------------------------------------------------------------------
  PROCEDURE sp_preparar (p_trigger_activo IN BOOLEAN) IS
    v_n NUMBER := 0;
  BEGIN
    FOR r IN (SELECT DISTINCT rh.id_reserva
                FROM reserva_habitacion rh
               WHERE rh.id_habitacion  = c_habitacion
                 AND rh.fecha_checkin  < c_checkout
                 AND rh.fecha_checkout > c_checkin) LOOP
      DELETE FROM pago    WHERE id_reserva = r.id_reserva;
      DELETE FROM reserva WHERE id_reserva = r.id_reserva;   -- cascada a rh
      v_n := v_n + 1;
    END LOOP;
    COMMIT;

    -- DDL: hace COMMIT implicito; por eso va despues de la limpieza
    EXECUTE IMMEDIATE 'ALTER TRIGGER trg_rh_no_solape ' ||
                      CASE WHEN p_trigger_activo THEN 'ENABLE' ELSE 'DISABLE' END;

    DBMS_OUTPUT.PUT_LINE('Reservas del experimento borradas: ' || v_n);
    DBMS_OUTPUT.PUT_LINE('Habitacion ' || c_habitacion || ', ' ||
                         TO_CHAR(c_checkin, 'YYYY-MM-DD') || ' a ' ||
                         TO_CHAR(c_checkout, 'YYYY-MM-DD'));
    DBMS_OUTPUT.PUT_LINE('trg_rh_no_solape: ' ||
                         CASE WHEN p_trigger_activo THEN 'ENABLED' ELSE 'DISABLED' END);
  END sp_preparar;

  -- -------------------------------------------------------------------
  PROCEDURE sp_resultado IS
    v_n NUMBER := 0;
  BEGIN
    DBMS_OUTPUT.PUT_LINE('Reservas activas de la habitacion ' || c_habitacion ||
                         ' entre ' || TO_CHAR(c_checkin, 'YYYY-MM-DD') ||
                         ' y ' || TO_CHAR(c_checkout, 'YYYY-MM-DD') || ':');
    FOR r IN (SELECT r.id_reserva, r.id_cliente, r.fecha_creacion
                FROM reserva_habitacion rh
                JOIN reserva r ON r.id_reserva = rh.id_reserva
               WHERE rh.id_habitacion  = c_habitacion
                 AND r.estado         <> 'CANCELADA'
                 AND rh.fecha_checkin  < c_checkout
                 AND rh.fecha_checkout > c_checkin
               ORDER BY r.id_reserva) LOOP
      v_n := v_n + 1;
      DBMS_OUTPUT.PUT_LINE('  reserva ' || r.id_reserva || '  cliente ' ||
                           r.id_cliente || '  creada ' ||
                           TO_CHAR(r.fecha_creacion, 'HH24:MI:SS'));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(CASE v_n
                           WHEN 0 THEN '  (ninguna)'
                           WHEN 1 THEN '  => CORRECTO: una sola reserva'
                           ELSE '  => ERROR: DOBLE RESERVA de la misma habitacion'
                         END);
  END sp_resultado;

END pkg_concurrencia;
/

SHOW ERRORS PACKAGE BODY pkg_concurrencia

COLUMN object_name FORMAT A20
COLUMN object_type FORMAT A14
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_CONCURRENCIA', 'V_MONITOR_BLOQUEOS')
 ORDER BY object_name, object_type;

PROMPT Paquete PKG_CONCURRENCIA compilado. Experimento: 14, 15 y 16.
