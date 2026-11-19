-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 11 · Transacciones: reserva + servicios + pago en una sola
--             transaccion, con SAVEPOINT y rollback parcial
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq, despues de 07_pkg_turismo.sql y 08_triggers.sql
--   (en Docker corre solo al crear el contenedor, en orden alfabetico)
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @11_pkg_transacciones.sql
--
-- Contenido:
--   LOG_TRANSACCION        Bitacora de cada intento de reserva + pago.
--   pkg_transacciones
--     sp_log               Escribe en la bitacora con PRAGMA
--                          AUTONOMOUS_TRANSACTION: el registro sobrevive
--                          aunque la transaccion principal haga ROLLBACK.
--     sp_reservar_y_pagar  Registra reserva, servicios opcionales y pago
--                          de forma ATOMICA (todo o nada), con dos
--                          SAVEPOINT:
--
--     SAVEPOINT sp_inicio ─┐
--        1. reserva + habitaciones (pkg_turismo.sp_crear_reserva, sin COMMIT)
--     SAVEPOINT sp_servicios ─┐
--        2. servicios complementarios (opcionales)
--           └─ si alguno falla: ROLLBACK TO sp_servicios  (ROLLBACK PARCIAL:
--              se descartan solo los servicios, la reserva sigue viva)
--        3. pago + actualizacion de la reserva
--           └─ si falla: ROLLBACK TO sp_inicio (ROLLBACK TOTAL: no queda
--              ni reserva ni pago; "todo o nada")
--     COMMIT  ← una sola vez, al final
--     sp_registrar_abono   Pago total o abono al saldo de una reserva ya
--                          creada. Bloquea la fila de la reserva con
--                          SELECT ... FOR UPDATE: dos abonos simultaneos
--                          se serializan y el segundo valida contra el
--                          saldo ya descontado (no se paga de mas).
--
-- Codigos de error:
--   -20050  valor del pago invalido (<= 0 o mayor que el total)
--   -20051  metodo de pago invalido
--   -20052  servicio invalido (interno: provoca el rollback parcial)
--   -20053  anticipo insuficiente (menos del 30 % del total)
--   -20054  la reserva no existe                      (sp_registrar_abono)
--   -20055  la reserva esta cancelada: no recibe pagos (sp_registrar_abono)
--   ademas se propagan los de sp_crear_reserva (-20040..-20047) y el
--   del trigger de solape (-20003).
-- =====================================================================

ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED

-- ---------------------------------------------------------------------
-- 0. Limpieza (el script se puede volver a correr)
-- ---------------------------------------------------------------------
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE log_transaccion CASCADE CONSTRAINTS PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'DROP SEQUENCE seq_log_transaccion';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE <> -2289 THEN RAISE; END IF;
END;
/

-- ---------------------------------------------------------------------
-- 1. Bitacora de transacciones
--    Sin FK a RESERVA a proposito: guarda tambien los intentos que se
--    deshicieron, cuya reserva ya no existe.
-- ---------------------------------------------------------------------
CREATE SEQUENCE seq_log_transaccion START WITH 1 CACHE 20;

CREATE TABLE log_transaccion (
  id_log        NUMBER         DEFAULT seq_log_transaccion.NEXTVAL,
  fecha         TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
  usuario_bd    VARCHAR2(30)   DEFAULT SYS_CONTEXT('USERENV','SESSION_USER') NOT NULL,
  id_cliente    NUMBER,
  habitaciones  VARCHAR2(200),
  id_reserva    NUMBER,          -- NULL si la reserva se deshizo
  id_pago       NUMBER,
  resultado     VARCHAR2(16)   NOT NULL,
  paso          VARCHAR2(12),    -- RESERVA | SERVICIOS | PAGO
  codigo_error  NUMBER,
  mensaje       VARCHAR2(400),
  CONSTRAINT pk_log_transaccion PRIMARY KEY (id_log)
             USING INDEX TABLESPACE ts_turismo_idx,
  CONSTRAINT ck_log_resultado CHECK (resultado IN ('COMPLETA',
                                                   'ROLLBACK_PARCIAL',
                                                   'ROLLBACK_TOTAL')),
  CONSTRAINT ck_log_paso CHECK (paso IS NULL
                                OR paso IN ('RESERVA','SERVICIOS','PAGO'))
) TABLESPACE ts_turismo_hist;

