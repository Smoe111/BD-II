import { ChangeDetectionStrategy, Component, computed, effect, inject, input } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Cliente, ReservaResumen } from '../../core/api/modelos';
import { PersonasApi } from '../../core/api/personas.api';
import { consulta } from '../../core/util/consulta';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { EstadoReservaComponent } from '../../shared/ui/estado-reserva';
import { KpiComponent } from '../../shared/ui/kpi';

/** Ficha del huesped con su historial de reservas (GET /api/clientes/{id} y /reservas). */
@Component({
  selector: 'app-huesped-detalle',
  imports: [RouterLink, FechaPipe, PesosPipe, AvisoComponent, CargandoComponent, EstadoReservaComponent, KpiComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="pagina">
      <a class="volver" routerLink="/huespedes"><span class="material-symbols-rounded" aria-hidden="true">arrow_back</span>Huéspedes</a>
      @if (cliente.error(); as e) { <app-aviso [error]="e" /> }
      @if (cliente.datos(); as c) {
        <header class="encabezado">
          <div class="perfil">
            <span class="avatar">{{ c.nombres[0] }}{{ c.apellidos[0] }}</span>
            <div>
              <span class="antetitulo">Huésped N.º {{ c.idCliente }}</span>
              <h1>{{ c.nombres }} {{ c.apellidos }}</h1>
              <p>{{ c.tipoDocumento }} {{ c.numeroDocumento }} · {{ c.correoElectronico }} · {{ c.telefono ?? 'sin teléfono' }}</p>
            </div>
          </div>
          <a class="boton" routerLink="/reservar"><span class="material-symbols-rounded" aria-hidden="true">add</span>Nueva reserva</a>
        </header>
      }

      <div class="kpis">
        <app-kpi icono="event_available" etiqueta="Reservas" [valor]="resumen().reservas.toString()" [detalle]="resumen().canceladas + ' canceladas'" />
        <app-kpi icono="receipt_long" etiqueta="Total contratado" [valor]="resumen().total" />
        <app-kpi icono="account_balance_wallet" etiqueta="Saldo pendiente" [valor]="resumen().pendiente" />
      </div>

      <article class="tarjeta">
        <header><h2>Historial de reservas</h2></header>
        @if (reservas.cargando()) { <app-cargando [filas]="5" /> }
        @else if (reservas.datos()?.length) {
          <div class="tabla-contenedor">
            <table class="tabla">
              <thead><tr><th>Reserva</th><th>Alojamiento</th><th>Llegada</th><th>Salida</th><th>Estado</th>
                <th class="der">Total</th><th class="der">Pendiente</th></tr></thead>
              <tbody>
                @for (r of reservas.datos(); track r.idReserva) {
                  <tr>
                    <td><a [routerLink]="['/reservas', r.idReserva]">#{{ r.idReserva }}</a></td>
                    <td>{{ r.alojamiento }} <small class="muted">· {{ r.municipio }}</small></td>
                    <td>{{ r.fechaCheckin | fecha }}</td>
                    <td>{{ r.fechaCheckout | fecha }}</td>
                    <td><app-estado-reserva [estado]="r.estado" /></td>
                    <td class="der">{{ r.valorTotal | pesos }}</td>
                    <td class="der">{{ r.valorPendiente | pesos }}</td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
        } @else if (reservas.datos()) { <p class="muted">Sin reservas registradas.</p> }
      </article>
    </section>`,
  styles: `
    .volver { display: inline-flex; align-items: center; gap: 4px; font-weight: 600; text-decoration: none; font-size: 0.88rem; width: fit-content; }
    .perfil { display: flex; gap: 16px; align-items: center; }
    .avatar { width: 64px; height: 64px; border-radius: 20px; display: grid; place-items: center; background: var(--ambar-100); color: var(--ambar-700); font: 600 1.4rem var(--fuente-titulo); flex: none; }
    .kpis { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }
  `,
})
export class HuespedDetalleComponent {
  private readonly api = inject(PersonasApi);
  readonly id = input.required<string>();

  protected readonly cliente = consulta<Cliente>();
  protected readonly reservas = consulta<ReservaResumen[]>();

  protected readonly resumen = computed(() => {
    const pesos = new PesosPipe();
    const rs = this.reservas.datos() ?? [];
    const vigentes = rs.filter((r) => r.estado !== 'CANCELADA');
    return {
      reservas: rs.length,
      canceladas: rs.length - vigentes.length,
      total: pesos.transform(vigentes.reduce((s, r) => s + r.valorTotal, 0), 'compacto'),
      pendiente: pesos.transform(vigentes.reduce((s, r) => s + r.valorPendiente, 0), 'compacto'),
    };
  });

  constructor() {
    effect(() => {
      const id = Number(this.id());
      this.cliente.ejecutar(this.api.cliente(id));
      this.reservas.ejecutar(this.api.reservasDeCliente(id));
    });
  }
}
