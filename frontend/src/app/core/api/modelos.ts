/**
 * Contratos de la API REST (ver API.md). Los nombres coinciden con el JSON
 * que devuelve el backend: columnas de Oracle en camelCase.
 * Las fechas llegan como texto ISO: 'AAAA-MM-DD' o 'AAAA-MM-DDTHH:mm:ss'.
 */
export type FechaIso = string;

// ---------------- Catalogo ----------------
export interface Municipio { idMunicipio: number; nombre: string; alojamientos: number; }
export interface TipoAlojamiento { idTipoAlojamiento: number; nombre: string; }

export interface Alojamiento {
  idAlojamiento: number; nombre: string; direccion: string; calificacion: number;
  activo: 'S' | 'N'; idMunicipio: number; municipio: string;
  idTipoAlojamiento: number; tipoAlojamiento: string; habitaciones: number;
}

export interface Habitacion {
  idHabitacion: number; numeroHabitacion: string; activo: 'S' | 'N';
  tipoHabitacion: string; capacidadMaxima: number;
  idTarifa: number; tarifa: string; valorNoche: number;
}

export interface AlojamientoDetalle { alojamiento: Alojamiento; habitaciones: Habitacion[]; }

export interface HabitacionDisponible {
  idHabitacion: number; numeroHabitacion: string; idAlojamiento: number; alojamiento: string;
  municipio: string; tipoHabitacion: string; capacidadMaxima: number;
  valorNoche: number; valorEstadia: number;
}

export interface Servicio { idServicio: number; nombre: string; tipoServicio: string; valorServicio: number; }

export interface Temporada {
  idTemporada: number; nombre: string; descripcion: string; porcentaje: number;
  fechaInicio: FechaIso; fechaFin: FechaIso;
}

export interface TramoTemporada {
  temporada: string; porcentaje: number; desde: FechaIso; hasta: FechaIso;
  noches: number; valorNoche: number; subtotal: number;
}

export interface Cotizacion {
  idHabitacion: number; checkin: FechaIso; checkout: FechaIso; noches: number;
  valorBase: number; valorEstadia: number; detalle: TramoTemporada[];
}

export interface FiltroDisponibilidad {
  checkin: FechaIso; checkout: FechaIso; huespedes: number;
  municipio?: number | null; alojamiento?: number | null;
}

// ---------------- Personas ----------------
export type Rol = 'RECEPCION' | 'ADMIN_ALOJAMIENTO' | 'GERENTE' | 'AUDITOR';
export interface Usuario { idUsuarioSistema: number; usuario: string; rol: Rol; activo: 'S' | 'N'; }

export interface Cliente {
  idCliente: number; tipoDocumento: string; numeroDocumento: string; nombres: string;
  apellidos: string; telefono: string | null; correoElectronico: string;
  fechaNacimiento: FechaIso | null; fechaRegistro: FechaIso; idUsuarioSistema: number | null;
}

export type EstadoReserva = 'PENDIENTE' | 'CONFIRMADA' | 'EN_CURSO' | 'FINALIZADA' | 'CANCELADA';

export interface ReservaResumen {
  idReserva: number; alojamiento: string; municipio: string; fechaCheckin: FechaIso;
  fechaCheckout: FechaIso; estado: EstadoReserva; numHuespedes: number;
  valorTotal: number; valorPagado: number; valorPendiente: number;
}

// ---------------- Reservas ----------------
export const METODOS_PAGO = ['PSE', 'TARJETA_CREDITO', 'TARJETA_DEBITO', 'TRANSFERENCIA', 'EFECTIVO'] as const;
export type MetodoPago = (typeof METODOS_PAGO)[number];

export interface CrearReserva {
  idCliente: number; idUsuarioSistema: number; checkin: FechaIso; checkout: FechaIso;
  numHuespedes: number; habitaciones: number[];
}

export interface ServicioPedido { idServicio: number; cantidad: number; }

export interface ReservarYPagar extends CrearReserva {
  servicios: ServicioPedido[]; valorPago: number; metodoPago: MetodoPago;
}

export interface CabeceraReserva {
  idReserva: number; idCliente: number; cliente: string; registradaPor: string;
  fechaCreacion: FechaIso; fechaCheckin: FechaIso; fechaCheckout: FechaIso; estado: EstadoReserva;
  numHuespedes: number; valorTotal: number; valorPagado: number; valorPendiente: number;
}
export interface HabitacionReservada {
  idHabitacion: number; numeroHabitacion: string; alojamiento: string; municipio: string;
  fechaCheckin: FechaIso; fechaCheckout: FechaIso; valorPrevio: number; valorReserva: number;
}
export interface ServicioReservado {
  idServicio: number; servicio: string; fechaServicio: FechaIso; cantidad: number;
  valorPrevio: number; valorServicio: number;
}
export interface PagoReserva { idPago: number; valor: number; fechaPago: FechaIso; metodoPago: MetodoPago; estado: string; }

export interface ReservaDetalle {
  reserva: CabeceraReserva; habitaciones: HabitacionReservada[];
  servicios: ServicioReservado[]; pagos: PagoReserva[];
}

