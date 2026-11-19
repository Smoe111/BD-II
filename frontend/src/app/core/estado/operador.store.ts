import { Injectable, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { catchError, of } from 'rxjs';
import { Usuario } from '../api/modelos';
import { PersonasApi } from '../api/personas.api';

const CLAVE = 'turismouq.operador';

/**
 * Funcionario que opera la aplicacion (no hay autenticacion en esta entrega).
 * Su id se envia como id_usuario_sistema al crear reservas y su usuario
 * como usuario_app al cambiar tarifas, para que lo registre la auditoria.
 */
@Injectable({ providedIn: 'root' })
export class OperadorStore {
  private readonly personas = inject(PersonasApi);

  readonly personal = toSignal(this.personas.personal().pipe(catchError(() => of([] as Usuario[]))),
    { initialValue: [] as Usuario[] });

  private readonly idSeleccionado = signal<number | null>(leerGuardado());

  readonly operador = computed<Usuario | undefined>(() => {
    const activos = this.personal().filter((u) => u.activo === 'S');
    return activos.find((u) => u.idUsuarioSistema === this.idSeleccionado())
      ?? activos.find((u) => u.rol === 'RECEPCION')
      ?? activos[0];
  });

  seleccionar(id: number): void {
    this.idSeleccionado.set(id);
    try { localStorage.setItem(CLAVE, String(id)); } catch { /* almacenamiento no disponible */ }
  }
}

function leerGuardado(): number | null {
  try {
    const v = localStorage.getItem(CLAVE);
    return v ? Number(v) : null;
  } catch {
    return null;
  }
}
