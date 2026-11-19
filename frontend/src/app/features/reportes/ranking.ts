import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TopAlojamiento } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

/** Consulta 3: top N alojamientos de cada municipio con RANK() OVER (PARTITION BY municipio). */
@Component({
  selector: 'app-reporte-ranking',
  imports: [FormsModule, PesosPipe, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div>
          <h2>Alojamientos que más facturan en cada municipio</h2>
          <p>RANK() OVER (PARTITION BY municipio). La barra es la participación en el ingreso del municipio (SUM() OVER).</p>
        </div>
        <label class="campo"><span>Top</span>
          <select class="control" [ngModel]="top()" (ngModelChange)="top.set(+$event)">
            @for (n of [1, 3, 5]; track n) { <option [value]="n">{{ n }}</option> }
          </select>
        </label>
      </header>
      @if (datos.cargando()) { <app-cargando [filas]="10" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else {
        <div class="grupos">
          @for (g of grupos(); track g.municipio) {
            <section>
              <h3>{{ g.municipio }}</h3>
              <ol>
                @for (a of g.alojamientos; track a.alojamiento) {
                  <li>
                    <span class="puesto" [class.oro]="a.ranking === 1">{{ a.ranking }}</span>
                    <div class="info">
                      <div class="fila"><strong>{{ a.alojamiento }}</strong><span class="num">{{ a.totalIngresos | pesos: 'compacto' }}</span></div>
                      <div class="pista" [title]="a.pctIngresoMunicipio + ' % del municipio'">
                        <span [style.width.%]="a.pctIngresoMunicipio"></span>
                      </div>
                      <small>{{ a.pctIngresoMunicipio }} % del ingreso de {{ g.municipio }}</small>
                    </div>
                  </li>
                }
              </ol>
            </section>
          }
        </div>
      }
    </article>`,
  styles: `
    .grupos { display: grid; gap: 14px; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); }
    section { border: 1px solid var(--crema-200); border-radius: var(--radio-m); padding: 14px; background: #fff; }
    h3 { margin-bottom: 10px; }
    ol { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
    li { display: flex; gap: 10px; align-items: flex-start; }
    .puesto { width: 26px; height: 26px; border-radius: 50%; display: grid; place-items: center; flex: none;
      background: var(--crema-200); font-weight: 700; font-size: 0.8rem; color: var(--cafe-700); }
    .puesto.oro { background: var(--ambar-100); color: var(--ambar-700); }
    .info { flex: 1; display: grid; gap: 4px; min-width: 0; }
    .fila { display: flex; justify-content: space-between; gap: 8px; font-size: 0.86rem; }
    .fila strong { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .pista { height: 8px; border-radius: 999px; background: var(--crema-200); span { display: block; height: 100%; border-radius: 999px; background: var(--serie-1); } }
    small { font-size: 0.74rem; color: var(--cafe-600); }
  `,
})
export class ReporteRankingComponent {
  private readonly api = inject(ReportesApi);
  protected readonly top = signal(3);
  protected readonly datos = consulta<TopAlojamiento[]>();

  protected readonly grupos = computed(() => {
    const mapa = new Map<string, TopAlojamiento[]>();
    for (const t of this.datos.datos() ?? []) mapa.set(t.municipio, [...(mapa.get(t.municipio) ?? []), t]);
    return [...mapa.entries()].map(([municipio, alojamientos]) => ({ municipio, alojamientos }));
  });

  constructor() {
    effect(() => this.datos.ejecutar(this.api.topAlojamientos(this.top())));
  }
}
