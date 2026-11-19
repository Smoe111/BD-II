import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/** Cifra principal con su etiqueta y un dato de contexto. */
@Component({
  selector: 'app-kpi',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="kpi">
      <span class="icono material-symbols-rounded" aria-hidden="true">{{ icono() }}</span>
      <div>
        <p class="etq">{{ etiqueta() }}</p>
        <p class="valor num">{{ valor() }}</p>
        @if (detalle()) { <p class="detalle">{{ detalle() }}</p> }
      </div>
    </article>`,
  styles: `
    .kpi {
      display: flex; gap: 14px; align-items: flex-start; height: 100%;
      background: var(--crema-50); border: var(--borde); border-radius: var(--radio-m);
      padding: 18px; box-shadow: var(--sombra-1);
    }
    .icono {
      font-size: 22px; width: 42px; height: 42px; display: grid; place-items: center; flex: none;
      border-radius: 12px; background: var(--verde-50); color: var(--verde-600);
    }
    .etq { font-size: 0.8rem; font-weight: 600; color: var(--cafe-600); }
    .valor { font-family: var(--fuente-titulo); font-size: 1.7rem; font-weight: 600; line-height: 1.2; margin-top: 2px; }
    .detalle { font-size: 0.8rem; color: var(--cafe-500); margin-top: 2px; }
  `,
})
export class KpiComponent {
  readonly etiqueta = input.required<string>();
  readonly valor = input.required<string>();
  readonly detalle = input('');
  readonly icono = input('insights');
}
