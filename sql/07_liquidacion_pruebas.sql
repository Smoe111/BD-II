-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 2
-- Script 07 · Ejecucion y verificacion de la liquidacion mensual
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq, despues de 05 y 06.
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @07_liquidacion_pruebas.sql
--
-- Igual que 04_consultas.sql, se corre a mano: depende de SYSDATE (solo
-- se liquidan meses cerrados) y no tiene sentido al crear el contenedor.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET PAGESIZE 100
SET LINESIZE 200
SET TIMING ON

-- =====================================================================
-- 1. Ejecucion
-- =====================================================================
PROMPT
PROMPT === 1.1 Un mes completo (todos los alojamientos) ===
EXEC pkg_turismo.sp_liquidar_mes(2026, 6);

PROMPT
PROMPT === 1.2 Un solo alojamiento, para revisar un caso puntual ===
EXEC pkg_turismo.sp_liquidar_mes(2026, 6, 12);

PROMPT
PROMPT === 1.3 Repetir el mismo periodo: actualiza, no duplica ===
EXEC pkg_turismo.sp_liquidar_mes(2026, 6);

SELECT COUNT(*) AS filas_2026_06, COUNT(DISTINCT id_alojamiento) AS alojamientos
  FROM liquidacion_mensual
 WHERE anio = 2026 AND mes = 6;

PROMPT
PROMPT === 1.4 Errores esperados ===
BEGIN
  pkg_turismo.sp_liquidar_mes(EXTRACT(YEAR FROM SYSDATE),
                              EXTRACT(MONTH FROM SYSDATE));
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Mes sin cerrar   -> ' || SQLERRM);
END;
/
BEGIN
  pkg_turismo.sp_liquidar_mes(2026, 13);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Mes invalido     -> ' || SQLERRM);
END;
/
BEGIN
  pkg_turismo.sp_liquidar_mes(2026, 6, 99999);
EXCEPTION
  WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Sin alojamiento  -> ' || SQLERRM);
END;
/

-- ---------------------------------------------------------------------
-- 1.5 Historico completo: todos los meses cerrados desde enero de 2024.
-- Se apaga la salida: son 60 lineas por mes. Si algun alojamiento
-- fallara, la verificacion 2.2 lo deja en evidencia.
-- ---------------------------------------------------------------------
PROMPT
PROMPT === 1.5 Historico: todos los meses cerrados desde 2024-01 ===
SET SERVEROUTPUT OFF
DECLARE
  v_mes DATE := DATE '2024-01-01';
BEGIN
  WHILE ADD_MONTHS(v_mes, 1) <= TRUNC(SYSDATE) LOOP
    pkg_turismo.sp_liquidar_mes(EXTRACT(YEAR FROM v_mes), EXTRACT(MONTH FROM v_mes));
    v_mes := ADD_MONTHS(v_mes, 1);
  END LOOP;
END;
/
SET SERVEROUTPUT ON SIZE UNLIMITED

-- =====================================================================
-- 2. Verificacion
-- =====================================================================
COLUMN alojamiento FORMAT A32
COLUMN municipio   FORMAT A14

-- ---------------------------------------------------------------------
-- 2.1 La funcion reproduce lo que guardo la carga. Si da distinto de 0
-- sobre datos recien cargados, los pesos del prorrateo estan mal. (Si
-- alguien cambio una tarifa despues, las diferencias son esperadas: por
-- eso la liquidacion usa valor_reserva y no la tarifa de hoy.)
-- ---------------------------------------------------------------------
PROMPT
PROMPT === 2.1 fn_valor_estadia vs valor_reserva guardado (debe dar 0) ===
SELECT COUNT(*) AS estadias,
       SUM(CASE WHEN pkg_turismo.fn_valor_estadia(rh.id_habitacion,
                                                  rh.fecha_checkin,
                                                  rh.fecha_checkout)
                     <> rh.valor_reserva THEN 1 ELSE 0 END) AS diferencias
  FROM reserva_habitacion rh;

-- ---------------------------------------------------------------------
-- 2.2 Cada periodo liquidado tiene a todos los alojamientos
-- ---------------------------------------------------------------------
PROMPT
PROMPT === 2.2 Periodos incompletos (debe salir vacio) ===
SELECT anio, mes, COUNT(*) AS alojamientos
  FROM liquidacion_mensual
 GROUP BY anio, mes
HAVING COUNT(*) <> (SELECT COUNT(*) FROM alojamiento)
 ORDER BY anio, mes;

