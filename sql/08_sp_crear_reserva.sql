-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 08 · Procedimiento sp_crear_reserva
-- ---------------------------------------------------------------------
-- Registra de forma ATOMICA una reserva: cabecera (RESERVA) + una fila
-- por habitacion (RESERVA_HABITACION). Valida las reglas de negocio y
-- las informa con RAISE_APPLICATION_ERROR.
--
-- Codigos de error (para mapear a HTTP en Spring Boot):
--   -20001  Fechas invalidas: check-out <= check-in (o fechas nulas)
--   -20002  Capacidad maxima superada
--   -20003  Habitacion(es) no disponible(s) en esas fechas
--           (el trigger trg_rh_no_solape tambien lo lanza, como red de
--            seguridad ante concurrencia o INSERT directos)
--   -20004  Check-in en el pasado
--   -20005  Cliente, usuario o habitacion inexistente / inactivo
--   -20006  Parametros invalidos: lista vacia, repetidas, huespedes < 1,
--           o habitaciones de alojamientos distintos
--   -20007  Alguna noche sin temporada definida (o con temporadas cruzadas)
--
-- Precio: igual que 03_carga.sql, NOCHE POR NOCHE:
--     tarifa.valor * (1 + temporada.porcentaje / 100)
--   Si ya tienes fn_valor_estadia (Sara Acosta), puedes reemplazar el
--   calculo de v_factor / valor_reserva por una llamada a esa funcion.
--
-- Transaccion: NO hace COMMIT. Quien llama decide (SQL*Plus: COMMIT;
--   Spring: @Transactional). Si algo falla, el procedimiento deshace solo
--   lo suyo (ROLLBACK TO SAVEPOINT) y relanza el mismo error.
--
-- EJECUTAR COMO: turismouq (o por Docker, con las dos lineas siguientes)
-- =====================================================================

ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

-- Lista de habitaciones que se envia al procedimiento
CREATE OR REPLACE TYPE t_lista_habitaciones AS TABLE OF NUMBER;
/

CREATE OR REPLACE PROCEDURE sp_crear_reserva (
  p_id_cliente         IN  reserva.id_cliente%TYPE,
  p_id_usuario_sistema IN  reserva.id_usuario_sistema%TYPE,
  p_habitaciones       IN  t_lista_habitaciones,
  p_fecha_checkin      IN  DATE,
  p_fecha_checkout     IN  DATE,
  p_num_huespedes      IN  reserva.num_huespedes%TYPE,
  p_id_reserva         OUT reserva.id_reserva%TYPE
) IS
  v_in            DATE;
  v_out           DATE;
  v_noches        PLS_INTEGER;
  v_existe        NUMBER;
  v_n_distintas   NUMBER;
  v_n_existen     NUMBER;
  v_n_aloj        NUMBER;
  v_n_inactivas   NUMBER;
  v_capacidad     NUMBER;
  v_cubiertas     NUMBER;
  v_factor        NUMBER;
  v_ocupadas      VARCHAR2(1000);
