import { Pipe, PipeTransform } from '@angular/core';

const COMPLETO = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });
const ENTERO = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 });
const DECIMAL = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 1 });

/**
 * Pesos colombianos: 1438200 -> "$ 1.438.200".
 * 'compacto' expresa en millones, como se lee en Colombia:
 * 28106000000 -> "$ 28.106 M", 919100000 -> "$ 919,1 M", 75000 -> "$ 75 mil".
 */
@Pipe({ name: 'pesos' })
export class PesosPipe implements PipeTransform {
  transform(valor: number | null | undefined, formato: 'completo' | 'compacto' = 'completo'): string {
    if (valor === null || valor === undefined || Number.isNaN(valor)) return '—';
    if (formato === 'completo') return COMPLETO.format(valor);
    const abs = Math.abs(valor);
    if (abs >= 1e9) return `$ ${ENTERO.format(valor / 1e6)} M`;
    if (abs >= 1e6) return `$ ${DECIMAL.format(valor / 1e6)} M`;
    if (abs >= 1e3) return `$ ${ENTERO.format(valor / 1e3)} mil`;
    return COMPLETO.format(valor);
  }
}
