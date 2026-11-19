import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IngresoCubo } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

const TODOS_MUN = 'TODOS LOS MUNICIPIOS';
const TODOS_TIPOS = 'TODOS LOS TIPOS';
const TODAS_TEMP = 'TODAS LAS TEMPORADAS';

/**
 * Consulta 2 (CUBE). Para el municipio elegido arma la matriz tipo x
 * temporada. Los totales de fila, columna y general NO se suman aqui:
 * son las filas de subtotal que produjo el CUBE (GROUPING_ID 1, 2 y 3; o
 * 5, 6 y 7 para todos los municipios).
 */
@Component({
  selector: 'app-reporte-ingresos',
  imports: [FormsModule, PesosPipe, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div>
          <h2>Ingresos por tipo de alojamiento y temporada</h2>
          <p>CUBE (municipio, tipo, temporada). Los totales son filas de subtotal del CUBE (GROUPING_ID), no sumas hechas en pantalla.</p>
        </div>
        <label class="campo"><span>Municipio</span>
          <select class="control" [ngModel]="municipio()" (ngModelChange)="municipio.set($event)">
            @for (m of municipios(); track m) { <option [value]="m">{{ m === todos ? 'Todos los municipios' : m }}</option> }
          </select>
        </label>
      </header>
      @if (datos.cargando()) { <app-cargando [filas]="8" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (datos.datos()) {
        <div class="tabla-contenedor">
          <table class="tabla">
            <thead>
              <tr><th>Tipo</th>@for (t of temporadas(); track t) { <th class="der">{{ t }}</th> }<th class="der">Total tipo</th></tr>
            </thead>
            <tbody>
              @for (tipo of tipos(); track tipo) {
                <tr>
                  <td><strong>{{ tipo }}</strong></td>
                  @for (t of temporadas(); track t) { <td class="der" [title]="celda(tipo, t) | pesos">{{ celda(tipo, t) | pesos: 'compacto' }}</td> }
                  <td class="der subtotal-col" [title]="celda(tipo, totalTemp) | pesos">{{ celda(tipo, totalTemp) | pesos: 'compacto' }}</td>
                </tr>
              }
              <tr class="subtotal">
                <td>Total temporada</td>
                @for (t of temporadas(); track t) { <td class="der" [title]="celda(totalTipos, t) | pesos">{{ celda(totalTipos, t) | pesos: 'compacto' }}</td> }
                <td class="der total-general">{{ celda(totalTipos, totalTemp) | pesos }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="nota muted">Pase el mouse por una cifra para ver el valor exacto: los valores se muestran abreviados (M = millones).</p>
      }
    </article>`,
  styles: `
    .subtotal-col { background: var(--crema-100); font-weight: 600; }
    .total-general { background: var(--verde-50) !important; color: var(--verde-800); font-weight: 700; }
    .nota { font-size: 0.78rem; margin-top: 10px; }
  `,
})
export class ReporteIngresosComponent {
  protected readonly todos = TODOS_MUN;
  protected readonly totalTipos = TODOS_TIPOS;
  protected readonly totalTemp = TODAS_TEMP;
  protected readonly datos = consulta<IngresoCubo[]>();
  protected readonly municipio = signal(TODOS_MUN);

  private readonly filas = computed(() => (this.datos.datos() ?? []).filter((f) => f.municipio === this.municipio()));
  protected readonly municipios = computed(() => {
    const ms = [...new Set((this.datos.datos() ?? []).map((f) => f.municipio))].filter((m) => m !== TODOS_MUN).sort();
    return [TODOS_MUN, ...ms];
  });
  protected readonly tipos = computed(() =>
    [...new Set(this.filas().map((f) => f.tipoAlojamiento))].filter((t) => t !== TODOS_TIPOS).sort());
  protected readonly temporadas = computed(() =>
    [...new Set(this.filas().map((f) => f.temporada))].filter((t) => t !== TODAS_TEMP).sort());

  private readonly indice = computed(() => {
    const m = new Map<string, number>();
    for (const f of this.filas()) m.set(`${f.tipoAlojamiento}|${f.temporada}`, f.ingresoTotal);
    return m;
  });

  constructor() {
    this.datos.ejecutar(inject(ReportesApi).ingresos());
  }

  protected celda(tipo: string, temporada: string): number | null {
    return this.indice().get(`${tipo}|${temporada}`) ?? null;
  }
}
