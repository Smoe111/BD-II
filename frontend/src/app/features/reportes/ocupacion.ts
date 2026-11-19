import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MESES, OcupacionMunicipio } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { colorSecuencial, PASOS_SECUENCIALES } from '../../shared/graficos/escala-secuencial';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

/**
 * Consulta 1 (PIVOT): distribucion mensual de las habitaciones reservadas
 * de cada municipio. RATIO_TO_REPORT ... OVER (PARTITION BY municipio):
 * cada fila suma 100 %, asi se ve en que meses se concentra la demanda.
 */
@Component({
  selector: 'app-reporte-ocupacion',
  imports: [FormsModule, DecimalPipe, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div>
          <h2>Ocupación por municipio y mes</h2>
          <p>PIVOT de los 12 meses en columnas. Cada celda es el % de las habitaciones reservadas del año en ese mes
            (RATIO_TO_REPORT por municipio): cada fila suma 100 %.</p>
        </div>
        <div class="filtros">
          <label class="campo"><span>Año</span>
            <select class="control" [ngModel]="anio()" (ngModelChange)="anio.set(+$event)">
              @for (a of anios; track a) { <option [value]="a">{{ a }}</option> }
            </select>
          </label>
        </div>
      </header>
      @if (datos.cargando()) { <app-cargando [filas]="12" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (datos.datos(); as filas) {
        <div class="tabla-contenedor">
          <table class="tabla calor">
            <thead><tr><th>Municipio</th>@for (m of meses; track m) { <th class="der">{{ m }}</th> }<th>Mes pico</th></tr></thead>
            <tbody>
              @for (f of filas; track f.municipio) {
                <tr>
                  <td><strong>{{ f.municipio }}</strong></td>
                  @for (m of meses; track m) {
                    <td class="celda" [style.background]="color(valor(f, m)).fondo" [style.color]="color(valor(f, m)).texto"
                        [title]="f.municipio + ' · ' + m + ': ' + valor(f, m) + ' %'">{{ valor(f, m) | number: '1.0-1' }}</td>
                  }
                  <td><strong>{{ mesPico(f) }}</strong></td>
                </tr>
              }
            </tbody>
          </table>
        </div>
        <div class="leyenda" aria-hidden="true">
          <span>0 %</span>
          @for (c of pasos; track c) { <i [style.background]="c"></i> }
          <span>{{ maximo() | number: '1.0-0' }} %</span>
        </div>
      }
    </article>`,
  styles: `
    .calor th, .calor td { text-transform: capitalize; }
    .celda { text-align: center; font-variant-numeric: tabular-nums; font-size: 0.82rem; border: 2px solid #fff; border-radius: 6px; }
    .leyenda { display: flex; align-items: center; gap: 2px; margin-top: 12px; font-size: 0.75rem; color: var(--cafe-600);
      i { width: 28px; height: 10px; border-radius: 2px; } span { margin: 0 6px; } }
  `,
})
export class ReporteOcupacionComponent {
  private readonly api = inject(ReportesApi);
  protected readonly meses = MESES;
  protected readonly pasos = PASOS_SECUENCIALES;
  protected readonly anios = [2024, 2025, 2026, 2027];
  protected readonly anio = signal(2025);
  protected readonly datos = consulta<OcupacionMunicipio[]>();

  protected readonly maximo = computed(() =>
    Math.max(1, ...(this.datos.datos() ?? []).flatMap((f) => this.meses.map((m) => this.valor(f, m)))));

  constructor() {
    effect(() => this.datos.ejecutar(this.api.ocupacion(this.anio())));
  }

  protected valor(f: OcupacionMunicipio, m: (typeof MESES)[number]): number {
    return f[`${m}Pct`] ?? 0;
  }
  protected color(v: number) {
    return colorSecuencial(v, this.maximo());
  }
  protected mesPico(f: OcupacionMunicipio): string {
    return this.meses.reduce((pico, m) => (this.valor(f, m) > this.valor(f, pico) ? m : pico), this.meses[0]);
  }
}
