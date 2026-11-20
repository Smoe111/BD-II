package com.uniquindio.turismo.reserva;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/** Solicitudes y respuestas del modulo de reservas. */
public final class Dto {

    private Dto() {
    }

    /** POST /api/reservas -> pkg_transacciones.sp_reservar_sin_pago */
    public record CrearReserva(
            @NotNull Long idCliente,
            @NotNull Long idUsuarioSistema,
            @NotNull LocalDate checkin,
            @NotNull LocalDate checkout,
            @NotNull @Min(1) @Max(60) Integer numHuespedes,
            @NotEmpty List<@NotNull Long> habitaciones) {
    }

    public record ServicioPedido(@NotNull Long idServicio, @NotNull @Min(1) Integer cantidad) {
    }

    /** POST /api/reservas/con-pago -> pkg_transacciones.sp_reservar_y_pagar */
    public record ReservarYPagar(
            @NotNull Long idCliente,
            @NotNull Long idUsuarioSistema,
            @NotNull LocalDate checkin,
            @NotNull LocalDate checkout,
            @NotNull @Min(1) @Max(60) Integer numHuespedes,
            @NotEmpty List<@NotNull Long> habitaciones,
            List<@Valid ServicioPedido> servicios,
            @NotNull @Positive BigDecimal valorPago,
            @NotBlank String metodoPago) {
    }

    /**
     * @param resultado COMPLETA o ROLLBACK_PARCIAL (los servicios se descartaron)
     * @param salida    pasos que informo el procedimiento (DBMS_OUTPUT)
     */
    public record ResultadoReservaPago(Long idReserva, Long idPago, String resultado,
                                       List<String> salida, ReservaDetalle reserva) {
    }

    /**
     * POST /api/reservas/{id}/pagos -> pkg_transacciones.sp_registrar_abono.
     * El valor y el metodo los valida el PL/SQL (-20050, -20051, -20053).
     */
    public record Abono(@NotNull BigDecimal valor, @NotBlank String metodoPago) {
    }

    /**
     * @param saldo  saldo pendiente despues del pago
     * @param salida pasos que informo el procedimiento (DBMS_OUTPUT)
     */
    public record ResultadoAbono(Long idPago, BigDecimal saldo, List<String> salida, ReservaDetalle reserva) {
    }

    // ---------------- detalle de una reserva ---------------------------

    public record Cabecera(Long idReserva, Long idCliente, String cliente, String registradaPor,
                           LocalDateTime fechaCreacion, LocalDate fechaCheckin, LocalDate fechaCheckout,
                           String estado, Integer numHuespedes, BigDecimal valorTotal,
                           BigDecimal valorPagado, BigDecimal valorPendiente) {
    }

    public record HabitacionReservada(Long idHabitacion, String numeroHabitacion, String alojamiento,
                                      String municipio, LocalDate fechaCheckin, LocalDate fechaCheckout,
                                      BigDecimal valorPrevio, BigDecimal valorReserva) {
    }

    public record ServicioReservado(Long idServicio, String servicio, LocalDate fechaServicio,
                                    Integer cantidad, BigDecimal valorPrevio, BigDecimal valorServicio) {
    }

    public record Pago(Long idPago, BigDecimal valor, LocalDateTime fechaPago, String metodoPago,
                       String estado) {
    }

    public record ReservaDetalle(Cabecera reserva, List<HabitacionReservada> habitaciones,
                                 List<ServicioReservado> servicios, List<Pago> pagos) {
    }
}
