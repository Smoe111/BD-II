import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { filter } from 'rxjs';
import { OperadorStore } from '../core/estado/operador.store';

interface Enlace { ruta: string; texto: string; icono: string; exacto?: boolean; }
interface Grupo { titulo: string; enlaces: Enlace[]; }

/** Estructura general: menu lateral, barra superior con el funcionario en turno y el contenido. */
@Component({
  selector: 'app-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './shell.html',
  styleUrl: './shell.scss',
})
export class ShellComponent {
  protected readonly operadores = inject(OperadorStore);
  protected readonly menuAbierto = signal(false);

  protected readonly grupos: Grupo[] = [
    {
      titulo: 'Recepción',
      enlaces: [
        { ruta: '/', texto: 'Panel', icono: 'space_dashboard', exacto: true },
        { ruta: '/reservar', texto: 'Nueva reserva', icono: 'add_circle' },
        { ruta: '/operacion', texto: 'Operación del día', icono: 'concierge' },
        { ruta: '/huespedes', texto: 'Huéspedes', icono: 'group' },
        { ruta: '/destinos', texto: 'Destinos y alojamientos', icono: 'landscape' },
      ],
    },
    {
      titulo: 'Gerencia',
      enlaces: [
        { ruta: '/reportes', texto: 'Reportes', icono: 'monitoring' },
        { ruta: '/administracion/liquidacion', texto: 'Liquidación mensual', icono: 'request_quote' },
        { ruta: '/administracion/tarifas', texto: 'Tarifas y auditoría', icono: 'sell' },
        { ruta: '/administracion/monitor', texto: 'Monitor de transacciones', icono: 'lan' },
      ],
    },
  ];

  private readonly router = inject(Router);

  constructor() {
    // En pantallas pequenas el menu se cierra al navegar.
    this.router.events.pipe(filter((e) => e instanceof NavigationEnd), takeUntilDestroyed())
      .subscribe(() => this.menuAbierto.set(false));
  }

  /** Abre el detalle de una reserva por su numero (desde ahi se registran pagos). */
  protected buscarReserva(evento: Event, campo: HTMLInputElement): void {
    evento.preventDefault();
    const id = Number(campo.value);
    if (!Number.isInteger(id) || id <= 0) return;
    this.router.navigate(['/reservas', id]);
    campo.value = '';
    campo.blur();
  }

  protected cambiarOperador(evento: Event): void {
    this.operadores.seleccionar(Number((evento.target as HTMLSelectElement).value));
  }
}
