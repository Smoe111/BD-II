import { HttpErrorResponse } from '@angular/common/http';
import { ErrorApi } from './error-api';

describe('ErrorApi', () => {
  it('conserva mensaje, codigo ORA y salida del PL/SQL', () => {
    const http = new HttpErrorResponse({
      status: 400,
      error: {
        estado: 400, mensaje: 'Anticipo insuficiente', codigoOracle: 20053,
        salida: ['[1] Reserva creada', 'ROLLBACK TO sp_inicio'],
      },
    });
    const e = ErrorApi.desde(http);
    expect(e.estado).toBe(400);
    expect(e.message).toBe('Anticipo insuficiente');
    expect(e.codigoOracle).toBe(20053);
    expect(e.salida).toHaveLength(2);
  });

  it('marca el 409 como conflicto', () => {
    expect(ErrorApi.desde(new HttpErrorResponse({ status: 409, error: { mensaje: 'ocupada' } })).esConflicto).toBe(true);
  });

  it('explica cuando no hay conexion con el backend', () => {
    expect(ErrorApi.desde(new HttpErrorResponse({ status: 0 })).message).toContain('8080');
  });
});
