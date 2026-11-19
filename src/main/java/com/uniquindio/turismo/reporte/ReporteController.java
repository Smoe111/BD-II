package com.uniquindio.turismo.reporte;

import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.comun.ErrorNegocio;
import com.uniquindio.turismo.comun.Filas;
import com.uniquindio.turismo.comun.Plsql;

/**
 * Las 8 consultas de analisis de la Entrega 1 (sql/04_consultas.sql)
 * expuestas como reportes. Las columnas salen en camelCase.
 */
@RestController
@RequestMapping("/api/reportes")
public class ReporteController {

    private final JdbcClient jdbc;
    private final Plsql plsql;

    public ReporteController(JdbcClient jdbc, Plsql plsql) {
        this.jdbc = jdbc;
        this.plsql = plsql;
    }

    /** 1. Ocupacion por municipio y mes, en % (PIVOT). Filtro opcional por anio. */
    @GetMapping("/ocupacion")
    public List<Map<String, Object>> ocupacion(@RequestParam(required = false) Integer anio) {
        return Filas.json(jdbc.sql("""
                SELECT municipio,
                       NVL(ene,0) AS ene_pct, NVL(feb,0) AS feb_pct, NVL(mar,0) AS mar_pct,
                       NVL(abr,0) AS abr_pct, NVL(may,0) AS may_pct, NVL(jun,0) AS jun_pct,
                       NVL(jul,0) AS jul_pct, NVL(ago,0) AS ago_pct, NVL(sep,0) AS sep_pct,
                       NVL(oct,0) AS oct_pct, NVL(nov,0) AS nov_pct, NVL(dic,0) AS dic_pct
                  FROM (SELECT m.nombre AS municipio,
                               EXTRACT(MONTH FROM rh.fecha_checkin) AS mes,
                               ROUND(RATIO_TO_REPORT(COUNT(rh.id_habitacion))
                                     OVER (PARTITION BY m.nombre) * 100, 2) AS pct
                          FROM municipio m
                          JOIN alojamiento a         ON m.id_municipio = a.id_municipio
                          JOIN habitacion h          ON a.id_alojamiento = h.id_alojamiento
                          JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
                         WHERE :anio IS NULL OR EXTRACT(YEAR FROM rh.fecha_checkin) = :anio
                         GROUP BY m.nombre, EXTRACT(MONTH FROM rh.fecha_checkin))
                 PIVOT (SUM(pct) FOR mes IN (1 AS ene, 2 AS feb, 3 AS mar, 4 AS abr,
                                             5 AS may, 6 AS jun, 7 AS jul, 8 AS ago,
                                             9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic))
                 ORDER BY municipio
                """).param("anio", anio, Types.NUMERIC).query().listOfRows());
    }

    /**
     * 2. Ingresos por municipio, tipo de alojamiento y temporada (CUBE con
     * GROUPING). La temporada se resuelve igual que la vista V_RH_TEMPORADA
     * de 04_consultas.sql, aqui en linea para no depender de ese script.
     */
    @GetMapping("/ingresos")
    public List<Map<String, Object>> ingresos() {
        return Filas.json(jdbc.sql("""
                WITH vt AS (
                  SELECT id_habitacion, valor_reserva, temporada
                    FROM (SELECT rh.id_habitacion, rh.valor_reserva,
                                 CASE WHEN t.porcentaje <> 0 THEN t.nombre
                                      WHEN TO_CHAR(rh.fecha_checkin, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH')
                                           IN ('FRI', 'SAT') THEN 'FIN DE SEMANA'
                                      ELSE COALESCE(t.nombre, 'TEMPORADA ORDINARIA')
                                 END AS temporada,
                                 ROW_NUMBER() OVER (PARTITION BY rh.ROWID
                                                    ORDER BY (t.fecha_fin - t.fecha_inicio) ASC NULLS LAST) AS rn
                            FROM reserva_habitacion rh
                            LEFT JOIN temporada t
                                   ON rh.fecha_checkin BETWEEN t.fecha_inicio AND t.fecha_fin)
                   WHERE rn = 1)
                SELECT CASE WHEN GROUPING(m.nombre)    = 1 THEN 'TODOS LOS MUNICIPIOS' ELSE m.nombre    END AS municipio,
                       CASE WHEN GROUPING(ta.nombre)   = 1 THEN 'TODOS LOS TIPOS'      ELSE ta.nombre   END AS tipo_alojamiento,
                       CASE WHEN GROUPING(vt.temporada) = 1 THEN 'TODAS LAS TEMPORADAS' ELSE vt.temporada END AS temporada,
                       GROUPING_ID(m.nombre, ta.nombre, vt.temporada) AS nivel_subtotal,
                       SUM(vt.valor_reserva) AS ingreso_total
                  FROM municipio m
                  JOIN alojamiento a       ON m.id_municipio = a.id_municipio
                  JOIN tipo_alojamiento ta ON a.id_tipo_alojamiento = ta.id_tipo_alojamiento
                  JOIN habitacion h        ON a.id_alojamiento = h.id_alojamiento
                  JOIN vt                  ON h.id_habitacion = vt.id_habitacion
                 GROUP BY CUBE(m.nombre, ta.nombre, vt.temporada)
                 ORDER BY GROUPING(m.nombre), GROUPING(ta.nombre), GROUPING(vt.temporada),
                          municipio, tipo_alojamiento, temporada
                """).query().listOfRows());
    }

