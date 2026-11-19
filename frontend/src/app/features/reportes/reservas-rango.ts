import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { EstadoReserva, ReservaRango } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { consulta } from '../../core/util/consulta';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { EstadoReservaComponent } from '../../shared/ui/estado-reserva';

const POR_PAGINA = 25;

/**
 * Consulta 5: reservas con check-in en un rango, usando variables de
 * enlace (:desde, :hasta). Las canceladas muestran su estado real y valor 0.
 */
@Component({
  selector: 'app-reporte-reservas',
  imports: [FormsModule, RouterLink, PesosPipe, FechaPipe, AvisoComponent, CargandoComponent, EstadoReservaComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div><h2>Reservas por rango de llegada</h2><p>Variables de enlace :desde y :hasta. Las canceladas aparecen como CANCELADA y con valor 0.</p></div>
      </header>
      <form class="filtros" (ngSubmit)="buscar()">
        <label class="campo"><span>Desde</span><input class="control" type="date" name="d" [(ngModel)]="desde" required /></label>
        <label class="campo"><span>Hasta</span><input class="control" type="date" name="h" [(ngModel)]="hasta" required /></label>
        <button class="boton" type="submit" [disabled]="!desde() || !hasta()">Consultar</button>
      </form>

      @if (datos.cargando()) { <app-cargando [filas]="8" /> }
      @else if (datos.error(); as e) { <app-aviso [error]="e" /> }
      @else if (datos.datos()) {
        <div class="estados" role="group" aria-label="Filtrar por estado">
          <button type="button" class="etiqueta" [class.info]="!estado()" (click)="filtrar(null)">Todas · {{ datos.datos()!.length }}</button>
          @for (c of conteos(); track c.estado) {
            <button type="button" class="etiqueta" [class.info]="estado() === c.estado" (click)="filtrar(c.estado)">
              {{ c.estado }} · {{ c.cantidad }} · {{ c.valor | pesos: 'compacto' }}
            </button>
          }
        </div>
        <div class="tabla-contenedor">
          <table class="tabla">
            <thead><tr><th>Reserva</th><th>Cliente</th><th>Alojamiento</th><th>Llegada</th><th>Salida</th><th>Registró</th><th>Estado</th><th class="der">Valor</th></tr></thead>
            <tbody>
              @for (r of pagina(); track r.idReserva) {
                <tr>
                  <td><a [routerLink]="['/reservas', r.idReserva]">#{{ r.idReserva }}</a></td>
                  <td>{{ r.cliente }}</td>
                  <td>{{ r.alojamiento }} <small class="muted">· {{ r.municipio }}</small></td>
                  <td>{{ r.fechaCheckin | fecha }}</td>
                  <td>{{ r.fechaCheckout | fecha }}</td>
                  <td>{{ r.usuario }}</td>
                  <td><app-estado-reserva [estado]="r.estado" /></td>
                  <td class="der">{{ r.valorTotal | pesos }}</td>
                </tr>
              }
            </tbody>
          </table>
        </div>
        <nav class="paginador" aria-label="Paginación">
          <button class="boton suave pequeno" type="button" (click)="numPagina.set(numPagina() - 1)" [disabled]="numPagina() === 0">Anterior</button>
          <span>Página {{ numPagina() + 1 }} de {{ totalPaginas() }}</span>
          <button class="boton suave pequeno" type="button" (click)="numPagina.set(numPagina() + 1)" [disabled]="numPagina() + 1 >= totalPaginas()">Siguiente</button>
        </nav>
      }
    </article>`,
  styles: `
    .filtros { margin-bottom: 16px; }
    .estados { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 12px; button { border: 0; cursor: pointer; font: inherit; font-size: 0.75rem; font-weight: 600; } }
    .paginador { display: flex; gap: 12px; align-items: center; justify-content: flex-end; margin-top: 12px; font-size: 0.85rem; color: var(--cafe-600); }
  `,
})
export class ReporteReservasComponent {
  private readonly api = inject(ReportesApi);
  protected readonly desde = signal('2025-06-15');
  protected readonly hasta = signal('2025-07-31');
  protected readonly estado = signal<EstadoReserva | null>(null);
  protected readonly numPagina = signal(0);
  protected readonly datos = consulta<ReservaRango[]>();

  private readonly filtradas = computed(() => {
    const e = this.estado();
    const filas = this.datos.datos() ?? [];
    return e ? filas.filter((r) => r.estado === e) : filas;
  });
  protected readonly totalPaginas = computed(() => Math.max(1, Math.ceil(this.filtradas().length / POR_PAGINA)));
  protected readonly pagina = computed(() =>
    this.filtradas().slice(this.numPagina() * POR_PAGINA, (this.numPagina() + 1) * POR_PAGINA));
  protected readonly conteos = computed(() => {
    const mapa = new Map<EstadoReserva, { estado: EstadoReserva; cantidad: number; valor: number }>();
    for (const r of this.datos.datos() ?? []) {
      const c = mapa.get(r.estado) ?? { estado: r.estado, cantidad: 0, valor: 0 };
      c.cantidad++;
      c.valor += r.valorTotal;
      mapa.set(r.estado, c);
    }
    return [...mapa.values()];
  });

  constructor() {
    this.buscar();
  }

  protected buscar(): void {
    this.filtrar(null);
    this.datos.ejecutar(this.api.reservas(this.desde(), this.hasta()));
  }

  protected filtrar(e: EstadoReserva | null): void {
    this.estado.set(e);
    this.numPagina.set(0);
  }
}
