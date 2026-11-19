import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { catchError, forkJoin, map, Observable, of, switchMap, throwError, timer } from 'rxjs';
import { AdministracionApi } from '../../core/api/administracion.api';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { Bloqueo, LogTransaccion } from '../../core/api/modelos';
import { ReservasApi } from '../../core/api/reservas.api';
import { OperadorStore } from '../../core/estado/operador.store';
import { ErrorApi } from '../../core/http/error-api';
import { consulta } from '../../core/util/consulta';
import { hoyIso, sumarDias } from '../../core/util/fechas';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';

/** Resultado de una de las dos solicitudes simultaneas. */
interface Intento { cliente: number; ok: boolean; texto: string; idReserva?: number; codigo?: number | null; }
interface Carrera { habitacion: string; intentos: Intento[]; }

/**
 * Monitoreo de la Entrega 3: sesiones y bloqueos (V_MONITOR_BLOQUEOS),
 * bitacora de transacciones (LOG_TRANSACCION) y una prueba de
 * concurrencia con dos reservas simultaneas sobre la misma habitacion.
 */
@Component({
  selector: 'app-monitor',
  imports: [FormsModule, RouterLink, FechaPipe, AvisoComponent, CargandoComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './monitor.html',
  styleUrl: './monitor.scss',
})
export class MonitorComponent {
  private readonly api = inject(AdministracionApi);
  private readonly catalogo = inject(CatalogoApi);
  private readonly reservas = inject(ReservasApi);
  private readonly operador = inject(OperadorStore).operador;

  protected readonly bloqueos = consulta<Bloqueo[]>();
  protected readonly bitacora = consulta<LogTransaccion[]>();
  protected readonly carrera = consulta<Carrera>();
  protected readonly enVivo = signal(true);

  protected readonly checkin = signal(sumarDias(hoyIso(), 120));
  protected readonly checkout = signal(sumarDias(hoyIso(), 122));
  protected readonly clienteA = signal(40);
  protected readonly clienteB = signal(41);

  protected readonly bloqueadas = computed(() => (this.bloqueos.datos() ?? []).filter((b) => b.bloqueadaPor !== null));

  constructor() {
    this.vigilar();
    this.bitacora.ejecutar(this.api.logTransacciones(30));
  }

  /** Consulta la vista de bloqueos cada 3 s mientras el modo en vivo este activo. */
  protected vigilar(): void {
    const fuente = this.enVivo()
      ? timer(0, 3000).pipe(switchMap(() => this.api.bloqueos()))
      : this.api.bloqueos();
    this.bloqueos.ejecutar(fuente);
  }

  protected alternarVivo(): void {
    this.enVivo.update((v) => !v);
    this.vigilar();
  }

  protected recargarBitacora(): void {
    this.bitacora.ejecutar(this.api.logTransacciones(30));
  }

  /**
   * Busca una habitacion libre y envia dos POST /api/reservas al mismo
   * tiempo. El SELECT ... FOR UPDATE de sp_crear_reserva serializa las dos
   * sesiones: una crea la reserva y la otra recibe 409.
   */
  protected lanzarCarrera(): void {
    const operador = this.operador();
    if (!operador) return;
    const ci = this.checkin();
    const co = this.checkout();
    const intento = (cliente: number, habitacion: number): Observable<Intento> =>
      this.reservas.crear({
        idCliente: cliente, idUsuarioSistema: operador.idUsuarioSistema, checkin: ci, checkout: co,
        numHuespedes: 1, habitaciones: [habitacion],
      }).pipe(
        map((r) => ({ cliente, ok: true, idReserva: r.reserva.idReserva, texto: `Reserva ${r.reserva.idReserva} creada` })),
        catchError((e: unknown) => {
          const err = ErrorApi.desde(e);
          return of({ cliente, ok: false, texto: err.message, codigo: err.codigoOracle });
        }),
      );

    this.carrera.ejecutar(this.catalogo.disponibles({ checkin: ci, checkout: co, huespedes: 1 }).pipe(
      switchMap((libres) => {
        const h = libres[0];
        if (!h) return throwError(() => new ErrorApi(404, 'No hay habitaciones libres en esas fechas.'));
        return forkJoin([intento(this.clienteA(), h.idHabitacion), intento(this.clienteB(), h.idHabitacion)]).pipe(
          map((intentos) => ({ habitacion: `${h.alojamiento} · N.º ${h.numeroHabitacion}`, intentos })),
        );
      }),
    ), () => this.recargarBitacora());
  }
}