BEGIN
  SAVEPOINT sp_crear_reserva;
  p_id_reserva := NULL;

  -- -----------------------------------------------------------------
  -- 1. Validacion de parametros y fechas
  -- -----------------------------------------------------------------
  IF p_habitaciones IS NULL OR p_habitaciones.COUNT = 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'Debe indicar al menos una habitacion');
  END IF;

  IF p_num_huespedes IS NULL OR p_num_huespedes < 1 THEN
    RAISE_APPLICATION_ERROR(-20006, 'El numero de huespedes debe ser al menos 1');
  END IF;

  IF p_fecha_checkin IS NULL OR p_fecha_checkout IS NULL THEN
    RAISE_APPLICATION_ERROR(-20001, 'Las fechas de check-in y check-out son obligatorias');
  END IF;

  v_in  := TRUNC(p_fecha_checkin);    -- las tablas exigen fechas sin hora
  v_out := TRUNC(p_fecha_checkout);

  IF v_out <= v_in THEN
    RAISE_APPLICATION_ERROR(-20001,
      'El check-out (' || TO_CHAR(v_out, 'YYYY-MM-DD') ||
      ') debe ser posterior al check-in (' || TO_CHAR(v_in, 'YYYY-MM-DD') || ')');
  END IF;

  IF v_in < TRUNC(SYSDATE) THEN
    RAISE_APPLICATION_ERROR(-20004,
      'El check-in (' || TO_CHAR(v_in, 'YYYY-MM-DD') || ') no puede estar en el pasado');
  END IF;

  v_noches := v_out - v_in;

  -- -----------------------------------------------------------------
  -- 2. Cliente y usuario
  -- -----------------------------------------------------------------
  SELECT COUNT(*) INTO v_existe FROM cliente WHERE id_cliente = p_id_cliente;
  IF v_existe = 0 THEN
    RAISE_APPLICATION_ERROR(-20005, 'El cliente ' || p_id_cliente || ' no existe');
  END IF;

  SELECT COUNT(*) INTO v_existe
    FROM usuario_sistema
   WHERE id_usuario_sistema = p_id_usuario_sistema AND activo = 'S';
  IF v_existe = 0 THEN
    RAISE_APPLICATION_ERROR(-20005,
      'El usuario ' || p_id_usuario_sistema || ' no existe o esta inactivo');
  END IF;

  -- -----------------------------------------------------------------
  -- 3. Bloqueo y validacion de habitaciones
  --    Se bloquean EN ORDEN (ORDER BY) para que dos reservas que piden
  --    las mismas habitaciones en distinto orden no se interbloqueen, y
  --    ANTES de revisar disponibilidad para que la revision sea fiable.
  -- -----------------------------------------------------------------
  FOR b IN (SELECT h.id_habitacion
              FROM habitacion h
             WHERE h.id_habitacion IN (SELECT COLUMN_VALUE FROM TABLE(p_habitaciones))
             ORDER BY h.id_habitacion
               FOR UPDATE OF h.id_habitacion) LOOP
    NULL;
  END LOOP;

  SELECT COUNT(DISTINCT COLUMN_VALUE) INTO v_n_distintas
    FROM TABLE(p_habitaciones);
  IF v_n_distintas <> p_habitaciones.COUNT THEN
    RAISE_APPLICATION_ERROR(-20006, 'La lista de habitaciones tiene valores repetidos o nulos');
  END IF;

  SELECT COUNT(*),
         COUNT(DISTINCT h.id_alojamiento),
         NVL(SUM(th.capacidad_maxima), 0),
         COUNT(CASE WHEN h.activo = 'N' OR a.activo = 'N' THEN 1 END)
    INTO v_n_existen, v_n_aloj, v_capacidad, v_n_inactivas
    FROM habitacion h
    JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
    JOIN alojamiento a      ON a.id_alojamiento      = h.id_alojamiento
   WHERE h.id_habitacion IN (SELECT COLUMN_VALUE FROM TABLE(p_habitaciones));

  IF v_n_existen <> v_n_distintas THEN
    RAISE_APPLICATION_ERROR(-20005, 'Alguna de las habitaciones indicadas no existe');
  END IF;
  IF v_n_inactivas > 0 THEN
    RAISE_APPLICATION_ERROR(-20005, 'Alguna habitacion (o su alojamiento) esta inactiva');
  END IF;
  IF v_n_aloj > 1 THEN
    RAISE_APPLICATION_ERROR(-20006,
      'Todas las habitaciones de una reserva deben ser del mismo alojamiento');
  END IF;

  -- -----------------------------------------------------------------
  -- 4. Capacidad
  -- -----------------------------------------------------------------
  IF p_num_huespedes > v_capacidad THEN
    RAISE_APPLICATION_ERROR(-20002,
      'Capacidad superada: ' || p_num_huespedes || ' huespedes para una capacidad maxima de '
      || v_capacidad);
  END IF;

  -- -----------------------------------------------------------------
  -- 5. Disponibilidad (las CANCELADAS no bloquean)
  -- -----------------------------------------------------------------
  SELECT LISTAGG(DISTINCT h.numero_habitacion, ', ')
           WITHIN GROUP (ORDER BY h.numero_habitacion)
    INTO v_ocupadas
    FROM reserva_habitacion rh
    JOIN reserva r    ON r.id_reserva    = rh.id_reserva
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
   WHERE rh.id_habitacion IN (SELECT COLUMN_VALUE FROM TABLE(p_habitaciones))
     AND r.estado <> 'CANCELADA'
     AND rh.fecha_checkin < v_out
     AND v_in < rh.fecha_checkout;

  IF v_ocupadas IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(-20003,
      'No hay disponibilidad entre ' || TO_CHAR(v_in, 'YYYY-MM-DD') || ' y '
      || TO_CHAR(v_out, 'YYYY-MM-DD') || ' para la(s) habitacion(es): ' || v_ocupadas);
  END IF;

  -- -----------------------------------------------------------------
  -- 6. Factor de temporada: suma, noche por noche, de (1 + pct/100).
  --    Cada noche debe caer en UNA sola temporada.
  -- -----------------------------------------------------------------
  SELECT COUNT(t.id_temporada), SUM(1 + t.porcentaje / 100)
    INTO v_cubiertas, v_factor
    FROM (SELECT v_in + LEVEL - 1 AS noche
            FROM dual
         CONNECT BY LEVEL <= v_noches) n
    LEFT JOIN temporada t
           ON n.noche BETWEEN t.fecha_inicio AND t.fecha_fin;

  IF v_cubiertas <> v_noches THEN
    RAISE_APPLICATION_ERROR(-20007,
      'Hay noches sin temporada definida (o con temporadas cruzadas) entre '
      || TO_CHAR(v_in, 'YYYY-MM-DD') || ' y ' || TO_CHAR(v_out, 'YYYY-MM-DD'));
  END IF;

  -- -----------------------------------------------------------------
  -- 7. Insercion: cabecera, detalle y total
  -- -----------------------------------------------------------------
  INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_checkin, fecha_checkout,
                       estado, num_huespedes, valor_total, valor_pagado)
  VALUES (p_id_cliente, p_id_usuario_sistema, v_in, v_out,
          'PENDIENTE', p_num_huespedes, 0, 0)
  RETURNING id_reserva INTO p_id_reserva;

  -- Una sola sentencia: el trigger trg_rh_no_solape la revisa completa
  INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                  fecha_checkout, valor_previo, valor_reserva)
  SELECT p_id_reserva, h.id_habitacion, v_in, v_out,
         v_noches * tf.valor,          -- sin ajuste de temporada
         tf.valor * v_factor           -- con ajuste noche por noche
    FROM habitacion h
    JOIN tarifa tf ON tf.id_tarifa = h.id_tarifa
   WHERE h.id_habitacion IN (SELECT COLUMN_VALUE FROM TABLE(p_habitaciones));

  -- El total sale de lo YA guardado (redondeado a 2 decimales) para que la
  -- cabecera siempre cuadre con el detalle (verificacion del script 03)
  UPDATE reserva
     SET valor_total = (SELECT SUM(valor_reserva)
                          FROM reserva_habitacion
                         WHERE id_reserva = p_id_reserva)
   WHERE id_reserva = p_id_reserva;

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO SAVEPOINT sp_crear_reserva;   -- deshace solo lo de este procedimiento
    p_id_reserva := NULL;
    RAISE;                                    -- conserva el codigo -200xx original
END sp_crear_reserva;
/
SHOW ERRORS