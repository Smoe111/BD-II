import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

/** Contenedor de los reportes de la Entrega 1: una pestana por consulta. */
@Component({
  selector: 'app-reportes',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="pagina">
      <header class="encabezado">
        <div>
          <span class="antetitulo">Reportes gerenciales</span>
          <h1>Así se mueve el turismo en el Quindío</h1>
          <p>Cada pestaña es una de las consultas analíticas de la Entrega 1 (04_consultas.sql), servida por la API.</p>
        </div>
      </header>
      <nav class="pestanas" aria-label="Reportes">
        @for (p of pestanas; track p.ruta) {
          <a [routerLink]="p.ruta" routerLinkActive="activa" ariaCurrentWhenActive="page">{{ p.texto }}</a>
        }
      </nav>
      <router-outlet />
    </section>`,
})
export class ReportesComponent {
  protected readonly pestanas = [
    { ruta: 'ocupacion', texto: '1 · Ocupación' },
    { ruta: 'ingresos', texto: '2 · Ingresos' },
    { ruta: 'ranking', texto: '3 · Ranking' },
    { ruta: 'tendencia', texto: '4 · Tendencia' },
    { ruta: 'reservas', texto: '5 · Reservas por fechas' },
    { ruta: 'ocupacion-mensual', texto: '6 · Vista materializada' },
    { ruta: 'cartera', texto: '8 · Cartera' },
  ];
}
