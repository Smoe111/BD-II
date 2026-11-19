import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import {
  CarteraMunicipio, EstadoFinanciero, FechaIso, IngresoCubo, OcupacionMensual, OcupacionMunicipio,
  ReservaRango, TopAlojamiento, VariacionMensual,
} from './modelos';
import { parametros } from './parametros';

/** Las 8 consultas analiticas de la Entrega 1 (04_consultas.sql). */
@Injectable({ providedIn: 'root' })
export class ReportesApi {
  private readonly http = inject(HttpClient);
  private readonly base = '/api/reportes';

  /** 1. PIVOT: % de ocupacion por municipio y mes. */
  ocupacion(anio: number): Observable<OcupacionMunicipio[]> {
    return this.http.get<OcupacionMunicipio[]>(`${this.base}/ocupacion`, { params: parametros({ anio }) });
  }

  /** 2. CUBE: ingresos por municipio, tipo de alojamiento y temporada, con subtotales. */
  ingresos(): Observable<IngresoCubo[]> {
    return this.http.get<IngresoCubo[]>(`${this.base}/ingresos`);
  }

  /** 3. RANK() OVER (PARTITION BY municipio). */
  topAlojamientos(top: number): Observable<TopAlojamiento[]> {
    return this.http.get<TopAlojamiento[]>(`${this.base}/top-alojamientos`, { params: parametros({ top }) });
  }

  /** 4. LAG(): variacion de ingresos mes contra mes. */
  variacionMensual(): Observable<VariacionMensual[]> {
    return this.http.get<VariacionMensual[]>(`${this.base}/variacion-mensual`);
  }

  /** 5. Reservas por rango (variables de enlace). */
  reservas(desde: FechaIso, hasta: FechaIso): Observable<ReservaRango[]> {
    return this.http.get<ReservaRango[]>(`${this.base}/reservas`, { params: parametros({ desde, hasta }) });
  }

  /** 6. Vista materializada MV_OCUPACION_MENSUAL. */
  ocupacionMensual(anio?: number | null, municipio?: number | null): Observable<OcupacionMensual[]> {
    return this.http.get<OcupacionMensual[]>(`${this.base}/ocupacion-mensual`, {
      params: parametros({ anio, municipio }),
    });
  }

  refrescarVista(): Observable<{ metodo: string; vista: string; milisegundos: number }> {
    return this.http.post<{ metodo: string; vista: string; milisegundos: number }>(
      `${this.base}/ocupacion-mensual/refresco`, null);
  }

  /** 7. UNPIVOT del estado financiero de reservas. */
  estadoFinanciero(filtro: { reserva?: number | null; cliente?: number | null; limite?: number | null }):
    Observable<EstadoFinanciero[]> {
    return this.http.get<EstadoFinanciero[]>(`${this.base}/estado-financiero`, { params: parametros(filtro) });
  }

  /** 8. Cartera pendiente por municipio. */
  cartera(): Observable<CarteraMunicipio[]> {
    return this.http.get<CarteraMunicipio[]>(`${this.base}/cartera`);
  }
}
