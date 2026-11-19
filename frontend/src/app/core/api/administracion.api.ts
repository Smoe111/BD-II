import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { AuditoriaTarifa, Bloqueo, Liquidacion, LogTransaccion, ResultadoLiquidacion, Tarifa } from './modelos';
import { parametros } from './parametros';

/** Liquidacion mensual, tarifas con auditoria y monitoreo de la base. */
@Injectable({ providedIn: 'root' })
export class AdministracionApi {
  private readonly http = inject(HttpClient);

  /** pkg_turismo.sp_liquidar_mes (cursor explicito con parametros). */
  liquidar(anio: number, mes: number, idAlojamiento?: number | null): Observable<ResultadoLiquidacion> {
    return this.http.post<ResultadoLiquidacion>('/api/liquidaciones', { anio, mes, idAlojamiento: idAlojamiento ?? null });
  }

  liquidaciones(anio?: number | null, mes?: number | null, alojamiento?: number | null): Observable<Liquidacion[]> {
    return this.http.get<Liquidacion[]>('/api/liquidaciones', { params: parametros({ anio, mes, alojamiento }) });
  }

  tarifas(): Observable<Tarifa[]> {
    return this.http.get<Tarifa[]>('/api/tarifas');
  }

  /** El trigger trg_tarifa_auditoria registra el cambio; la respuesta es la auditoria de la tarifa. */
  cambiarTarifa(id: number, valor: number, usuario: string): Observable<AuditoriaTarifa[]> {
    return this.http.put<AuditoriaTarifa[]>(`/api/tarifas/${id}`, { valor, usuario });
  }

  auditoriaTarifa(id: number): Observable<AuditoriaTarifa[]> {
    return this.http.get<AuditoriaTarifa[]>(`/api/tarifas/${id}/auditoria`);
  }

  bloqueos(): Observable<Bloqueo[]> {
    return this.http.get<Bloqueo[]>('/api/admin/bloqueos');
  }

  logTransacciones(limite = 50): Observable<LogTransaccion[]> {
    return this.http.get<LogTransaccion[]>('/api/admin/log-transacciones', { params: parametros({ limite }) });
  }
}
