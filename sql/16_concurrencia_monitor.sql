-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 3
-- Script 16 · Concurrencia: monitor de bloqueos (tercera sesion)
-- ---------------------------------------------------------------------
-- EJECUCION MANUAL, como turismouq, MIENTRAS la sesion B esta esperando:
--
--   docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 \
--          @/docker-entrypoint-initdb.d/16_concurrencia_monitor.sql
--
-- Muestra:
--   1. Las sesiones de turismouq y quien bloquea a quien (V$SESSION)
--   2. Los bloqueos tomados (V$LOCK): TX = fila (transaccion),
--      TM = tabla. LMODE = modo que tiene, REQUEST = modo que espera.
--   3. Que objetos tienen filas bloqueadas (V$LOCKED_OBJECT)
-- Requiere los permisos de diagnostico de 01_tablespaces.sql.
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

SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF
COLUMN sesion          FORMAT A6
COLUMN username        FORMAT A10
COLUMN status          FORMAT A8
COLUMN evento          FORMAT A32
COLUMN tabla_esperada  FORMAT A12
COLUMN objeto          FORMAT A20
COLUMN tipo            FORMAT A4
COLUMN modo_tenido     FORMAT A20
COLUMN modo_pedido     FORMAT A20

PROMPT
PROMPT === 1. Sesiones y quien bloquea a quien ===
SELECT sid, sesion, status, bloqueada_por, evento, seg_esperando, tabla_esperada
  FROM v_monitor_bloqueos
 WHERE sid <> SYS_CONTEXT('USERENV', 'SID')
 ORDER BY sesion, sid;

PROMPT
PROMPT === 2. Bloqueos TX/TM de esas sesiones (BLOCK = 1: bloquea a otra) ===
SELECT l.sid,
       s.client_info AS sesion,
       l.type        AS tipo,
       DECODE(l.lmode, 0, '-', 2, '2 row share', 3, '3 row exclusive',
                       4, '4 share', 6, '6 exclusive', TO_CHAR(l.lmode))   AS modo_tenido,
       DECODE(l.request, 0, '-', 2, '2 row share', 3, '3 row exclusive',
                       4, '4 share', 6, '6 exclusive', TO_CHAR(l.request)) AS modo_pedido,
       l.ctime AS segundos,
       l.block
  FROM v$lock l
  JOIN v$session s ON s.sid = l.sid
 WHERE s.username = 'TURISMOUQ'
   AND l.type IN ('TX', 'TM')
 ORDER BY l.sid, l.type;

PROMPT
PROMPT === 3. Objetos con filas bloqueadas ===
SELECT lo.session_id AS sid, s.client_info AS sesion, o.object_name AS objeto,
       DECODE(lo.locked_mode, 2, 'row share', 3, 'row exclusive',
                              6, 'exclusive', TO_CHAR(lo.locked_mode)) AS modo_tenido
  FROM v$locked_object lo
  JOIN user_objects o ON o.object_id = lo.object_id
  JOIN v$session s   ON s.sid = lo.session_id
 ORDER BY lo.session_id, o.object_name;

EXIT
