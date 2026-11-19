import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { Cliente, ReservaResumen, Usuario } from './modelos';
import { parametros } from './parametros';

/** Clientes (huespedes) y cuentas del personal. */
@Injectable({ providedIn: 'root' })
export class PersonasApi {
  private readonly http = inject(HttpClient);

  /** Busca por apellido (contiene) o por numero de documento; maximo 50 resultados. */
  buscarClientes(criterio: { apellido?: string; documento?: string }): Observable<Cliente[]> {
    return this.http.get<Cliente[]>('/api/clientes', { params: parametros(criterio) });
  }

  cliente(id: number): Observable<Cliente> {
    return this.http.get<Cliente>(`/api/clientes/${id}`);
  }

  reservasDeCliente(id: number): Observable<ReservaResumen[]> {
    return this.http.get<ReservaResumen[]>(`/api/clientes/${id}/reservas`);
  }

  personal(): Observable<Usuario[]> {
    return this.http.get<Usuario[]>('/api/usuarios');
  }
}
