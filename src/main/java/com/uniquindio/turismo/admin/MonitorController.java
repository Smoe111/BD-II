package com.uniquindio.turismo.admin;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.comun.Filas;

/** Monitoreo (Entrega 3): bloqueos entre sesiones y bitacora de transacciones. */
@RestController
@RequestMapping("/api/admin")
public class MonitorController {

    public record LogTransaccion(Long idLog, LocalDateTime fecha, String usuarioBd, Long idCliente,
                                 String habitaciones, Long idReserva, Long idPago, String resultado,
                                 String paso, Integer codigoError, String mensaje) {
    }

    private final JdbcClient jdbc;

    public MonitorController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** Sesiones de turismouq y quien bloquea a quien (vista V_MONITOR_BLOQUEOS). */
    @GetMapping("/bloqueos")
    public List<Map<String, Object>> bloqueos() {
        return Filas.json(jdbc.sql("""
                SELECT sid, serial#  AS serial, status, sesion, bloqueada_por, evento,
                       seg_esperando, tabla_esperada, sql_id
                  FROM v_monitor_bloqueos
                 WHERE sid <> SYS_CONTEXT('USERENV', 'SID')
                 ORDER BY bloqueada_por NULLS FIRST, sid
                """).query().listOfRows());
    }

    /** Reservas (con y sin pago) y abonos, incluidos los intentos que hicieron ROLLBACK. */
    @GetMapping("/log-transacciones")
    public List<LogTransaccion> logTransacciones(@RequestParam(defaultValue = "50") int limite) {
        return jdbc.sql("""
                SELECT id_log, CAST(fecha AS TIMESTAMP) AS fecha, usuario_bd, id_cliente, habitaciones,
                       id_reserva, id_pago, resultado, paso, codigo_error, mensaje
                  FROM log_transaccion
                 ORDER BY id_log DESC
                 FETCH FIRST :limite ROWS ONLY
                """).param("limite", Math.max(1, Math.min(limite, 500)))
                .query(LogTransaccion.class).list();
    }
}
