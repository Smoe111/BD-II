import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { catchError, of } from 'rxjs';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { Municipio, OcupacionMensual } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { GraficoColumnasComponent } from '../../shared/graficos/grafico-columnas';
import { Punto } from '../../shared/graficos/modelo';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const pesos = new PesosPipe();

/** Consulta 6: lectura de la vista materializada MV_OCUPACION_MENSUAL y su refresco bajo demanda. */
@Component({
  selector: 'app-reporte-vista',
  imports: [FormsModule, PesosPipe, GraficoColumnasComponent, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div>
          <h2>Habitaciones reservadas por mes</h2>
          <p>Lectura directa de MV_OCUPACION_MENSUAL (precalculada). El refresco ejecuta DBMS_MVIEW.REFRESH en modo completo.</p>
        </div>
        <div class="filtros">
          <label class="campo"><span>Municipio</span>
            <select class="control" [ngModel]="municipio()" (ngModelChange)="municipio.set(+$event)">
              @for (m of municipios(); track m.idMunicipio) { <option [value]="m.idMunicipio">{{ m.nombre }}</option> }
            </select>
          </label>
          <label class="campo"><span>Año</span>
            <select class="control" [ngModel]="anio()" (ngModelChange)="anio.set(+$event)">
              @for (a of [2024, 2025, 2026, 2027]; track a) { <option [value]="a">{{ a }}</option> }
            </select>
          </label>
          <button class="boton suave" type="button" (click)="refrescar()" [disabled]="refresco.cargando()">
            <span class="material-symbols-rounded" aria-hidden="true">sync</span>Refrescar vista
          </button>
        </div>
      </header>

      @if (refresco.datos(); as r) {
        <p class="refrescada"><span class="material-symbols-rounded" aria-hidden="true">check_circle</span>
          {{ r.vista }} refrescada ({{ r.metodo }}) en {{ r.milisegundos }} ms.</p>
      }
      @if (refresco.error(); as e) { <app-aviso [error]="e" /> }

      @if (datos.cargando()) { <app-cargando [filas]="6" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (puntos().length) {
        <app-grafico-columnas [puntos]="puntos()" [alto]="240" descripcion="Habitaciones reservadas por mes" />
        <p class="total">Ingreso por habitaciones del año: <strong class="num">{{ ingresoAnio() | pesos }}</strong></p>
      } @else if (datos.datos()) {
        <p class="muted">La vista no tiene filas para ese municipio y año.</p>
      }
    </article>`,
  styles: `
    .refrescada { display: flex; gap: 6px; align-items: center; color: var(--ok); font-size: 0.86rem; margin-bottom: 12px; }
    .total { margin-top: 14px; font-size: 0.9rem; color: var(--cafe-700); }
  `,
})
export class ReporteVistaComponent {
  private readonly api = inject(ReportesApi);
  protected readonly municipios = toSignal(
    inject(CatalogoApi).municipios().pipe(catchError(() => of([] as Municipio[]))), { initialValue: [] });
  protected readonly municipio = signal(12);
  protected readonly anio = signal(2025);
  protected readonly datos = consulta<OcupacionMensual[]>();
  protected readonly refresco = consulta<{ metodo: string; vista: string; milisegundos: number }>();

  protected readonly puntos = computed<Punto[]>(() => (this.datos.datos() ?? []).map((f) => ({
    etiqueta: MES[f.mes - 1],
    titulo: `${MES[f.mes - 1]} ${f.anio} · ${f.municipio}`,
    valor: f.totalReservasHabitacion,
    detalle: [`Ingreso: ${pesos.transform(f.totalIngresoHabitaciones)}`],
  })));
  protected readonly ingresoAnio = computed(() =>
    (this.datos.datos() ?? []).reduce((s, f) => s + f.totalIngresoHabitaciones, 0));

  constructor() {
    effect(() => this.datos.ejecutar(this.api.ocupacionMensual(this.anio(), this.municipio())));
  }

  protected refrescar(): void {
    this.refresco.ejecutar(this.api.refrescarVista(),
      () => this.datos.ejecutar(this.api.ocupacionMensual(this.anio(), this.municipio())));
  }
}
