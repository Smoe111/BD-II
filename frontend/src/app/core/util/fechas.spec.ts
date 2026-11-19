import { hoyIso, noches, sumarDias } from './fechas';

describe('fechas', () => {
  it('cuenta las noches entre llegada y salida', () => {
    expect(noches('2026-12-29', '2027-01-03')).toBe(5);
  });

  it('suma dias cruzando el fin de anio', () => {
    expect(sumarDias('2026-12-30', 3)).toBe('2027-01-02');
  });

  it('da la fecha local en formato ISO', () => {
    expect(hoyIso(new Date(2026, 10, 12, 23, 30))).toBe('2026-11-12');
  });
});
