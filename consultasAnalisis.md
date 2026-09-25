# Consultas Analíticas - Sistema de Turismo (TurismoUQ)

Este documento contiene la solución en SQL para los 8 requerimientos de análisis basados en el modelo entidad-relación del sistema de turismo.

---

## 1. Ocupación por Municipio y Mes (PIVOT)
Muestra la cantidad total de reservas de habitaciones distribuidas por municipio y rotadas horizontalmente por cada mes del año.

```sql
SELECT * FROM (
                  SELECT
                      m.nombre AS municipio,
                      EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
                      rh.id_habitacion
                  FROM MUNICIPIO m
                           JOIN ALOJAMIENTO a ON m.id_municipio = a.id_municipio
                           JOIN HABITACION h ON a.id_alojamiento = h.id_alojamiento
                           JOIN RESERVA_HABITACION rh ON h.id_habitacion = rh.id_habitacion
              )
                  PIVOT (
                         COUNT(id_habitacion)
    FOR mes IN (
        1 AS Ene, 2 AS Feb, 3 AS Mar, 4 AS Abr,
        5 AS May, 6 AS Jun, 7 AS Jul, 8 AS Ago,
        9 AS Sep, 10 AS Oct, 11 AS Nov, 12 AS Dic
    )
        )
ORDER BY municipio;
```

### Ejemplo de salida

| MUNICIPIO | ENE | FEB | MAR | ABR | MAY | JUN | JUL | AGO | SEP | OCT | NOV | DIC |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Armenia | 389 | 201 | 284 | 236 | 196 | 342 | 418 | 225 | 207 | 248 | 202 | 405 |
| Buenavista | 142 | 74 | 104 | 86 | 72 | 125 | 153 | 82 | 76 | 91 | 74 | 148 |
| Calarcá | 243 | 126 | 178 | 148 | 123 | 214 | 261 | 141 | 130 | 155 | 126 | 253 |
| Córdoba | 96 | 49 | 70 | 58 | 48 | 84 | 103 | 55 | 51 | 61 | 50 | 99 |
| Salento | 452 | 236 | 331 | 274 | 228 | 398 | 486 | 262 | 241 | 289 | 235 | 471 |

---

## 2. Ingresos por Municipio, Tipo de Alojamiento y Temporada (CUBE con GROUPING)
Calcula el total facturado combinando dimensiones de municipio, tipo de alojamiento y temporada. Aplica la función `GROUPING` para etiquetar claramente los subtotales y gran total.

```sql
SELECT
    CASE WHEN GROUPING(m.nombre) = 1 THEN 'TODOS LOS MUNICIPIOS' ELSE m.nombre END AS municipio,
    CASE WHEN GROUPING(ta.nombre) = 1 THEN 'TODOS LOS TIPOS' ELSE ta.nombre END AS tipo_alojamiento,
    CASE WHEN GROUPING(t.nombre) = 1 THEN 'TODAS LAS TEMPORADAS' ELSE t.nombre END AS temporada,
    SUM(rh.valor_reserva) AS ingreso_total
FROM MUNICIPIO m
         JOIN ALOJAMIENTO a ON m.id_municipio = a.id_municipio
         JOIN TIPO_ALOJAMIENTO ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
         JOIN HABITACION h ON a.id_alojamiento = h.id_alojamiento
         JOIN RESERVA_HABITACION rh ON h.id_habitacion = rh.id_habitacion
         JOIN TEMPORADA t ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin
GROUP BY CUBE(m.nombre, ta.nombre, t.nombre)
ORDER BY
    GROUPING(m.nombre),
    GROUPING(ta.nombre),
    GROUPING(t.nombre),
    municipio;
```

