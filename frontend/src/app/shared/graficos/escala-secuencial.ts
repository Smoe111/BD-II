/**
 * Escala secuencial de un solo tono (verde cafetal, claro -> oscuro) para el
 * mapa de calor. Devuelve fondo y color de texto con contraste suficiente.
 */
const PASOS = ['#ecf5ef', '#d3e9db', '#a9d3b8', '#74b58d', '#3f9566', '#1f7a4d', '#17633e', '#114c30'];

export function colorSecuencial(valor: number, maximo: number): { fondo: string; texto: string } {
  if (maximo <= 0 || valor <= 0) return { fondo: '#fffdf9', texto: 'var(--cafe-500)' };
  const i = Math.min(PASOS.length - 1, Math.floor((valor / maximo) * (PASOS.length - 1) + 0.5));
  return { fondo: PASOS[i], texto: i >= 4 ? '#fff' : 'var(--cafe-900)' };
}

export const PASOS_SECUENCIALES = PASOS;
