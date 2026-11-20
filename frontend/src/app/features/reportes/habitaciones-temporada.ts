import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { HabitacionTemporada, Temporada, TipoTemporada } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';

const TIPOS: { valor: TipoTemporada; texto: string }[] = [
  { valor: 'ALTA', texto: 'Alta (con recargo)' },
  { valor: 'BAJA', texto: 'Baja (sin recargo)' },
  { valor: 'DESCUENTO', texto: 'Descuento' },
];

/**
 * Consulta 9: habitaciones con mas reservas en un tipo de temporada. El
 * tipo se deduce del porcentaje de TEMPORADA y la temporada concreta es
 * opcional; ambos viajan como variables de enlace.
 */
@Component({
  selector: 'app-reporte-habitaciones-temporada',
  imports: [FormsModule, RouterLink, PesosPipe, AvisoComponent, CargandoComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div>
          <h2>Habitaciones con más reservas por temporada</h2>
          <p>El tipo sale del porcentaje de TEMPORADA (recargo = alta, 0 % = baja). Cada estadía cuenta en la temporada de su check-in. Sin canceladas; DENSE_RANK conserva los empates.</p>
        </div>
      </header>
      <div class="filtros">
        <label class="campo"><span>Tipo de temporada</span>
          <select class="control" [ngModel]="tipo()" (ngModelChange)="cambiarTipo($event)">
            @for (t of tipos; track t.valor) { <option [value]="t.valor">{{ t.texto }}</option> }
          </select>
        </label>
        <label class="campo"><span>Temporada</span>
          <select class="control" [ngModel]="temporada()" (ngModelChange)="temporada.set($event)">
            <option value="">Todas las del tipo</option>
            @for (t of temporadasDelTipo(); track t.nombre) {
              <option [value]="t.nombre">{{ t.nombre }} ({{ t.porcentaje > 0 ? '+' : '' }}{{ t.porcentaje }} %)</option>
            }
          </select>
        </label>
        <label class="campo"><span>Puestos</span>
          <select class="control" [ngModel]="top()" (ngModelChange)="top.set(+$event)">
            @for (n of [1, 3, 5, 10]; track n) { <option [value]="n">{{ n }}</option> }
          </select>
        </label>
      </div>

      @if (datos.cargando()) { <app-cargando [filas]="6" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (filas().length) {
        @if (lideres(); as l) {
          <p class="respuesta">
            <span class="material-symbols-rounded" aria-hidden="true">emoji_events</span>
            @if (l.length === 1) {
              La habitación con más reservas es la <strong>{{ l[0].numeroHabitacion }}</strong> de
              <strong>{{ l[0].alojamiento }}</strong> ({{ l[0].municipio }}), con <strong>{{ l[0].cantidadReservas }}</strong> reservas.
            } @else {
              {{ l.length }} habitaciones empatan en el primer puesto con <strong>{{ l[0].cantidadReservas }}</strong> reservas.
            }
          </p>
        }
        <div class="tabla-contenedor">
          <table class="tabla">
            <thead><tr><th>Puesto</th><th>Habitación</th><th>Alojamiento</th><th>Municipio</th><th>Reservas</th><th class="der">Ingreso</th></tr></thead>
            <tbody>
              @for (h of filas(); track h.idHabitacion) {
                <tr>
                  <td><span class="puesto" [class.oro]="h.puesto === 1">{{ h.puesto }}</span></td>
                  <td>{{ h.numeroHabitacion }} <small class="muted">· id {{ h.idHabitacion }}</small></td>
                  <td><a [routerLink]="['/destinos', h.idAlojamiento]">{{ h.alojamiento }}</a></td>
                  <td>{{ h.municipio }}</td>
                  <td>
                    <div class="barra">
                      <span class="pista"><span [style.width.%]="h.cantidadReservas / maximo() * 100"></span></span>
                      <span class="num">{{ h.cantidadReservas }}</span>
                    </div>
                  </td>
                  <td class="der" [title]="h.ingresoTotal | pesos">{{ h.ingresoTotal | pesos: 'compacto' }}</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
      } @else if (datos.datos()) {
        <app-vacio icono="event_busy" titulo="Sin reservas" texto="No hay reservas con check-in en temporadas de este tipo." />
      }
    </article>`,
  styles: `
    .filtros { margin-bottom: 16px; }
    .respuesta { display: flex; gap: 8px; align-items: center; margin-bottom: 14px; padding: 12px 14px;
      border-radius: var(--radio-m); background: var(--ambar-100); color: var(--cafe-800); font-size: 0.92rem;
      .material-symbols-rounded { color: var(--ambar-700); } }
    .puesto { width: 26px; height: 26px; border-radius: 50%; display: inline-grid; place-items: center;
      background: var(--crema-200); font-weight: 700; font-size: 0.8rem; color: var(--cafe-700); }
    .puesto.oro { background: var(--ambar-100); color: var(--ambar-700); }
    .barra { display: flex; align-items: center; gap: 8px; min-width: 140px; }
    .pista { flex: 1; height: 8px; border-radius: 999px; background: var(--crema-200);
      span { display: block; height: 100%; border-radius: 999px; background: var(--serie-1); } }
  `,
})
export class ReporteHabitacionesTemporadaComponent {
  private readonly api = inject(ReportesApi);
  protected readonly tipos = TIPOS;
  protected readonly tipo = signal<TipoTemporada>('ALTA');
  protected readonly temporada = signal('');
  protected readonly top = signal(5);
  protected readonly datos = consulta<HabitacionTemporada[]>();
  private readonly catalogo = consulta<Temporada[]>();

  protected readonly temporadasDelTipo = computed(() =>
    (this.catalogo.datos() ?? []).filter((t) => t.tipo === this.tipo()));
  protected readonly filas = computed(() => this.datos.datos() ?? []);
  protected readonly maximo = computed(() => Math.max(1, ...this.filas().map((h) => h.cantidadReservas)));
  protected readonly lideres = computed(() => {
    const l = this.filas().filter((h) => h.puesto === 1);
    return l.length ? l : null;
  });

  constructor() {
    this.catalogo.ejecutar(this.api.temporadas());
    effect(() => this.datos.ejecutar(this.api.habitacionesPorTemporada({
      tipo: this.tipo(), temporada: this.temporada() || null, top: this.top(),
    })));
  }

  protected cambiarTipo(t: TipoTemporada): void {
    this.temporada.set('');   // la temporada elegida puede no ser del nuevo tipo
    this.tipo.set(t);
  }
}
