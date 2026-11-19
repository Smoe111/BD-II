import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import {
  Alojamiento, AlojamientoDetalle, Cotizacion, FechaIso, FiltroDisponibilidad, HabitacionDisponible,
  Municipio, Servicio, Temporada, TipoAlojamiento,
} from './modelos';
import { parametros } from './parametros';

/** Catalogo turistico: municipios, alojamientos, disponibilidad y cotizacion (pkg_turismo.fn_valor_estadia). */
@Injectable({ providedIn: 'root' })
export class CatalogoApi {
  private readonly http = inject(HttpClient);

  municipios(): Observable<Municipio[]> {
    return this.http.get<Municipio[]>('/api/municipios');
  }

  tiposAlojamiento(): Observable<TipoAlojamiento[]> {
    return this.http.get<TipoAlojamiento[]>('/api/tipos-alojamiento');
  }

  alojamientos(municipio?: number | null, tipo?: number | null): Observable<Alojamiento[]> {
    return this.http.get<Alojamiento[]>('/api/alojamientos', { params: parametros({ municipio, tipo }) });
  }

  alojamiento(id: number): Observable<AlojamientoDetalle> {
    return this.http.get<AlojamientoDetalle>(`/api/alojamientos/${id}`);
  }

  disponibles(f: FiltroDisponibilidad): Observable<HabitacionDisponible[]> {
    return this.http.get<HabitacionDisponible[]>('/api/habitaciones/disponibles', {
      params: parametros({ ...f }),
    });
  }

  cotizacion(idHabitacion: number, checkin: FechaIso, checkout: FechaIso): Observable<Cotizacion> {
    return this.http.get<Cotizacion>(`/api/habitaciones/${idHabitacion}/cotizacion`, {
      params: parametros({ checkin, checkout }),
    });
  }

  servicios(): Observable<Servicio[]> {
    return this.http.get<Servicio[]>('/api/servicios');
  }

  temporadas(anio?: number | null): Observable<Temporada[]> {
    return this.http.get<Temporada[]>('/api/temporadas', { params: parametros({ anio }) });
  }
}
