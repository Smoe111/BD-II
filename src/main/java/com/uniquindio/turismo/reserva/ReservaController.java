package com.uniquindio.turismo.reserva;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.reserva.Dto.Abono;
import com.uniquindio.turismo.reserva.Dto.CrearReserva;
import com.uniquindio.turismo.reserva.Dto.ReservaDetalle;
import com.uniquindio.turismo.reserva.Dto.ReservarYPagar;
import com.uniquindio.turismo.reserva.Dto.ResultadoAbono;
import com.uniquindio.turismo.reserva.Dto.ResultadoReservaPago;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/reservas")
public class ReservaController {

    private final ReservaServicio servicio;

    public ReservaController(ReservaServicio servicio) {
        this.servicio = servicio;
    }

    /** Reserva sin pago (queda PENDIENTE): pkg_transacciones.sp_reservar_sin_pago (sp_crear_reserva + bitacora). */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ReservaDetalle crear(@Valid @RequestBody CrearReserva solicitud) {
        return servicio.crear(solicitud);
    }

    /** Reserva + servicios + pago atomicos: pkg_transacciones.sp_reservar_y_pagar. */
    @PostMapping("/con-pago")
    @ResponseStatus(HttpStatus.CREATED)
    public ResultadoReservaPago reservarYPagar(@Valid @RequestBody ReservarYPagar solicitud) {
        return servicio.reservarYPagar(solicitud);
    }

    /** Pago total o abono al saldo pendiente: pkg_transacciones.sp_registrar_abono. */
    @PostMapping("/{id}/pagos")
    @ResponseStatus(HttpStatus.CREATED)
    public ResultadoAbono abonar(@PathVariable long id, @Valid @RequestBody Abono abono) {
        return servicio.abonar(id, abono);
    }

    @GetMapping("/{id}")
    public ReservaDetalle detalle(@PathVariable long id) {
        return servicio.detalle(id);
    }
}
