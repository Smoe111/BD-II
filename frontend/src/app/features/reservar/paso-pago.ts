import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormsModule } from '@angular/forms';
import { catchError, of } from 'rxjs';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { METODOS_PAGO, MetodoPago, Servicio } from '../../core/api/modelos';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { BorradorReserva, PCT_ANTICIPO } from './borrador.store';

const NOMBRE_METODO: Record<MetodoPago, string> = {
  PSE: 'PSE', TARJETA_CREDITO: 'Tarjeta de crédito', TARJETA_DEBITO: 'Tarjeta débito',
  TRANSFERENCIA: 'Transferencia', EFECTIVO: 'Efectivo',
};

/** Paso 3: servicios complementarios y forma de pago. */
@Component({
  selector: 'app-paso-pago',
  imports: [FormsModule, PesosPipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './paso-pago.html',
  styleUrl: './paso-pago.scss',
})
export class PasoPagoComponent {
  protected readonly borrador = inject(BorradorReserva);
  protected readonly metodos = METODOS_PAGO;
  protected readonly nombreMetodo = NOMBRE_METODO;
  protected readonly pct = PCT_ANTICIPO;

  private readonly catalogo = toSignal(
    inject(CatalogoApi).servicios().pipe(catchError(() => of([] as Servicio[]))), { initialValue: [] });

  /** Servicios agrupados por tipo (tour, alimentacion, bienestar…). */
  protected readonly tipos = computed(() => {
    const mapa = new Map<string, Servicio[]>();
    for (const s of this.catalogo()) mapa.set(s.tipoServicio, [...(mapa.get(s.tipoServicio) ?? []), s]);
    return [...mapa.entries()].map(([tipo, servicios]) => ({ tipo, servicios }));
  });

  /** Lineas pedidas por codigo que no estan en el catalogo (el PL/SQL las rechazara). */
  protected readonly porCodigo = computed(() => this.borrador.servicios().filter((l) => !l.servicio));

  protected readonly codigo = signal<number | null>(null);

  protected cambiar(s: Servicio, delta: number): void {
    const nueva = Math.max(0, Math.min(20, this.borrador.cantidadDe(s.idServicio) + delta));
    this.borrador.ponerServicio(s, s.idServicio, nueva);
  }

  protected agregarPorCodigo(): void {
    const id = this.codigo();
    if (!id || id < 1) return;
    const s = this.catalogo().find((x) => x.idServicio === id);
    this.borrador.ponerServicio(s, id, this.borrador.cantidadDe(id) + 1);
    this.codigo.set(null);
  }

  protected sugerir(fraccion: number): void {
    this.borrador.valorPago.set(Math.ceil((this.borrador.total() * fraccion) / 1000) * 1000);
  }
}
