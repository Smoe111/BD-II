import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { VacioComponent } from '../../shared/ui/vacio';

@Component({
  selector: 'app-no-encontrado',
  imports: [RouterLink, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <app-vacio icono="explore_off" titulo="Esta página se perdió entre los cafetales" texto="La dirección no existe.">
      <a class="boton" routerLink="/">Volver al panel</a>
    </app-vacio>`,
})
export class NoEncontradoComponent {}
