package com.uniquindio.turismo.liquidacion;

import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.comun.Plsql;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/**
 * Liquidacion mensual por alojamiento (Entrega 2): proceso masivo con
 * cursor explicito con parametros, pkg_turismo.sp_liquidar_mes.
 */
@RestController
@RequestMapping("/api/liquidaciones")
public class LiquidacionController {

    public record Solicitud(@NotNull @Min(2020) @Max(2100) Integer anio,
                            @NotNull @Min(1) @Max(12) Integer mes,
                            Long idAlojamiento) {
    }

    public record Liquidacion(Long idLiquidacion, Long idAlojamiento, String alojamiento, Integer anio,
                              Integer mes, Integer reservas, Integer nochesVendidas,
                              BigDecimal ingresoHospedaje, BigDecimal ingresoServicios,
                              BigDecimal recaudoCaja, BigDecimal pctComision, BigDecimal valorComision,
                              BigDecimal netoAlojamiento, LocalDateTime fechaProceso) {
    }

    public record Resultado(List<String> salida, List<Liquidacion> liquidaciones) {
    }

    private final Plsql plsql;
    private final JdbcClient jdbc;

    public LiquidacionController(Plsql plsql, JdbcClient jdbc) {
        this.plsql = plsql;
        this.jdbc = jdbc;
    }

    /** Ejecuta (o repite: es idempotente) la liquidacion de un mes cerrado. */
    @PostMapping
    public Resultado liquidar(@Valid @RequestBody Solicitud s) {
        var llamada = plsql.ejecutar(con -> {
            try (CallableStatement cs = con.prepareCall("BEGIN pkg_turismo.sp_liquidar_mes(?, ?, ?); END;")) {
                cs.setInt(1, s.anio());
                cs.setInt(2, s.mes());
                if (s.idAlojamiento() == null) {
                    cs.setNull(3, Types.NUMERIC);
                } else {
                    cs.setLong(3, s.idAlojamiento());
                }
                cs.execute();
                return null;
            }
        });
        return new Resultado(llamada.salida(), consultar(s.anio(), s.mes(), s.idAlojamiento()));
    }

    @GetMapping
    public List<Liquidacion> consultar(@RequestParam Integer anio, @RequestParam Integer mes,
                                       @RequestParam(required = false) Long alojamiento) {
        return jdbc.sql("""
                SELECT l.id_liquidacion, l.id_alojamiento, a.nombre AS alojamiento, l.anio, l.mes,
                       l.reservas, l.noches_vendidas, l.ingreso_hospedaje, l.ingreso_servicios,
                       l.recaudo_caja, l.pct_comision, l.valor_comision, l.neto_alojamiento,
                       l.fecha_proceso
                  FROM liquidacion_mensual l
                  JOIN alojamiento a ON a.id_alojamiento = l.id_alojamiento
                 WHERE l.anio = :anio AND l.mes = :mes
                   AND (:aloj IS NULL OR l.id_alojamiento = :aloj)
                 ORDER BY l.ingreso_hospedaje DESC
                """)
                .param("anio", anio).param("mes", mes)
                .param("aloj", alojamiento, Types.NUMERIC)
                .query(Liquidacion.class).list();
    }
}
