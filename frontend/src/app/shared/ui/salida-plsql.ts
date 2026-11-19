import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/**
 * Muestra las lineas de DBMS_OUTPUT que devuelve la API. Resalta los
 * COMMIT y los ROLLBACK para que se vea como termino la transaccion.
 */
@Component({
  selector: 'app-salida-plsql',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <figure>
      <figcaption>
        <span class="material-symbols-rounded" aria-hidden="true">terminal</span>{{ titulo() }}
      </figcaption>
      <ol>
        @for (linea of lineas(); track $index) {
          <li [class.rollback]="linea.includes('ROLLBACK')" [class.commit]="linea.startsWith('COMMIT')">{{ linea }}</li>
        }
      </ol>
    </figure>`,
  styles: `
    figure { margin: 0; border-radius: var(--radio-s); overflow: hidden; background: #22180f; color: #eadfcd; }
    figcaption {
      display: flex; align-items: center; gap: 6px; padding: 8px 12px; font-size: 0.74rem; font-weight: 600;
      letter-spacing: 0.06em; text-transform: uppercase; color: #c9b8a0; background: #2e2117;
    }
    ol { margin: 0; padding: 10px 12px 12px 40px; font: 0.82rem/1.6 ui-monospace, 'SFMono-Regular', Menlo, monospace; }
    li::marker { color: #7d6a55; }
    .rollback { color: #ffb4a0; }
    .commit { color: #9fe0b6; font-weight: 600; }
  `,
})
export class SalidaPlsqlComponent {
  readonly lineas = input.required<string[]>();
  readonly titulo = input('Salida del procedimiento');
}
