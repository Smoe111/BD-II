import { ChangeDetectionStrategy, Component, computed, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { Cotizacion, ReservaDetalle, ResultadoReservaPago } from '../../core/api/modelos';
import { ReservasApi } from '../../core/api/reservas.api';
import { OperadorStore } from '../../core/estado/operador.store';
import { consulta } from '../../core/util/consulta';
import { noches } from '../../core/util/fechas';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { SalidaPlsqlComponent } from '../../shared/ui/salida-plsql';
import { BorradorReserva } from './borrador.store';
import { PasoHabitacionesComponent } from './paso-habitaciones';
import { PasoHuespedComponent } from './paso-huesped';
import { PasoPagoComponent } from './paso-pago';

type Paso = 1 | 2 | 3 | 4;

/**
 * Asistente de reserva en tres pasos. Al confirmar llama a
 * sp_reservar_y_pagar (con pago) o a sp_crear_reserva (sin pago) y muestra
 * como termino la transaccion: COMPLETA, ROLLBACK_PARCIAL o el error con
 * los pasos que alcanzo a dar antes del ROLLBACK total.
 */
@Component({
  selector: 'app-reservar',
  imports: [
    RouterLink, PesosPipe, FechaPipe, AvisoComponent, SalidaPlsqlComponent,
    PasoHabitacionesComponent, PasoHuespedComponent, PasoPagoComponent,
  ],
  providers: [BorradorReserva],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './reservar.html',
  styleUrl: './reservar.scss',
})
export class ReservarComponent {
  private readonly catalogo = inject(CatalogoApi);
  private readonly reservas = inject(ReservasApi);
  protected readonly operador = inject(OperadorStore).operador;
  protected readonly b = inject(BorradorReserva);

  // Query params opcionales (vienen del buscador del panel)
  readonly checkin = input<string>();
  readonly checkout = input<string>();
  readonly huespedes = input<string>();
  readonly municipio = input<string>();

  protected readonly paso = signal<Paso>(1);
  protected readonly pasos = [
    { n: 1, titulo: 'Habitaciones', icono: 'bed' },
    { n: 2, titulo: 'Huésped', icono: 'person' },
    { n: 3, titulo: 'Servicios y pago', icono: 'payments' },
  ] as const;

  protected readonly cotizacion = consulta<Cotizacion[]>();
  protected readonly envio = consulta<ResultadoReservaPago | ReservaDetalle>();

  protected readonly noches = computed(() => {
    const c = this.b.criterio();
    return c ? noches(c.checkin, c.checkout) : 0;
  });

  protected readonly puedeContinuar = computed(() => {
    switch (this.paso()) {
      case 1: return this.b.habitaciones().length > 0 && this.b.capacidadSuficiente();
      case 2: return this.b.cliente() !== null;
      case 3: return !this.b.conPago() || (this.b.valorPago() ?? 0) > 0;
      default: return false;
    }
  });

  /** Resultado de sp_reservar_y_pagar (con 'resultado') o de sp_crear_reserva (detalle directo). */
  protected readonly conPago = computed(() => {
    const r = this.envio.datos();
    return r && 'resultado' in r ? r : null;
  });
  protected readonly detalleCreado = computed(() => {
    const r = this.envio.datos();
    return r && !('resultado' in r) ? r : r?.reserva ?? null;
  });

  protected irA(paso: Paso): void {
    if (paso < this.paso()) this.paso.set(paso);
  }

  protected continuar(): void {
    if (!this.puedeContinuar()) return;
    if (this.paso() === 1) {
      // Desglose por temporada de cada habitacion antes de seguir.
      const c = this.b.criterio()!;
      this.cotizacion.ejecutar(
        forkJoin(this.b.habitaciones().map((h) => this.catalogo.cotizacion(h.idHabitacion, c.checkin, c.checkout))),
        (cot) => {
          this.b.cotizaciones.set(cot);
          this.paso.set(2);
        },
      );
      return;
    }
    if (this.paso() === 2) {
      this.paso.set(3);
      return;
    }
    this.confirmar();
  }

  private confirmar(): void {
    const c = this.b.criterio();
    const cliente = this.b.cliente();
    const operador = this.operador();
    if (!c || !cliente || !operador) return;

    const base = {
      idCliente: cliente.idCliente,
      idUsuarioSistema: operador.idUsuarioSistema,
      checkin: c.checkin,
      checkout: c.checkout,
      numHuespedes: c.huespedes,
      habitaciones: this.b.habitaciones().map((h) => h.idHabitacion),
    };
    const peticion = this.b.conPago()
      ? this.reservas.reservarYPagar({
        ...base, servicios: this.b.pedidoServicios(),
        valorPago: this.b.valorPago() ?? 0, metodoPago: this.b.metodoPago(),
      })
      : this.reservas.crear(base);
    this.envio.ejecutar(peticion, () => this.paso.set(4));
  }

  protected nuevaReserva(): void {
    this.envio.limpiar();
    this.b.reiniciarSeleccion();
    this.b.cliente.set(null);
    this.paso.set(1);
  }

  /** Tras un 409 la habitacion ya no esta libre: se vuelve a buscar. */
  protected volverABuscar(): void {
    this.envio.limpiar();
    this.b.reiniciarSeleccion();
    this.paso.set(1);
  }
}
