import { FechaIso } from '../api/modelos';

/** Fecha local en formato AAAA-MM-DD (sin pasar por UTC, que en Colombia corre el dia). */
export function hoyIso(base: Date = new Date()): FechaIso {
  const y = base.getFullYear();
  const m = String(base.getMonth() + 1).padStart(2, '0');
  const d = String(base.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function sumarDias(fecha: FechaIso, dias: number): FechaIso {
  const [y, m, d] = fecha.split('-').map(Number);
  return hoyIso(new Date(y, m - 1, d + dias));
}

/** Noches entre dos fechas ISO (checkout - checkin). */
export function noches(checkin: FechaIso, checkout: FechaIso): number {
  const a = Date.UTC(...partes(checkin));
  const b = Date.UTC(...partes(checkout));
  return Math.round((b - a) / 86_400_000);
}

function partes(f: FechaIso): [number, number, number] {
  const [y, m, d] = f.slice(0, 10).split('-').map(Number);
  return [y, m - 1, d];
}
