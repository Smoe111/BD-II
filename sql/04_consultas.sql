-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 1
-- Script 04 · Consultas analiticas (8 requerimientos)
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq, despues de 01/02/03.
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @04_consultas.sql
--
-- Cada consulta esta numerada y separada por un bloque "-- ====".
-- Se puede correr:
--   a) el archivo completo de una sola vez (@04_consultas.sql), o
--   b) una consulta a la vez: abrir el archivo en SQL Developer / DBeaver
--      / la extension de SQL de tu editor, seleccionar el bloque de la
--      consulta que quieras (desde su comentario "-- N." hasta el ";"
--      final) y ejecutar solo esa seleccion.
--
-- La consulta 5 usa variables de enlace (VARIABLE + EXEC), una sintaxis
-- de SQL*Plus. Si la corres en una herramienta grafica (SQL Developer,
-- DBeaver) usa el dialogo de "bind variables" que te pida al ejecutar,
-- o reemplaza :fecha_inicio/:fecha_fin por fechas literales.
-- =====================================================================

SET PAGESIZE 100
SET LINESIZE 200

-- =====================================================================
-- 1. Ocupacion por municipio y mes (PIVOT)
-- ---------------------------------------------------------------------
-- Cantidad de habitaciones reservadas por municipio, con los 12 meses
-- del anio como columnas.
-- =====================================================================
PROMPT
PROMPT === 1. Ocupacion por municipio y mes (PIVOT) ===
SELECT * FROM (
    SELECT
        m.nombre AS municipio,
        EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
        rh.id_habitacion
    FROM municipio m
    JOIN alojamiento a       ON m.id_municipio = a.id_municipio
    JOIN habitacion h        ON a.id_alojamiento = h.id_alojamiento
    JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
)
PIVOT (
    COUNT(id_habitacion)
    FOR mes IN (
        1 AS ene, 2 AS feb, 3 AS mar, 4 AS abr,
        5 AS may, 6 AS jun, 7 AS jul, 8 AS ago,
        9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic
    )
)
ORDER BY municipio;

-- =====================================================================
-- 2. Ingresos por municipio, tipo de alojamiento y temporada (CUBE)
-- ---------------------------------------------------------------------
-- Total facturado por habitaciones, con subtotales por cada combinacion
-- de dimensiones y el gran total, usando GROUPING para etiquetarlos.
-- =====================================================================
PROMPT
PROMPT === 2. Ingresos por municipio, tipo de alojamiento y temporada (CUBE) ===
SELECT
    CASE WHEN GROUPING(m.nombre)  = 1 THEN 'TODOS LOS MUNICIPIOS'  ELSE m.nombre  END AS municipio,
    CASE WHEN GROUPING(ta.nombre) = 1 THEN 'TODOS LOS TIPOS'       ELSE ta.nombre END AS tipo_alojamiento,
    CASE WHEN GROUPING(t.nombre)  = 1 THEN 'TODAS LAS TEMPORADAS'  ELSE t.nombre  END AS temporada,
    SUM(rh.valor_reserva) AS ingreso_total
FROM municipio m
JOIN alojamiento a         ON m.id_municipio = a.id_municipio
JOIN tipo_alojamiento ta   ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
JOIN habitacion h          ON a.id_alojamiento = h.id_alojamiento
JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
JOIN temporada t           ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
GROUP BY CUBE(m.nombre, ta.nombre, t.nombre)
ORDER BY
    GROUPING(m.nombre),
    GROUPING(ta.nombre),
    GROUPING(t.nombre),
    municipio;

-- =====================================================================
-- 3. Top 3 alojamientos de mayor ingreso por municipio (RANK)
-- =====================================================================
PROMPT
PROMPT === 3. Top 3 alojamientos de mayor ingreso por municipio (RANK) ===
WITH ingresos_alojamiento AS (
    SELECT
        m.nombre AS municipio,
        a.nombre AS alojamiento,
        SUM(rh.valor_reserva) AS total_ingresos,
        RANK() OVER (
            PARTITION BY m.id_municipio
            ORDER BY SUM(rh.valor_reserva) DESC
        ) AS ranking
    FROM municipio m
    JOIN alojamiento a         ON m.id_municipio = a.id_municipio
    JOIN habitacion h          ON a.id_alojamiento = h.id_alojamiento
    JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
    GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
)
SELECT municipio, alojamiento, total_ingresos, ranking
FROM ingresos_alojamiento
WHERE ranking <= 3
ORDER BY municipio, ranking;

-- =====================================================================
-- 4. Variacion de ingresos mes a mes (LAG)
-- =====================================================================
PROMPT
PROMPT === 4. Variacion de ingresos mes a mes (LAG) ===
WITH ingresos_mensuales AS (
    SELECT
        EXTRACT(YEAR FROM r.fecha_checkin)  AS anio,
        EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
        SUM(r.valor_total) AS ingreso_mes
    FROM reserva r
    GROUP BY EXTRACT(YEAR FROM r.fecha_checkin), EXTRACT(MONTH FROM r.fecha_checkin)
)
SELECT
    anio,
    mes,
    ingreso_mes,
    LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes) AS ingreso_mes_anterior,
    (ingreso_mes - LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes)) AS variacion_absoluta,
    ROUND(
        ((ingreso_mes - LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes)) /
         NULLIF(LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes), 0)) * 100, 2
    ) AS pct_variacion
FROM ingresos_mensuales
ORDER BY anio, mes;

