import { HttpInterceptorFn } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { ErrorApi } from './error-api';

/** Convierte toda respuesta de error en ErrorApi para que los componentes no lidien con HttpErrorResponse. */
export const erroresInterceptor: HttpInterceptorFn = (req, next) =>
  next(req).pipe(catchError((err: unknown) => throwError(() => ErrorApi.desde(err))));
