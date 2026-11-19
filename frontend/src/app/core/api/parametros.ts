import { HttpParams } from '@angular/common/http';

/** Construye HttpParams omitiendo null, undefined y cadenas vacias. */
export function parametros(valores: Record<string, string | number | null | undefined>): HttpParams {
  let p = new HttpParams();
  for (const [clave, valor] of Object.entries(valores)) {
    if (valor !== null && valor !== undefined && valor !== '') {
      p = p.set(clave, String(valor));
    }
  }
  return p;
}