### Ejemplo de salida:
| MUNICIPIO | TIPO_ALOJAMIENTO | TEMPORADA | INGRESO_TOTAL |
|---|---|---|---|
| Armenia | Ecohotel | Semana Santa | 43120000 |
| Armenia | Ecohotel | Temporada baja | 142380000 |
| Armenia | Ecohotel | Vacaciones de enero | 64850000 |
| Armenia | Hotel | Semana Santa | 91460000 |
| Armenia | Hotel | Temporada baja | 298740000 |
| … | | | |
| Armenia | Hotel | TODAS LAS TEMPORADAS | 768230000 |
| Armenia | TODOS LOS TIPOS | TODAS LAS TEMPORADAS | 2087600000 |
| TODOS LOS MUNICIPIOS | Hotel | Semana Santa | 1142800000 |
| TODOS LOS MUNICIPIOS | TODOS LOS TIPOS | Temporada decembrina | 3684200000 |
| TODOS LOS MUNICIPIOS | TODOS LOS TIPOS | TODAS LAS TEMPORADAS | 23815400000 |

---

## 3. Top 3 Alojamientos de Mayor Ingreso por Municipio (RANK con PARTITION BY)
Clasifica los 3 mejores alojamientos de cada municipio mediante funciones analíticas de ventana basadas en sus recaudos acumulados.

```sql
WITH IngresosAlojamiento AS (
    SELECT
        m.nombre AS municipio,
        a.nombre AS alojamiento,
        SUM(rh.valor_reserva) AS total_ingresos,
        RANK() OVER (
            PARTITION BY m.id_municipio
            ORDER BY SUM(rh.valor_reserva) DESC
        ) AS ranking
    FROM MUNICIPIO m
             JOIN ALOJAMIENTO a ON m.id_municipio = a.id_municipio
             JOIN HABITACION h ON a.id_alojamiento = h.id_alojamiento
             JOIN RESERVA_HABITACION rh ON h.id_habitacion = rh.id_habitacion
    GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre
)
SELECT municipio, alojamiento, total_ingresos, ranking
FROM IngresosAlojamiento
WHERE ranking <= 3
ORDER BY municipio, ranking;
```

### Ejemplo de salida

| MUNICIPIO | ALOJAMIENTO | TOTAL_INGRESOS | RANKING |
|---|---|---|---|
| Armenia | Hotel El Cafetal | 331480000 | 1 |
| Armenia | Hotel La Palma de Cera | 304920000 | 2 |
| Armenia | Hotel Los Guaduales | 286350000 | 3 |
| Córdoba | Finca Monte Verde | 74610000 | 1 |
| Córdoba | Ecohotel La Aurora | 45230000 | 2 |
| Salento | Hostal Luna Llena | 258740000 | 1 |
| Salento | Glamping Cielo Abierto | 241160000 | 2 |
| Salento | Finca La Cumbre | 227890000 | 3 |

---

## 4. Variación de Ingresos Mes a Mes (LAG)
Compara los ingresos del mes actual contra el mes inmediatamente anterior utilizando la función analítica `LAG`, calculando tanto el cambio absoluto como la variación porcentual.

```sql
WITH IngresosMensuales AS (
    SELECT
        EXTRACT(YEAR FROM r.fecha_checkin) AS anio,
        EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
        SUM(r.valor_total) AS ingreso_mes
    FROM RESERVA r
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
FROM IngresosMensuales
ORDER BY anio, mes;
```
### Ejemplo de salida
| ANIO | MES | INGRESO_MES | INGRESO_MES_ANTERIOR | VARIACION_ABSOLUTA | PCT_VARIACION |
|---|---|---|---|---|---|
| 2024 | 1 | 731450000 | 0 | 731450000 | *(nulo)* |
| 2024 | 2 | 402180000 | 731450000 | -329270000 | -45.02 |
| 2024 | 3 | 528930000 | 402180000 | 126750000 | 31.52 |
| 2024 | 4 | 421600000 | 528930000 | -107330000 | -20.29 |
| 2024 | 5 | 389740000 | 421600000 | -31860000 | -7.56 |
| 2024 | 6 | 612380000 | 389740000 | 222640000 | 57.13 |
| 2024 | 7 | 795210000 | 612380000 | 182830000 | 29.85 |

---

