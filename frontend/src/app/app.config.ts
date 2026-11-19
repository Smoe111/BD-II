import { provideHttpClient, withFetch, withInterceptors } from '@angular/common/http';
import { registerLocaleData } from '@angular/common';
import localeEsCo from '@angular/common/locales/es-CO';
import { ApplicationConfig, LOCALE_ID, provideBrowserGlobalErrorListeners } from '@angular/core';
import {
  provideRouter, withComponentInputBinding, withInMemoryScrolling, withViewTransitions,
} from '@angular/router';

import { routes } from './app.routes';
import { erroresInterceptor } from './core/http/errores.interceptor';

// Numeros y fechas de los pipes de Angular en espanol de Colombia (1.234,5).
registerLocaleData(localeEsCo);

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    { provide: LOCALE_ID, useValue: 'es-CO' },
    provideHttpClient(withFetch(), withInterceptors([erroresInterceptor])),
    provideRouter(
      routes,
      withComponentInputBinding(), // :id y query params llegan como input() del componente
      withViewTransitions(),
      withInMemoryScrolling({ scrollPositionRestoration: 'top' }),
    ),
  ],
};
