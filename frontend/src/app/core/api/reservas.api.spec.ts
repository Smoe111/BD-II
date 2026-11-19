import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { ErrorApi } from '../http/error-api';
import { erroresInterceptor } from '../http/errores.interceptor';
import { CatalogoApi } from './catalogo.api';
import { ReservasApi } from './reservas.api';

describe('Servicios HTTP', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(withInterceptors([erroresInterceptor])), provideHttpClientTesting()],
    });
    http = TestBed.inject(HttpTestingController);
  });
  afterEach(() => http.verify());

  it('omite los filtros vacios al buscar disponibilidad', () => {
    TestBed.inject(CatalogoApi)
      .disponibles({ checkin: '2027-02-10', checkout: '2027-02-13', huespedes: 2, municipio: null })
      .subscribe();
    const req = http.expectOne((r) => r.url === '/api/habitaciones/disponibles');
    expect(req.request.params.keys().sort()).toEqual(['checkin', 'checkout', 'huespedes']);
    req.flush([]);
  });

  it('convierte el 409 de Oracle en ErrorApi', () => {
    let error: ErrorApi | undefined;
    TestBed.inject(ReservasApi).crear({
      idCliente: 1, idUsuarioSistema: 1, checkin: '2027-02-10', checkout: '2027-02-13', numHuespedes: 1, habitaciones: [49],
    }).subscribe({ error: (e) => (error = e) });

    const req = http.expectOne('/api/reservas');
    expect(req.request.method).toBe('POST');
    req.flush({ mensaje: 'La habitacion 49 no esta disponible', codigoOracle: 20047 }, { status: 409, statusText: 'Conflict' });

    expect(error).toBeInstanceOf(ErrorApi);
    expect(error?.esConflicto).toBe(true);
    expect(error?.codigoOracle).toBe(20047);
  });

  it('registra un abono con POST /api/reservas/{id}/pagos', () => {
    TestBed.inject(ReservasApi).abonar(25512, { valor: 50000, metodoPago: 'EFECTIVO' }).subscribe();
    const req = http.expectOne('/api/reservas/25512/pagos');
    expect(req.request.method).toBe('POST');
    expect(req.request.body).toEqual({ valor: 50000, metodoPago: 'EFECTIVO' });
    req.flush({});
  });
});
