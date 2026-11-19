import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AdministracionApi } from '../../core/api/administracion.api';
import { AuditoriaTarifa, Tarifa } from '../../core/api/modelos';
import { OperadorStore } from '../../core/estado/operador.store';
import { consulta } from '../../core/util/consulta';
import { FechaPipe } from '../../shared/pipes/fecha.pipe';
import { PesosPipe } from '../../shared/pipes/pesos.pipe';
import { AvisoComponent } from '../../shared/ui/aviso';
import { CargandoComponent } from '../../shared/ui/cargando';

/**
 * Tarifas base y su auditoria. El cambio lo registra el trigger
 * trg_tarifa_auditoria; el usuario de la aplicacion le llega por CLIENT_INFO.
 */
@Component({
  selector: 'app-tarifas',
  imports: [FormsModule, DecimalPipe, PesosPipe, FechaPipe, AvisoComponent, CargandoComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './tarifas.html',
  styleUrl: './tarifas.scss',
})
export class TarifasComponent {
  private readonly api = inject(AdministracionApi);
  protected readonly operador = inject(OperadorStore).operador;

  protected readonly tarifas = consulta<Tarifa[]>();
  protected readonly auditoria = consulta<AuditoriaTarifa[]>();
  protected readonly cambio = consulta<AuditoriaTarifa[]>();

  protected readonly filtro = signal('');
  protected readonly elegida = signal<Tarifa | null>(null);
  protected readonly nuevoValor = signal<number | null>(null);

  protected readonly visibles = computed(() => {
    const f = this.filtro().trim().toLowerCase();
    const ts = this.tarifas.datos() ?? [];
    return f ? ts.filter((t) => t.nombre.toLowerCase().includes(f)) : ts;
  });
  protected readonly variacion = computed(() => {
    const t = this.elegida();
    const v = this.nuevoValor();
    return t && v ? ((v - t.valor) / t.valor) * 100 : 0;
  });

  constructor() {
    this.tarifas.ejecutar(this.api.tarifas());
  }

  protected elegir(t: Tarifa): void {
    this.elegida.set(t);
    this.nuevoValor.set(t.valor);
    this.cambio.limpiar();
    this.auditoria.ejecutar(this.api.auditoriaTarifa(t.idTarifa));
  }

  protected guardar(): void {
    const t = this.elegida();
    const v = this.nuevoValor();
    const usuario = this.operador()?.usuario;
    if (!t || !v || v <= 0 || v === t.valor || !usuario) return;
    this.cambio.ejecutar(this.api.cambiarTarifa(t.idTarifa, v, usuario), () => {
      this.elegida.set({ ...t, valor: v });
      this.auditoria.ejecutar(this.api.auditoriaTarifa(t.idTarifa));
      this.tarifas.ejecutar(this.api.tarifas());
    });
  }
}
