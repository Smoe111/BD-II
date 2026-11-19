import { Pipe, PipeTransform } from '@angular/core';

const CORTA = new Intl.DateTimeFormat('es-CO', { day: 'numeric', month: 'short', year: 'numeric' });
const LARGA = new Intl.DateTimeFormat('es-CO', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
const CON_HORA = new Intl.DateTimeFormat('es-CO', {
  day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
});

/**
 * Fechas ISO de la API en espanol de Colombia. 'AAAA-MM-DD' se interpreta
 * como fecha local (new Date('2026-12-18') seria medianoche UTC y en
 * Colombia mostraria el dia anterior).
 */
@Pipe({ name: 'fecha' })
export class FechaPipe implements PipeTransform {
  transform(valor: string | null | undefined, formato: 'corta' | 'larga' | 'hora' = 'corta'): string {
    if (!valor) return '—';
    const fecha = aFecha(valor);
    if (Number.isNaN(fecha.getTime())) return valor;
    return (formato === 'larga' ? LARGA : formato === 'hora' ? CON_HORA : CORTA).format(fecha);
  }
}

export function aFecha(iso: string): Date {
  if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
    const [y, m, d] = iso.split('-').map(Number);
    return new Date(y, m - 1, d);
  }
  return new Date(iso);
}
