import { ChangeDetectionStrategy, Component, input } from '@angular/core';

@Component({
  selector: 'app-vacio',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="vacio">
      <span class="material-symbols-rounded" aria-hidden="true">{{ icono() }}</span>
      <strong>{{ titulo() }}</strong>
      @if (texto()) { <p>{{ texto() }}</p> }
      <ng-content />
    </div>`,
  styles: `
    .vacio { display: grid; justify-items: center; gap: 6px; padding: 36px 16px; text-align: center; color: var(--cafe-600); }
    .material-symbols-rounded { font-size: 40px; color: var(--verde-300); }
    strong { color: var(--cafe-800); font-family: var(--fuente-titulo); font-size: 1.05rem; }
    p { max-width: 48ch; font-size: 0.9rem; }
  `,
})
export class VacioComponent {
  readonly icono = input('travel_explore');
  readonly titulo = input.required<string>();
  readonly texto = input('');
}
