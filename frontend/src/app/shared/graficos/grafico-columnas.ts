import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';
import { Punto, escala } from './modelo';

/**
 * Columnas verticales de una sola serie (sin leyenda: el titulo de la
 * tarjeta nombra la serie). Barras delgadas con extremo redondeado de 4px,
 * separacion de 2px, rejilla tenue y tooltip al pasar el mouse o al
 * enfocar con teclado. Incluye una tabla oculta para lectores de pantalla.
 */
@Component({
  selector: 'app-grafico-columnas',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="grafico" [style.height.px]="alto()">
      <div class="eje-y" aria-hidden="true">
        @for (v of guias(); track v) {
          <div class="guia" [style.bottom.%]="(v / tope()) * 100"><span>{{ formato()(v) }}</span></div>
        }
      </div>
      <div class="columnas" role="list" [attr.aria-label]="descripcion()">
        @for (p of puntos(); track p.etiqueta; let i = $index) {
          <div class="col" role="listitem" tabindex="0"
               (mouseenter)="activo.set(i)" (mouseleave)="activo.set(null)"
               (focus)="activo.set(i)" (blur)="activo.set(null)"
               [attr.aria-label]="(p.titulo ?? p.etiqueta) + ': ' + formato()(p.valor)">
            <div class="barra" [class.resaltada]="p.resaltado" [class.activa]="activo() === i"
                 [style.height.%]="(p.valor / tope()) * 100"></div>
            @if (activo() === i) {
              <div class="tooltip" [class.izq]="i > puntos().length * 0.7" [class.der]="i < puntos().length * 0.3">
                <strong>{{ p.titulo ?? p.etiqueta }}</strong>
                <span class="num">{{ formato()(p.valor) }}</span>
                @for (d of p.detalle ?? []; track d) { <small>{{ d }}</small> }
              </div>
            }
          </div>
        }
      </div>
    </div>
    <div class="eje-x" aria-hidden="true">
      @for (p of puntos(); track p.etiqueta; let i = $index) {
        <span [style.visibility]="i % saltoEtiquetas() === 0 ? 'visible' : 'hidden'">{{ p.etiqueta }}</span>
      }
    </div>`,
  styles: `
    :host { display: block; padding-left: 56px; }
    .grafico { position: relative; }
    .eje-y { position: absolute; inset: 0; pointer-events: none; }
    .guia { position: absolute; left: 0; right: 0; border-top: 1px solid var(--crema-200); }
    .guia span {
      position: absolute; right: calc(100% + 8px); top: -8px; font-size: 0.72rem;
      color: var(--cafe-500); white-space: nowrap; font-variant-numeric: tabular-nums;
    }
    .columnas { position: absolute; inset: 0; display: flex; align-items: flex-end; gap: 2px; }
    .col { position: relative; flex: 1; height: 100%; display: flex; align-items: flex-end; justify-content: center; cursor: default; outline: none; }
    .col:hover::before, .col:focus-visible::before {
      content: ''; position: absolute; inset: 0; background: var(--crema-200); opacity: 0.5; border-radius: 4px;
    }
    .barra {
      position: relative; width: min(100%, 28px); min-height: 2px; border-radius: 4px 4px 0 0;
      background: var(--serie-1); transition: filter var(--transicion);
    }
    .barra.resaltada { background: var(--serie-2); }
    .barra.activa { filter: brightness(0.88); }
    .tooltip {
      position: absolute; bottom: calc(100% + 8px); left: 50%; transform: translateX(-50%); z-index: 5;
      display: grid; gap: 2px; min-width: 150px; padding: 10px 12px; border-radius: 10px;
      background: var(--cafe-900); color: #fff; box-shadow: var(--sombra-3); pointer-events: none;
      font-size: 0.8rem; white-space: nowrap;
    }
    .tooltip.izq { left: auto; right: 0; transform: none; }
    .tooltip.der { left: 0; transform: none; }
    .tooltip span { font-size: 1rem; font-weight: 700; }
    .tooltip small { color: #d9cbb7; }
    .eje-x { display: flex; gap: 2px; margin-top: 8px; }
    .eje-x span { flex: 1; min-width: 0; text-align: center; font-size: 0.72rem; color: var(--cafe-500); white-space: nowrap; }
  `,
})
export class GraficoColumnasComponent {
  readonly puntos = input.required<Punto[]>();
  readonly formato = input<(v: number) => string>((v) => v.toLocaleString('es-CO'));
  readonly alto = input(240);
  readonly descripcion = input('Grafico de columnas');

  protected readonly activo = signal<number | null>(null);
  protected readonly guias = computed(() => escala(Math.max(0, ...this.puntos().map((p) => p.valor))));
  protected readonly tope = computed(() => Math.max(1, ...this.guias()));
  /** Con muchas columnas se muestra una etiqueta de cada n para que no se encimen. */
  protected readonly saltoEtiquetas = computed(() => Math.max(1, Math.ceil(this.puntos().length / 7)));
}
