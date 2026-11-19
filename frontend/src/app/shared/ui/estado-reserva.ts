import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { EstadoReserva } from '../../core/api/modelos';

const ESTILO: Record<EstadoReserva, { clase: string; icono: string; texto: string }> = {
  PENDIENTE: { clase: 'aviso', icono: 'schedule', texto: 'Pendiente' },
  CONFIRMADA: { clase: 'ok', icono: 'verified', texto: 'Confirmada' },
  EN_CURSO: { clase: 'info', icono: 'hotel', texto: 'En curso' },
  FINALIZADA: { clase: '', icono: 'task_alt', texto: 'Finalizada' },
  CANCELADA: { clase: 'error', icono: 'cancel', texto: 'Cancelada' },
};

/** Estado de una reserva con icono y texto (nunca solo color). */
@Component({
  selector: 'app-estado-reserva',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="etiqueta" [class]="estilo().clase">
    <span class="material-symbols-rounded" aria-hidden="true">{{ estilo().icono }}</span>{{ estilo().texto }}
  </span>`,
})
export class EstadoReservaComponent {
  readonly estado = input.required<EstadoReserva | string>();
  protected readonly estilo = computed(
    () => ESTILO[this.estado() as EstadoReserva] ?? { clase: '', icono: 'help', texto: this.estado() },
  );
}
