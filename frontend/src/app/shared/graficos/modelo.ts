/** Un punto de un grafico de una sola serie. */
export interface Punto {
  /** Texto corto bajo la barra (eje). */
  etiqueta: string;
  valor: number;
  /** Titulo del tooltip; si falta se usa la etiqueta. */
  titulo?: string;
  /** Lineas extra del tooltip. */
  detalle?: string[];
  /** Marca la barra con el color de enfasis (p. ej. la seleccionada). */
  resaltado?: boolean;
}

/** Valores "redondos" para las lineas guia del eje. */
export function escala(maximo: number, pasos = 4): number[] {
  if (maximo <= 0) return [0];
  const bruto = maximo / pasos;
  const magnitud = 10 ** Math.floor(Math.log10(bruto));
  const paso = [1, 2, 2.5, 5, 10].map((f) => f * magnitud).find((p) => p >= bruto) ?? bruto;
  return Array.from({ length: Math.ceil(maximo / paso) + 1 }, (_, i) => i * paso);
}
