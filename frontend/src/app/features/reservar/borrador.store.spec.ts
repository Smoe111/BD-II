import { Cotizacion, HabitacionDisponible, Servicio } from '../../core/api/modelos';
import { BorradorReserva } from './borrador.store';

const habitacion = (id: number, alojamiento: number, capacidad: number, valor: number): HabitacionDisponible => ({
  idHabitacion: id, numeroHabitacion: String(100 + id), idAlojamiento: alojamiento, alojamiento: `A${alojamiento}`,
  municipio: 'Salento', tipoHabitacion: 'Doble', capacidadMaxima: capacidad, valorNoche: 100000, valorEstadia: valor,
});

describe('BorradorReserva', () => {
  let b: BorradorReserva;
  beforeEach(() => {
    b = new BorradorReserva();
    b.criterio.set({ checkin: '2027-02-10', checkout: '2027-02-13', huespedes: 4, municipio: null });
  });

  it('solo deja habitaciones de un mismo alojamiento (regla -20045)', () => {
    b.alternarHabitacion(habitacion(1, 5, 2, 500000));
    b.alternarHabitacion(habitacion(2, 5, 2, 500000));
    expect(b.habitaciones().map((h) => h.idHabitacion)).toEqual([1, 2]);

    b.alternarHabitacion(habitacion(3, 9, 4, 900000));
    expect(b.habitaciones().map((h) => h.idHabitacion)).toEqual([3]);
  });

  it('valida la capacidad frente a los huespedes', () => {
    b.alternarHabitacion(habitacion(1, 5, 2, 500000));
    expect(b.capacidadSuficiente()).toBe(false);
    b.alternarHabitacion(habitacion(2, 5, 2, 500000));
    expect(b.capacidadSuficiente()).toBe(true);
  });

  it('calcula servicios igual que agregar_servicios y el anticipo del 30 %', () => {
    b.alternarHabitacion(habitacion(1, 5, 4, 726000));
    b.cotizaciones.set([{ detalle: [{ porcentaje: 10 }] } as unknown as Cotizacion]);
    const tour: Servicio = { idServicio: 2, nombre: 'Tour', tipoServicio: 'Tour', valorServicio: 75050 };
    b.ponerServicio(tour, 2, 2);
    // ROUND(2 * 75050, -2) = 150100 ; ROUND(150100 * 1.10, -2) = 165100
    expect(b.totalServicios()).toBe(165100);
    expect(b.total()).toBe(891100);
    expect(b.anticipoMinimo()).toBe(267330);
  });

  it('recalcula el pago sugerido al agregar servicios', () => {
    b.alternarHabitacion(habitacion(1, 5, 4, 891000));
    expect(b.valorPago()).toBe(268000);
    b.ponerServicio({ idServicio: 19, nombre: 'Cena', tipoServicio: 'Alimentacion', valorServicio: 85000 }, 19, 1);
    expect(b.valorPago()).toBe(293000);
  });

  it('envia los servicios como id y cantidad', () => {
    b.ponerServicio(undefined, 999, 1);
    expect(b.pedidoServicios()).toEqual([{ idServicio: 999, cantidad: 1 }]);
    expect(b.totalServicios()).toBe(0);
  });
});
