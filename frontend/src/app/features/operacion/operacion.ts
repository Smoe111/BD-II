import { ChangeDetectionStrategy, Component, computed, effect, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { AgendaServicio, CierreCaja, Llegada } from '../../core/api/modelos';
import { OperacionApi } from '../../core/api/operacion.api';
import { consulta } from '../../core/util/consulta';
import { hoyIso, sumarDias } from '../../core/util/fechas';
import { BarrasHorizontalesComponent } from '../../shared/graficos/barras-horizontales';
import { Punto } from '../../shared/graficos/modelo';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';

const pesos = new PesosPipe();
const METODO: Record<string, string> = {
  PSE: 'PSE', TARJETA_CREDITO: 'Tarjeta de crédito', TARJETA_DEBITO: 'Tarjeta débito', TRANSFERENCIA: 'Transferencia', EFECTIVO: 'Efectivo',
};

/**
 * Operacion diaria de recepcion. Son las tres consultas que se aceleraron
 * con indices en la Entrega 3 (17_indices.sql).
 */
@Component({
  selector: 'app-operacion',
  imports: [FormsModule, RouterLink, PesosPipe, FechaPipe, AvisoComponent, CargandoComponent, VacioComponent, BarrasHorizontalesComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './operacion.html',
  styleUrl: './operacion.scss',
})
export class OperacionComponent {
  private readonly api = inject(OperacionApi);
  protected readonly fecha = signal(hoyIso());
  protected readonly formato = (v: number) => pesos.transform(v);

  protected readonly llegadas = consulta<Llegada[]>();
  protected readonly caja = consulta<CierreCaja[]>();
  protected readonly agenda = consulta<AgendaServicio[]>();

  protected readonly totalCaja = computed(() => (this.caja.datos() ?? []).reduce((s, c) => s + c.total, 0));
  protected readonly huespedes = computed(() => (this.llegadas.datos() ?? []).reduce((s, l) => s + l.numHuespedes, 0));
  protected readonly porCobrar = computed(() => (this.llegadas.datos() ?? []).reduce((s, l) => s + l.valorPendiente, 0));
  protected readonly barrasCaja = computed<Punto[]>(() =>
    (this.caja.datos() ?? []).map((c) => ({ etiqueta: `${METODO[c.metodoPago] ?? c.metodoPago} (${c.pagos})`, valor: c.total })));

  constructor() {
    effect(() => {
      const f = this.fecha();
      if (!f) return;
      this.llegadas.ejecutar(this.api.llegadas(f));
      this.caja.ejecutar(this.api.cierreCaja(f));
      this.agenda.ejecutar(this.api.agendaServicios(f));
    });
  }

  protected mover(dias: number): void {
    this.fecha.set(sumarDias(this.fecha(), dias));
  }
}