COMMENT ON TABLE log_transaccion IS
  'Intentos de reserva + pago (pkg_transacciones). Se escribe con transaccion autonoma';

-- =====================================================================
-- 2. Especificacion
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_transacciones AS

  -- Anticipo minimo para confirmar una reserva, en % del total
  c_pct_anticipo CONSTANT NUMBER := 30;

  -- Escribe en LOG_TRANSACCION en su propia transaccion (autonoma)
  PROCEDURE sp_log (p_id_cliente   IN NUMBER,
                    p_habitaciones IN VARCHAR2,
                    p_id_reserva   IN NUMBER,
                    p_id_pago      IN NUMBER,
                    p_resultado    IN VARCHAR2,
                    p_paso         IN VARCHAR2,
                    p_codigo       IN NUMBER,
                    p_mensaje      IN VARCHAR2);

  -- Reserva + servicios + pago, atomico. Hace COMMIT al final.
  --   p_servicios : 'id_servicio:cantidad,...' (ej. '2:2,16:3'), opcional
  --   p_resultado : COMPLETA | ROLLBACK_PARCIAL (quedo sin servicios)
  PROCEDURE sp_reservar_y_pagar (p_id_cliente         IN  NUMBER,
                                 p_id_usuario_sistema IN  NUMBER,
                                 p_checkin            IN  DATE,
                                 p_checkout           IN  DATE,
                                 p_num_huespedes      IN  NUMBER,
                                 p_habitaciones       IN  VARCHAR2,
                                 p_servicios          IN  VARCHAR2,
                                 p_valor_pago         IN  NUMBER,
                                 p_metodo_pago        IN  VARCHAR2,
                                 p_id_reserva         OUT NUMBER,
                                 p_id_pago            OUT NUMBER,
                                 p_resultado          OUT VARCHAR2);

  -- Pago total o abono al saldo pendiente de una reserva existente.
  -- Si la reserva esta PENDIENTE, lo pagado tras el abono debe cubrir el
  -- anticipo (c_pct_anticipo) y entonces pasa a CONFIRMADA. Hace COMMIT.
  --   p_saldo : saldo pendiente despues del abono
  PROCEDURE sp_registrar_abono (p_id_reserva  IN  NUMBER,
                                p_valor       IN  NUMBER,
                                p_metodo_pago IN  VARCHAR2,
                                p_id_pago     OUT NUMBER,
                                p_saldo       OUT NUMBER);

END pkg_transacciones;
/

