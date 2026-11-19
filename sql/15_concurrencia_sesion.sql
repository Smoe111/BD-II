-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 15 · Concurrencia: lo que ejecuta CADA sesion
-- ---------------------------------------------------------------------
-- EJECUCION MANUAL, en DOS terminales distintas (dos sesiones reales):
--
--   Terminal 1 (sesion A):
--   docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 \
--          @/docker-entrypoint-initdb.d/15_concurrencia_sesion.sql 2 A
--
--   Terminal 2 (sesion B), 2 o 3 segundos despues:
--   docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 \
--          @/docker-entrypoint-initdb.d/15_concurrencia_sesion.sql 2 B
--
-- Parametro 1 = escenario (1..4, ver 14_concurrencia_preparar.sql)
-- Parametro 2 = A o B. A reserva para el cliente 10 y B para el 20; las
-- dos piden la MISMA habitacion y las MISMAS noches.
--
-- Mientras B espera, en una tercera terminal: 16_concurrencia_monitor.sql
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

BEGIN
  CASE '&1'
    WHEN '1' THEN pkg_concurrencia.sp_reservar_sin_control(
                    '&2', CASE '&2' WHEN 'A' THEN 10 ELSE 20 END);
    WHEN '2' THEN pkg_concurrencia.sp_reservar_con_bloqueo(
                    '&2', CASE '&2' WHEN 'A' THEN 10 ELSE 20 END, 'ESPERAR');
    WHEN '3' THEN pkg_concurrencia.sp_reservar_con_bloqueo(
                    '&2', CASE '&2' WHEN 'A' THEN 10 ELSE 20 END, 'NOWAIT');
    WHEN '4' THEN pkg_concurrencia.sp_reservar_sin_control(
                    '&2', CASE '&2' WHEN 'A' THEN 10 ELSE 20 END);
    ELSE DBMS_OUTPUT.PUT_LINE('Escenario desconocido: use 1, 2, 3 o 4');
  END CASE;
END;
/

PROMPT
BEGIN
  pkg_concurrencia.sp_resultado;
END;
/

EXIT
