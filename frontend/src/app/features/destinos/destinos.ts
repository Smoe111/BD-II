import { ChangeDetectionStrategy, Component, computed, effect, inject, input } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { Router, RouterLink } from '@angular/router';
import { catchError, of } from 'rxjs';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { Alojamiento, Municipio, TipoAlojamiento } from '../../core/api/modelos';
import { consulta } from '../../core/util/consulta';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';

/** Icono por tipo de alojamiento del catalogo. */
// 'ecohotel' va antes que 'hotel' porque se busca por coincidencia parcial.
const ICONO_TIPO: Record<string, string> = {
  ecohotel: 'eco', hotel: 'apartment', finca: 'cottage', glamping: 'camping', hostal: 'single_bed',
};

/** Catalogo de destinos: municipios del Quindio y sus alojamientos (filtros en la URL). */
@Component({
  selector: 'app-destinos',
  imports: [RouterLink, AvisoComponent, CargandoComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './destinos.html',
  styleUrl: './destinos.scss',
})
export class DestinosComponent {
  private readonly catalogo = inject(CatalogoApi);
  private readonly router = inject(Router);

  readonly municipio = input<string>();
  readonly tipo = input<string>();

  protected readonly municipios = toSignal(this.catalogo.municipios().pipe(catchError(() => of([] as Municipio[]))), { initialValue: [] });
  protected readonly tipos = toSignal(this.catalogo.tiposAlojamiento().pipe(catchError(() => of([] as TipoAlojamiento[]))), { initialValue: [] });
  protected readonly alojamientos = consulta<Alojamiento[]>();

  protected readonly idMunicipio = computed(() => Number(this.municipio()) || null);
  protected readonly idTipo = computed(() => Number(this.tipo()) || null);
  protected readonly nombreMunicipio = computed(() =>
    this.municipios().find((m) => m.idMunicipio === this.idMunicipio())?.nombre ?? 'Todo el Quindío');

  constructor() {
    effect(() => this.alojamientos.ejecutar(this.catalogo.alojamientos(this.idMunicipio(), this.idTipo())));
  }

  protected filtrar(cambios: { municipio?: number | null; tipo?: number | null }): void {
    this.router.navigate([], { queryParams: cambios, queryParamsHandling: 'merge' });
  }

  protected icono(tipo: string): string {
    const clave = Object.keys(ICONO_TIPO).find((k) => tipo.toLowerCase().includes(k));
    return clave ? ICONO_TIPO[clave] : 'holiday_village';
  }

  protected estrellas(n: number): number[] {
    return Array.from({ length: Math.max(0, Math.min(5, n ?? 0)) });
  }
}
