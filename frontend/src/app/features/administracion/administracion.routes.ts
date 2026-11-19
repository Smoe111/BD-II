import { Routes } from '@angular/router';

const titulo = (t: string) => `${t} · TurismoUQ`;

export const ADMINISTRACION_RUTAS: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'liquidacion' },
  { path: 'liquidacion', title: titulo('Liquidación mensual'), loadComponent: () => import('./liquidacion').then((m) => m.LiquidacionComponent) },
  { path: 'tarifas', title: titulo('Tarifas'), loadComponent: () => import('./tarifas').then((m) => m.TarifasComponent) },
  { path: 'monitor', title: titulo('Monitor'), loadComponent: () => import('./monitor').then((m) => m.MonitorComponent) },
];
