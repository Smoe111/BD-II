package com.uniquindio.turismo.cliente;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.comun.ErrorNegocio;

/** Busqueda de clientes y su historial (lo que usa recepcion). */
@RestController
@RequestMapping("/api/clientes")
public class ClienteController {

    public record Cliente(Long idCliente, String tipoDocumento, String numeroDocumento, String nombres,
                          String apellidos, String telefono, String correoElectronico,
                          LocalDate fechaNacimiento, LocalDate fechaRegistro, Long idUsuarioSistema) {
    }

    public record ReservaResumen(Long idReserva, String alojamiento, String municipio, LocalDate fechaCheckin,
                                 LocalDate fechaCheckout, String estado, Integer numHuespedes,
                                 BigDecimal valorTotal, BigDecimal valorPagado, BigDecimal valorPendiente) {
    }

    private static final String SELECT_CLIENTE = """
            SELECT c.id_cliente, td.nombre AS tipo_documento, c.numero_documento, c.nombres,
                   c.apellidos, c.telefono, c.correo_electronico, c.fecha_nacimiento,
                   c.fecha_registro, u.id_usuario_sistema
              FROM cliente c
              JOIN tipo_documento td    ON td.id_tipo_documento = c.id_tipo_documento
              LEFT JOIN usuario_sistema u ON u.id_cliente = c.id_cliente
            """;

    private final JdbcClient jdbc;

    public ClienteController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** GET /api/clientes?apellido=gar  o  ?documento=1094... (maximo 50) */
    @GetMapping
    public List<Cliente> buscar(@RequestParam(required = false) String apellido,
                                @RequestParam(required = false) String documento) {
        if ((apellido == null || apellido.isBlank()) && (documento == null || documento.isBlank())) {
            throw ErrorNegocio.solicitudInvalida("Indique 'apellido' o 'documento' para buscar");
        }
        return jdbc.sql(SELECT_CLIENTE + """
                 WHERE (:ape IS NULL OR UPPER(c.apellidos) LIKE UPPER(:ape) || '%')
                   AND (:doc IS NULL OR c.numero_documento = :doc)
                 ORDER BY c.apellidos, c.nombres
                 FETCH FIRST 50 ROWS ONLY
                """)
                .param("ape", vacioANulo(apellido), java.sql.Types.VARCHAR)
                .param("doc", vacioANulo(documento), java.sql.Types.VARCHAR)
                .query(Cliente.class).list();
    }

    @GetMapping("/{id}")
    public Cliente cliente(@PathVariable long id) {
        return jdbc.sql(SELECT_CLIENTE + " WHERE c.id_cliente = :id")
                .param("id", id).query(Cliente.class).optional()
                .orElseThrow(() -> ErrorNegocio.noEncontrado("El cliente " + id + " no existe"));
    }

    @GetMapping("/{id}/reservas")
    public List<ReservaResumen> reservas(@PathVariable long id) {
        cliente(id);
        return jdbc.sql("""
                SELECT r.id_reserva,
                       (SELECT MIN(a.nombre) FROM reserva_habitacion rh
                          JOIN habitacion h  ON h.id_habitacion = rh.id_habitacion
                          JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
                         WHERE rh.id_reserva = r.id_reserva) AS alojamiento,
                       (SELECT MIN(m.nombre) FROM reserva_habitacion rh
                          JOIN habitacion h  ON h.id_habitacion = rh.id_habitacion
                          JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
                          JOIN municipio m   ON m.id_municipio = a.id_municipio
                         WHERE rh.id_reserva = r.id_reserva) AS municipio,
                       r.fecha_checkin, r.fecha_checkout, r.estado, r.num_huespedes,
                       r.valor_total, r.valor_pagado, r.valor_pendiente
                  FROM reserva r
                 WHERE r.id_cliente = :id
                 ORDER BY r.fecha_checkin DESC
                """).param("id", id).query(ReservaResumen.class).list();
    }

    private static String vacioANulo(String s) {
        return s == null || s.isBlank() ? null : s.strip();
    }
}
