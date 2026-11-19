import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { CarteraMunicipio } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

/**
 * Consulta 8: cartera por municipio. Barra apilada al 100 % con dos
 * series (recaudado / pendiente), leyenda y porcentaje rotulado.
 */
@Component({
  selector: 'app-reporte-cartera',
  imports: [PesosPipe, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div><h2>Cartera pendiente por municipio</h2><p>Facturado frente a recaudado de las reservas no canceladas.</p></div>
        <div class="leyenda">
          <span><i class="s1"></i>Recaudado</span><span><i class="s2"></i>Pendiente</span>
        </div>
      </header>
      @if (datos.cargando()) { <app-cargando [filas]="10" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (filas().length) {
        <ul class="barras">
          @for (c of filas(); track c.municipio) {
            <li>
              <span class="etq">{{ c.municipio }}</span>
              <span class="apilada" [title]="c.municipio + ': pendiente ' + (c.carteraPendiente | pesos)">
                <span class="s1" [style.width.%]="100 - c.porcentajeCartera"></span>
                <span class="s2" [style.width.%]="c.porcentajeCartera"></span>
              </span>
              <span class="num pct">{{ c.porcentajeCartera }} %</span>
            </li>
          }
        </ul>
        <div class="tabla-contenedor">
          <table class="tabla">
            <thead><tr><th>Municipio</th><th class="der">Reservas</th><th class="der">Facturado</th><th class="der">Recaudado</th><th class="der">Pendiente</th><th class="der">%</th></tr></thead>
            <tbody>
              @for (c of filas(); track c.municipio) {
                <tr>
                  <td>{{ c.municipio }}</td>
                  <td class="der">{{ c.cantidadReservas }}</td>
                  <td class="der">{{ c.totalFacturado | pesos }}</td>
                  <td class="der">{{ c.totalRecaudado | pesos }}</td>
                  <td class="der"><strong>{{ c.carteraPendiente | pesos }}</strong></td>
                  <td class="der">{{ c.porcentajeCartera }} %</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      }
    </article>`,
  styles: `
    .leyenda { display: flex; gap: 14px; font-size: 0.8rem; color: var(--cafe-700);
      span { display: flex; align-items: center; gap: 6px; } i { width: 12px; height: 12px; border-radius: 3px; } }
    .s1 { background: var(--serie-1); } .s2 { background: var(--serie-2); }
    .barras { list-style: none; margin: 0 0 20px; padding: 0; display: grid; gap: 8px; }
    li { display: grid; grid-template-columns: 110px 1fr 60px; gap: 12px; align-items: center; font-size: 0.86rem; }
    .apilada { display: flex; gap: 2px; height: 14px; }
    .apilada span:first-child { border-radius: 4px 0 0 4px; }
    .apilada span:last-child { border-radius: 0 4px 4px 0; min-width: 2px; }
    .pct { text-align: right; font-weight: 600; }
  `,
})
export class ReporteCarteraComponent {
  protected readonly datos = consulta<CarteraMunicipio[]>();
  protected readonly filas = computed(() =>
    [...(this.datos.datos() ?? [])].sort((a, b) => b.porcentajeCartera - a.porcentajeCartera));

  constructor() {
    this.datos.ejecutar(inject(ReportesApi).cartera());
  }
}