export type ResultadoTransaccion = 'COMPLETA' | 'ROLLBACK_PARCIAL';
export interface ResultadoReservaPago {
  idReserva: number; idPago: number; resultado: ResultadoTransaccion;
  salida: string[]; reserva: ReservaDetalle;
}

/** POST /api/reservas/{id}/pagos (pkg_transacciones.sp_registrar_abono). */
export interface Abono { valor: number; metodoPago: MetodoPago; }
export interface ResultadoAbono { idPago: number; saldo: number; salida: string[]; reserva: ReservaDetalle; }

// ---------------- Administracion ----------------
export interface Liquidacion {
  idLiquidacion: number; idAlojamiento: number; alojamiento: string; anio: number; mes: number;
  reservas: number; nochesVendidas: number; ingresoHospedaje: number; ingresoServicios: number;
  recaudoCaja: number; pctComision: number; valorComision: number; netoAlojamiento: number;
  fechaProceso: FechaIso;
}
export interface ResultadoLiquidacion { salida: string[]; liquidaciones: Liquidacion[]; }

export interface Tarifa { idTarifa: number; nombre: string; descripcion: string; valor: number; habitaciones: number; }
export interface AuditoriaTarifa {
  idAuditoria: number; idSentencia: number; idTarifa: number; operacion: 'INSERT' | 'UPDATE' | 'DELETE';
  usuarioBd: string; usuarioApp: string | null; fechaCambio: FechaIso;
  valorAnterior: number | null; valorNuevo: number | null;
}

export interface Bloqueo {
  sid: number; serial: number; status: string; sesion: string | null; bloqueadaPor: number | null;
  evento: string; segEsperando: number; tablaEsperada: string | null; sqlId: string | null;
}

export interface LogTransaccion {
  idLog: number; fecha: FechaIso; usuarioBd: string; idCliente: number | null; habitaciones: string | null;
  idReserva: number | null; idPago: number | null;
  resultado: 'COMPLETA' | 'ROLLBACK_PARCIAL' | 'ROLLBACK_TOTAL' | 'SIN_PAGO' | 'ABONO';
  paso: 'RESERVA' | 'SERVICIOS' | 'PAGO' | 'ABONO' | null; codigoError: number | null; mensaje: string | null;
}

// ---------------- Reportes (Entrega 1) ----------------
export const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'] as const;
export type OcupacionMunicipio = { municipio: string } & Record<`${(typeof MESES)[number]}Pct`, number>;

export interface IngresoCubo {
  municipio: string; tipoAlojamiento: string; temporada: string;
  /** GROUPING_ID: 0 = detalle; >0 = algun subtotal; 7 = gran total */
  nivelSubtotal: number; ingresoTotal: number;
}
export interface TopAlojamiento {
  municipio: string; alojamiento: string; totalIngresos: number; ranking: number; pctIngresoMunicipio: number;
}
export interface VariacionMensual {
  anio: number; mes: number; ingresoMes: number; ingresoMesAnterior: number;
  variacionAbsoluta: number; pctVariacion: number | null;
}
export interface ReservaRango {
  idReserva: number; usuario: string; cliente: string; municipio: string; alojamiento: string;
  fechaCheckin: FechaIso; fechaCheckout: FechaIso; valorTotal: number; estado: EstadoReserva;
}
export interface OcupacionMensual {
  idMunicipio: number; municipio: string; anio: number; mes: number;
  totalReservasHabitacion: number; totalIngresoHabitaciones: number;
}
export interface EstadoFinanciero {
  idReserva: number; conceptoPago: 'TOTAL_CONTRATADO' | 'TOTAL_PAGADO' | 'TOTAL_PENDIENTE'; monto: number;
}
export interface CarteraMunicipio {
  municipio: string; cantidadReservas: number; totalFacturado: number; totalRecaudado: number;
  carteraPendiente: number; porcentajeCartera: number;
}
/** Tipo deducido del porcentaje de TEMPORADA: recargo = ALTA, 0 = BAJA, negativo = DESCUENTO. */
export type TipoTemporada = 'ALTA' | 'BAJA' | 'DESCUENTO';
export interface Temporada { nombre: string; porcentaje: number; tipo: TipoTemporada; }
export interface HabitacionTemporada {
  puesto: number; idHabitacion: number; numeroHabitacion: string; idAlojamiento: number;
  alojamiento: string; municipio: string; cantidadReservas: number; ingresoTotal: number;
}

// ---------------- Operacion diaria (Entrega 3) ----------------
export interface Llegada {
  idReserva: number; numHuespedes: number; fechaCheckout: FechaIso; nombres: string;
  apellidos: string; telefono: string | null; valorPendiente: number;
}
export interface CierreCaja { metodoPago: MetodoPago; pagos: number; total: number; }
export interface AgendaServicio { servicio: string; cupos: number; reservas: number; }

// ---------------- Errores ----------------
export interface RespuestaError {
  fecha: FechaIso; estado: number; error: string; mensaje: string;
  codigoOracle: number | null; ruta: string; salida: string[] | null;
}
