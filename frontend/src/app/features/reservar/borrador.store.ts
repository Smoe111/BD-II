import { Injectable, computed, linkedSignal, signal } from '@angular/core';
import {
  Cliente, Cotizacion, FechaIso, HabitacionDisponible, MetodoPago, Servicio, ServicioPedido,
} from '../../core/api/modelos';

export interface Criterio { checkin: FechaIso; checkout: FechaIso; huespedes: number; municipio: number | null; }

/** Linea de servicio elegida. 'servicio' falta cuando se pidio por codigo (puede no existir). */
export interface LineaServicio { idServicio: number; cantidad: number; servicio?: Servicio; }

/** Porcentaje minimo de anticipo; el valor real lo exige pkg_transacciones (c_pct_anticipo). */
export const PCT_ANTICIPO = 30;

/** Redondeo a centenas, igual que ROUND(x, -2) en PL/SQL. */
export const aCentenas = (x: number) => Math.round(x / 100) * 100;

/**
 * Estado del asistente de reserva, vivo mientras el componente exista.
 * Los totales son una vista previa: los calcula de nuevo el PL/SQL al
 * guardar (fn_valor_estadia y agregar_servicios), que es la fuente de verdad.
 */
@Injectable()
export class BorradorReserva {
  readonly criterio = signal<Criterio | null>(null);
  readonly habitaciones = signal<HabitacionDisponible[]>([]);
  readonly cotizaciones = signal<Cotizacion[]>([]);
  readonly cliente = signal<Cliente | null>(null);
  readonly servicios = signal<LineaServicio[]>([]);
  readonly metodoPago = signal<MetodoPago>('PSE');
  /** true: sp_reservar_y_pagar (CONFIRMADA); false: sp_crear_reserva (PENDIENTE, sin pago). */
  readonly conPago = signal(true);

  readonly alojamiento = computed(() => this.habitaciones()[0]?.alojamiento ?? null);
  readonly capacidad = computed(() => this.habitaciones().reduce((s, h) => s + h.capacidadMaxima, 0));
  readonly capacidadSuficiente = computed(() => this.capacidad() >= (this.criterio()?.huespedes ?? 0));

  readonly totalHospedaje = computed(() => this.habitaciones().reduce((s, h) => s + h.valorEstadia, 0));

  /** Porcentaje de temporada del dia de llegada (los servicios se agendan ese dia). */
  readonly pctTemporadaLlegada = computed(() => this.cotizaciones()[0]?.detalle[0]?.porcentaje ?? 0);

  readonly totalServicios = computed(() =>
    this.servicios().reduce((s, l) => s + this.valorLinea(l), 0));

  readonly total = computed(() => this.totalHospedaje() + this.totalServicios());
  readonly anticipoMinimo = computed(() => Math.round((this.total() * PCT_ANTICIPO) / 100));

  /**
   * Valor a pagar. Sugiere el anticipo minimo redondeado a miles y se
   * recalcula cuando cambia el total (al agregar servicios); el usuario
   * puede escribir otro valor.
   */
  readonly valorPago = linkedSignal<number | null>(() => Math.ceil(this.anticipoMinimo() / 1000) * 1000);

  /** Mismo calculo de agregar_servicios: ROUND(ROUND(cant*valor,-2) * (1+pct/100), -2). */
  valorLinea(l: LineaServicio): number {
    if (!l.servicio) return 0;
    return aCentenas(aCentenas(l.cantidad * l.servicio.valorServicio) * (1 + this.pctTemporadaLlegada() / 100));
  }

  alternarHabitacion(h: HabitacionDisponible): void {
    this.habitaciones.update((sel) => {
      if (sel.some((x) => x.idHabitacion === h.idHabitacion)) {
        return sel.filter((x) => x.idHabitacion !== h.idHabitacion);
      }
      // Una reserva es de un solo alojamiento (regla -20045 de sp_crear_reserva).
      const mismoAlojamiento = sel.filter((x) => x.idAlojamiento === h.idAlojamiento);
      return [...mismoAlojamiento, h];
    });
    this.cotizaciones.set([]);
  }

  ponerServicio(servicio: Servicio | undefined, idServicio: number, cantidad: number): void {
    this.servicios.update((ls) => {
      const resto = ls.filter((l) => l.idServicio !== idServicio);
      return cantidad > 0 ? [...resto, { idServicio, cantidad, servicio }] : resto;
    });
  }

  cantidadDe(idServicio: number): number {
    return this.servicios().find((l) => l.idServicio === idServicio)?.cantidad ?? 0;
  }

  pedidoServicios(): ServicioPedido[] {
    return this.servicios().map(({ idServicio, cantidad }) => ({ idServicio, cantidad }));
  }

  reiniciarSeleccion(): void {
    this.habitaciones.set([]);
    this.cotizaciones.set([]);
    this.servicios.set([]);
  }
}
