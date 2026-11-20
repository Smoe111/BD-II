import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { Abono, CrearReserva, ReservaDetalle, ReservarYPagar, ResultadoAbono, ResultadoReservaPago } from './modelos';

/**
 * Reservas. Las reglas (disponibilidad, capacidad, anticipo del 30 %,
 * SAVEPOINT y ROLLBACK) las aplica el PL/SQL; este servicio solo envia la solicitud.
 */
@Injectable({ providedIn: 'root' })
export class ReservasApi {
  private readonly http = inject(HttpClient);

  /** pkg_transacciones.sp_reservar_sin_pago (sp_crear_reserva + bitacora): reserva PENDIENTE sin pago. */
  crear(solicitud: CrearReserva): Observable<ReservaDetalle> {
    return this.http.post<ReservaDetalle>('/api/reservas', solicitud);
  }

  /** pkg_transacciones.sp_reservar_y_pagar: reserva + servicios + pago en una sola transaccion. */
  reservarYPagar(solicitud: ReservarYPagar): Observable<ResultadoReservaPago> {
    return this.http.post<ResultadoReservaPago>('/api/reservas/con-pago', solicitud);
  }

  /** pkg_transacciones.sp_registrar_abono: pago total o abono al saldo (bloquea la reserva con FOR UPDATE). */
  abonar(id: number, abono: Abono): Observable<ResultadoAbono> {
    return this.http.post<ResultadoAbono>(`/api/reservas/${id}/pagos`, abono);
  }

  detalle(id: number): Observable<ReservaDetalle> {
    return this.http.get<ReservaDetalle>(`/api/reservas/${id}`);
  }
}
