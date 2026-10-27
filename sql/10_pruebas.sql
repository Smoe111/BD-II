-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 10 · Pruebas automaticas: PKG_TURISMO, triggers y auditoria
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq, despues de 01..08 (ya con los triggers).
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @10_pruebas_entrega2.sql
--
-- Cada prueba imprime [PASS] o [FAIL]; al final hay un resumen.
-- Todo lo que las pruebas crean se deshace:
--   * reservas creadas por sp_crear_reserva: se borran al final (id mayor
--     al maximo existente al empezar);
--   * pruebas de triggers y auditoria: se hacen dentro de SAVEPOINTs y se
--     revierten con ROLLBACK TO.
--
-- IMPORTANTE: guardar este archivo FUERA de ./sql (por ejemplo en
-- ./pruebas). Docker ejecuta todo lo que haya en ./sql al crear el
-- contenedor y estas pruebas son de ejecucion manual.
--
-- SUPUESTOS:
--   * Las fechas de prueba son hoy+10 .. hoy+13 (y hasta hoy+22). Las
--     temporadas cubren hasta 2027-12-31 (05_auditoria_estructuras.sql):
--     si corres esto despues de ~2027-12-10 daran -20022.
--   * Las habitaciones libres se buscan solas: no depende de ids fijos.
--   * Los triggers se prueban con fechas de 2030, donde no hay datos
--     reales, para no chocar con la carga.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF

VARIABLE v_max_res NUMBER
BEGIN
  SELECT NVL(MAX(id_reserva), 0) INTO :v_max_res FROM reserva;
END;
/

