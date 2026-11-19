import { ChangeDetectionStrategy, Component, computed, effect, inject, input } from '@angular/core';
import { Location } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { of } from 'rxjs';
import { EstadoFinanciero, ReservaDetalle, ResultadoAbono } from '../../core/api/modelos';
import { ReportesApi } from '../../core/api/reportes.api';
import { ReservasApi } from '../../core/api/reservas.api';
import { consulta } from '../../core/util/consulta';
import { noches } from '../../core/util/fechas';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { EstadoReservaComponent } from '../../shared/ui/estado-reserva';
import { RegistrarPagoComponent } from './registrar-pago';

/** Detalle de una reserva (GET /api/reservas/{id}) y su estado financiero (consulta 7, UNPIVOT). */
@Component({
  selector: 'app-reserva-detalle',
  imports: [RouterLink, PesosPipe, FechaPipe, AvisoComponent, CargandoComponent, EstadoReservaComponent, RegistrarPagoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './reserva-detalle.html',
  styleUrl: './reserva-detalle.scss',
})
export class ReservaDetalleComponent {
  private readonly reservas = inject(ReservasApi);
  private readonly reportes = inject(ReportesApi);
  private readonly location = inject(Location);
  private readonly router = inject(Router);

  /** :id de la ruta (withComponentInputBinding). */
  readonly id = input.required<string>();

  protected readonly detalle = consulta<ReservaDetalle>();
  protected readonly financiero = consulta<EstadoFinanciero[]>();

  protected readonly noches = computed(() => {
    const r = this.detalle.datos()?.reserva;
    return r ? noches(r.fechaCheckin, r.fechaCheckout) : 0;
  });
  protected readonly pctPagado = computed(() => {
    const r = this.detalle.datos()?.reserva;
    return r && r.valorTotal > 0 ? Math.min(100, Math.round((r.valorPagado / r.valorTotal) * 100)) : 0;
  });
  protected readonly totalServicios = computed(() =>
    (this.detalle.datos()?.servicios ?? []).reduce((s, x) => s + x.valorServicio, 0));

  constructor() {
    effect(() => {
      const id = Number(this.id());
      this.detalle.ejecutar(this.reservas.detalle(id));
      this.financiero.ejecutar(this.reportes.estadoFinanciero({ reserva: id }));
    });
  }

  /** Vuelve a la pantalla anterior; si se entro directo por URL, va a huespedes. */
  protected volver(): void {
    if (this.router.lastSuccessfulNavigation()?.previousNavigation) this.location.back();
    else this.router.navigate(['/huespedes']);
  }

  /** Tras un pago: la respuesta ya trae la reserva actualizada; el estado financiero se vuelve a consultar. */
  protected alPagar(r: ResultadoAbono): void {
    this.detalle.ejecutar(of(r.reserva));
    this.financiero.ejecutar(this.reportes.estadoFinanciero({ reserva: r.reserva.reserva.idReserva }));
  }

  protected concepto(c: EstadoFinanciero['conceptoPago']): string {
    return { TOTAL_CONTRATADO: 'Contratado', TOTAL_PAGADO: 'Pagado', TOTAL_PENDIENTE: 'Pendiente' }[c];
  }
}
