-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 06 · Paquete PKG_TURISMO
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq, despues de 05_liquidacion_tabla.sql
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @06_pkg_turismo.sql
--
-- Contenido:
--   fn_valor_estadia   Regla de precio noche por noche. Es la misma que
--                      uso 03_carga.sql para llenar valor_reserva, asi que
--                      sobre los datos cargados debe reproducirlo exacto.
--   sp_liquidar_mes    Liquidacion mensual por alojamiento: proceso
--                      masivo con CURSOR EXPLICITO CON PARAMETROS.
--
-- Los demas programas de la Entrega 2 (crear reserva, etc.) se agregan a
-- este mismo paquete: especificacion y cuerpo van juntos en este archivo.
--
-- Codigos de error del paquete:
--   -20020..-20022  fn_valor_estadia
--   -20030..-20032  sp_liquidar_mes
-- =====================================================================

ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

-- =====================================================================
-- 1. Especificacion
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_turismo AS

  -- Comision de la plataforma sobre el hospedaje devengado, en %
  c_pct_comision CONSTANT NUMBER := 12;

  -- Valor de una estadia en una habitacion: suma, noche por noche, de
  --   tarifa.valor * (1 + temporada.porcentaje / 100)
  -- con la temporada en que cae cada noche. p_checkout es exclusivo (la
  -- noche del checkout no se cobra).
  FUNCTION fn_valor_estadia (p_id_habitacion IN NUMBER,
                             p_checkin       IN DATE,
                             p_checkout      IN DATE) RETURN NUMBER;

  -- Liquida un mes cerrado para todos los alojamientos, o solo para
  -- p_id_alojamiento si se indica. Se puede repetir: actualiza el corte.
  -- Hace COMMIT al terminar.
  PROCEDURE sp_liquidar_mes (p_anio           IN NUMBER,
                             p_mes            IN NUMBER,
                             p_id_alojamiento IN NUMBER DEFAULT NULL);

  PROCEDURE sp_crear_reserva (p_id_cliente         IN  NUMBER,
                              p_id_usuario_sistema IN  NUMBER,
                              p_checkin            IN  DATE,
                              p_checkout           IN  DATE,
                              p_num_huespedes      IN  NUMBER,
                              p_habitaciones       IN  VARCHAR2,
                              p_id_reserva         OUT NUMBER);

END pkg_turismo;
/


