import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { AgendaServicio, CierreCaja, FechaIso, Llegada } from './modelos';
import { parametros } from './parametros';

/** Consultas de la operacion diaria, aceleradas con los indices de 17_indices.sql. */
@Injectable({ providedIn: 'root' })
export class OperacionApi {
  private readonly http = inject(HttpClient);

  /** Indice compuesto ix_reserva_estado_checkin. */
  llegadas(fecha: FechaIso): Observable<Llegada[]> {
    return this.http.get<Llegada[]>('/api/operacion/llegadas', { params: parametros({ fecha }) });
  }

  /** Indice basado en funcion ix_pago_dia (TRUNC(fecha_pago)). */
  cierreCaja(fecha: FechaIso): Observable<CierreCaja[]> {
    return this.http.get<CierreCaja[]>('/api/operacion/cierre-caja', { params: parametros({ fecha }) });
  }

  /** Indice que cubre la consulta ix_rs_fecha_servicio. */
  agendaServicios(fecha: FechaIso): Observable<AgendaServicio[]> {
    return this.http.get<AgendaServicio[]>('/api/operacion/agenda-servicios', { params: parametros({ fecha }) });
  }
}
