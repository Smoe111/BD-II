package com.uniquindio.turismo.reserva;

import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;

import com.uniquindio.turismo.comun.ErrorNegocio;
import com.uniquindio.turismo.comun.Fechas;
import com.uniquindio.turismo.comun.Plsql;
import com.uniquindio.turismo.reserva.Dto.Abono;
import com.uniquindio.turismo.reserva.Dto.Cabecera;
import com.uniquindio.turismo.reserva.Dto.CrearReserva;
import com.uniquindio.turismo.reserva.Dto.HabitacionReservada;
import com.uniquindio.turismo.reserva.Dto.Pago;
import com.uniquindio.turismo.reserva.Dto.ReservaDetalle;
import com.uniquindio.turismo.reserva.Dto.ReservarYPagar;
import com.uniquindio.turismo.reserva.Dto.ResultadoAbono;
import com.uniquindio.turismo.reserva.Dto.ResultadoReservaPago;
import com.uniquindio.turismo.reserva.Dto.ServicioReservado;

/**
 * Las reglas de la reserva viven en la base de datos (Entregas 2 y 3):
 * validaciones, disponibilidad con SELECT ... FOR UPDATE, calculo noche
 * por noche, trigger de solape y la transaccion reserva + pago con
 * SAVEPOINT. Este servicio solo prepara los parametros, llama los
 * procedimientos y devuelve el resultado.
 */
@Service
public class ReservaServicio {

    private final Plsql plsql;
    private final JdbcClient jdbc;

    public ReservaServicio(Plsql plsql, JdbcClient jdbc) {
        this.plsql = plsql;
        this.jdbc = jdbc;
    }

    /** pkg_transacciones.sp_reservar_sin_pago: sp_crear_reserva + COMMIT + bitacora (SIN_PAGO). */
    public ReservaDetalle crear(CrearReserva r) {
        Fechas.validarRango(r.checkin(), r.checkout(), "checkin", "checkout");
        Long id = plsql.ejecutar(con -> {
            try (CallableStatement cs = con.prepareCall(
                    "BEGIN pkg_transacciones.sp_reservar_sin_pago(?, ?, ?, ?, ?, ?, ?); END;")) {
                cs.setLong(1, r.idCliente());
                cs.setLong(2, r.idUsuarioSistema());
                cs.setObject(3, r.checkin());
                cs.setObject(4, r.checkout());
                cs.setInt(5, r.numHuespedes());
                cs.setString(6, lista(r.habitaciones()));
                cs.registerOutParameter(7, Types.NUMERIC);
                cs.execute();
                return cs.getLong(7);
            }
        }).resultado();
        return detalle(id);
    }

    /**
     * pkg_transacciones.sp_reservar_y_pagar: reserva, servicios y pago en
     * una sola transaccion. Si falla un servicio responde 201 con resultado
     * ROLLBACK_PARCIAL; si falla el pago o la reserva, el procedimiento
     * deshace todo y el error llega con los pasos en "salida".
     */
    public ResultadoReservaPago reservarYPagar(ReservarYPagar r) {
        Fechas.validarRango(r.checkin(), r.checkout(), "checkin", "checkout");
        String servicios = r.servicios() == null || r.servicios().isEmpty() ? null
                : r.servicios().stream()
                        .map(s -> s.idServicio() + ":" + s.cantidad())
                        .collect(Collectors.joining(","));

        var llamada = plsql.ejecutar(con -> {
            try (CallableStatement cs = con.prepareCall(
                    "BEGIN pkg_transacciones.sp_reservar_y_pagar(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?); END;")) {
                cs.setLong(1, r.idCliente());
                cs.setLong(2, r.idUsuarioSistema());
                cs.setObject(3, r.checkin());
                cs.setObject(4, r.checkout());
                cs.setInt(5, r.numHuespedes());
                cs.setString(6, lista(r.habitaciones()));
                cs.setString(7, servicios);
                cs.setBigDecimal(8, r.valorPago());
                cs.setString(9, r.metodoPago().strip().toUpperCase());
                cs.registerOutParameter(10, Types.NUMERIC);
                cs.registerOutParameter(11, Types.NUMERIC);
                cs.registerOutParameter(12, Types.VARCHAR);
                cs.execute();
                return new Salida(cs.getLong(10), cs.getLong(11), cs.getString(12));
            }
        });
        Salida out = llamada.resultado();
        return new ResultadoReservaPago(out.idReserva(), out.idPago(), out.resultado(),
                llamada.salida(), detalle(out.idReserva()));
    }