-- =====================================================================
-- 3. Cuerpo
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_transacciones AS

  -- -------------------------------------------------------------------
  -- sp_log: TRANSACCION AUTONOMA
  -- Si se escribiera la bitacora dentro de la transaccion principal, el
  -- ROLLBACK que deshace una reserva fallida borraria tambien el registro
  -- del fallo. Con PRAGMA AUTONOMOUS_TRANSACTION el INSERT se confirma
  -- con su propio COMMIT, sin confirmar ni deshacer nada del llamador.
  -- -------------------------------------------------------------------
  PROCEDURE sp_log (p_id_cliente   IN NUMBER,
                    p_habitaciones IN VARCHAR2,
                    p_id_reserva   IN NUMBER,
                    p_id_pago      IN NUMBER,
                    p_resultado    IN VARCHAR2,
                    p_paso         IN VARCHAR2,
                    p_codigo       IN NUMBER,
                    p_mensaje      IN VARCHAR2)
  IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO log_transaccion (id_cliente, habitaciones, id_reserva, id_pago,
                                 resultado, paso, codigo_error, mensaje)
    VALUES (p_id_cliente, SUBSTR(p_habitaciones, 1, 200), p_id_reserva, p_id_pago,
            p_resultado, p_paso, p_codigo, SUBSTR(p_mensaje, 1, 400));
    COMMIT;      -- confirma SOLO este insert
  END sp_log;

  -- -------------------------------------------------------------------
  -- Agrega los servicios a la reserva. Cualquier problema se reporta
  -- con -20052 para que el llamador haga el rollback parcial.
  -- El valor sigue la misma regla que 03_carga.sql: cantidad x valor del
  -- catalogo, ajustado por la temporada del dia del servicio y redondeado
  -- a centenas. El servicio se agenda el dia del check-in.
  -- -------------------------------------------------------------------
  PROCEDURE agregar_servicios (p_id_reserva IN  NUMBER,
                               p_fecha      IN  DATE,
                               p_servicios  IN  VARCHAR2,
                               p_total      OUT NUMBER)
  IS
    v_item    VARCHAR2(40);
    v_id      NUMBER;
    v_cant    NUMBER;
    v_valor   servicio.valor_servicio%TYPE;
    v_pct     temporada.porcentaje%TYPE;
    v_previo  NUMBER;
    v_final   NUMBER;
    i         PLS_INTEGER := 1;
  BEGIN
    p_total := 0;

    SELECT porcentaje INTO v_pct
      FROM temporada
     WHERE p_fecha BETWEEN fecha_inicio AND fecha_fin;

    LOOP
      v_item := TRIM(REGEXP_SUBSTR(p_servicios, '[^,]+', 1, i));
      EXIT WHEN v_item IS NULL;

      BEGIN
        v_id   := TO_NUMBER(REGEXP_SUBSTR(v_item, '^[0-9]+'));
        v_cant := TO_NUMBER(NVL(REGEXP_SUBSTR(v_item, '[0-9]+$'), '1'));
      EXCEPTION
        WHEN VALUE_ERROR OR INVALID_NUMBER THEN
          RAISE_APPLICATION_ERROR(-20052, 'Servicio mal formado: ' || v_item);
      END;
      IF v_id IS NULL OR v_cant IS NULL OR v_cant <= 0 THEN
        RAISE_APPLICATION_ERROR(-20052,
          'Servicio mal formado: "' || v_item || '" (se espera id:cantidad).');
      END IF;

      BEGIN
        SELECT valor_servicio INTO v_valor
          FROM servicio
         WHERE id_servicio = v_id;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(-20052, 'El servicio ' || v_id || ' no existe.');
      END;

      v_previo := ROUND(v_cant * v_valor, -2);
      v_final  := ROUND(v_previo * (1 + v_pct / 100), -2);

      BEGIN
        INSERT INTO reserva_servicio (id_reserva, id_servicio, fecha_servicio,
                                      cantidad, valor_previo, valor_servicio)
        VALUES (p_id_reserva, v_id, p_fecha, v_cant, v_previo, v_final);
      EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
          RAISE_APPLICATION_ERROR(-20052,
            'El servicio ' || v_id || ' esta repetido en la lista.');
      END;

      p_total := p_total + v_final;
      i := i + 1;
    END LOOP;

    -- El total de la reserva incluye los servicios (igual que la carga)
    UPDATE reserva
       SET valor_total = valor_total + p_total
     WHERE id_reserva = p_id_reserva;
  END agregar_servicios;

  -- -------------------------------------------------------------------
  -- sp_reservar_y_pagar
  -- -------------------------------------------------------------------
  PROCEDURE sp_reservar_y_pagar (p_id_cliente         IN  NUMBER,
                                 p_id_usuario_sistema IN  NUMBER,
                                 p_checkin            IN  DATE,
                                 p_checkout           IN  DATE,
                                 p_num_huespedes      IN  NUMBER,
                                 p_habitaciones       IN  VARCHAR2,
                                 p_servicios          IN  VARCHAR2,
                                 p_valor_pago         IN  NUMBER,
                                 p_metodo_pago        IN  VARCHAR2,
                                 p_id_reserva         OUT NUMBER,
                                 p_id_pago            OUT NUMBER,
                                 p_resultado          OUT VARCHAR2)
  IS
    v_paso      VARCHAR2(12);
    v_total     reserva.valor_total%TYPE;
    v_serv      NUMBER := 0;
    v_minimo    NUMBER;
    v_msg_serv  VARCHAR2(400);
    v_code      NUMBER;
    v_msg       VARCHAR2(400);
  BEGIN
    p_id_reserva := NULL;
    p_id_pago    := NULL;
    p_resultado  := 'COMPLETA';

    -- Punto de partida: deshacer hasta aqui = como si nada hubiera pasado
    SAVEPOINT sp_inicio;

    -- ----- Paso 1: reserva + habitaciones (sin COMMIT) ----------------
    -- Reutiliza toda la validacion de la Entrega 2 (fechas, capacidad,
    -- disponibilidad con SELECT ... FOR UPDATE) y el trigger de solape.
    v_paso := 'RESERVA';
    pkg_turismo.sp_crear_reserva(p_id_cliente, p_id_usuario_sistema,
                                 p_checkin, p_checkout, p_num_huespedes,
                                 p_habitaciones, p_id_reserva,
                                 p_confirmar => FALSE);
    DBMS_OUTPUT.PUT_LINE('  [1] Reserva ' || p_id_reserva || ' creada (sin confirmar)');

    -- ----- Paso 2: servicios opcionales ------------------------------
    SAVEPOINT sp_servicios;
    v_paso := 'SERVICIOS';
    IF TRIM(p_servicios) IS NOT NULL THEN
      BEGIN
        agregar_servicios(p_id_reserva, TRUNC(p_checkin), p_servicios, v_serv);
        DBMS_OUTPUT.PUT_LINE('  [2] Servicios agregados por ' ||
                             TO_CHAR(v_serv, 'FM999G999G990'));
      EXCEPTION
        WHEN OTHERS THEN
          -- ROLLBACK PARCIAL: se deshace solo lo posterior a sp_servicios
          -- (lineas de servicio y el ajuste de valor_total). La reserva y
          -- sus habitaciones siguen pendientes de confirmar, con sus
          -- bloqueos intactos.
          v_msg_serv := SQLERRM;
          ROLLBACK TO sp_servicios;
          v_serv      := 0;
          p_resultado := 'ROLLBACK_PARCIAL';
          DBMS_OUTPUT.PUT_LINE('  [2] ROLLBACK TO sp_servicios: ' || v_msg_serv);
          DBMS_OUTPUT.PUT_LINE('      la reserva continua sin servicios');
      END;
    END IF;

    -- ----- Paso 3: pago ------------------------------------------------
    v_paso := 'PAGO';
    SELECT valor_total INTO v_total
      FROM reserva
     WHERE id_reserva = p_id_reserva;

    IF p_metodo_pago IS NULL
       OR p_metodo_pago NOT IN ('EFECTIVO','TARJETA_CREDITO','TARJETA_DEBITO',
                                'PSE','TRANSFERENCIA') THEN
      RAISE_APPLICATION_ERROR(-20051,
        'Metodo de pago invalido: ' || NVL(p_metodo_pago, 'NULL'));
    END IF;
    IF p_valor_pago IS NULL OR p_valor_pago <= 0 OR p_valor_pago > v_total THEN
      RAISE_APPLICATION_ERROR(-20050,
        'Valor de pago invalido (' || NVL(TO_CHAR(p_valor_pago), 'NULL') ||
        '): debe ser mayor que 0 y no superar el total de ' ||
        TO_CHAR(v_total, 'FM999G999G990') || '.');
    END IF;
    v_minimo := ROUND(v_total * c_pct_anticipo / 100, 2);
    IF p_valor_pago < v_minimo THEN
      RAISE_APPLICATION_ERROR(-20053,
        'Anticipo insuficiente: se pagan ' ||
        TO_CHAR(p_valor_pago, 'FM999G999G990') || ' y el minimo (' ||
        c_pct_anticipo || ' %) es ' || TO_CHAR(v_minimo, 'FM999G999G990') || '.');
    END IF;

    INSERT INTO pago (id_reserva, valor, fecha_pago, metodo_pago, estado)
    VALUES (p_id_reserva, p_valor_pago, SYSDATE, p_metodo_pago, 'APROBADO')
    RETURNING id_pago INTO p_id_pago;

    UPDATE reserva
       SET valor_pagado = valor_pagado + p_valor_pago,
           estado       = 'CONFIRMADA'
     WHERE id_reserva = p_id_reserva;
    DBMS_OUTPUT.PUT_LINE('  [3] Pago ' || p_id_pago || ' por ' ||
                         TO_CHAR(p_valor_pago, 'FM999G999G990') ||
                         ' -> reserva CONFIRMADA');

    -- ----- Fin: UN solo COMMIT para reserva, servicios y pago ----------
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('  COMMIT: total ' || TO_CHAR(v_total, 'FM999G999G990') ||
                         ', pagado ' || TO_CHAR(p_valor_pago, 'FM999G999G990'));

    sp_log(p_id_cliente, p_habitaciones, p_id_reserva, p_id_pago,
           p_resultado,
           CASE WHEN p_resultado = 'ROLLBACK_PARCIAL' THEN 'SERVICIOS' END,
           NULL, v_msg_serv);

  EXCEPTION
    WHEN OTHERS THEN
      v_code := SQLCODE;
      v_msg  := SQLERRM;
      -- ROLLBACK TOTAL: reserva, habitaciones, servicios y pago se van
      -- juntos, y se liberan los bloqueos tomados desde sp_inicio.
      ROLLBACK TO sp_inicio;
      DBMS_OUTPUT.PUT_LINE('  ROLLBACK TO sp_inicio (paso ' || v_paso || '): ' || v_msg);
      -- La bitacora sobrevive al rollback: transaccion autonoma
      sp_log(p_id_cliente, p_habitaciones, NULL, NULL,
             'ROLLBACK_TOTAL', v_paso, v_code, v_msg);
      p_id_reserva := NULL;
      p_id_pago    := NULL;
      p_resultado  := 'ROLLBACK_TOTAL';
      RAISE;     -- el llamador recibe el error original
  END sp_reservar_y_pagar;

  -- -------------------------------------------------------------------
  -- sp_registrar_abono
  -- -------------------------------------------------------------------
  -- Concurrencia: el SELECT ... FOR UPDATE toma el bloqueo TX de la fila
  -- de la reserva ANTES de validar el saldo. Si dos cajeros abonan a la
  -- vez, el segundo espera; cuando el primero confirma, lee el saldo ya
  -- descontado. Sin el bloqueo, los dos verian el mismo saldo y entre
  -- ambos podrian pagar mas que el total (actualizacion perdida).
  -- -------------------------------------------------------------------
  PROCEDURE sp_registrar_abono (p_id_reserva  IN  NUMBER,
                                p_valor       IN  NUMBER,
                                p_metodo_pago IN  VARCHAR2,
                                p_id_pago     OUT NUMBER,
                                p_saldo       OUT NUMBER)
  IS
    v_estado  reserva.estado%TYPE;
    v_total   reserva.valor_total%TYPE;
    v_pagado  reserva.valor_pagado%TYPE;
    v_saldo   NUMBER;
    v_minimo  NUMBER;
    v_nuevo   reserva.estado%TYPE;
  BEGIN
    SAVEPOINT sp_abono;

    IF p_metodo_pago IS NULL
       OR p_metodo_pago NOT IN ('EFECTIVO','TARJETA_CREDITO','TARJETA_DEBITO',
                                'PSE','TRANSFERENCIA') THEN
      RAISE_APPLICATION_ERROR(-20051,
        'Metodo de pago invalido: ' || NVL(p_metodo_pago, 'NULL'));
    END IF;

    BEGIN
      SELECT estado, valor_total, valor_pagado
        INTO v_estado, v_total, v_pagado
        FROM reserva
       WHERE id_reserva = p_id_reserva
         FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20054,
          'La reserva ' || NVL(TO_CHAR(p_id_reserva), 'NULL') || ' no existe.');
    END;
    DBMS_OUTPUT.PUT_LINE('  [1] Reserva ' || p_id_reserva || ' bloqueada (FOR UPDATE), estado ' ||
                         v_estado || ', saldo ' || TO_CHAR(v_total - v_pagado, 'FM999G999G990'));

    IF v_estado = 'CANCELADA' THEN
      RAISE_APPLICATION_ERROR(-20055,
        'La reserva ' || p_id_reserva || ' esta cancelada: no recibe pagos.');
    END IF;

    v_saldo := v_total - v_pagado;
    IF p_valor IS NULL OR p_valor <= 0 OR p_valor > v_saldo THEN
      RAISE_APPLICATION_ERROR(-20050,
        'Valor de pago invalido (' || NVL(TO_CHAR(p_valor), 'NULL') ||
        '): debe ser mayor que 0 y no superar el saldo pendiente de ' ||
        TO_CHAR(v_saldo, 'FM999G999G990') || '.');
    END IF;

    -- Una reserva PENDIENTE se confirma con el anticipo minimo acumulado
    v_nuevo := v_estado;
    IF v_estado = 'PENDIENTE' THEN
      v_minimo := ROUND(v_total * c_pct_anticipo / 100, 2);
      IF v_pagado + p_valor < v_minimo THEN
        RAISE_APPLICATION_ERROR(-20053,
          'Anticipo insuficiente: con este pago quedan pagados ' ||
          TO_CHAR(v_pagado + p_valor, 'FM999G999G990') || ' y el minimo (' ||
          c_pct_anticipo || ' %) para confirmar es ' ||
          TO_CHAR(v_minimo, 'FM999G999G990') || '.');
      END IF;
      v_nuevo := 'CONFIRMADA';
    END IF;

    INSERT INTO pago (id_reserva, valor, fecha_pago, metodo_pago, estado)
    VALUES (p_id_reserva, p_valor, SYSDATE, p_metodo_pago, 'APROBADO')
    RETURNING id_pago INTO p_id_pago;

    UPDATE reserva
       SET valor_pagado = valor_pagado + p_valor,
           estado       = v_nuevo
     WHERE id_reserva = p_id_reserva;

    p_saldo := v_saldo - p_valor;
    DBMS_OUTPUT.PUT_LINE('  [2] Pago ' || p_id_pago || ' por ' ||
                         TO_CHAR(p_valor, 'FM999G999G990') || ' (' || p_metodo_pago || ')' ||
                         CASE WHEN v_nuevo <> v_estado THEN ' -> reserva ' || v_nuevo END);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('  COMMIT: saldo pendiente ' || TO_CHAR(p_saldo, 'FM999G999G990') ||
                         CASE WHEN p_saldo = 0 THEN ' (reserva paga en su totalidad)' END);

  EXCEPTION
    WHEN OTHERS THEN
      -- Deshace lo hecho desde sp_abono y libera el bloqueo de la fila
      ROLLBACK TO sp_abono;
      DBMS_OUTPUT.PUT_LINE('  ROLLBACK TO sp_abono: ' || SQLERRM);
      p_id_pago := NULL;
      p_saldo   := NULL;
      RAISE;
  END sp_registrar_abono;

END pkg_transacciones;
/

SHOW ERRORS PACKAGE BODY pkg_transacciones

PROMPT
PROMPT === Estado de los paquetes (deben decir VALID) ===
COLUMN object_name FORMAT A20
COLUMN object_type FORMAT A14
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_TURISMO', 'PKG_TRANSACCIONES')
 ORDER BY object_name, object_type;

PROMPT Paquete PKG_TRANSACCIONES compilado. Demostracion: 12_transacciones_demo.sql
