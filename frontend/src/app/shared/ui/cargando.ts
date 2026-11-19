import { ChangeDetectionStrategy, Component, input } from '@angular/core';

/** Marcador de carga con forma de filas, para que la pagina no salte al llegar los datos. */
@Component({
  selector: 'app-cargando',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="cargando" role="status" aria-live="polite">
      <span class="sr-only">Cargando…</span>
      @for (f of filasArr(); track $index) { <div class="barra" [style.width.%]="100 - ($index % 3) * 14"></div> }
    </div>`,
  styles: `
    .cargando { display: grid; gap: 10px; padding: 6px 0; }
    .barra {
      height: 14px; border-radius: 6px;
      background: linear-gradient(90deg, var(--crema-200) 0%, var(--crema-100) 50%, var(--crema-200) 100%);
      background-size: 200% 100%; animation: brillo 1.3s ease-in-out infinite;
    }
    @keyframes brillo { from { background-position: 100% 0; } to { background-position: -100% 0; } }
  `,
})
export class CargandoComponent {
  readonly filas = input(4);
  protected filasArr() { return Array.from({ length: this.filas() }); }
}