DECLARE
  v_pass PLS_INTEGER := 0;
  v_fail PLS_INTEGER := 0;
  v_skip PLS_INTEGER := 0;

  v_in   DATE := TRUNC(SYSDATE) + 10;
  v_out  DATE := TRUNC(SYSDATE) + 13;

  v_h1 NUMBER;  v_h2 NUMBER;  v_h3 NUMBER;  v_a1 NUMBER;
  v_cli NUMBER; v_ucli NUMBER; v_cli2 NUMBER; v_ucli2 NUMBER;
  c_staff CONSTANT NUMBER := 1;          -- recep01
  v_res NUMBER; v_res2 NUMBER;
  v_n0 NUMBER;  v_n1 NUMBER;
  v_tarifa NUMBER; v_esp NUMBER; v_val NUMBER;
  v_estado reserva.estado%TYPE;
  v_total NUMBER; v_pagado NUMBER;
  v_sum_rh NUMBER; v_sum_prev NUMBER; v_sum_tar NUMBER;

  -- usados por las pruebas de triggers / auditoria
  v_code NUMBER;  v_msg VARCHAR2(400);
  v_ra NUMBER; v_rb NUMBER; v_rc NUMBER;
  v_t1 DATE := DATE '2030-03-10';        -- 10 a 12 de marzo de 2030
  v_t2 DATE := DATE '2030-03-12';
  v_t3 DATE := DATE '2030-03-14';
  v_t4 DATE := DATE '2030-03-20';
  v_t5 DATE := DATE '2030-03-22';
  v_aud0 NUMBER;
  v_c1 NUMBER; v_c2 NUMBER; v_c3 NUMBER; v_c4 NUMBER; v_c5 NUMBER;
  v_op VARCHAR2(6); v_usr VARCHAR2(30); v_app VARCHAR2(64);
  v_tid NUMBER;

  -- ---------------- utilidades de prueba -----------------------------
  PROCEDURE ok(p_nombre VARCHAR2, p_cond BOOLEAN, p_detalle VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF p_cond THEN
      v_pass := v_pass + 1;
      DBMS_OUTPUT.PUT_LINE('  [PASS] ' || p_nombre);
    ELSE
      v_fail := v_fail + 1;
      DBMS_OUTPUT.PUT_LINE('  [FAIL] ' || p_nombre ||
                           CASE WHEN p_detalle IS NOT NULL THEN ' -> ' || p_detalle END);
    END IF;
  END;

  PROCEDURE omitir(p_nombre VARCHAR2, p_motivo VARCHAR2) IS
  BEGIN
    v_skip := v_skip + 1;
    DBMS_OUTPUT.PUT_LINE('  [OMITIDA] ' || p_nombre || ' -> ' || p_motivo);
  END;

  -- Ejecuta un bloque PL/SQL y comprueba que falle con el codigo dado
  PROCEDURE espera_error(p_nombre VARCHAR2, p_codigo NUMBER, p_bloque VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_bloque;
    ok(p_nombre, FALSE, 'no lanzo error; se esperaba ' || p_codigo);
  EXCEPTION WHEN OTHERS THEN
    ok(p_nombre, SQLCODE = p_codigo,
       'se esperaba ' || p_codigo || ' y llego: ' || SQLERRM);
  END;

  FUNCTION d(p_f DATE) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'DATE ''' || TO_CHAR(p_f, 'YYYY-MM-DD') || '''';
  END;

  FUNCTION llamar(p_cli NUMBER, p_usr NUMBER, p_in DATE, p_out DATE,
                  p_hues NUMBER, p_habs VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'DECLARE v NUMBER; BEGIN pkg_turismo.sp_crear_reserva('
      || NVL(TO_CHAR(p_cli), 'NULL') || ',' || NVL(TO_CHAR(p_usr), 'NULL') || ','
      || d(p_in) || ',' || d(p_out) || ','
      || NVL(TO_CHAR(p_hues), 'NULL') || ','
      || CASE WHEN p_habs IS NULL THEN 'NULL' ELSE '''' || p_habs || '''' END
      || ', v); END;';
  END;

  FUNCTION llamar_fn(p_hab NUMBER, p_in DATE, p_out DATE) RETURN VARCHAR2 IS
  BEGIN
    RETURN 'DECLARE v NUMBER; BEGIN v := pkg_turismo.fn_valor_estadia('
      || p_hab || ',' || d(p_in) || ',' || d(p_out) || '); END;';
  END;

  FUNCTION libre(p_h NUMBER, p_in DATE, p_out DATE) RETURN BOOLEAN IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n
      FROM reserva_habitacion rh
      JOIN reserva r ON r.id_reserva = rh.id_reserva
     WHERE rh.id_habitacion = p_h
       AND r.estado <> 'CANCELADA'
       AND rh.fecha_checkin  < p_out
       AND rh.fecha_checkout > p_in;
    RETURN n = 0;
  END;

  FUNCTION contar_reservas RETURN NUMBER IS
    n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO n FROM reserva;
    RETURN n;
  END;

  -- INSERT directo (sin pasar por sp_crear_reserva) para probar triggers
  FUNCTION nueva_reserva(p_ci DATE, p_co DATE, p_estado VARCHAR2) RETURN NUMBER IS
    v_id NUMBER;
  BEGIN
    INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_creacion,
                         fecha_checkin, fecha_checkout, estado, num_huespedes,
                         valor_total, valor_pagado)
    VALUES (v_cli, c_staff, LEAST(SYSDATE, p_ci - 1),
            p_ci, p_co, p_estado, 1, 100000, 0)
    RETURNING id_reserva INTO v_id;
    RETURN v_id;
  END;

  PROCEDURE ins_rh(p_res NUMBER, p_hab NUMBER, p_ci DATE, p_co DATE) IS
  BEGIN
    INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                    fecha_checkout, valor_previo, valor_reserva)
    VALUES (p_res, p_hab, p_ci, p_co, 100000, 100000);
  END;

BEGIN
  -- ==================================================================
  -- 0. Pre-requisitos: objetos creados y validos
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE('=== 0. Pre-requisitos ===');
  SELECT COUNT(*) INTO v_n0 FROM user_objects
   WHERE object_name = 'PKG_TURISMO' AND object_type = 'PACKAGE BODY' AND status = 'VALID';
  ok('0.1 PKG_TURISMO (cuerpo) compilado y VALID', v_n0 = 1);

  SELECT COUNT(*) INTO v_n0 FROM user_objects
   WHERE object_type = 'TRIGGER' AND status = 'VALID'
     AND object_name IN ('TRG_RH_NO_SOLAPE', 'TRG_TARIFA_AUDITORIA');
  ok('0.2 triggers trg_rh_no_solape y trg_tarifa_auditoria VALID', v_n0 = 2,
     v_n0 || ' de 2');

  SELECT COUNT(*) INTO v_n0 FROM user_triggers
   WHERE trigger_name IN ('TRG_RH_NO_SOLAPE', 'TRG_TARIFA_AUDITORIA')
     AND status = 'ENABLED';
  ok('0.3 los dos triggers estan ENABLED', v_n0 = 2, v_n0 || ' de 2');

  -- Temporadas sin huecos ni cruces de 2024 a 2027
  SELECT COUNT(*) INTO v_n0
    FROM (SELECT fecha_inicio,
                 LAG(fecha_fin) OVER (ORDER BY fecha_inicio) AS fin_ant
            FROM temporada)
   WHERE fin_ant IS NOT NULL AND fecha_inicio <> fin_ant + 1;
  ok('0.4 temporadas continuas, sin huecos ni cruces', v_n0 = 0, v_n0 || ' problemas');

  SELECT COUNT(*) INTO v_n0 FROM temporada
   WHERE fecha_fin = DATE '2027-12-31';
  ok('0.5 las temporadas llegan hasta 2027-12-31', v_n0 = 1);

  -- ------------------------------------------------------------------
  -- Datos de partida: habitaciones libres y clientes con cuenta
  -- ------------------------------------------------------------------
  FOR h IN (SELECT hb.id_habitacion, hb.id_alojamiento
              FROM habitacion hb
              JOIN alojamiento a ON a.id_alojamiento = hb.id_alojamiento
             WHERE hb.activo = 'S' AND a.activo = 'S'
             ORDER BY hb.id_habitacion) LOOP
    IF libre(h.id_habitacion, v_in - 1, v_out + 25) THEN
      IF v_h1 IS NULL THEN
        v_h1 := h.id_habitacion;  v_a1 := h.id_alojamiento;
      ELSIF v_h2 IS NULL AND h.id_alojamiento = v_a1 THEN
        v_h2 := h.id_habitacion;
      ELSIF v_h3 IS NULL AND h.id_alojamiento <> v_a1 THEN
        v_h3 := h.id_habitacion;
      END IF;
    END IF;
    EXIT WHEN v_h2 IS NOT NULL AND v_h3 IS NOT NULL;
  END LOOP;

  SELECT id_cliente, id_usuario_sistema INTO v_cli, v_ucli
    FROM (SELECT id_cliente, id_usuario_sistema FROM usuario_sistema
           WHERE rol = 'CLIENTE' ORDER BY id_usuario_sistema)
   WHERE ROWNUM = 1;
  SELECT id_cliente, id_usuario_sistema INTO v_cli2, v_ucli2
    FROM (SELECT id_cliente, id_usuario_sistema FROM usuario_sistema
           WHERE rol = 'CLIENTE' ORDER BY id_usuario_sistema DESC)
   WHERE ROWNUM = 1;

  DBMS_OUTPUT.PUT_LINE('Habitaciones de prueba: ' || v_h1 || ', ' || v_h2 ||
                       ' (mismo alojamiento) y ' || v_h3 || ' (otro alojamiento)');
  DBMS_OUTPUT.PUT_LINE('Fechas de prueba: ' || TO_CHAR(v_in, 'YYYY-MM-DD') ||
                       ' a ' || TO_CHAR(v_out, 'YYYY-MM-DD'));

  IF v_h1 IS NULL OR v_h2 IS NULL OR v_h3 IS NULL THEN
    RAISE_APPLICATION_ERROR(-20999,
      'No se hallaron 3 habitaciones libres para las fechas de prueba; mueve v_in/v_out.');
  END IF;

  -- ==================================================================
  -- A. fn_valor_estadia
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== A. fn_valor_estadia ===');

  SELECT t.valor INTO v_tarifa
    FROM habitacion h JOIN tarifa t ON t.id_tarifa = h.id_tarifa
   WHERE h.id_habitacion = v_h1;

  -- 14-dic baja (0 %), 15 y 16-dic decembrina (+45 %)
  v_val := pkg_turismo.fn_valor_estadia(v_h1, DATE '2026-12-14', DATE '2026-12-17');
  v_esp := ROUND(v_tarifa * (1 + 1.45 + 1.45), 2);
  ok('A1 cruce de temporada baja a decembrina (3 noches)',
     ABS(v_val - v_esp) < 0.01, 'obtuvo ' || v_val || ', esperaba ' || v_esp);

  -- Semana Santa 2026 empieza el 29-mar (+40 %); el 28 es temporada baja
  v_val := pkg_turismo.fn_valor_estadia(v_h1, DATE '2026-03-28', DATE '2026-03-30');
  v_esp := ROUND(v_tarifa * (1 + 1.40), 2);
  ok('A2 frontera: 28-mar (0 %) + 29-mar (+40 %)',
     ABS(v_val - v_esp) < 0.01, 'obtuvo ' || v_val || ', esperaba ' || v_esp);

  -- El checkout es exclusivo: una noche cuesta una noche
  v_val := pkg_turismo.fn_valor_estadia(v_h1, DATE '2026-03-29', DATE '2026-03-30');
  ok('A3 checkout exclusivo (1 noche de Semana Santa)',
     ABS(v_val - ROUND(v_tarifa * 1.40, 2)) < 0.01, 'obtuvo ' || v_val);

  v_val := pkg_turismo.fn_valor_estadia(v_h1, DATE '2026-08-10', DATE '2026-08-12');
  ok('A4 temporada baja = tarifa x noches',
     ABS(v_val - ROUND(v_tarifa * 2, 2)) < 0.01, 'obtuvo ' || v_val);

  -- Cruce de anio hacia las temporadas de 2027: 31-dic-2026 (+45 %) y 1-ene-2027 (+35 %)
  v_val := pkg_turismo.fn_valor_estadia(v_h1, DATE '2026-12-31', DATE '2027-01-02');
  v_esp := ROUND(v_tarifa * (1.45 + 1.35), 2);
  ok('A5 cruce de anio 2026 -> 2027 (usa las temporadas nuevas)',
     ABS(v_val - v_esp) < 0.01, 'obtuvo ' || v_val || ', esperaba ' || v_esp);

  -- Semana Santa 2027: 21 a 28 de marzo (+40 %)
  v_val := pkg_turismo.fn_valor_estadia(v_h1, DATE '2027-03-21', DATE '2027-03-23');
  ok('A6 Semana Santa 2027 (+40 %)',
     ABS(v_val - ROUND(v_tarifa * 2 * 1.40, 2)) < 0.01, 'obtuvo ' || v_val);

  espera_error('A7 checkout = checkin -> -20020', -20020,
               llamar_fn(v_h1, v_in, v_in));
  espera_error('A8 checkout < checkin -> -20020', -20020,
               llamar_fn(v_h1, v_out, v_in));
  espera_error('A9 habitacion inexistente -> -20021', -20021,
               llamar_fn(999999, v_in, v_out));
  espera_error('A10 noche sin temporada (2028) -> -20022', -20022,
               llamar_fn(v_h1, DATE '2027-12-30', DATE '2028-01-02'));

  -- Contra lo guardado por 03_carga.sql (muestra de 1 de cada 25)
  SELECT COUNT(*) INTO v_n0
    FROM reserva_habitacion rh
   WHERE MOD(rh.id_reserva, 25) = 0
     AND ABS(pkg_turismo.fn_valor_estadia(rh.id_habitacion, rh.fecha_checkin,
                                          rh.fecha_checkout) - rh.valor_reserva) > 0.01;
  ok('A11 fn reproduce valor_reserva de la carga (muestra)', v_n0 = 0,
     v_n0 || ' diferencias');

  -- ==================================================================
  -- B1. sp_crear_reserva: errores (no deben dejar nada guardado)
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== B1. sp_crear_reserva: validaciones ===');
  v_n0 := contar_reservas;

  espera_error('B1.1 checkout = checkin -> -20040', -20040,
               llamar(v_cli, c_staff, v_in, v_in, 2, TO_CHAR(v_h1)));
  espera_error('B1.2 check-in en el pasado -> -20040', -20040,
               llamar(v_cli, c_staff, TRUNC(SYSDATE) - 1, TRUNC(SYSDATE) + 1, 2, TO_CHAR(v_h1)));
  espera_error('B1.3 cliente inexistente -> -20041', -20041,
               llamar(999999, c_staff, v_in, v_out, 2, TO_CHAR(v_h1)));
  espera_error('B1.4 usuario inexistente -> -20042', -20042,
               llamar(v_cli, 999999, v_in, v_out, 2, TO_CHAR(v_h1)));
  espera_error('B1.5 cuenta de otro cliente -> -20042', -20042,
               llamar(v_cli2, v_ucli, v_in, v_out, 2, TO_CHAR(v_h1)));
  espera_error('B1.6 0 huespedes -> -20043', -20043,
               llamar(v_cli, c_staff, v_in, v_out, 0, TO_CHAR(v_h1)));
  espera_error('B1.7 61 huespedes -> -20043', -20043,
               llamar(v_cli, c_staff, v_in, v_out, 61, TO_CHAR(v_h1)));
  espera_error('B1.8 lista de habitaciones vacia -> -20044', -20044,
               llamar(v_cli, c_staff, v_in, v_out, 2, NULL));
  espera_error('B1.9 lista mal formada -> -20044', -20044,
               llamar(v_cli, c_staff, v_in, v_out, 2, 'abc'));
  espera_error('B1.10 habitacion inexistente -> -20044', -20044,
               llamar(v_cli, c_staff, v_in, v_out, 2, '999999'));
  espera_error('B1.11 habitacion repetida -> -20044', -20044,
               llamar(v_cli, c_staff, v_in, v_out, 2, v_h1 || ',' || v_h1));
  espera_error('B1.12 alojamientos distintos -> -20045', -20045,
               llamar(v_cli, c_staff, v_in, v_out, 2, v_h1 || ',' || v_h3));
  espera_error('B1.13 capacidad superada (60 en 1 habitacion) -> -20046', -20046,
               llamar(v_cli, c_staff, v_in, v_out, 60, TO_CHAR(v_h1)));

  v_n1 := contar_reservas;
  ok('B1.14 ningun error dejo reservas a medias', v_n0 = v_n1,
     'antes ' || v_n0 || ', despues ' || v_n1);

  -- ==================================================================
  -- B2. sp_crear_reserva: caso feliz
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== B2. sp_crear_reserva: caso feliz (2 habitaciones) ===');
  BEGIN
    pkg_turismo.sp_crear_reserva(v_cli, c_staff, v_in, v_out, 2,
                                 v_h1 || ',' || v_h2, v_res);
    ok('B2.1 devuelve id_reserva', v_res IS NOT NULL);
  EXCEPTION WHEN OTHERS THEN
    v_res := NULL;
    ok('B2.1 devuelve id_reserva', FALSE, SQLERRM);
  END;

  IF v_res IS NOT NULL THEN
    SELECT estado, valor_total, valor_pagado
      INTO v_estado, v_total, v_pagado
      FROM reserva WHERE id_reserva = v_res;
    SELECT COUNT(*), SUM(valor_reserva), SUM(valor_previo)
      INTO v_n1, v_sum_rh, v_sum_prev
      FROM reserva_habitacion WHERE id_reserva = v_res;
    SELECT SUM(t.valor) INTO v_sum_tar
      FROM habitacion h JOIN tarifa t ON t.id_tarifa = h.id_tarifa
     WHERE h.id_habitacion IN (v_h1, v_h2);

    ok('B2.2 estado inicial PENDIENTE y sin pagos',
       v_estado = 'PENDIENTE' AND v_pagado = 0, v_estado || ' / ' || v_pagado);
    ok('B2.3 dos filas en reserva_habitacion', v_n1 = 2, TO_CHAR(v_n1));
    ok('B2.4 valor_total = suma del detalle', ABS(v_total - v_sum_rh) < 0.01,
       v_total || ' vs ' || v_sum_rh);
    ok('B2.5 valor_total = fn(h1) + fn(h2)',
       ABS(v_total - (pkg_turismo.fn_valor_estadia(v_h1, v_in, v_out)
                    + pkg_turismo.fn_valor_estadia(v_h2, v_in, v_out))) < 0.01);
    ok('B2.6 valor_previo = noches x tarifa base',
       ABS(v_sum_prev - (v_out - v_in) * v_sum_tar) < 0.01,
       v_sum_prev || ' vs ' || (v_out - v_in) * v_sum_tar);
  END IF;

  -- ==================================================================
  -- B3. Disponibilidad (el SP la valida antes que el trigger)
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== B3. Disponibilidad ===');
  espera_error('B3.1 mismas fechas, misma habitacion -> -20047', -20047,
               llamar(v_cli2, c_staff, v_in, v_out, 1, TO_CHAR(v_h1)));
  espera_error('B3.2 solape parcial -> -20047', -20047,
               llamar(v_cli2, c_staff, v_in + 1, v_out + 2, 1, TO_CHAR(v_h1)));
  espera_error('B3.3 una estadia dentro de otra -> -20047', -20047,
               llamar(v_cli2, c_staff, v_in + 1, v_in + 2, 1, TO_CHAR(v_h1)));

  IF libre(v_h1, v_out, v_out + 2) THEN
    BEGIN
      pkg_turismo.sp_crear_reserva(v_cli2, c_staff, v_out, v_out + 2, 1,
                                   TO_CHAR(v_h1), v_res2);
      ok('B3.4 llegada el dia del checkout anterior es valida', v_res2 IS NOT NULL);
    EXCEPTION WHEN OTHERS THEN
      ok('B3.4 llegada el dia del checkout anterior es valida', FALSE, SQLERRM);
    END;
  ELSE
    omitir('B3.4 back-to-back', 'la habitacion ya tiene una reserva real en esos dias');
  END IF;

  IF v_res IS NOT NULL THEN
    UPDATE reserva SET estado = 'CANCELADA' WHERE id_reserva = v_res;
    COMMIT;
    BEGIN
      pkg_turismo.sp_crear_reserva(v_cli2, c_staff, v_in, v_out, 2,
                                   v_h1 || ',' || v_h2, v_res2);
      ok('B3.5 reserva CANCELADA no bloquea la habitacion', v_res2 IS NOT NULL);
    EXCEPTION WHEN OTHERS THEN
      ok('B3.5 reserva CANCELADA no bloquea la habitacion', FALSE, SQLERRM);
    END;
  END IF;

  -- ==================================================================
  -- B4. Un cliente reservando a su propio nombre
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== B4. Cuenta de cliente ===');
  IF libre(v_h3, v_in + 20, v_in + 22) THEN
    BEGIN
      pkg_turismo.sp_crear_reserva(v_cli, v_ucli, v_in + 20, v_in + 22, 1,
                                   TO_CHAR(v_h3), v_res2);
      ok('B4.1 el cliente reserva a su propio nombre', v_res2 IS NOT NULL);
    EXCEPTION WHEN OTHERS THEN
      ok('B4.1 el cliente reserva a su propio nombre', FALSE, SQLERRM);
    END;
  ELSE
    omitir('B4.1 cliente reserva a su nombre', 'habitacion ocupada en esas fechas');
  END IF;

  COMMIT;

  -- ==================================================================
  -- C. trg_rh_no_solape (INSERT/UPDATE directo, sin sp_crear_reserva)
  --    Fechas de 2030: sin datos reales. Todo se revierte.
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== C. trg_rh_no_solape ===');

  -- C1. Contra una estadia REAL de la carga
  BEGIN
    DECLARE
      v_hab NUMBER; v_ci DATE; v_co DATE; v_rid NUMBER;
    BEGIN
      SELECT id_habitacion, fecha_checkin, fecha_checkout
        INTO v_hab, v_ci, v_co
        FROM (SELECT rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout
                FROM reserva_habitacion rh
                JOIN reserva r ON r.id_reserva = rh.id_reserva
               WHERE r.estado = 'FINALIZADA'
               ORDER BY rh.id_reserva)
       WHERE ROWNUM = 1;

      SAVEPOINT sp_c1;
      v_rid := nueva_reserva(v_ci, v_co, 'CONFIRMADA');
      v_code := 0;
      BEGIN
        ins_rh(v_rid, v_hab, v_ci, v_co);
      EXCEPTION WHEN OTHERS THEN
        v_code := SQLCODE;  v_msg := SQLERRM;
      END;
      ok('C1 INSERT solapado con una reserva real -> -20003',
         v_code = -20003,
         CASE WHEN v_code = 0 THEN 'se inserto sin error'
              WHEN v_code = -4091 THEN 'ORA-04091 tabla mutante'
              ELSE v_code || ': ' || v_msg END);
      ROLLBACK TO sp_c1;
    END;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('C1 INSERT solapado con una reserva real', FALSE, SQLERRM);
  END;

  -- C2. Back-to-back permitido y reserva CANCELADA no choca
  BEGIN
    SAVEPOINT sp_c2;
    v_ra := nueva_reserva(v_t1, v_t2, 'CONFIRMADA');
    ins_rh(v_ra, v_h3, v_t1, v_t2);                      -- 10 a 12 de marzo

    v_code := 0;
    BEGIN
      v_rb := nueva_reserva(v_t2, v_t3, 'CONFIRMADA');
      ins_rh(v_rb, v_h3, v_t2, v_t3);                    -- 12 a 14: llega el dia del checkout
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; v_msg := SQLERRM; END;
    ok('C2 back-to-back (checkout = checkin siguiente) es valido',
       v_code = 0, v_code || ': ' || v_msg);

    v_code := 0;
    BEGIN
      v_rc := nueva_reserva(v_t1, v_t2, 'CANCELADA');
      ins_rh(v_rc, v_h3, v_t1, v_t2);                    -- mismas fechas, pero CANCELADA
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; v_msg := SQLERRM; END;
    ok('C3 una reserva CANCELADA no choca con la activa',
       v_code = 0, v_code || ': ' || v_msg);
    ROLLBACK TO sp_c2;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('C2/C3 back-to-back y canceladas', FALSE, SQLERRM);
  END;

  -- C4. Solape parcial por INSERT (dentro de una activa)
  BEGIN
    SAVEPOINT sp_c4;
    v_ra := nueva_reserva(v_t1, v_t2, 'CONFIRMADA');
    ins_rh(v_ra, v_h3, v_t1, v_t2);
    v_rb := nueva_reserva(v_t1 + 1, v_t3, 'CONFIRMADA');
    v_code := 0;
    BEGIN
      ins_rh(v_rb, v_h3, v_t1 + 1, v_t3);                -- 11 a 14 pisa el 11
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; v_msg := SQLERRM; END;
    ok('C4 solape parcial por INSERT -> -20003', v_code = -20003,
       v_code || ': ' || v_msg);
    ROLLBACK TO sp_c4;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('C4 solape parcial por INSERT', FALSE, SQLERRM);
  END;

  -- C5. UPDATE de fechas que genera un cruce (el caso de tabla mutante)
  BEGIN
    SAVEPOINT sp_c5;
    v_ra := nueva_reserva(v_t1, v_t2, 'CONFIRMADA');
    ins_rh(v_ra, v_h3, v_t1, v_t2);                      -- 10 a 12
    v_rb := nueva_reserva(v_t4, v_t5, 'CONFIRMADA');
    ins_rh(v_rb, v_h3, v_t4, v_t5);                      -- 20 a 22 (sin cruce)
    v_code := 0;
    BEGIN
      UPDATE reserva_habitacion
         SET fecha_checkin = v_t1, fecha_checkout = v_t2 -- se mueve encima de la primera
       WHERE id_reserva = v_rb AND id_habitacion = v_h3;
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; v_msg := SQLERRM; END;
    ok('C5 UPDATE de fechas hacia un cruce -> -20003 (no ORA-04091)',
       v_code = -20003,
       CASE WHEN v_code = -4091 THEN 'ORA-04091 tabla mutante' ELSE v_code || ': ' || v_msg END);
    ROLLBACK TO sp_c5;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('C5 UPDATE de fechas', FALSE, SQLERRM);
  END;

  -- C6. INSERT ... SELECT de dos filas que chocan ENTRE SI en la misma sentencia
  BEGIN
    SAVEPOINT sp_c6;
    v_ra := nueva_reserva(v_t1, v_t2, 'CONFIRMADA');
    v_rb := nueva_reserva(v_t1, v_t2, 'CONFIRMADA');
    v_code := 0;
    BEGIN
      INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                      fecha_checkout, valor_previo, valor_reserva)
      SELECT v_ra, v_h3, v_t1, v_t2, 100000, 100000 FROM dual
      UNION ALL
      SELECT v_rb, v_h3, v_t1, v_t2, 100000, 100000 FROM dual;
    EXCEPTION WHEN OTHERS THEN v_code := SQLCODE; v_msg := SQLERRM; END;
    ok('C6 INSERT...SELECT de dos filas que se cruzan -> -20003',
       v_code = -20003,
       CASE WHEN v_code = 0 THEN 'las dos filas entraron'
            WHEN v_code = -4091 THEN 'ORA-04091 tabla mutante'
            ELSE v_code || ': ' || v_msg END);
    ROLLBACK TO sp_c6;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('C6 INSERT...SELECT', FALSE, SQLERRM);
  END;

  -- ==================================================================
  -- D. trg_tarifa_auditoria -> auditoria_tarifa
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== D. trg_tarifa_auditoria ===');
  SELECT NVL(MAX(id_auditoria), 0) INTO v_aud0 FROM auditoria_tarifa;

  -- D1. UPDATE masivo de 3 tarifas = 3 filas con el MISMO id_sentencia
  BEGIN
    SAVEPOINT sp_d1;
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO('prueba_app');
    UPDATE tarifa SET valor = valor + 1000 WHERE id_tarifa <= 3;
    v_n1 := SQL%ROWCOUNT;
    SELECT COUNT(*), COUNT(DISTINCT id_sentencia), COUNT(DISTINCT id_tarifa),
           MIN(operacion), MAX(operacion),
           SUM(CASE WHEN valor_nuevo = valor_anterior + 1000 THEN 1 ELSE 0 END),
           MIN(usuario_bd), MIN(usuario_app)
      INTO v_c1, v_c2, v_c3, v_op, v_usr, v_c4, v_usr, v_app
      FROM auditoria_tarifa
     WHERE id_auditoria > v_aud0;
    ok('D1.1 UPDATE de ' || v_n1 || ' tarifas deja una fila por tarifa',
       v_c1 = v_n1 AND v_c3 = v_n1, v_c1 || ' filas, ' || v_c3 || ' tarifas');
    ok('D1.2 todas comparten el mismo id_sentencia', v_c2 = 1, v_c2 || ' ids distintos');
    ok('D1.3 operacion = UPDATE y valor_nuevo = valor_anterior + 1000',
       v_op = 'UPDATE' AND v_c4 = v_c1, v_op || ' / ' || v_c4 || ' de ' || v_c1);
    ok('D1.4 usuario_bd = usuario de la sesion',
       v_usr = SYS_CONTEXT('USERENV', 'SESSION_USER'), v_usr);
    ok('D1.5 usuario_app = CLIENT_INFO de la sesion', v_app = 'prueba_app', v_app);
    DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
    ROLLBACK TO sp_d1;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('D1 UPDATE masivo', FALSE, SQLERRM);
  END;

  -- D2. Un UPDATE que no cambia el valor no audita
  BEGIN
    SAVEPOINT sp_d2;
    UPDATE tarifa SET valor = valor WHERE id_tarifa <= 3;
    SELECT COUNT(*) INTO v_c1 FROM auditoria_tarifa WHERE id_auditoria > v_aud0;
    ok('D2 UPDATE sin cambio de valor no genera auditoria', v_c1 = 0, v_c1 || ' filas');
    ROLLBACK TO sp_d2;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('D2 UPDATE sin cambio', FALSE, SQLERRM);
  END;

  -- D3. Cambiar otra columna (no valor) no audita
  BEGIN
    SAVEPOINT sp_d3;
    UPDATE tarifa SET descripcion = descripcion || ' ' WHERE id_tarifa = 1;
    SELECT COUNT(*) INTO v_c1 FROM auditoria_tarifa WHERE id_auditoria > v_aud0;
    ok('D3 UPDATE de la descripcion no genera auditoria', v_c1 = 0, v_c1 || ' filas');
    ROLLBACK TO sp_d3;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('D3 UPDATE de otra columna', FALSE, SQLERRM);
  END;

  -- D4. INSERT y DELETE
  BEGIN
    SAVEPOINT sp_d4;
    INSERT INTO tarifa (nombre, descripcion, valor)
    VALUES ('ZZ_PRUEBA_AUDITORIA', 'tarifa de prueba', 123456)
    RETURNING id_tarifa INTO v_tid;
    SELECT COUNT(*) INTO v_c1 FROM auditoria_tarifa
     WHERE id_auditoria > v_aud0 AND id_tarifa = v_tid AND operacion = 'INSERT'
       AND valor_anterior IS NULL AND valor_nuevo = 123456;
    ok('D4.1 INSERT: valor_anterior NULL y valor_nuevo correcto', v_c1 = 1, v_c1 || ' filas');

    DELETE FROM tarifa WHERE id_tarifa = v_tid;
    SELECT COUNT(*) INTO v_c1 FROM auditoria_tarifa
     WHERE id_auditoria > v_aud0 AND id_tarifa = v_tid AND operacion = 'DELETE'
       AND valor_nuevo IS NULL AND valor_anterior = 123456;
    ok('D4.2 DELETE: valor_nuevo NULL y valor_anterior correcto', v_c1 = 1, v_c1 || ' filas');
    ROLLBACK TO sp_d4;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('D4 INSERT/DELETE', FALSE, SQLERRM);
  END;

  -- D5. Dos sentencias = dos id_sentencia distintos
  BEGIN
    SAVEPOINT sp_d5;
    UPDATE tarifa SET valor = valor + 1 WHERE id_tarifa = 1;
    UPDATE tarifa SET valor = valor + 1 WHERE id_tarifa = 2;
    SELECT COUNT(*), COUNT(DISTINCT id_sentencia) INTO v_c1, v_c2
      FROM auditoria_tarifa WHERE id_auditoria > v_aud0;
    ok('D5 dos UPDATE separados tienen id_sentencia distinto',
       v_c1 = 2 AND v_c2 = 2, v_c1 || ' filas, ' || v_c2 || ' sentencias');
    ROLLBACK TO sp_d5;
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    ok('D5 dos sentencias', FALSE, SQLERRM);
  END;

  -- D6. El ROLLBACK deshace tambien la auditoria (misma transaccion)
  SELECT COUNT(*) INTO v_c1 FROM auditoria_tarifa WHERE id_auditoria > v_aud0;
  ok('D6 despues de los ROLLBACK no queda auditoria de prueba', v_c1 = 0, v_c1 || ' filas');

  -- ==================================================================
  -- Resumen
  -- ==================================================================
  DBMS_OUTPUT.PUT_LINE(CHR(10) || '=====================================');
  DBMS_OUTPUT.PUT_LINE('PASS: ' || v_pass || '   FAIL: ' || v_fail || '   OMITIDAS: ' || v_skip);
  DBMS_OUTPUT.PUT_LINE('=====================================');
END;
/

-- ---------------------------------------------------------------------
-- Limpieza: borra las reservas creadas por sp_crear_reserva (el detalle
-- cae por ON DELETE CASCADE; las pruebas no generan pagos ni resenas)
-- ---------------------------------------------------------------------
BEGIN
  DELETE FROM reserva WHERE id_reserva > :v_max_res;
  DBMS_OUTPUT.PUT_LINE('Reservas de prueba eliminadas: ' || SQL%ROWCOUNT);
  COMMIT;
END;
/

-- ---------------------------------------------------------------------
-- PRUEBA MANUAL DE CONCURRENCIA (FOR UPDATE), con dos sesiones sqlplus:
--   Sesion 1:  DECLARE v NUMBER; BEGIN
--                SELECT id_habitacion INTO v FROM habitacion
--                 WHERE id_habitacion = 1 FOR UPDATE; END;   -- sin COMMIT
--   Sesion 2:  EXEC pkg_turismo.sp_crear_reserva(...habitacion 1...)
--              -> se queda esperando.
--   Sesion 1:  ROLLBACK;  -> la sesion 2 continua.
-- Para el trigger de solape: en dos sesiones, insertar a la vez estadias
-- que se crucen en la misma habitacion; la segunda espera (WAIT 10) y
-- al confirmar la primera debe fallar con -20003.
-- ---------------------------------------------------------------------
SET FEEDBACK ON