-- ---------------------------------------------------------------------
-- 2.3 Cuadre de noches por anio contra un calculo independiente en SQL.
-- Prueba que el recorte por mes no pierde ni duplica noches en las
-- estadias que cruzan el cambio de mes (y de anio: diciembre-enero es
-- temporada alta y hay muchas).
-- ---------------------------------------------------------------------
PROMPT
PROMPT === 2.3 Cuadre de noches por anio (diferencia debe ser 0) ===
WITH anios AS (
  SELECT 2024 AS anio, DATE '2024-01-01' AS ini, DATE '2025-01-01' AS fin FROM dual
  UNION ALL
  SELECT 2025,         DATE '2025-01-01',        DATE '2026-01-01'        FROM dual
)
SELECT x.anio,
       (SELECT SUM(l.noches_vendidas)
          FROM liquidacion_mensual l
         WHERE l.anio = x.anio) AS liquidadas,
       (SELECT SUM(LEAST(rh.fecha_checkout, x.fin) - GREATEST(rh.fecha_checkin, x.ini))
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE r.estado IN ('FINALIZADA', 'EN_CURSO')
           AND rh.fecha_checkin  < x.fin
           AND rh.fecha_checkout > x.ini) AS esperadas,
       (SELECT SUM(l.noches_vendidas)
          FROM liquidacion_mensual l
         WHERE l.anio = x.anio)
     - (SELECT SUM(LEAST(rh.fecha_checkout, x.fin) - GREATEST(rh.fecha_checkin, x.ini))
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE r.estado IN ('FINALIZADA', 'EN_CURSO')
           AND rh.fecha_checkin  < x.fin
           AND rh.fecha_checkout > x.ini) AS diferencia
  FROM anios x
 ORDER BY x.anio;

-- ---------------------------------------------------------------------
-- 2.4 Cuadre de valor: el mismo prorrateo hecho en UNA sola sentencia
-- SQL, sin cursor ni funcion (calendario de noches x temporada), contra
-- lo que dejo el cursor, alojamiento por alojamiento y mes por mes.
-- Solo admite centavos de redondeo.
-- ---------------------------------------------------------------------
PROMPT
PROMPT === 2.4 Cuadre de valor cursor vs SQL (descuadres debe ser 0) ===
WITH cal AS (
  SELECT DATE '2024-01-01' + LEVEL - 1 AS noche
    FROM dual
 CONNECT BY LEVEL <= DATE '2027-01-01' - DATE '2024-01-01'
), noches AS (
  SELECT h.id_alojamiento, rh.id_reserva, rh.id_habitacion, rh.valor_reserva,
         c.noche,
         tf.valor * (1 + te.porcentaje / 100) AS peso
    FROM reserva_habitacion rh
    JOIN reserva r     ON r.id_reserva    = rh.id_reserva
    JOIN habitacion h  ON h.id_habitacion = rh.id_habitacion
    JOIN tarifa tf     ON tf.id_tarifa    = h.id_tarifa
    JOIN cal c         ON c.noche >= rh.fecha_checkin
                      AND c.noche <  rh.fecha_checkout
    JOIN temporada te  ON c.noche BETWEEN te.fecha_inicio AND te.fecha_fin
   WHERE r.estado IN ('FINALIZADA', 'EN_CURSO')
), prorrateo AS (
  -- Lo cobrado de la estadia, repartido entre sus noches segun su peso
  SELECT id_alojamiento, noche,
         valor_reserva * peso
           / SUM(peso) OVER (PARTITION BY id_reserva, id_habitacion) AS devengado
    FROM noches
), esperado AS (
  SELECT id_alojamiento,
         EXTRACT(YEAR  FROM noche) AS anio,
         EXTRACT(MONTH FROM noche) AS mes,
         SUM(devengado) AS devengado
    FROM prorrateo
   GROUP BY id_alojamiento, EXTRACT(YEAR FROM noche), EXTRACT(MONTH FROM noche)
)
SELECT COUNT(*)                                      AS cortes_comparados,
       SUM(CASE WHEN ABS(l.ingreso_hospedaje - NVL(e.devengado, 0)) > 0.05
                THEN 1 ELSE 0 END)                   AS descuadres,
       ROUND(MAX(ABS(l.ingreso_hospedaje - NVL(e.devengado, 0))), 4) AS max_diferencia
  FROM liquidacion_mensual l
  LEFT JOIN esperado e
    ON e.id_alojamiento = l.id_alojamiento
   AND e.anio = l.anio
   AND e.mes  = l.mes;

-- ---------------------------------------------------------------------
-- 2.5 Reportes
-- ---------------------------------------------------------------------
PROMPT
PROMPT === 2.5 Liquidacion de 2026-06: los 10 alojamientos de mayor ingreso ===
SELECT mu.nombre AS municipio, a.nombre AS alojamiento,
       l.reservas, l.noches_vendidas,
       TO_CHAR(l.ingreso_hospedaje, '999G999G999') AS hospedaje,
       TO_CHAR(l.valor_comision,    '999G999G999') AS comision,
       TO_CHAR(l.neto_alojamiento,  '999G999G999') AS neto
  FROM liquidacion_mensual l
  JOIN alojamiento a ON a.id_alojamiento = l.id_alojamiento
  JOIN municipio mu  ON mu.id_municipio  = a.id_municipio
 WHERE l.anio = 2026 AND l.mes = 6
 ORDER BY l.ingreso_hospedaje DESC
 FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT === 2.6 Devengado vs. recaudado por periodo ===
SELECT anio, mes,
       TO_CHAR(SUM(ingreso_hospedaje), '9G999G999G999') AS devengado,
       TO_CHAR(SUM(ingreso_servicios), '9G999G999G999') AS servicios,
       TO_CHAR(SUM(recaudo_caja),      '9G999G999G999') AS recaudado,
       TO_CHAR(SUM(valor_comision),    '9G999G999G999') AS comision,
       TO_CHAR(SUM(neto_alojamiento),  '9G999G999G999') AS neto
  FROM liquidacion_mensual
 GROUP BY anio, mes
 ORDER BY anio, mes;

SET TIMING OFF
PROMPT
PROMPT === Script 07 finalizado ===
