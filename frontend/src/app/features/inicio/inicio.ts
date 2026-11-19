import { DecimalPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormBuilder, ReactiveFormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { catchError, of } from 'rxjs';
import { CatalogoApi } from '../../core/api/catalogo.api';
import { CarteraMunicipio, Llegada, Municipio, TopAlojamiento, VariacionMensual } from '../../core/api/modelos';
import { OperacionApi } from '../../core/api/operacion.api';
import { ReportesApi } from '../../core/api/reportes.api';
import { OperadorStore } from '../../core/estado/operador.store';
import { consulta } from '../../core/util/consulta';
import { hoyIso, sumarDias } from '../../core/util/fechas';
import { BarrasHorizontalesComponent } from '../../shared/graficos/barras-horizontales';
import { GraficoColumnasComponent } from '../../shared/graficos/grafico-columnas';
import { Punto } from '../../shared/graficos/modelo';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';
import { KpiComponent } from '../../shared/ui/kpi';

const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const pesos = new PesosPipe();

/** Panel de inicio: buscador rapido, indicadores y resumen de los reportes. */
@Component({
  selector: 'app-inicio',
  imports: [
    ReactiveFormsModule, RouterLink, DecimalPipe, PesosPipe, FechaPipe, KpiComponent, AvisoComponent, CargandoComponent,
    GraficoColumnasComponent, BarrasHorizontalesComponent,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './inicio.html',
  styleUrl: './inicio.scss',
})
export class InicioComponent {
  private readonly router = inject(Router);
  private readonly reportes = inject(ReportesApi);
  protected readonly operador = inject(OperadorStore).operador;
  protected readonly hoy = hoyIso();
  protected readonly formatoCompacto = (v: number) => pesos.transform(v, 'compacto');
  protected readonly formatoPesos = (v: number) => pesos.transform(v);

  protected readonly municipios = toSignal(
    inject(CatalogoApi).municipios().pipe(catchError(() => of([] as Municipio[]))), { initialValue: [] });

  protected readonly busqueda = inject(FormBuilder).nonNullable.group({
    checkin: sumarDias(this.hoy, 14),
    checkout: sumarDias(this.hoy, 16),
    huespedes: 2,
    municipio: 0,
  });

  protected readonly cartera = consulta<CarteraMunicipio[]>();
  protected readonly variacion = consulta<VariacionMensual[]>();
  protected readonly top = consulta<TopAlojamiento[]>();
  protected readonly llegadas = consulta<Llegada[]>();

  protected readonly totales = computed(() => {
    const filas = this.cartera.datos() ?? [];
    const facturado = filas.reduce((s, f) => s + f.totalFacturado, 0);
    const recaudado = filas.reduce((s, f) => s + f.totalRecaudado, 0);
    const reservas = filas.reduce((s, f) => s + f.cantidadReservas, 0);
    return { facturado, recaudado, pendiente: facturado - recaudado, reservas, pct: facturado ? ((facturado - recaudado) / facturado) * 100 : 0 };
  });

  /** Ultimos 18 meses de la consulta 4 (LAG); se resalta el mes en curso. */
  protected readonly meses = computed<Punto[]>(() => {
    const actual = this.hoy.slice(0, 7);
    return (this.variacion.datos() ?? []).slice(-18).map((v) => {
      const clave = `${v.anio}-${String(v.mes).padStart(2, '0')}`;
      return {
        etiqueta: `${MES[v.mes - 1]} ${String(v.anio).slice(2)}`,
        titulo: `${MES[v.mes - 1]} ${v.anio}`,
        valor: v.ingresoMes,
        resaltado: clave === actual,
        detalle: v.pctVariacion === null ? [] : [`${v.pctVariacion > 0 ? '+' : ''}${v.pctVariacion} % frente al mes anterior`],
      };
    });
  });

  protected readonly mesActual = computed(() => {
    const actual = this.hoy.slice(0, 7);
    return (this.variacion.datos() ?? []).find((v) => `${v.anio}-${String(v.mes).padStart(2, '0')}` === actual);
  });

  /** Lider de cada municipio (ranking = 1 de la consulta 3). */
  protected readonly lideres = computed<Punto[]>(() =>
    (this.top.datos() ?? []).filter((t) => t.ranking === 1)
      .sort((a, b) => b.totalIngresos - a.totalIngresos)
      .map((t) => ({ etiqueta: `${t.alojamiento} · ${t.municipio}`, valor: t.totalIngresos,
        detalle: [`${t.pctIngresoMunicipio} % del ingreso de ${t.municipio}`] })));

  constructor() {
    const operacion = inject(OperacionApi);
    this.cartera.ejecutar(this.reportes.cartera());
    this.variacion.ejecutar(this.reportes.variacionMensual());
    this.top.ejecutar(this.reportes.topAlojamientos(1));
    this.llegadas.ejecutar(operacion.llegadas(this.hoy));
  }

  protected buscar(): void {
    const v = this.busqueda.getRawValue();
    this.router.navigate(['/reservar'], {
      queryParams: { checkin: v.checkin, checkout: v.checkout, huespedes: v.huespedes, municipio: v.municipio || null },
    });
  }
}
