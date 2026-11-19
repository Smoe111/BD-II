import { FechaPipe, aFecha } from './fecha.pipe';
import { PesosPipe } from './pesos.pipe';

const limpio = (s: string) => s.replace(/\s/g, ' ');

describe('PesosPipe', () => {
  const pipe = new PesosPipe();

  it('formatea pesos colombianos sin decimales', () => {
    expect(limpio(pipe.transform(1438200))).toBe('$ 1.438.200');
  });

  it('usa millones en notacion compacta', () => {
    expect(pipe.transform(23_006_931_300, 'compacto')).toBe('$ 23.007 M');
    expect(pipe.transform(919_559_250, 'compacto')).toBe('$ 919,6 M');
    expect(pipe.transform(75_000, 'compacto')).toBe('$ 75 mil');
  });

  it('muestra guion para valores ausentes', () => {
    expect(pipe.transform(null)).toBe('—');
    expect(pipe.transform(undefined)).toBe('—');
  });
});

describe('FechaPipe', () => {
  it('interpreta AAAA-MM-DD como fecha local (no corre el dia en Colombia)', () => {
    const f = aFecha('2026-12-18');
    expect([f.getFullYear(), f.getMonth(), f.getDate()]).toEqual([2026, 11, 18]);
  });

  it('formatea en espanol', () => {
    expect(new FechaPipe().transform('2026-12-18')).toBe('18 de dic de 2026');
  });
});
