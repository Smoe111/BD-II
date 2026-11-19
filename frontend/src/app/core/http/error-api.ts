import { HttpErrorResponse } from '@angular/common/http';
import { RespuestaError } from '../api/modelos';

/**
 * Error normalizado de la API. Los mensajes de negocio los escribe el
 * PL/SQL (RAISE_APPLICATION_ERROR); aqui solo se conservan junto con el
 * codigo ORA y los pasos (DBMS_OUTPUT) que el procedimiento alcanzo a dar.
 */
export class ErrorApi extends Error {
  constructor(
    readonly estado: number,
    mensaje: string,
    readonly codigoOracle: number | null = null,
    readonly salida: string[] = [],
  ) {
    super(mensaje);
    this.name = 'ErrorApi';
  }

  /** 409: otra reserva u otra sesion ya tiene la habitacion */
  get esConflicto(): boolean {
    return this.estado === 409;
  }

  static desde(err: unknown): ErrorApi {
    if (err instanceof ErrorApi) return err;
    if (err instanceof HttpErrorResponse) {
      if (err.status === 0) {
        return new ErrorApi(0, 'No hay conexión con la API. ¿Está corriendo el backend en el puerto 8080?');
      }
      const cuerpo = err.error as Partial<RespuestaError> | null;
      if (cuerpo && typeof cuerpo === 'object' && cuerpo.mensaje) {
        return new ErrorApi(err.status, cuerpo.mensaje, cuerpo.codigoOracle ?? null, cuerpo.salida ?? []);
      }
      return new ErrorApi(err.status, `Error ${err.status}: ${err.statusText || 'respuesta inesperada'}`);
    }
    return new ErrorApi(-1, err instanceof Error ? err.message : 'Error inesperado');
  }
}
