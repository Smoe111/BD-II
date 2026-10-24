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