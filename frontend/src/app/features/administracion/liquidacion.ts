import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { catchError, of } from 'rxjs';
import { AdministracionApi } from '../../core/api/administracion.api';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { Alojamiento, Liquidacion, ResultadoLiquidacion } from '../../core/api/modelos';
import { consulta } from '../../core/util/consulta';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { KpiComponent } from '../../shared/ui/kpi';
import { SalidaPlsqlComponent } from '../../shared/ui/salida-plsql';
import { VacioComponent } from '../../shared/ui/vacio';

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
const pesos = new PesosPipe();

/** Liquidacion mensual a los alojamientos: pkg_turismo.sp_liquidar_mes (cursor explicito con parametros). */
@Component({
  selector: 'app-liquidacion',
  imports: [FormsModule, PesosPipe, AvisoComponent, CargandoComponent, KpiComponent, SalidaPlsqlComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="pagina">
      <header class="encabezado">
        <div>
          <span class="antetitulo">Gerencia</span>
          <h1>Liquidación mensual</h1>
          <p>Calcula lo que se le paga a cada alojamiento por un mes cerrado: hospedaje, servicios y comisión de la plataforma.
            Se puede repetir; el procedimiento reemplaza el corte anterior.</p>
        </div>
      </header>

      <form class="tarjeta filtros" (ngSubmit)="liquidar()">
        <label class="campo"><span>Año</span>
          <select class="control" name="anio" [ngModel]="anio()" (ngModelChange)="anio.set(+$event)">
            @for (a of [2024, 2025, 2026]; track a) { <option [value]="a">{{ a }}</option> }
          </select>
        </label>
        <label class="campo"><span>Mes</span>
          <select class="control" name="mes" [ngModel]="mes()" (ngModelChange)="mes.set(+$event)">
            @for (m of meses; track m; let i = $index) { <option [value]="i + 1">{{ m }}</option> }
          </select>
        </label>
        <label class="campo ancho"><span>Alojamiento</span>
          <select class="control" name="aloj" [ngModel]="alojamiento()" (ngModelChange)="alojamiento.set(+$event || null)">
            <option [value]="0">Todos los alojamientos</option>
            @for (a of alojamientos(); track a.idAlojamiento) { <option [value]="a.idAlojamiento">{{ a.nombre }} · {{ a.municipio }}</option> }
          </select>
        </label>
        <button class="boton acento" type="submit" [disabled]="proceso.cargando()">
          <span class="material-symbols-rounded" aria-hidden="true">play_arrow</span>Ejecutar liquidación
        </button>
      </form>

      @if (procesoVigente()) {
        @if (proceso.error(); as e) { <app-aviso [error]="e" /> }
        @if (proceso.datos(); as r) { <app-salida-plsql [lineas]="r.salida" titulo="sp_liquidar_mes (DBMS_OUTPUT)" /> }
      }

      @if (cortes.datos()?.length) {
        <div class="kpis">
          <app-kpi icono="hotel" etiqueta="Ingreso hospedaje" [valor]="t().hospedaje" />
          <app-kpi icono="hiking" etiqueta="Ingreso servicios" [valor]="t().servicios" />
          <app-kpi icono="percent" etiqueta="Comisión plataforma" [valor]="t().comision" />
          <app-kpi icono="payments" etiqueta="Neto a alojamientos" [valor]="t().neto" />
        </div>
      }

      <article class="tarjeta">
        <header><div><h2>Cortes de {{ meses[mes() - 1] }} {{ anio() }}</h2><p>Tabla LIQUIDACION_MENSUAL</p></div></header>
        @if (cortes.cargando()) { <app-cargando [filas]="6" /> }
        @else if (cortes.error(); as e) { <app-aviso [error]="e" /> }
        @else if (cortes.datos()?.length) {
          <div class="tabla-contenedor tabla-alta">
            <table class="tabla">
              <thead><tr><th>Alojamiento</th><th class="der">Reservas</th><th class="der">Noches</th><th class="der">Hospedaje</th>
                <th class="der">Servicios</th><th class="der">Recaudo caja</th><th class="der">Comisión</th><th class="der">Neto</th></tr></thead>
              <tbody>
                @for (l of cortes.datos(); track l.idLiquidacion) {
                  <tr>
                    <td>{{ l.alojamiento }}</td>
                    <td class="der">{{ l.reservas }}</td>
                    <td class="der">{{ l.nochesVendidas }}</td>
                    <td class="der">{{ l.ingresoHospedaje | pesos }}</td>
                    <td class="der">{{ l.ingresoServicios | pesos }}</td>
                    <td class="der">{{ l.recaudoCaja | pesos }}</td>
                    <td class="der">{{ l.valorComision | pesos }} <small class="muted">({{ l.pctComision }} %)</small></td>
                    <td class="der"><strong>{{ l.netoAlojamiento | pesos }}</strong></td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        } @else {
          <app-vacio icono="request_quote" titulo="Ese mes aún no se ha liquidado" texto="Ejecute la liquidación. Solo se aceptan meses ya terminados." />
        }
      </article>
    </section>`,
  styles: `
    .ancho { max-width: 360px !important; flex: 2 1 260px !important; }
    .kpis { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); }
  `,
})
export class LiquidacionComponent {
  private readonly api = inject(AdministracionApi);
  protected readonly meses = MESES;
  protected readonly anio = signal(2026);
  protected readonly mes = signal(Math.max(1, new Date().getMonth()));
  protected readonly alojamiento = signal<number | null>(null);
  protected readonly alojamientos = toSignal(
    inject(CatalogoApi).alojamientos().pipe(catchError(() => of([] as Alojamiento[]))), { initialValue: [] });

  protected readonly proceso = consulta<ResultadoLiquidacion>();

  /** Periodo (año-mes-alojamiento) que se envio en la ultima liquidacion. */
  private readonly periodoProceso = signal<string | null>(null);
  private readonly periodoActual = computed(() => `${this.anio()}-${this.mes()}-${this.alojamiento() ?? 'todos'}`);
  /**
   * El resultado (error o DBMS_OUTPUT) solo se muestra mientras el filtro siga
   * en el periodo liquidado. Si se cambia de mes, el aviso del anterior no
   * queda junto a la tabla de otro mes, como si acabara de ejecutarse.
   */
  protected readonly procesoVigente = computed(() => this.periodoProceso() === this.periodoActual());
  protected readonly cortes = consulta<Liquidacion[]>();

  protected readonly t = computed(() => {
    const ls = this.cortes.datos() ?? [];
    const suma = (f: (l: Liquidacion) => number) => pesos.transform(ls.reduce((s, l) => s + f(l), 0), 'compacto');
    return {
      hospedaje: suma((l) => l.ingresoHospedaje), servicios: suma((l) => l.ingresoServicios),
      comision: suma((l) => l.valorComision), neto: suma((l) => l.netoAlojamiento),
    };
  });

  constructor() {
    effect(() => this.cargarCortes());
  }

  private cargarCortes(): void {
    this.cortes.ejecutar(this.api.liquidaciones(this.anio(), this.mes(), this.alojamiento()));
  }

  protected liquidar(): void {
    this.periodoProceso.set(this.periodoActual());
    this.proceso.ejecutar(this.api.liquidar(this.anio(), this.mes(), this.alojamiento()), () => this.cargarCortes());
  }
}