-- =====================================================================
-- 5. Reservas por rango de fechas (variables de enlace)
-- ---------------------------------------------------------------------
-- Sintaxis de SQL*Plus. Cambia las dos fechas de abajo por el rango que
-- quieras consultar antes de ejecutar el bloque.
-- =====================================================================
PROMPT
PROMPT === 5. Reservas por rango de fechas (bind variables) ===
VARIABLE fecha_inicio VARCHAR2(10)
VARIABLE fecha_fin    VARCHAR2(10)

EXEC :fecha_inicio := '2025-06-15';
EXEC :fecha_fin    := '2025-07-31';

SELECT DISTINCT
    r.id_reserva,
    u.usuario,
    c.nombres || ' ' || c.apellidos AS cliente,
    m.nombre AS municipio,
    a.nombre AS alojamiento,
    r.fecha_checkin,
    r.fecha_checkout,
    r.valor_total,
    r.estado
FROM reserva r
JOIN usuario_sistema u     ON r.id_usuario_sistema = u.id_usuario_sistema
JOIN cliente c              ON r.id_cliente = c.id_cliente
JOIN reserva_habitacion rh ON r.id_reserva = rh.id_reserva
JOIN habitacion h           ON rh.id_habitacion = h.id_habitacion
JOIN alojamiento a          ON h.id_alojamiento = a.id_alojamiento
JOIN municipio m            ON a.id_municipio = m.id_municipio
WHERE r.fecha_checkin >= TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
  AND r.fecha_checkin <= TO_DATE(:fecha_fin,    'YYYY-MM-DD')
ORDER BY r.fecha_checkin ASC;

-- =====================================================================
-- 6. Vista materializada de ocupacion mensual
-- ---------------------------------------------------------------------
-- Politica de refresco: COMPLETE ON DEMAND. Se refresca con
--   EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
-- en un job nocturno (DBMS_SCHEDULER), no en cada transaccion, porque:
--   * Impacto OLTP vs OLAP: agregar sobre toda la tabla RESERVA_HABITACION
--     en cada consulta gerencial competiria por recursos con las
--     transacciones en vivo (crear reservas, registrar pagos).
--   * Frecuencia de uso: los reportes de ocupacion mensual son para
--     decisiones estrategicas, no necesitan el dato al segundo.
--   * Se programa en horario de baja carga (ej. 2:00 AM).
-- =====================================================================
PROMPT
PROMPT === 6. Creando vista materializada mv_ocupacion_mensual ===
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    m.id_municipio,
    m.nombre AS municipio,
    EXTRACT(YEAR FROM rh.fecha_checkin)  AS anio,
    EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
    COUNT(rh.id_habitacion)   AS total_reservas_habitacion,
    SUM(rh.valor_reserva)     AS total_ingreso_habitaciones
FROM municipio m
JOIN alojamiento a         ON m.id_municipio = a.id_municipio
JOIN habitacion h          ON a.id_alojamiento = h.id_alojamiento
JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
GROUP BY m.id_municipio, m.nombre,
         EXTRACT(YEAR FROM rh.fecha_checkin), EXTRACT(MONTH FROM rh.fecha_checkin);

PROMPT === Consultando mv_ocupacion_mensual ===
SELECT * FROM mv_ocupacion_mensual ORDER BY municipio, anio, mes;

-- =====================================================================
-- 7. UNPIVOT del estado financiero de la reserva
-- =====================================================================
PROMPT
PROMPT === 7. UNPIVOT del estado financiero de la reserva ===
SELECT
    id_reserva,
    concepto_pago,
    monto
FROM (
    SELECT id_reserva, valor_total, valor_pagado, valor_pendiente
    FROM reserva
)
UNPIVOT (
    monto FOR concepto_pago IN (
        valor_total     AS 'TOTAL_CONTRATADO',
        valor_pagado    AS 'TOTAL_PAGADO',
        valor_pendiente AS 'TOTAL_PENDIENTE'
    )
)
ORDER BY id_reserva, concepto_pago;

-- =====================================================================
-- 8. Consulta libre: cartera pendiente por municipio
-- ---------------------------------------------------------------------
-- Pregunta de negocio: cuanto saldo pendiente (cartera por cobrar) tiene
-- cada municipio y que porcentaje representa sobre lo contratado.
-- =====================================================================
PROMPT
PROMPT === 8. Cartera pendiente por municipio ===
WITH reserva_municipio AS (
    SELECT DISTINCT rh.id_reserva, a.id_municipio
    FROM reserva_habitacion rh
    JOIN habitacion h  ON rh.id_habitacion = h.id_habitacion
    JOIN alojamiento a ON h.id_alojamiento = a.id_alojamiento
)
SELECT
    m.nombre AS municipio,
    COUNT(r.id_reserva)    AS cantidad_reservas,
    SUM(r.valor_total)     AS total_facturado,
    SUM(r.valor_pagado)    AS total_recaudado,
    SUM(r.valor_pendiente) AS cartera_pendiente,
    ROUND((SUM(r.valor_pendiente) / NULLIF(SUM(r.valor_total), 0)) * 100, 2) AS porcentaje_cartera
FROM reserva_municipio rm
JOIN reserva r   ON r.id_reserva = rm.id_reserva
JOIN municipio m ON m.id_municipio = rm.id_municipio
WHERE r.estado <> 'CANCELADA'
GROUP BY m.id_municipio, m.nombre
ORDER BY cartera_pendiente DESC;

PROMPT
PROMPT === Script 04 finalizado ===
