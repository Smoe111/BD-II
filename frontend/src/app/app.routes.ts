import { Routes } from '@angular/router';
import { ShellComponent } from './layout/shell';

const titulo = (t: string) => `${t} · TurismoUQ`;

/** Todas las pantallas se cargan bajo demanda (lazy loading). */
export const routes: Routes = [
  {
    path: '',
    component: ShellComponent,
    children: [
      { path: '', title: titulo('Panel'), loadComponent: () => import('./features/inicio/inicio').then((m) => m.InicioComponent) },
      { path: 'reservar', title: titulo('Nueva reserva'), loadComponent: () => import('./features/reservar/reservar').then((m) => m.ReservarComponent) },
      { path: 'reservas/:id', title: titulo('Reserva'), loadComponent: () => import('./features/reserva-detalle/reserva-detalle').then((m) => m.ReservaDetalleComponent) },
      { path: 'operacion', title: titulo('Operación del día'), loadComponent: () => import('./features/operacion/operacion').then((m) => m.OperacionComponent) },
      { path: 'huespedes', title: titulo('Huéspedes'), loadComponent: () => import('./features/huespedes/huespedes').then((m) => m.HuespedesComponent) },
      { path: 'huespedes/:id', title: titulo('Huésped'), loadComponent: () => import('./features/huespedes/huesped-detalle').then((m) => m.HuespedDetalleComponent) },
      { path: 'destinos', title: titulo('Destinos'), loadComponent: () => import('./features/destinos/destinos').then((m) => m.DestinosComponent) },
      { path: 'destinos/:id', title: titulo('Alojamiento'), loadComponent: () => import('./features/destinos/alojamiento-detalle').then((m) => m.AlojamientoDetalleComponent) },
      {
        path: 'reportes',
        loadComponent: () => import('./features/reportes/reportes').then((m) => m.ReportesComponent),
        children: [
          { path: '', loadChildren: () => import('./features/reportes/reportes.routes').then((m) => m.REPORTES_RUTAS) },
        ],
      },
      {
        path: 'administracion',
        loadChildren: () => import('./features/administracion/administracion.routes').then((m) => m.ADMINISTRACION_RUTAS),
      },
      { path: '**', title: titulo('No encontrado'), loadComponent: () => import('./features/no-encontrado/no-encontrado').then((m) => m.NoEncontradoComponent) },
    ],
  },
];