    /** Pago total o abono al saldo: pkg_transacciones.sp_registrar_abono (FOR UPDATE + COMMIT). */
    public ResultadoAbono abonar(long idReserva, Abono a) {
        var llamada = plsql.ejecutar(con -> {
            try (CallableStatement cs = con.prepareCall(
                    "BEGIN pkg_transacciones.sp_registrar_abono(?, ?, ?, ?, ?); END;")) {
                cs.setLong(1, idReserva);
                cs.setBigDecimal(2, a.valor());
                cs.setString(3, a.metodoPago().strip().toUpperCase());
                cs.registerOutParameter(4, Types.NUMERIC);
                cs.registerOutParameter(5, Types.NUMERIC);
                cs.execute();
                return new SalidaAbono(cs.getLong(4), cs.getBigDecimal(5));
            }
        });
        SalidaAbono out = llamada.resultado();
        return new ResultadoAbono(out.idPago(), out.saldo(), llamada.salida(), detalle(idReserva));
    }

    /** Parametros OUT de sp_registrar_abono. */
    private record SalidaAbono(long idPago, BigDecimal saldo) {
    }

    /** Parametros OUT de sp_reservar_y_pagar. */
    private record Salida(long idReserva, long idPago, String resultado) {
    }

    public ReservaDetalle detalle(long id) {
        Cabecera cab = jdbc.sql("""
                SELECT r.id_reserva, r.id_cliente, c.nombres || ' ' || c.apellidos AS cliente,
                       u.usuario AS registrada_por, r.fecha_creacion, r.fecha_checkin,
                       r.fecha_checkout, r.estado, r.num_huespedes, r.valor_total,
                       r.valor_pagado, r.valor_pendiente
                  FROM reserva r
                  JOIN cliente c         ON c.id_cliente = r.id_cliente
                  JOIN usuario_sistema u ON u.id_usuario_sistema = r.id_usuario_sistema
                 WHERE r.id_reserva = :id
                """).param("id", id).query(Cabecera.class).optional()
                .orElseThrow(() -> ErrorNegocio.noEncontrado("La reserva " + id + " no existe"));

        List<HabitacionReservada> habitaciones = jdbc.sql("""
                SELECT rh.id_habitacion, h.numero_habitacion, a.nombre AS alojamiento,
                       m.nombre AS municipio, rh.fecha_checkin, rh.fecha_checkout,
                       rh.valor_previo, rh.valor_reserva
                  FROM reserva_habitacion rh
                  JOIN habitacion h  ON h.id_habitacion = rh.id_habitacion
                  JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
                  JOIN municipio m   ON m.id_municipio = a.id_municipio
                 WHERE rh.id_reserva = :id
                 ORDER BY rh.id_habitacion
                """).param("id", id).query(HabitacionReservada.class).list();

        List<ServicioReservado> servicios = jdbc.sql("""
                SELECT rs.id_servicio, s.nombre AS servicio, rs.fecha_servicio, rs.cantidad,
                       rs.valor_previo, rs.valor_servicio
                  FROM reserva_servicio rs
                  JOIN servicio s ON s.id_servicio = rs.id_servicio
                 WHERE rs.id_reserva = :id
                 ORDER BY rs.fecha_servicio, s.nombre
                """).param("id", id).query(ServicioReservado.class).list();

        List<Pago> pagos = jdbc.sql("""
                SELECT id_pago, valor, fecha_pago, metodo_pago, estado
                  FROM pago WHERE id_reserva = :id ORDER BY fecha_pago, id_pago
                """).param("id", id).query(Pago.class).list();

        return new ReservaDetalle(cab, habitaciones, servicios, pagos);
    }

    private static String lista(List<Long> ids) {
        return ids.stream().map(String::valueOf).collect(Collectors.joining(","));
    }
}