## 5. Consulta Parametrizada por Rango de Fechas (Variables de Enlace)
Permite obtener el listado de reservas detalladas asociando parámetros dinámicos (`:fecha_inicio` y `:fecha_fin`) para optimizar el plan de ejecución y evitar la concatenación de variables.

```sql
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
FROM RESERVA r
         JOIN USUARIO_SISTEMA u ON r.id_usuario_sistema = u.id_usuario_sistema
         JOIN CLIENTE c ON r.id_cliente = c.id_cliente
         JOIN RESERVA_HABITACION rh ON r.id_reserva = rh.id_reserva
         JOIN HABITACION h ON rh.id_habitacion = h.id_habitacion
         JOIN ALOJAMIENTO a ON h.id_alojamiento = a.id_alojamiento
         JOIN MUNICIPIO m ON a.id_municipio = m.id_municipio
WHERE r.fecha_checkin >= TO_DATE(:fecha_inicio, 'YYYY-MM-DD')
  AND r.fecha_checkin <= TO_DATE(:fecha_fin,    'YYYY-MM-DD')
ORDER BY r.fecha_checkin ASC;
```
 ### Ejemplo salida 
| ID_RESERVA | USUARIO | CLIENTE | MUNICIPIO | ALOJAMIENTO | FECHA_CHECKIN | FECHA_CHECKOUT | VALOR_TOTAL | ESTADO |
|---|---|---|---|---|---|---|---|---|
| 14832 | cli0417 | Laura Castro Vargas | Salento | Hostal Luna Llena | 2025-06-15 | 2025-06-18 | 892400 | FINALIZADA |
| 14833 | recep03 | Diego Montoya Rojas | Filandia | Glamping El Encanto | 2025-06-15 | 2025-06-17 | 1204600 | FINALIZADA |
| 14840 | cli1882 | Camila Restrepo Henao | Armenia | Hotel El Cafetal | 2025-06-16 | 2025-06-20 | 2316800 | FINALIZADA |
| 14851 | recep11 | Juan Giraldo Ospina | Quimbaya | Finca Los Naranjos | 2025-06-16 | 2025-06-19 | 1478200 | FINALIZADA |
---

## 6. Vista Materializada de Ocupación Mensual y Justificación de Refresco
Crea una vista persistida en disco para agilizar reportes consolidados sobre volumen de reservas e ingresos.

```sql
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    m.id_municipio,
    m.nombre AS municipio,
    EXTRACT(YEAR FROM rh.fecha_checkin) AS anio,
    EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
    COUNT(rh.id_habitacion) AS total_reservas_habitacion,
    SUM(rh.valor_reserva) AS total_ingreso_habitaciones
FROM MUNICIPIO m
         JOIN ALOJAMIENTO a ON m.id_municipio = a.id_municipio
         JOIN HABITACION h ON a.id_alojamiento = h.id_alojamiento
         JOIN RESERVA_HABITACION rh ON h.id_habitacion = rh.id_habitacion
GROUP BY m.id_municipio, m.nombre, EXTRACT(YEAR FROM rh.fecha_checkin), EXTRACT(MONTH FROM rh.fecha_checkin);
```

### Justificación de la Política de Refresco (`ON DEMAND` / Proceso Nocturno)
* **Impacto en Rendimiento (OLTP vs OLAP):** Las consultas de ocupación mensual procesan volúmenes significativos de datos agregados. Realizar este cálculo en tiempo real sobre la base de datos operacional penalizaría las transacciones en vivo (como creación de reservas o registros de pago).
* **Frecuencia de Análisis Gerencial:** Los reportes de ocupación mensual y tendencias no requieren actualización al segundo; sirven para la toma de decisiones estratégicas.
* **Estrategia Implementada:** Se define la política `REFRESH COMPLETE ON DEMAND` programada a través de un orquestador (`DBMS_SCHEDULER`) durante horarios de baja carga transaccional (ej. 2:00 AM), garantizando alta disponibilidad del sistema primario.

### Ejemplo de salida

