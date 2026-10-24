-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 07 · Disparadores
-- ---------------------------------------------------------------------
--   trg_tarifa_auditoria  nivel de SENTENCIA: bitacora de cambios en TARIFA
--   trg_rh_no_solape      nivel de FILA: impide reservas solapadas
--
-- Por que son COMPOUND TRIGGER y no dos triggers "simples":
--
--  * Un trigger de sentencia (FOR EACH ROW ausente) NO tiene :OLD ni :NEW,
--    y la auditoria necesita el valor anterior y el nuevo. El compound
--    trigger captura cada fila en su seccion AFTER EACH ROW y escribe la
--    bitacora UNA vez por sentencia en AFTER STATEMENT (y le pone a todas
--    las filas de esa sentencia el mismo id_sentencia).
--
--  * Un trigger de fila que consulta su propia tabla (para buscar el
--    cruce) falla con ORA-04091 "tabla mutante" en cuanto la sentencia es
--    un UPDATE o un INSERT ... SELECT. La seccion AFTER EACH ROW solo
--    anota (id_reserva, habitacion, fechas) y la verificacion se hace en
--    AFTER STATEMENT, cuando la tabla ya no esta mutando.

 
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;
 
CREATE OR REPLACE TRIGGER trg_rh_no_solape
FOR INSERT OR UPDATE OF id_habitacion, fecha_checkin, fecha_checkout
ON reserva_habitacion
COMPOUND TRIGGER
 
  TYPE t_fila IS RECORD (
    id_reserva     reserva_habitacion.id_reserva%TYPE,
    id_habitacion  reserva_habitacion.id_habitacion%TYPE,
    fecha_checkin  reserva_habitacion.fecha_checkin%TYPE,
    fecha_checkout reserva_habitacion.fecha_checkout%TYPE
  );
  TYPE t_filas IS TABLE OF t_fila INDEX BY PLS_INTEGER;
  g_filas t_filas;
 
  -- ---------------------------------------------------------------
  -- Nivel de FILA: solo recolecta
  -- ---------------------------------------------------------------
  AFTER EACH ROW IS
    v_i PLS_INTEGER := g_filas.COUNT + 1;
  BEGIN
    g_filas(v_i).id_reserva     := :NEW.id_reserva;
    g_filas(v_i).id_habitacion  := :NEW.id_habitacion;
    g_filas(v_i).fecha_checkin  := :NEW.fecha_checkin;
    g_filas(v_i).fecha_checkout := :NEW.fecha_checkout;
  END AFTER EACH ROW;
 
  -- ---------------------------------------------------------------
  -- Fin de la sentencia: verifica
  -- ---------------------------------------------------------------
  AFTER STATEMENT IS
    v_fila   t_fila;
    v_numero habitacion.numero_habitacion%TYPE;
    v_choque reserva_habitacion.id_reserva%TYPE;
  BEGIN
    FOR i IN 1 .. g_filas.COUNT LOOP
      v_fila := g_filas(i);
 
      -- Bloquea la habitacion; despues de obtener el bloqueo la consulta
      -- siguiente ya ve lo que otras sesiones hayan confirmado.
      SELECT numero_habitacion
        INTO v_numero
        FROM habitacion
       WHERE id_habitacion = v_fila.id_habitacion
         FOR UPDATE WAIT 10;
 
      -- Busca otra reserva ACTIVA de la misma habitacion que se cruce,
      -- siempre que la reserva de la fila nueva tambien este activa.
      SELECT MIN(rh.id_reserva)
        INTO v_choque
        FROM reserva_habitacion rh
        JOIN reserva r ON r.id_reserva = rh.id_reserva
       WHERE rh.id_habitacion = v_fila.id_habitacion
         AND rh.id_reserva   <> v_fila.id_reserva
         AND r.estado        <> 'CANCELADA'
         AND rh.fecha_checkin  < v_fila.fecha_checkout
         AND v_fila.fecha_checkin < rh.fecha_checkout
         AND EXISTS (SELECT 1
                       FROM reserva p
                      WHERE p.id_reserva = v_fila.id_reserva
                        AND p.estado    <> 'CANCELADA');
 
      IF v_choque IS NOT NULL THEN
        RAISE_APPLICATION_ERROR(-20003,
          'La habitacion ' || v_numero || ' ya tiene la reserva activa '
          || v_choque || ' que se cruza con las fechas '
          || TO_CHAR(v_fila.fecha_checkin,  'YYYY-MM-DD') || ' a '
          || TO_CHAR(v_fila.fecha_checkout, 'YYYY-MM-DD'));
      END IF;
    END LOOP;
 
    g_filas.DELETE;
  END AFTER STATEMENT;
 
END trg_rh_no_solape;
/
SHOW ERRORS
 
--
-- EJECUTAR COMO: turismouq
-- =====================================================================
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED

-- ---------------------------------------------------------------------
-- 1. Auditoria de TARIFA
-- ---------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_tarifa_auditoria
  FOR INSERT OR UPDATE OF valor OR DELETE ON tarifa
COMPOUND TRIGGER

  TYPE t_aud IS TABLE OF auditoria_tarifa%ROWTYPE INDEX BY PLS_INTEGER;
  g_aud  t_aud;
  g_sent NUMBER;

  BEFORE STATEMENT IS
  BEGIN
    g_aud.DELETE;
    g_sent := seq_auditoria_sentencia.NEXTVAL;
  END BEFORE STATEMENT;

  AFTER EACH ROW IS
    v_i PLS_INTEGER;
  BEGIN
    -- un UPDATE que deja el mismo valor no es un cambio
    IF INSERTING OR DELETING OR :OLD.valor <> :NEW.valor THEN
      v_i := g_aud.COUNT + 1;
      g_aud(v_i).id_sentencia   := g_sent;
      g_aud(v_i).id_tarifa      := NVL(:NEW.id_tarifa, :OLD.id_tarifa);
      g_aud(v_i).operacion      := CASE WHEN INSERTING THEN 'INSERT'
                                        WHEN UPDATING  THEN 'UPDATE'
                                        ELSE 'DELETE' END;
      g_aud(v_i).valor_anterior := :OLD.valor;   -- NULL en INSERT
      g_aud(v_i).valor_nuevo    := :NEW.valor;   -- NULL en DELETE
    END IF;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
  BEGIN
    FOR i IN 1 .. g_aud.COUNT LOOP
      INSERT INTO auditoria_tarifa
             (id_sentencia, id_tarifa, operacion, usuario_bd, usuario_app,
              fecha_cambio, valor_anterior, valor_nuevo)
      VALUES (g_aud(i).id_sentencia, g_aud(i).id_tarifa, g_aud(i).operacion,
              SYS_CONTEXT('USERENV', 'SESSION_USER'),
              SYS_CONTEXT('USERENV', 'CLIENT_INFO'),
              SYSTIMESTAMP, g_aud(i).valor_anterior, g_aud(i).valor_nuevo);
    END LOOP;
    g_aud.DELETE;
  END AFTER STATEMENT;

END trg_tarifa_auditoria;
/
SHOW ERRORS