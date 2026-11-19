import { ChangeDetectionStrategy, Component, computed, inject, input, linkedSignal, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { CabeceraReserva, METODOS_PAGO, MetodoPago, ResultadoAbono } from '../../core/api/modelos';
import { ReservasApi } from '../../core/api/reservas.api';
import { consulta } from '../../core/util/consulta';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { SalidaPlsqlComponent } from '../../shared/ui/salida-plsql';
import { PCT_ANTICIPO } from '../reservar/borrador.store';

const NOMBRE_METODO: Record<MetodoPago, string> = {
  PSE: 'PSE', TARJETA_CREDITO: 'Tarjeta de crédito', TARJETA_DEBITO: 'Tarjeta débito',
  TRANSFERENCIA: 'Transferencia', EFECTIVO: 'Efectivo',
};

/**
 * Pago total o abono al saldo de una reserva (pkg_transacciones.sp_registrar_abono).
 * Las sugerencias y avisos son solo de ayuda: el PL/SQL valida el saldo, el
 * anticipo de una reserva PENDIENTE y el metodo, con la fila bloqueada (FOR UPDATE).
 */
@Component({
  selector: 'app-registrar-pago',
  imports: [FormsModule, PesosPipe, AvisoComponent, SalidaPlsqlComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="tarjeta">
      <header>
        <div>
          <h2>Registrar pago</h2>
          <p>Pago total o abono al saldo · sp_registrar_abono</p>
        </div>
        @if (reserva().valorPendiente === 0) {
          <span class="etiqueta ok"><span class="material-symbols-rounded" aria-hidden="true">task_alt</span>Pagada en su totalidad</span>
        }
      </header>

      @if (reserva().valorPendiente > 0) {
        <form class="pago" (ngSubmit)="pagar()">
          <label class="campo">
            <span>Método</span>
            <select class="control" name="metodo" [ngModel]="metodo()" (ngModelChange)="metodo.set($event)">
              @for (m of metodos; track m) { <option [value]="m">{{ nombreMetodo[m] }}</option> }
            </select>
          </label>
          <label class="campo">
            <span>Valor</span>
            <input class="control num" type="number" min="1" step="1000" name="valor"
                   [ngModel]="valor()" (ngModelChange)="valor.set($event)" />
          </label>
          <div class="atajos">
            <button type="button" class="boton suave pequeno" (click)="valor.set(reserva().valorPendiente)">
              Saldo total · {{ reserva().valorPendiente | pesos }}
            </button>
            @if (faltaAnticipo() > 0) {
              <button type="button" class="boton suave pequeno" (click)="valor.set(faltaAnticipo())">
                Anticipo {{ pct }} % · {{ faltaAnticipo() | pesos }}
              </button>
            }
          </div>
          <button class="boton acento" type="submit" [disabled]="!valor() || (valor() ?? 0) <= 0 || envio.cargando()">
            <span class="material-symbols-rounded" aria-hidden="true">payments</span>
            {{ (valor() ?? 0) >= reserva().valorPendiente ? 'Pagar saldo' : 'Registrar abono' }}
          </button>
        </form>

        @if (reserva().estado === 'PENDIENTE') {
          <p class="nota"><span class="material-symbols-rounded" aria-hidden="true">info</span>
            La reserva está PENDIENTE: con {{ faltaAnticipo() | pesos }} o más se completa el anticipo y pasa a CONFIRMADA.</p>
        }
        @if ((valor() ?? 0) > reserva().valorPendiente) {
          <p class="nota aviso"><span class="material-symbols-rounded" aria-hidden="true">warning</span>
            Supera el saldo pendiente: la base de datos rechazará el pago (ORA-20050).</p>
        }
      }

      @if (envio.error(); as e) { <app-aviso [error]="e" /> }
      @if (ultimo(); as r) {
        <app-aviso tipo="ok" [texto]="'Pago N.º ' + r.idPago + ' registrado. Saldo pendiente: ' + (r.saldo | pesos)" />
        <app-salida-plsql [lineas]="r.salida" titulo="sp_registrar_abono (DBMS_OUTPUT)" />
      }
    </article>`,
  styles: `
    article { display: grid; gap: 14px; }
    .pago { display: grid; gap: 12px; grid-template-columns: minmax(160px, 1fr) minmax(160px, 1fr) auto; align-items: end; }
    .atajos { grid-column: 1 / -1; display: flex; gap: 8px; flex-wrap: wrap; order: 3; }
    .nota { display: flex; gap: 8px; align-items: center; font-size: 0.84rem; color: var(--info);
      &.aviso { color: var(--aviso); } }
    @media (max-width: 640px) { .pago { grid-template-columns: 1fr; } }
  `,
})
export class RegistrarPagoComponent {
  private readonly api = inject(ReservasApi);

  readonly reserva = input.required<CabeceraReserva>();
  /** Emite el resultado para que la pagina refresque cuenta y pagos. */
  readonly pagado = output<ResultadoAbono>();

  protected readonly metodos = METODOS_PAGO;
  protected readonly nombreMetodo = NOMBRE_METODO;
  protected readonly pct = PCT_ANTICIPO;
  protected readonly metodo = signal<MetodoPago>('EFECTIVO');
  /** Por defecto se propone pagar el saldo completo; se recalcula si cambia la reserva. */
  protected readonly valor = linkedSignal<number | null>(() => this.reserva().valorPendiente);
  protected readonly envio = consulta<ResultadoAbono>();
  protected readonly ultimo = signal<ResultadoAbono | null>(null);

  /** Lo que falta para el anticipo si la reserva sigue PENDIENTE (0 si no aplica). */
  protected readonly faltaAnticipo = computed(() => {
    const r = this.reserva();
    if (r.estado !== 'PENDIENTE') return 0;
    return Math.max(0, Math.ceil((r.valorTotal * PCT_ANTICIPO) / 100 - r.valorPagado));
  });

  protected pagar(): void {
    const valor = this.valor();
    if (!valor || valor <= 0) return;
    this.ultimo.set(null);
    this.envio.ejecutar(this.api.abonar(this.reserva().idReserva, { valor, metodoPago: this.metodo() }), (r) => {
      this.ultimo.set(r);
      this.pagado.emit(r);
    });
  }
}
