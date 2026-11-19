import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { VariacionMensual } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { GraficoColumnasComponent } from '../../shared/graficos/grafico-columnas';
import { Punto } from '../../shared/graficos/modelo';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const pesos = new PesosPipe();

/** Consulta 4: ingreso de cada mes frente al anterior con LAG(). */
@Component({
  selector: 'app-reporte-tendencia',
  imports: [DecimalPipe, PesosPipe, GraficoColumnasComponent, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div><h2>Ingresos mes a mes</h2><p>LAG(ingreso) OVER (ORDER BY año, mes). Pase el mouse por una columna para ver la variación.</p></div>
      </header>
      @if (datos.cargando()) { <app-cargando [filas]="8" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (puntos().length) {
        <app-grafico-columnas [puntos]="puntos()" [formato]="compacto" [alto]="280" descripcion="Ingreso mensual" />
      }
    </article>

    @if (datos.datos(); as filas) {
      <article class="tarjeta">
        <header><h2>Detalle</h2></header>
        <div class="tabla-contenedor tabla-alta">
          <table class="tabla">
            <thead><tr><th>Mes</th><th class="der">Ingreso</th><th class="der">Mes anterior</th><th class="der">Variación</th><th class="der">%</th></tr></thead>
            <tbody>
              @for (v of filasInvertidas(); track v.anio * 100 + v.mes) {
                <tr>
                  <td>{{ nombreMes(v) }}</td>
                  <td class="der">{{ v.ingresoMes | pesos }}</td>
                  <td class="der">{{ v.ingresoMesAnterior | pesos }}</td>
                  <td class="der">{{ v.variacionAbsoluta | pesos }}</td>
                  <td class="der">
                    @if (v.pctVariacion === null) { — }
                    @else {
                      <span class="etiqueta" [class.ok]="v.pctVariacion > 0" [class.error]="v.pctVariacion < 0">
                        <span class="material-symbols-rounded" aria-hidden="true">{{ v.pctVariacion >= 0 ? 'trending_up' : 'trending_down' }}</span>
                        {{ v.pctVariacion | number: '1.0-1' }} %
                      </span>
                    }
                  </td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      </article>
    }`,
  styles: `:host { display: grid; gap: 18px; }`,
})
export class ReporteTendenciaComponent {
  protected readonly datos = consulta<VariacionMensual[]>();
  protected readonly compacto = (v: number) => pesos.transform(v, 'compacto');

  protected readonly puntos = computed<Punto[]>(() => (this.datos.datos() ?? []).map((v) => ({
    etiqueta: `${MES[v.mes - 1]} ${String(v.anio).slice(2)}`,
    titulo: this.nombreMes(v),
    valor: v.ingresoMes,
    detalle: v.pctVariacion === null ? ['Primer mes de la serie']
      : [`${v.pctVariacion > 0 ? '+' : ''}${v.pctVariacion} % vs. mes anterior`, `Diferencia: ${pesos.transform(v.variacionAbsoluta)}`],
  })));
  protected readonly filasInvertidas = computed(() => [...(this.datos.datos() ?? [])].reverse());

  constructor() {
    this.datos.ejecutar(inject(ReportesApi).variacionMensual());
  }

  protected nombreMes(v: VariacionMensual): string {
    return `${MES[v.mes - 1]} ${v.anio}`;
  }
}
