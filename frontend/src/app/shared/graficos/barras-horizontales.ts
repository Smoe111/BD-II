import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { Punto } from './modelo';

/**
 * Ranking en barras horizontales: etiqueta a la izquierda, valor rotulado
 * al final de cada barra (cada barra lleva su numero, asi no hace falta eje).
 */
@Component({
  selector: 'app-barras-horizontales',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <ol class="barras">
      @for (p of puntos(); track p.etiqueta) {
        <li [title]="(p.detalle ?? []).join(' · ')">
          <span class="etq">{{ p.etiqueta }}</span>
          <span class="pista">
            <span class="barra" [class.resaltada]="p.resaltado" [style.width.%]="(p.valor / maximo()) * 100"></span>
          </span>
          <span class="valor num">{{ formato()(p.valor) }}</span>
        </li>
      }
    </ol>`,
  styles: `
    .barras { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
    li { display: grid; grid-template-columns: minmax(110px, 38%) 1fr auto; gap: 12px; align-items: center; }
    .etq { font-size: 0.86rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .pista { height: 12px; display: flex; }
    .barra { height: 100%; min-width: 2px; border-radius: 0 4px 4px 0; background: var(--serie-1); }
    .barra.resaltada { background: var(--serie-2); }
    .valor { font-size: 0.82rem; font-weight: 600; color: var(--cafe-800); min-width: 72px; text-align: right; }
  `,
})
export class BarrasHorizontalesComponent {
  readonly puntos = input.required<Punto[]>();
  readonly formato = input<(v: number) => string>((v) => v.toLocaleString('es-CO'));
  protected readonly maximo = computed(() => Math.max(1, ...this.puntos().map((p) => p.valor)));
}