-- =====================================================================
-- 2. Cuerpo
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_turismo AS

  -- -------------------------------------------------------------------
  -- fn_valor_estadia
  -- -------------------------------------------------------------------
  FUNCTION fn_valor_estadia (p_id_habitacion IN NUMBER,
                             p_checkin       IN DATE,
                             p_checkout      IN DATE) RETURN NUMBER
  IS
    v_tarifa   tarifa.valor%TYPE;
    v_noches   PLS_INTEGER;
    v_cubiertas PLS_INTEGER;
    v_valor    NUMBER;
  BEGIN
    IF p_checkin IS NULL OR p_checkout IS NULL
       OR TRUNC(p_checkout) <= TRUNC(p_checkin) THEN
      RAISE_APPLICATION_ERROR(-20020,
        'Rango de fechas invalido: el checkout debe ser posterior al checkin.');
    END IF;

    BEGIN
      SELECT t.valor
        INTO v_tarifa
        FROM habitacion h
        JOIN tarifa t ON t.id_tarifa = h.id_tarifa
       WHERE h.id_habitacion = p_id_habitacion;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20021,
          'La habitacion ' || p_id_habitacion || ' no existe.');
    END;

    v_noches := TRUNC(p_checkout) - TRUNC(p_checkin);

    -- Una fila por noche, cruzada con la temporada que la contiene
    SELECT COUNT(*), SUM(v_tarifa * (1 + te.porcentaje / 100))
      INTO v_cubiertas, v_valor
      FROM (SELECT TRUNC(p_checkin) + LEVEL - 1 AS noche
              FROM dual
           CONNECT BY LEVEL <= v_noches) n
      JOIN temporada te
        ON n.noche BETWEEN te.fecha_inicio AND te.fecha_fin;

    -- Una noche sin temporada se cobraria en cero sin que nadie lo note
    IF v_cubiertas <> v_noches THEN
      RAISE_APPLICATION_ERROR(-20022,
        (v_noches - v_cubiertas) || ' noche(s) entre ' ||
        TO_CHAR(p_checkin, 'YYYY-MM-DD') || ' y ' ||
        TO_CHAR(p_checkout, 'YYYY-MM-DD') || ' no tienen temporada definida.');
    END IF;

    RETURN ROUND(v_valor, 2);
  END fn_valor_estadia;

  -- -------------------------------------------------------------------
  -- sp_liquidar_mes
  -- -------------------------------------------------------------------
  PROCEDURE sp_liquidar_mes (p_anio           IN NUMBER,
                             p_mes            IN NUMBER,
                             p_id_alojamiento IN NUMBER DEFAULT NULL)
  IS
    -- -----------------------------------------------------------------
    -- Cursor de alojamientos a liquidar. No filtra por activo = 'S': un
    -- alojamiento que se dio de baja despues vendio noches en el mes y
    -- hay que pagarselas. La liquidacion es historica, no del estado
    -- actual del catalogo.
    -- -----------------------------------------------------------------
    CURSOR c_alojamientos (p_aloj NUMBER) IS
      SELECT id_alojamiento, nombre
        FROM alojamiento
       WHERE p_aloj IS NULL OR id_alojamiento = p_aloj
       ORDER BY id_alojamiento;

    -- -----------------------------------------------------------------
    -- CURSOR EXPLICITO CON PARAMETROS
    --
    -- Se declara una vez y se reabre con parametros distintos para cada
    -- alojamiento: una sola sentencia analizada, una ejecucion por
    -- alojamiento. Ese es el motivo de que el cursor lleve parametros y
    -- no literales: los parametros viajan como variables de enlace, el
    -- mismo argumento de la consulta 5 de la Entrega 1.
    --
    -- Devuelve las ESTADIAS (reserva x habitacion) que tocan el mes, no
    -- las reservas: una estadia del 28 de febrero al 3 de marzo aparece
    -- en la liquidacion de febrero y en la de marzo, cada una con sus
    -- noches. La condicion es la de solapamiento de rangos
    -- (checkin < fin AND checkout > inicio), con el mes como rango
    -- semiabierto [inicio, fin) para que el dia frontera no se cuente
    -- dos veces.
    --
    -- Solo FINALIZADA y EN_CURSO: las canceladas no generan ingreso, y
    -- en un mes ya cerrado no puede haber estadias PENDIENTES o
    -- CONFIRMADAS que lo toquen (ya habrian empezado).
    -- -----------------------------------------------------------------
    CURSOR c_estadias (p_aloj NUMBER, p_ini DATE, p_fin DATE) IS
      SELECT rh.id_reserva,
             rh.id_habitacion,
             rh.fecha_checkin,
             rh.fecha_checkout,
             rh.valor_reserva
        FROM reserva_habitacion rh
        JOIN reserva r    ON r.id_reserva    = rh.id_reserva
        JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
       WHERE h.id_alojamiento  = p_aloj
         AND r.estado IN ('FINALIZADA', 'EN_CURSO')
         AND rh.fecha_checkin  < p_fin
         AND rh.fecha_checkout > p_ini
       ORDER BY rh.fecha_checkin, rh.id_reserva;

    r_estadia c_estadias%ROWTYPE;

    TYPE t_vistas IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
    v_vistas t_vistas;            -- reservas distintas (una reserva puede
                                  -- traer varias habitaciones)
    v_mes_ini    DATE;
    v_mes_fin    DATE;            -- primer dia del mes siguiente (exclusivo)
    v_ini        DATE;
    v_fin        DATE;
    v_valor      NUMBER;
    v_noches     NUMBER;
    v_hospedaje  NUMBER;
    v_servicios  NUMBER;
    v_recaudo    NUMBER;
    v_comision   NUMBER;
    v_reservas   NUMBER;
    v_filas      NUMBER;
    v_procesados NUMBER := 0;
    v_fallidos   NUMBER := 0;
    v_existe     NUMBER;
  BEGIN
    -- ----- Validaciones -----------------------------------------------
    IF p_anio IS NULL OR p_mes IS NULL
       OR p_anio <> TRUNC(p_anio) OR p_mes <> TRUNC(p_mes)
       OR p_mes NOT BETWEEN 1 AND 12 THEN
      RAISE_APPLICATION_ERROR(-20030,
        'Periodo invalido: ' || NVL(TO_CHAR(p_anio), 'NULL') || '-' ||
        NVL(TO_CHAR(p_mes), 'NULL'));
    END IF;

    v_mes_ini := TO_DATE(p_anio || LPAD(p_mes, 2, '0') || '01', 'YYYYMMDD');
    v_mes_fin := ADD_MONTHS(v_mes_ini, 1);

    -- Solo se liquidan meses cerrados: hacerlo sobre el mes en curso daria
    -- un corte parcial que al dia siguiente ya no cuadra.
    IF v_mes_fin > TRUNC(SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20031,
        'El periodo ' || TO_CHAR(v_mes_ini, 'YYYY-MM') ||
        ' no ha cerrado; solo se liquidan meses terminados.');
    END IF;

    IF p_id_alojamiento IS NOT NULL THEN
      SELECT COUNT(*) INTO v_existe
        FROM alojamiento
       WHERE id_alojamiento = p_id_alojamiento;
      IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20032,
          'El alojamiento ' || p_id_alojamiento || ' no existe.');
      END IF;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Liquidando ' || TO_CHAR(v_mes_ini, 'YYYY-MM'));

    -- ----- Recorrido masivo -------------------------------------------
    FOR a IN c_alojamientos(p_id_alojamiento) LOOP

      -- Un alojamiento que falle no debe tumbar el lote completo: se
      -- deshace solo su parte y el proceso sigue con el siguiente.
      SAVEPOINT sp_alojamiento;

      BEGIN
        v_hospedaje := 0;
        v_noches    := 0;
        v_vistas.DELETE;

        -- --- Cursor explicito: OPEN, FETCH, %NOTFOUND, CLOSE ----------
        OPEN c_estadias(a.id_alojamiento, v_mes_ini, v_mes_fin);
        LOOP
          FETCH c_estadias INTO r_estadia;
          EXIT WHEN c_estadias%NOTFOUND;

          -- Recorte de la estadia al mes que se liquida
          v_ini := GREATEST(r_estadia.fecha_checkin,  v_mes_ini);
          v_fin := LEAST   (r_estadia.fecha_checkout, v_mes_fin);

          -- Se liquida sobre lo COBRADO (valor_reserva, la foto de la
          -- reserva), no sobre la tarifa de hoy: si una tarifa cambia
          -- despues de reservar, al alojamiento se le liquida lo que el
          -- cliente pago.
          IF v_ini = r_estadia.fecha_checkin AND v_fin = r_estadia.fecha_checkout THEN
            -- Estadia completa dentro del mes: el caso comun
            v_valor := r_estadia.valor_reserva;
          ELSE
            -- Estadia que cruza el cambio de mes: lo cobrado se reparte
            -- con el peso de cada noche segun su temporada. Repartir por
            -- numero de noches seria un error: la noche del 31 de
            -- diciembre no vale lo mismo que la del 1 de febrero.
            -- fn_valor_estadia solo pone los pesos; el total sigue
            -- siendo valor_reserva, asi que las partes suman exacto.
            v_valor := r_estadia.valor_reserva
                     * fn_valor_estadia(r_estadia.id_habitacion, v_ini, v_fin)
                     / fn_valor_estadia(r_estadia.id_habitacion,
                                        r_estadia.fecha_checkin,
                                        r_estadia.fecha_checkout);
          END IF;

          v_hospedaje := v_hospedaje + v_valor;
          v_noches    := v_noches    + (v_fin - v_ini);
          v_vistas(r_estadia.id_reserva) := TRUE;
        END LOOP;
        v_filas := c_estadias%ROWCOUNT;     -- se lee ANTES de cerrar
        CLOSE c_estadias;

        v_reservas  := v_vistas.COUNT;
        v_hospedaje := ROUND(v_hospedaje, 2);

        -- --- Servicios consumidos en el mes ---------------------------
        -- SERVICIO es catalogo de la plataforma y no pertenece a un
        -- alojamiento, asi que este ingreso se informa pero NO entra a
        -- la base de comision ni al neto: no es plata del establecimiento.
        -- (03_carga.sql garantiza que una reserva no mezcla alojamientos.)
        SELECT NVL(SUM(rs.valor_servicio), 0)
          INTO v_servicios
          FROM reserva_servicio rs
          JOIN reserva r ON r.id_reserva = rs.id_reserva
         WHERE r.estado IN ('FINALIZADA', 'EN_CURSO')
           AND rs.fecha_servicio >= v_mes_ini
           AND rs.fecha_servicio <  v_mes_fin
           AND EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
                        WHERE rh.id_reserva     = r.id_reserva
                          AND h.id_alojamiento  = a.id_alojamiento);

        -- --- Recaudo de caja del mes ----------------------------------
        -- Se informa aparte porque NO coincide con lo devengado: el
        -- anticipo de una estadia de diciembre pudo entrar en octubre.
        SELECT NVL(SUM(p.valor), 0)
          INTO v_recaudo
          FROM pago p
         WHERE p.estado = 'APROBADO'
           AND p.fecha_pago >= v_mes_ini
           AND p.fecha_pago <  v_mes_fin
           AND EXISTS (SELECT 1
                         FROM reserva_habitacion rh
                         JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
                        WHERE rh.id_reserva     = p.id_reserva
                          AND h.id_alojamiento  = a.id_alojamiento);

        v_comision := ROUND(v_hospedaje * c_pct_comision / 100, 2);

        -- --- Resultado idempotente ------------------------------------
        MERGE INTO liquidacion_mensual l
        USING (SELECT a.id_alojamiento AS id_aloj, p_anio AS anio, p_mes AS mes
                 FROM dual) s
           ON (l.id_alojamiento = s.id_aloj AND l.anio = s.anio AND l.mes = s.mes)
        WHEN MATCHED THEN
          UPDATE SET reservas          = v_reservas,
                     noches_vendidas   = v_noches,
                     ingreso_hospedaje = v_hospedaje,
                     ingreso_servicios = v_servicios,
                     recaudo_caja      = v_recaudo,
                     pct_comision      = c_pct_comision,
                     valor_comision    = v_comision,
                     neto_alojamiento  = v_hospedaje - v_comision,
                     fecha_proceso     = SYSDATE
        WHEN NOT MATCHED THEN
          INSERT (id_alojamiento, anio, mes, reservas, noches_vendidas,
                  ingreso_hospedaje, ingreso_servicios, recaudo_caja,
                  pct_comision, valor_comision, neto_alojamiento)
          VALUES (s.id_aloj, s.anio, s.mes, v_reservas, v_noches,
                  v_hospedaje, v_servicios, v_recaudo,
                  c_pct_comision, v_comision, v_hospedaje - v_comision);

        v_procesados := v_procesados + 1;

        IF v_filas > 0 THEN
          DBMS_OUTPUT.PUT_LINE(
            '  ' || RPAD(a.nombre, 32) ||
            LPAD(v_filas, 5)  || ' estadias ' ||
            LPAD(v_noches, 5) || ' noches ' ||
            LPAD(TO_CHAR(v_hospedaje, '999G999G999'), 14));
        END IF;

      EXCEPTION
        WHEN OTHERS THEN
          -- Si el error salto con el cursor abierto, el OPEN del siguiente
          -- alojamiento fallaria con ORA-06511 (cursor ya abierto) y el
          -- resto del lote caeria en cadena.
          IF c_estadias%ISOPEN THEN
            CLOSE c_estadias;
          END IF;
          ROLLBACK TO sp_alojamiento;
          v_fallidos := v_fallidos + 1;
          DBMS_OUTPUT.PUT_LINE('  *** Fallo ' || a.nombre || ': ' || SQLERRM);
      END;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Alojamientos liquidados: ' || v_procesados ||
                         ' - con error: ' || v_fallidos);
  END sp_liquidar_mes;

  -- -------------------------------------------------------------------
  -- sp_crear_reserva
  -- -------------------------------------------------------------------
  PROCEDURE sp_crear_reserva (p_id_cliente         IN  NUMBER,
                              p_id_usuario_sistema IN  NUMBER,
                              p_checkin            IN  DATE,
                              p_checkout           IN  DATE,
                              p_num_huespedes      IN  NUMBER,
                              p_habitaciones       IN  VARCHAR2,
                              p_id_reserva         OUT NUMBER)
  IS
    TYPE t_n IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
 
    v_ids        t_n;       -- habitaciones pedidas, ordenadas por id
    v_valor      t_n;       -- valor de la estadia por habitacion
    v_previo     t_n;       -- noches x tarifa base por habitacion
 
    v_checkin    DATE := TRUNC(p_checkin);
    v_checkout   DATE := TRUNC(p_checkout);
    v_noches     PLS_INTEGER;
 
    v_existe     NUMBER;
    v_rol        usuario_sistema.rol%TYPE;
    v_activo_u   usuario_sistema.activo%TYPE;
    v_cli_cuenta usuario_sistema.id_cliente%TYPE;
 
    v_aloj       habitacion.id_alojamiento%TYPE;
    v_aloj_ref   habitacion.id_alojamiento%TYPE;
    v_act_hab    habitacion.activo%TYPE;
    v_act_aloj   alojamiento.activo%TYPE;
    v_numero     habitacion.numero_habitacion%TYPE;
    v_cap        tipo_habitacion.capacidad_maxima%TYPE;
    v_tarifa     tarifa.valor%TYPE;
    v_cap_total  NUMBER := 0;
    v_total      NUMBER := 0;
  BEGIN
    p_id_reserva := NULL;
 
    -- ----- 1. Fechas ----------------------------------------------------
    IF v_checkin IS NULL OR v_checkout IS NULL THEN
      RAISE_APPLICATION_ERROR(-20040,
        'Las fechas de check-in y check-out son obligatorias.');
    END IF;
    IF v_checkout <= v_checkin THEN
      RAISE_APPLICATION_ERROR(-20040,
        'El check-out (' || TO_CHAR(v_checkout, 'YYYY-MM-DD') ||
        ') debe ser posterior al check-in (' ||
        TO_CHAR(v_checkin, 'YYYY-MM-DD') || ').');
    END IF;
    -- Misma regla que ck_reserva_anticipo, pero con un mensaje legible
    -- en vez de ORA-02290.
    IF v_checkin < TRUNC(SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20040,
        'No se puede reservar con check-in en el pasado (' ||
        TO_CHAR(v_checkin, 'YYYY-MM-DD') || ').');
    END IF;
    v_noches := v_checkout - v_checkin;
 
    -- ----- 2. Cliente ---------------------------------------------------
    SELECT COUNT(*) INTO v_existe
      FROM cliente
     WHERE id_cliente = p_id_cliente;
    IF v_existe = 0 THEN
      RAISE_APPLICATION_ERROR(-20041,
        'El cliente ' || NVL(TO_CHAR(p_id_cliente), 'NULL') || ' no existe.');
    END IF;
 
    -- ----- 3. Usuario que registra --------------------------------------
    BEGIN
      SELECT rol, activo, id_cliente
        INTO v_rol, v_activo_u, v_cli_cuenta
        FROM usuario_sistema
       WHERE id_usuario_sistema = p_id_usuario_sistema;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20042,
          'El usuario ' || NVL(TO_CHAR(p_id_usuario_sistema), 'NULL') ||
          ' no existe.');
    END;
    IF v_activo_u <> 'S' THEN
      RAISE_APPLICATION_ERROR(-20042,
        'El usuario ' || p_id_usuario_sistema || ' esta inactivo.');
    END IF;
    -- Un cliente solo puede reservar a su propio nombre; el personal
    -- (recepcion, admin) reserva a nombre de cualquier cliente.
    IF v_rol = 'CLIENTE' AND v_cli_cuenta <> p_id_cliente THEN
      RAISE_APPLICATION_ERROR(-20042,
        'La cuenta ' || p_id_usuario_sistema ||
        ' pertenece a otro cliente y no puede reservar por el cliente ' ||
        p_id_cliente || '.');
    END IF;
 
    -- ----- 4. Huespedes -------------------------------------------------
    IF p_num_huespedes IS NULL OR p_num_huespedes <> TRUNC(p_num_huespedes)
       OR p_num_huespedes NOT BETWEEN 1 AND 60 THEN
      RAISE_APPLICATION_ERROR(-20043,
        'Numero de huespedes invalido (' ||
        NVL(TO_CHAR(p_num_huespedes), 'NULL') || '): debe estar entre 1 y 60.');
    END IF;
 
    -- ----- 5. Lista de habitaciones -------------------------------------
    -- Ordenada por id: las filas se bloquean siempre en el mismo orden y
    -- dos reservas concurrentes sobre las mismas habitaciones no pueden
    -- quedar en deadlock.
    BEGIN
      SELECT TO_NUMBER(TRIM(REGEXP_SUBSTR(p_habitaciones, '[^,]+', 1, LEVEL)))
        BULK COLLECT INTO v_ids
        FROM dual
     CONNECT BY REGEXP_SUBSTR(p_habitaciones, '[^,]+', 1, LEVEL) IS NOT NULL
       ORDER BY 1;
    EXCEPTION
      WHEN INVALID_NUMBER OR VALUE_ERROR THEN
        RAISE_APPLICATION_ERROR(-20044,
          'Lista de habitaciones mal formada: ' || p_habitaciones ||
          ' (se esperan ids separados por coma, ej. 12,13).');
    END;
 
    IF v_ids.COUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20044,
        'Debe indicar al menos una habitacion.');
    END IF;
 
    -- Todo lo que sigue toca datos: si algo falla, se deshace y se
    -- liberan los bloqueos de las habitaciones.
    SAVEPOINT sp_crear_reserva;
 
    BEGIN
      FOR i IN 1 .. v_ids.COUNT LOOP
 
        IF v_ids(i) <> TRUNC(v_ids(i)) THEN
          RAISE_APPLICATION_ERROR(-20044,
            'Id de habitacion invalido: ' || v_ids(i));
        END IF;
        IF i > 1 AND v_ids(i) = v_ids(i - 1) THEN
          RAISE_APPLICATION_ERROR(-20044,
            'La habitacion ' || v_ids(i) || ' esta repetida en la lista.');
        END IF;
 
        -- --- 6. Existencia, capacidad y tarifa, bloqueando la fila ----
        -- FOR UPDATE serializa a quienes reservan la misma habitacion:
        -- el segundo espera a que el primero confirme y entonces ve la
        -- reserva ya creada en la verificacion de disponibilidad. Sin el
        -- bloqueo, dos sesiones podrian pasar la verificacion a la vez y
        -- guardar la misma noche dos veces.
        BEGIN
          SELECT h.id_alojamiento, h.activo, a.activo,
                 h.numero_habitacion, th.capacidad_maxima, tf.valor
            INTO v_aloj, v_act_hab, v_act_aloj,
                 v_numero, v_cap, v_tarifa
            FROM habitacion h
            JOIN alojamiento a      ON a.id_alojamiento      = h.id_alojamiento
            JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
            JOIN tarifa tf          ON tf.id_tarifa          = h.id_tarifa
           WHERE h.id_habitacion = v_ids(i)
             FOR UPDATE OF h.id_habitacion;
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20044,
              'La habitacion ' || v_ids(i) || ' no existe.');
        END;
 
        IF v_act_hab <> 'S' THEN
          RAISE_APPLICATION_ERROR(-20044,
            'La habitacion ' || v_ids(i) || ' (No. ' || v_numero ||
            ') esta inactiva.');
        END IF;
        IF v_act_aloj <> 'S' THEN
          RAISE_APPLICATION_ERROR(-20045,
            'El alojamiento de la habitacion ' || v_ids(i) || ' esta inactivo.');
        END IF;
 
        -- --- Un solo alojamiento por reserva --------------------------
        -- La liquidacion (sp_liquidar_mes) y la consulta 8 asumen que una
        -- reserva no mezcla alojamientos; aqui se garantiza.
        IF i = 1 THEN
          v_aloj_ref := v_aloj;
        ELSIF v_aloj <> v_aloj_ref THEN
          RAISE_APPLICATION_ERROR(-20045,
            'Las habitaciones de una reserva deben ser del mismo alojamiento ' ||
            '(la ' || v_ids(i) || ' es de otro).');
        END IF;
 
        v_cap_total := v_cap_total + v_cap;
 
        -- --- 7. Disponibilidad ----------------------------------------
        -- Las CANCELADAS no bloquean. Solape de rangos semiabiertos
        -- [checkin, checkout): la noche del checkout queda libre para
        -- el huesped que llega ese mismo dia.
        SELECT COUNT(*) INTO v_existe
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = v_ids(i)
           AND r.estado        <> 'CANCELADA'
           AND rh.fecha_checkin  < v_checkout
           AND rh.fecha_checkout > v_checkin;
        IF v_existe > 0 THEN
          RAISE_APPLICATION_ERROR(-20047,
            'La habitacion ' || v_ids(i) || ' (No. ' || v_numero ||
            ') no esta disponible entre ' || TO_CHAR(v_checkin, 'YYYY-MM-DD') ||
            ' y ' || TO_CHAR(v_checkout, 'YYYY-MM-DD') || '.');
        END IF;
 
        -- --- 8. Valor: noche por noche, con la temporada de cada una --
        -- Si falta una temporada, fn_valor_estadia levanta -20022 y se
        -- propaga: mejor no reservar que cobrar una noche en cero.
        v_valor(i)  := fn_valor_estadia(v_ids(i), v_checkin, v_checkout);
        v_previo(i) := v_noches * v_tarifa;     -- sin ajuste de temporada
        v_total     := v_total + v_valor(i);
      END LOOP;
 
      -- Capacidad total de las habitaciones pedidas (la suma, no una por
      -- una: 5 personas pueden repartirse en dos dobles y una sencilla).
      IF p_num_huespedes > v_cap_total THEN
        RAISE_APPLICATION_ERROR(-20046,
          'Capacidad superada: ' || p_num_huespedes || ' huespedes para ' ||
          'habitaciones con capacidad total de ' || v_cap_total || '.');
      END IF;
 
      -- ----- 9. Insercion: cabecera y detalle ---------------------------
      -- fecha_creacion toma SYSDATE; estado nace PENDIENTE y sin pagos.
      -- Los valores quedan como FOTO del momento de la reserva.
      INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_checkin,
                           fecha_checkout, estado, num_huespedes,
                           valor_total, valor_pagado)
      VALUES (p_id_cliente, p_id_usuario_sistema, v_checkin,
              v_checkout, 'PENDIENTE', p_num_huespedes,
              v_total, 0)
      RETURNING id_reserva INTO p_id_reserva;
 
      FOR i IN 1 .. v_ids.COUNT LOOP
        INSERT INTO reserva_habitacion (id_reserva, id_habitacion,
                                        fecha_checkin, fecha_checkout,
                                        valor_previo, valor_reserva)
        VALUES (p_id_reserva, v_ids(i), v_checkin, v_checkout,
                v_previo(i), v_valor(i));
      END LOOP;
 
      COMMIT;
 
    EXCEPTION
      WHEN OTHERS THEN
        ROLLBACK TO sp_crear_reserva;
        p_id_reserva := NULL;
        RAISE;      -- el error original (-200xx u ORA-) llega intacto al llamador
    END;
  END sp_crear_reserva;
 

END pkg_turismo;
/

SHOW ERRORS PACKAGE BODY pkg_turismo

PROMPT
PROMPT === Estado del paquete (debe decir VALID) ===
SELECT object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_TURISMO'
 ORDER BY object_type;

PROMPT Paquete PKG_TURISMO compilado. Continue con 07_liquidacion_pruebas.sql