    /** 3. Los N alojamientos de mayor ingreso de cada municipio (RANK con PARTITION BY). */
    @GetMapping("/top-alojamientos")
    public List<Map<String, Object>> topAlojamientos(@RequestParam(defaultValue = "3") int top) {
        return Filas.json(jdbc.sql("""
                WITH ingresos_alojamiento AS (
                  SELECT m.nombre AS municipio, a.nombre AS alojamiento,
                         SUM(rh.valor_reserva) AS total_ingresos,
                         RANK() OVER (PARTITION BY m.id_municipio
                                      ORDER BY SUM(rh.valor_reserva) DESC) AS ranking,
                         SUM(SUM(rh.valor_reserva)) OVER (PARTITION BY m.id_municipio) AS total_municipio
                    FROM municipio m
                    JOIN alojamiento a         ON m.id_municipio = a.id_municipio
                    JOIN habitacion h          ON a.id_alojamiento = h.id_alojamiento
                    JOIN reserva_habitacion rh ON h.id_habitacion = rh.id_habitacion
                   GROUP BY m.id_municipio, m.nombre, a.id_alojamiento, a.nombre)
                SELECT municipio, alojamiento, total_ingresos, ranking,
                       ROUND(total_ingresos / NULLIF(total_municipio, 0) * 100, 2) AS pct_ingreso_municipio
                  FROM ingresos_alojamiento
                 WHERE ranking <= :top
                 ORDER BY municipio, ranking
                """).param("top", Math.max(1, top)).query().listOfRows());
    }

    /** 4. Variacion de ingresos mes contra mes (LAG). */
    @GetMapping("/variacion-mensual")
    public List<Map<String, Object>> variacionMensual() {
        return Filas.json(jdbc.sql("""
                WITH ingresos_mensuales AS (
                  SELECT EXTRACT(YEAR FROM r.fecha_checkin)  AS anio,
                         EXTRACT(MONTH FROM r.fecha_checkin) AS mes,
                         SUM(r.valor_total) AS ingreso_mes
                    FROM reserva r
                   GROUP BY EXTRACT(YEAR FROM r.fecha_checkin), EXTRACT(MONTH FROM r.fecha_checkin))
                SELECT anio, mes, ingreso_mes,
                       LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes) AS ingreso_mes_anterior,
                       ingreso_mes - LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes) AS variacion_absoluta,
                       ROUND((ingreso_mes - LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes))
                             / NULLIF(LAG(ingreso_mes, 1, 0) OVER (ORDER BY anio, mes), 0) * 100, 2)
                         AS pct_variacion
                  FROM ingresos_mensuales
                 ORDER BY anio, mes
                """).query().listOfRows());
    }

    /**
     * 5. Reservas por rango de fechas. En la API las fechas viajan SIEMPRE
     * como variables de enlace (:desde, :hasta): una sola sentencia
     * analizada para cualquier rango y sin riesgo de inyeccion SQL.
     */
    @GetMapping("/reservas")
    public List<Map<String, Object>> reservasPorRango(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate desde,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate hasta) {
        if (hasta.isBefore(desde)) {
            throw ErrorNegocio.solicitudInvalida("'hasta' no puede ser anterior a 'desde'");
        }
        return Filas.json(jdbc.sql("""
                SELECT DISTINCT r.id_reserva, u.usuario,
                       c.nombres || ' ' || c.apellidos AS cliente,
                       m.nombre AS municipio, a.nombre AS alojamiento,
                       r.fecha_checkin, r.fecha_checkout,
                       CASE WHEN r.estado = 'CANCELADA' THEN 0 ELSE r.valor_total END AS valor_total,
                       r.estado
                  FROM reserva r
                  JOIN usuario_sistema u     ON r.id_usuario_sistema = u.id_usuario_sistema
                  JOIN cliente c             ON r.id_cliente = c.id_cliente
                  JOIN reserva_habitacion rh ON r.id_reserva = rh.id_reserva
                  JOIN habitacion h          ON rh.id_habitacion = h.id_habitacion
                  JOIN alojamiento a         ON h.id_alojamiento = a.id_alojamiento
                  JOIN municipio m           ON a.id_municipio = m.id_municipio
                 WHERE r.fecha_checkin >= :desde AND r.fecha_checkin <= :hasta
                 ORDER BY r.fecha_checkin, r.id_reserva
                """).param("desde", desde).param("hasta", hasta).query().listOfRows());
    }

