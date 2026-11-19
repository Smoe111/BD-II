package com.uniquindio.turismo.operacion;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.comun.Filas;

/**
 * Consultas del dia a dia que la Entrega 3 acelero con indices
 * (sql/17_indices.sql). El texto del WHERE es el mismo que se midio para
 * que el optimizador pueda usar el indice:
 *   llegadas         -> ix_reserva_estado_checkin (estado, fecha_checkin)
 *   cierre de caja   -> ix_pago_dia (TRUNC(fecha_pago))      basado en funcion
 *   agenda servicios -> ix_rs_fecha_servicio (fecha_servicio, id_servicio, cantidad)
 * Sin el script 17 funcionan igual, solo que con TABLE ACCESS FULL.
 */
@RestController
@RequestMapping("/api/operacion")
public class OperacionController {

    private final JdbcClient jdbc;

    public OperacionController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Llegadas del dia (recepcion): reservas CONFIRMADAS con check-in en la fecha. */
    @GetMapping("/llegadas")
    public List<Map<String, Object>> llegadas(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate fecha) {
        return Filas.json(jdbc.sql("""
                SELECT r.id_reserva, r.num_huespedes, r.fecha_checkout,
                       c.nombres, c.apellidos, c.telefono, r.valor_pendiente
                  FROM reserva r
                  JOIN cliente c ON c.id_cliente = r.id_cliente
                 WHERE r.estado = 'CONFIRMADA'
                   AND r.fecha_checkin = :fecha
                 ORDER BY c.apellidos, c.nombres
                """).param("fecha", fecha).query().listOfRows());
    }

    /** Cierre de caja del dia: pagos aprobados por metodo de pago. */
    @GetMapping("/cierre-caja")
    public List<Map<String, Object>> cierreCaja(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate fecha) {
        return Filas.json(jdbc.sql("""
                SELECT metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total
                  FROM pago
                 WHERE TRUNC(fecha_pago) = :fecha
                   AND estado = 'APROBADO'
                 GROUP BY metodo_pago
                 ORDER BY metodo_pago
                """).param("fecha", fecha).query().listOfRows());
    }

    /** Agenda de servicios complementarios del dia: cupos a programar por servicio. */
    @GetMapping("/agenda-servicios")
    public List<Map<String, Object>> agendaServicios(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate fecha) {
        return Filas.json(jdbc.sql("""
                SELECT s.nombre AS servicio, SUM(rs.cantidad) AS cupos, COUNT(*) AS reservas
                  FROM reserva_servicio rs
                  JOIN servicio s ON s.id_servicio = rs.id_servicio
                 WHERE rs.fecha_servicio = :fecha
                 GROUP BY s.nombre
                 ORDER BY cupos DESC
                """).param("fecha", fecha).query().listOfRows());
    }
}
