import { ChangeDetectionStrategy, Component, OnInit, computed, inject, input } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { AbstractControl, FormBuilder, ReactiveFormsModule, ValidationErrors, Validators } from '@angular/forms';
import { catchError, of } from 'rxjs';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { HabitacionDisponible, Municipio } from '../../core/api/modelos';
import { consulta } from '../../core/util/consulta';
import { hoyIso, noches, sumarDias } from '../../core/util/fechas';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { VacioComponent } from '../../shared/ui/vacio';
import { BorradorReserva } from './borrador.store';

interface GrupoAlojamiento { idAlojamiento: number; alojamiento: string; municipio: string; habitaciones: HabitacionDisponible[]; }

/** checkout debe ser posterior a checkin (misma regla -20040 de sp_crear_reserva). */
function rangoValido(g: AbstractControl): ValidationErrors | null {
  const { checkin, checkout } = g.value as { checkin: string; checkout: string };
  return checkin && checkout && checkout <= checkin ? { rango: true } : null;
}

/** Paso 1: buscar habitaciones libres (GET /api/habitaciones/disponibles) y elegirlas. */
@Component({
  selector: 'app-paso-habitaciones',
  imports: [ReactiveFormsModule, PesosPipe, AvisoComponent, CargandoComponent, VacioComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './paso-habitaciones.html',
  styleUrl: './paso-habitaciones.scss',
})
export class PasoHabitacionesComponent implements OnInit {
  private readonly catalogo = inject(CatalogoApi);
  protected readonly borrador = inject(BorradorReserva);

  // Valores iniciales opcionales (llegan como query params desde el panel)
  readonly checkin = input<string>();
  readonly checkout = input<string>();
  readonly huespedes = input<string>();
  readonly municipio = input<string>();

  protected readonly hoy = hoyIso();
  protected readonly municipios = toSignal(
    this.catalogo.municipios().pipe(catchError(() => of([] as Municipio[]))), { initialValue: [] });

  protected readonly form = inject(FormBuilder).nonNullable.group({
    checkin: [sumarDias(this.hoy, 14), Validators.required],
    checkout: [sumarDias(this.hoy, 17), Validators.required],
    huespedes: [2, [Validators.required, Validators.min(1), Validators.max(60)]],
    municipio: [0],
  }, { validators: rangoValido });

  protected readonly disponibles = consulta<HabitacionDisponible[]>();

  protected readonly grupos = computed<GrupoAlojamiento[]>(() => {
    const mapa = new Map<number, GrupoAlojamiento>();
    for (const h of this.disponibles.datos() ?? []) {
      const g = mapa.get(h.idAlojamiento)
        ?? { idAlojamiento: h.idAlojamiento, alojamiento: h.alojamiento, municipio: h.municipio, habitaciones: [] };
      g.habitaciones.push(h);
      mapa.set(h.idAlojamiento, g);
    }
    return [...mapa.values()];
  });

  protected readonly noches = computed(() => {
    const c = this.borrador.criterio();
    return c ? noches(c.checkin, c.checkout) : 0;
  });

  ngOnInit(): void {
    const previo = this.borrador.criterio();
    if (previo) {
      // Volviendo desde otro paso: se conserva la busqueda.
      this.form.setValue({ ...previo, municipio: previo.municipio ?? 0 });
      this.buscar(false);
      return;
    }
    if (this.checkin() && this.checkout()) {
      this.form.patchValue({
        checkin: this.checkin(), checkout: this.checkout(),
        huespedes: Number(this.huespedes() ?? 2), municipio: Number(this.municipio() ?? 0),
      });
      this.buscar();
    }
  }

  protected buscar(reiniciar = true): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }
    const v = this.form.getRawValue();
    const criterio = { checkin: v.checkin, checkout: v.checkout, huespedes: v.huespedes, municipio: v.municipio || null };
    if (reiniciar) this.borrador.reiniciarSeleccion();
    this.borrador.criterio.set(criterio);
    // Se piden habitaciones de cualquier capacidad: varias pequenas pueden sumar los huespedes.
    this.disponibles.ejecutar(this.catalogo.disponibles({
      checkin: criterio.checkin, checkout: criterio.checkout, huespedes: 1, municipio: criterio.municipio,
    }));
  }

  protected seleccionada(h: HabitacionDisponible): boolean {
    return this.borrador.habitaciones().some((x) => x.idHabitacion === h.idHabitacion);
  }
}
