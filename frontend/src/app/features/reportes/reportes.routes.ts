import { Routes } from '@angular/router';

const titulo = (t: string) => `${t} · Reportes · TurismoUQ`;

export const REPORTES_RUTAS: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'ocupacion' },
  { path: 'ocupacion', title: titulo('Ocupación'), loadComponent: () => import('./ocupacion').then((m) => m.ReporteOcupacionComponent) },
  { path: 'ingresos', title: titulo('Ingresos'), loadComponent: () => import('./ingresos').then((m) => m.ReporteIngresosComponent) },
  { path: 'ranking', title: titulo('Ranking'), loadComponent: () => import('./ranking').then((m) => m.ReporteRankingComponent) },
  { path: 'tendencia', title: titulo('Tendencia'), loadComponent: () => import('./tendencia').then((m) => m.ReporteTendenciaComponent) },
  { path: 'reservas', title: titulo('Reservas por fechas'), loadComponent: () => import('./reservas-rango').then((m) => m.ReporteReservasComponent) },
  { path: 'ocupacion-mensual', title: titulo('Vista materializada'), loadComponent: () => import('./vista-materializada').then((m) => m.ReporteVistaComponent) },
  { path: 'cartera', title: titulo('Cartera'), loadComponent: () => import('./cartera').then((m) => m.ReporteCarteraComponent) },
];
