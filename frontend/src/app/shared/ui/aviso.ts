import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { ErrorApi } from '../../core/http/error-api';
import { SalidaPlsqlComponent } from './salida-plsql';

/**
 * Mensaje de error de la API (con el codigo ORA que lo produjo) o un aviso
 * informativo. Si el procedimiento alcanzo a escribir pasos en DBMS_OUTPUT
 * se muestran debajo, por ejemplo hasta donde llego antes del ROLLBACK.
 */
@Component({
  selector: 'app-aviso',
  imports: [SalidaPlsqlComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="aviso" [class]="tipo()" role="alert">
      <span class="material-symbols-rounded icono" aria-hidden="true">{{ icono() }}</span>
      <div class="cuerpo">
        <strong>{{ titulo() }}</strong>
        <p>{{ mensaje() }}</p>
        @if (error()?.codigoOracle; as codigo) {
          <span class="codigo">ORA-{{ codigo }}</span>
        }
        @if (error()?.salida?.length) {
          <app-salida-plsql [lineas]="error()!.salida" titulo="Pasos del procedimiento (DBMS_OUTPUT)" />
        }
      </div>
    </div>`,
  styles: `
    .aviso { display: flex; gap: 12px; padding: 14px 16px; border-radius: var(--radio-m); border: 1px solid; }
    .error { background: var(--error-fondo); border-color: #f0c4b8; color: var(--error); }
    .info { background: var(--info-fondo); border-color: #c7d9ec; color: var(--info); }
    .ok { background: var(--ok-fondo); border-color: var(--verde-200); color: var(--ok); }
    .icono { font-size: 24px; }
    .cuerpo { display: grid; gap: 4px; min-width: 0; flex: 1; }
    p { color: var(--cafe-800); }
    .codigo { font: 600 0.75rem ui-monospace, monospace; opacity: 0.8; }
    app-salida-plsql { margin-top: 8px; }
  `,
})
export class AvisoComponent {
  readonly error = input<ErrorApi | undefined>();
  readonly texto = input<string>('');
  readonly tipo = input<'error' | 'info' | 'ok'>('error');

  protected readonly icono = computed(() => ({ error: 'error', info: 'info', ok: 'check_circle' })[this.tipo()]);
  protected readonly mensaje = computed(() => this.error()?.message ?? this.texto());
  protected readonly titulo = computed(() => {
    const e = this.error();
    if (!e) return this.tipo() === 'ok' ? 'Listo' : 'Información';
    if (e.estado === 0) return 'Sin conexión';
    if (e.estado === 409) return 'Conflicto con otra reserva';
    if (e.estado === 422) return 'La regla de negocio no lo permite';
    if (e.estado === 404) return 'No encontrado';
    if (e.estado === 503) return 'Recurso no disponible';
    if (e.estado >= 500) return 'Error del servidor';
    return 'Revise los datos';
  });
}
