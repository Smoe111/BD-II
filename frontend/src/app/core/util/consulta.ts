import { DestroyRef, Signal, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Observable, Subscription } from 'rxjs';
import { ErrorApi } from '../http/error-api';

/**
 * Estado de una llamada a la API expuesto como signals (datos, cargando, error).
 * Cada ejecutar() cancela la anterior, asi una respuesta lenta no pisa a una nueva.
 * Debe crearse en un contexto de inyeccion (campo de un componente).
 */
export interface Consulta<T> {
  readonly datos: Signal<T | undefined>;
  readonly cargando: Signal<boolean>;
  readonly error: Signal<ErrorApi | undefined>;
  readonly lista: Signal<boolean>;
  ejecutar(fuente: Observable<T>, alTerminar?: (datos: T) => void): void;
  limpiar(): void;
}

export function consulta<T>(): Consulta<T> {
  const destroyRef = inject(DestroyRef);
  const datos = signal<T | undefined>(undefined);
  const cargando = signal(false);
  const error = signal<ErrorApi | undefined>(undefined);
  let actual: Subscription | undefined;

  return {
    datos: datos.asReadonly(),
    cargando: cargando.asReadonly(),
    error: error.asReadonly(),
    lista: computed(() => !cargando() && !error() && datos() !== undefined),
    ejecutar(fuente, alTerminar) {
      actual?.unsubscribe();
      cargando.set(true);
      error.set(undefined);
      actual = fuente.pipe(takeUntilDestroyed(destroyRef)).subscribe({
        next: (valor) => {
          datos.set(valor);
          cargando.set(false);
          alTerminar?.(valor);
        },
        error: (e: unknown) => {
          error.set(ErrorApi.desde(e));
          cargando.set(false);
        },
      });
    },
    limpiar() {
      actual?.unsubscribe();
      datos.set(undefined);
      error.set(undefined);
      cargando.set(false);
    },
  };
}