    /** 6. Vista materializada de ocupacion mensual (la crea 04_consultas.sql). */
    @GetMapping("/ocupacion-mensual")
    public List<Map<String, Object>> ocupacionMensual(@RequestParam(required = false) Integer anio,
                                                      @RequestParam(required = false) Long municipio) {
        return Filas.json(jdbc.sql("""
                SELECT * FROM mv_ocupacion_mensual
                 WHERE (:anio IS NULL OR anio = :anio)
                   AND (:mun  IS NULL OR id_municipio = :mun)
                 ORDER BY municipio, anio, mes
                """).param("anio", anio, Types.NUMERIC).param("mun", municipio, Types.NUMERIC)
                .query().listOfRows());
    }

    /** Refresco completo bajo demanda: la politica justificada en la Entrega 1. */
    @PostMapping("/ocupacion-mensual/refresco")
    public Map<String, Object> refrescar() {
        long inicio = System.currentTimeMillis();
        plsql.ejecutar(con -> {
            try (CallableStatement cs = con.prepareCall(
                    "BEGIN DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C'); END;")) {
                cs.execute();
                return null;
            }
        });
        return Map.of("vista", "MV_OCUPACION_MENSUAL", "metodo", "COMPLETE",
                      "milisegundos", System.currentTimeMillis() - inicio);
    }

    /** 7. UNPIVOT del estado financiero: una fila por concepto (total, pagado, pendiente). */
    @GetMapping("/estado-financiero")
    public List<Map<String, Object>> estadoFinanciero(@RequestParam(required = false) Long reserva,
                                                      @RequestParam(required = false) Long cliente,
                                                      @RequestParam(defaultValue = "100") int limite) {
        return Filas.json(jdbc.sql("""
                SELECT id_reserva, concepto_pago, monto
                  FROM (SELECT id_reserva, valor_total, valor_pagado, valor_pendiente
                          FROM reserva
                         WHERE (:res IS NULL OR id_reserva = :res)
                           AND (:cli IS NULL OR id_cliente = :cli))
                UNPIVOT (monto FOR concepto_pago IN (valor_total     AS 'TOTAL_CONTRATADO',
                                                     valor_pagado    AS 'TOTAL_PAGADO',
                                                     valor_pendiente AS 'TOTAL_PENDIENTE'))
                 ORDER BY id_reserva, concepto_pago
                 FETCH FIRST :filas ROWS ONLY
                """).param("res", reserva, Types.NUMERIC).param("cli", cliente, Types.NUMERIC)
                .param("filas", 3 * Math.max(1, Math.min(limite, 1000)))
                .query().listOfRows());
    }

    /** 8. Consulta libre: cartera pendiente por municipio. */
    @GetMapping("/cartera")
    public List<Map<String, Object>> cartera() {
        return Filas.json(jdbc.sql("""
                WITH reserva_municipio AS (
                  SELECT DISTINCT rh.id_reserva, a.id_municipio
                    FROM reserva_habitacion rh
                    JOIN habitacion h  ON rh.id_habitacion = h.id_habitacion
                    JOIN alojamiento a ON h.id_alojamiento = a.id_alojamiento)
                SELECT m.nombre AS municipio,
                       COUNT(r.id_reserva)    AS cantidad_reservas,
                       SUM(r.valor_total)     AS total_facturado,
                       SUM(r.valor_pagado)    AS total_recaudado,
                       SUM(r.valor_pendiente) AS cartera_pendiente,
                       ROUND(SUM(r.valor_pendiente) / NULLIF(SUM(r.valor_total), 0) * 100, 2)
                         AS porcentaje_cartera
                  FROM reserva_municipio rm
                  JOIN reserva r   ON r.id_reserva = rm.id_reserva
                  JOIN municipio m ON m.id_municipio = rm.id_municipio
                 WHERE r.estado <> 'CANCELADA'
                 GROUP BY m.id_municipio, m.nombre
                 ORDER BY cartera_pendiente DESC
                """).query().listOfRows());
    }
}
