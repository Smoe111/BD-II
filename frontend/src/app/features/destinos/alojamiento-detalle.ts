import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { AlojamientoDetalle, Cotizacion, Habitacion } from '../../core/api/modelos';
import { consulta } from '../../core/util/consulta';
import { hoyIso, sumarDias } from '../../core/util/fechas';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

/**
 * Ficha del alojamiento con sus habitaciones y un cotizador que muestra el
 * desglose de pkg_turismo.fn_valor_estadia por temporada.
 */
@Component({
  selector: 'app-alojamiento-detalle',
  imports: [FormsModule, RouterLink, PesosPipe, FechaPipe, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './alojamiento-detalle.html',
  styleUrl: './alojamiento-detalle.scss',
})
export class AlojamientoDetalleComponent {
  private readonly catalogo = inject(CatalogoApi);
  readonly id = input.required<string>();

  protected readonly detalle = consulta<AlojamientoDetalle>();
  protected readonly cotizacion = consulta<Cotizacion>();

  protected readonly habitacion = signal<Habitacion | null>(null);
  protected readonly checkin = signal(sumarDias(hoyIso(), 47));
  protected readonly checkout = signal(sumarDias(hoyIso(), 52));

  protected readonly tramoMaximo = computed(() =>
    Math.max(1, ...(this.cotizacion.datos()?.detalle ?? []).map((t) => t.subtotal)));

  constructor() {
    effect(() => this.detalle.ejecutar(this.catalogo.alojamiento(Number(this.id())), (d) => {
      this.habitacion.set(d.habitaciones.find((h) => h.activo === 'S') ?? null);
      this.cotizar();
    }));
  }

  protected cotizar(): void {
    const h = this.habitacion();
    if (!h || !this.checkin() || !this.checkout()) return;
    this.cotizacion.ejecutar(this.catalogo.cotizacion(h.idHabitacion, this.checkin(), this.checkout()));
  }

  protected elegir(h: Habitacion): void {
    this.habitacion.set(h);
    this.cotizar();
  }
}
