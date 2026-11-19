import { ChangeDetectionStrategy, Component, inject, input, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { Cliente } from '../../core/api/modelos';
import { PersonasApi } from '../../core/api/personas.api';
import { consulta } from '../../core/util/consulta';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';

/** Busqueda de huespedes por apellido o documento. El criterio queda en la URL para poder volver. */
@Component({
  selector: 'app-huespedes',
  imports: [FormsModule, RouterLink, FechaPipe, AvisoComponent, CargandoComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="pagina">
      <header class="encabezado">
        <div>
          <span class="antetitulo">Huéspedes</span>
          <h1>Directorio de huéspedes</h1>
          <p>Busque por apellido o por número de documento para ver el historial y el estado de cuenta.</p>
        </div>
      </header>

      <form class="tarjeta filtros" (ngSubmit)="buscar()">
        <label class="campo"><span>Buscar por</span>
          <select class="control" name="por" [(ngModel)]="por">
            <option value="apellido">Apellido</option><option value="documento">Documento</option>
          </select>
        </label>
        <label class="campo texto"><span>Texto</span>
          <input class="control" name="t" [(ngModel)]="texto" placeholder="Ej.: Ocampo" minlength="2" required />
        </label>
        <button class="boton" type="submit" [disabled]="texto().trim().length < 2">
          <span class="material-symbols-rounded" aria-hidden="true">search</span>Buscar
        </button>
      </form>

      @if (clientes.cargando()) { <app-cargando [filas]="6" /> }
      @else if (clientes.error(); as e) { <app-aviso [error]="e" /> }
      @else if (clientes.datos(); as lista) {
        @if (lista.length) {
          <div class="tabla-contenedor">
            <table class="tabla">
              <thead><tr><th>Huésped</th><th>Documento</th><th>Correo</th><th>Teléfono</th><th>Registro</th></tr></thead>
              <tbody>
                @for (c of lista; track c.idCliente) {
                  <tr class="clic" (click)="abrir(c)" (keydown.enter)="abrir(c)" tabindex="0">
                    <td><a [routerLink]="['/huespedes', c.idCliente]" (click)="$event.stopPropagation()">{{ c.nombres }} {{ c.apellidos }}</a></td>
                    <td>{{ c.tipoDocumento }} {{ c.numeroDocumento }}</td>
                    <td>{{ c.correoElectronico }}</td>
                    <td>{{ c.telefono ?? '—' }}</td>
                    <td>{{ c.fechaRegistro | fecha }}</td>
                  </tr>
                }
              </tbody>
            </table>
          </div>
          @if (lista.length === 50) { <p class="muted">Se muestran los primeros 50. Refine la búsqueda.</p> }
        } @else {
          <app-vacio icono="person_off" titulo="Sin coincidencias" />
        }
      } @else {
        <app-vacio icono="groups" titulo="Escriba un apellido para empezar" texto="Por ejemplo: Restrepo, Ocampo, Duque o Giraldo." />
      }
    </section>`,
  styles: `.texto { max-width: 360px !important; flex: 2 1 240px !important; }`,
})
export class HuespedesComponent implements OnInit {
  private readonly api = inject(PersonasApi);
  private readonly router = inject(Router);

  /** ?apellido= o ?documento= */
  readonly apellido = input<string>();
  readonly documento = input<string>();

  protected readonly por = signal<'apellido' | 'documento'>('apellido');
  protected readonly texto = signal('');
  protected readonly clientes = consulta<Cliente[]>();

  ngOnInit(): void {
    const doc = this.documento();
    const ape = this.apellido();
    if (doc || ape) {
      this.por.set(doc ? 'documento' : 'apellido');
      this.texto.set(doc ?? ape ?? '');
      this.consultar();
    }
  }

  protected buscar(): void {
    this.router.navigate([], { queryParams: { [this.por()]: this.texto().trim() }, replaceUrl: true });
    this.consultar();
  }

  private consultar(): void {
    const t = this.texto().trim();
    this.clientes.ejecutar(this.api.buscarClientes(this.por() === 'apellido' ? { apellido: t } : { documento: t }));
  }

  protected abrir(c: Cliente): void {
    this.router.navigate(['/huespedes', c.idCliente]);
  }
}
