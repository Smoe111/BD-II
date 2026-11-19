-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 14 · Concurrencia: preparar un escenario del experimento
-- ---------------------------------------------------------------------
-- EJECUCION MANUAL, como turismouq, ANTES de cada escenario:
--
--   docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 \
--          @/docker-entrypoint-initdb.d/14_concurrencia_preparar.sql 2
--
-- Parametro 1 = escenario:
--   1  ANTES   SELECT normal, sin trigger        -> doble reserva
--   2  DESPUES SELECT ... FOR UPDATE (espera)    -> B espera y es rechazada
--   3  DESPUES SELECT ... FOR UPDATE NOWAIT      -> B falla al instante
--   4  SELECT normal + trigger trg_rh_no_solape  -> el trigger la detiene
--   0  restaurar: borra las reservas del experimento y deja el trigger
--      ENABLED. CORRERLO AL TERMINAR.
--
-- Por que se apaga el trigger en 1-3: trg_rh_no_solape (Entrega 2) ya
-- bloquea la habitacion con FOR UPDATE antes de verificar, asi que con
-- el encendido el escenario "antes" no mostraria el problema. Se apaga
-- para medir cada mecanismo por separado; el escenario 4 lo vuelve a
-- encender para mostrar que es la segunda linea de defensa.
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
SET VERIFY OFF
SET FEEDBACK OFF

PROMPT
PROMPT === Preparando escenario &1 ===
BEGIN
  pkg_concurrencia.sp_preparar(p_trigger_activo => ('&1' IN ('0', '4')));
END;
/

BEGIN
  DBMS_OUTPUT.PUT_LINE(CASE '&1'
    WHEN '1' THEN 'Escenario 1 (ANTES): sin bloqueo, sin trigger'
    WHEN '2' THEN 'Escenario 2 (DESPUES): SELECT ... FOR UPDATE, la segunda sesion espera'
    WHEN '3' THEN 'Escenario 3 (DESPUES): SELECT ... FOR UPDATE NOWAIT'
    WHEN '4' THEN 'Escenario 4: sin bloqueo en el procedimiento, trigger encendido'
    WHEN '0' THEN 'Restaurado: trigger encendido, sin reservas de prueba'
    ELSE 'Escenario desconocido: use 0, 1, 2, 3 o 4' END);
  IF '&1' <> '0' THEN
    DBMS_OUTPUT.PUT_LINE('Ahora: sesion A corre 15_concurrencia_sesion.sql &1 A');
    DBMS_OUTPUT.PUT_LINE('       y a los 2-3 segundos, sesion B: 15_concurrencia_sesion.sql &1 B');
  END IF;
END;
/

EXIT