| ID_MUNICIPIO | MUNICIPIO | ANIO | MES | TOTAL_RESERVAS_HABITACION | TOTAL_INGRESO_HABITACIONES |
|---|---|---|---|---|---|
| 1 | Armenia | 2024 | 1 | 112 | 98420000 |
| 1 | Armenia | 2024 | 2 | 58 | 41360000 |
| 1 | Armenia | 2024 | 3 | 82 | 63180000 |
| 12 | Salento | 2024 | 1 | 131 | 118640000 |
| 12 | Salento | 2024 | 2 | 68 | 49820000 |
---

## 7. UNPIVOT
Transforma las columnas de estado financiero de la entidad `RESERVA` (`valor_total`, `valor_pagado`, `valor_pendiente`) en un formato vertical relacional por filas.

```sql
SELECT
    id_reserva,
    concepto_pago,
    monto
FROM (
         SELECT
             id_reserva,
             valor_total,
             valor_pagado,
             valor_pendiente
         FROM RESERVA
     )
         UNPIVOT (
                  monto FOR concepto_pago IN (
        valor_total AS 'TOTAL_CONTRATADO',
        valor_pagado AS 'TOTAL_PAGADO',
        valor_pendiente AS 'TOTAL_PENDIENTE'
    )
        );
```

### Ejemplo de salida 

| ID_RESERVA | CONCEPTO_PAGO | MONTO |
|---|---|---|
| 1 | TOTAL_CONTRATADO | 892400 |
| 1 | TOTAL_PAGADO | 892400 |
| 1 | TOTAL_PENDIENTE | 0 |
| 2 | TOTAL_CONTRATADO | 1204600 |
| 2 | TOTAL_PAGADO | 481840 |
| 2 | TOTAL_PENDIENTE | 722760 |
---

## 8. Consulta Libre - Pregunta de Negocio Propuesta

### Pregunta de Negocio:
*¿Cuál es el saldo pendiente (cartera por cobrar) por municipio y qué porcentaje representa frente al total contratado?*

```sql
WITH ReservaMunicipio AS (
    SELECT DISTINCT rh.id_reserva, a.id_municipio
    FROM RESERVA_HABITACION rh
             JOIN HABITACION h ON rh.id_habitacion = h.id_habitacion
             JOIN ALOJAMIENTO a ON h.id_alojamiento = a.id_alojamiento
)
SELECT
    m.nombre AS municipio,
    COUNT(r.id_reserva) AS cantidad_reservas,
    SUM(r.valor_total) AS total_facturado,
    SUM(r.valor_pagado) AS total_recaudado,
    SUM(r.valor_pendiente) AS cartera_pendiente,
    ROUND((SUM(r.valor_pendiente) / NULLIF(SUM(r.valor_total), 0)) * 100, 2) AS porcentaje_cartera
FROM ReservaMunicipio rm
         JOIN RESERVA r ON r.id_reserva = rm.id_reserva
         JOIN MUNICIPIO m ON m.id_municipio = rm.id_municipio
WHERE r.estado <> 'CANCELADA'
GROUP BY m.id_municipio, m.nombre
ORDER BY cartera_pendiente DESC;
```
### Ejemplo de salida
| MUNICIPIO | CANTIDAD_RESERVAS | TOTAL_FACTURADO | TOTAL_RECAUDADO | CARTERA_PENDIENTE | PORCENTAJE_CARTERA |
|---|---|---|---|---|---|
| Salento | 3712 | 3884500000 | 3688200000 | 196300000 | 5.05 |
| Armenia | 3240 | 3102800000 | 2955600000 | 147200000 | 4.74 |
| Montenegro | 2880 | 2744100000 | 2610900000 | 133200000 | 4.85 |
| Filandia | 2615 | 2588300000 | 2467400000 | 120900000 | 4.67 |
| Quimbaya | 2190 | 2013700000 | 1921500000 | 92200000 | 4.58 |
| La Tebaida | 1460 | 1284600000 | 1226300000 | 58300000 | 4.54 |