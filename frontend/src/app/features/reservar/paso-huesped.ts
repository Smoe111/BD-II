import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Cliente } from '../../core/api/modelos';
import { PersonasApi } from '../../core/api/personas.api';
import { consulta } from '../../core/util/consulta';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';
import { BorradorReserva } from './borrador.store';

/** Paso 2: elegir el huesped titular (GET /api/clientes). */
@Component({
  selector: 'app-paso-huesped',
  imports: [FormsModule, AvisoComponent, CargandoComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <form class="tarjeta buscador" (ngSubmit)="buscar()">
      <div class="tipo" role="radiogroup" aria-label="Buscar por">
        <label><input type="radio" name="por" value="apellido" [(ngModel)]="por" /> Apellido</label>
        <label><input type="radio" name="por" value="documento" [(ngModel)]="por" /> Documento</label>
      </div>
      <label class="campo">
        <span class="sr-only">Texto a buscar</span>
        <input class="control" name="texto" [(ngModel)]="texto" required minlength="2"
               [placeholder]="por() === 'apellido' ? 'Ej.: Restrepo, Ocampo, Duque…' : 'Número de documento'" />
      </label>
      <button class="boton" type="submit" [disabled]="texto().trim().length < 2">
        <span class="material-symbols-rounded" aria-hidden="true">person_search</span>Buscar huésped
      </button>
    </form>

    @if (borrador.cliente(); as c) {
      <div class="elegido">
        <span class="avatar">{{ c.nombres[0] }}{{ c.apellidos[0] }}</span>
        <div>
          <strong>{{ c.nombres }} {{ c.apellidos }}</strong>
          <small>{{ c.tipoDocumento }} {{ c.numeroDocumento }} · {{ c.correoElectronico }}</small>
        </div>
        <span class="etiqueta ok"><span class="material-symbols-rounded" aria-hidden="true">check</span>Titular</span>
      </div>
    }

    @if (resultados.cargando()) {
      <app-cargando />
    } @else if (resultados.error(); as e) {
      <app-aviso [error]="e" />
    } @else if (resultados.datos(); as lista) {
      @if (lista.length) {
        <ul class="clientes">
          @for (c of lista; track c.idCliente) {
            <li>
              <button type="button" [class.activo]="borrador.cliente()?.idCliente === c.idCliente" (click)="borrador.cliente.set(c)">
                <span class="avatar">{{ c.nombres[0] }}{{ c.apellidos[0] }}</span>
                <span class="datos">
                  <strong>{{ c.nombres }} {{ c.apellidos }}</strong>
                  <small>{{ c.tipoDocumento }} {{ c.numeroDocumento }}</small>
                </span>
                <small class="contacto">{{ c.telefono ?? 'sin teléfono' }}</small>
              </button>
            </li>
          }
        </ul>
      } @else {
        <app-vacio icono="person_off" titulo="Sin coincidencias" texto="Revise el apellido o busque por documento." />
      }
    }`,
  styles: `
    :host { display: grid; gap: 16px; }
    .buscador { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
    .buscador .campo { flex: 1 1 240px; }
    .tipo { display: flex; gap: 14px; font-size: 0.88rem; color: var(--cafe-700); }
    .tipo label { display: flex; gap: 6px; align-items: center; cursor: pointer; }
    .avatar {
      width: 38px; height: 38px; border-radius: 50%; display: grid; place-items: center; flex: none;
      background: var(--ambar-100); color: var(--ambar-700); font-weight: 700; font-size: 0.85rem;
    }
    .elegido {
      display: flex; gap: 12px; align-items: center; padding: 14px 16px; border-radius: var(--radio-m);
      background: var(--verde-50); border: 1px solid var(--verde-200);
      div { flex: 1; display: grid; } small { color: var(--cafe-600); }
    }
    .clientes { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); }
    .clientes button {
      width: 100%; display: flex; gap: 12px; align-items: center; text-align: left; font: inherit; color: inherit;
      padding: 10px 12px; border-radius: var(--radio-s); border: 1px solid var(--crema-300); background: #fff; cursor: pointer;
      &:hover { border-color: var(--verde-300); }
      &.activo { border-color: var(--verde-500); background: var(--verde-50); }
    }
    .datos { flex: 1; display: grid; min-width: 0; }
    .datos small, .contacto { color: var(--cafe-600); font-size: 0.78rem; }
  `,
})
export class PasoHuespedComponent {
  private readonly personas = inject(PersonasApi);
  protected readonly borrador = inject(BorradorReserva);

  protected readonly por = signal<'apellido' | 'documento'>('apellido');
  protected readonly texto = signal('');
  protected readonly resultados = consulta<Cliente[]>();

  protected buscar(): void {
    const t = this.texto().trim();
    if (t.length < 2) return;
    this.resultados.ejecutar(this.personas.buscarClientes(this.por() === 'apellido' ? { apellido: t } : { documento: t }));
  }
}
