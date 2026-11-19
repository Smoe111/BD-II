package com.uniquindio.turismo.catalogo;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** Registros de solo lectura del catalogo. */
public final class Modelos {

    private Modelos() {
    }

    public record Municipio(Long idMunicipio, String nombre, Integer alojamientos) {
    }

    public record TipoAlojamiento(Long idTipoAlojamiento, String nombre) {
    }

    public record Alojamiento(Long idAlojamiento, String nombre, String direccion, Integer calificacion,
                              String activo, Long idMunicipio, String municipio,
                              Long idTipoAlojamiento, String tipoAlojamiento, Integer habitaciones) {
    }

    public record Habitacion(Long idHabitacion, String numeroHabitacion, String activo,
                             String tipoHabitacion, Integer capacidadMaxima,
                             Long idTarifa, String tarifa, BigDecimal valorNoche) {
    }

    public record AlojamientoDetalle(Alojamiento alojamiento, List<Habitacion> habitaciones) {
    }

    /** Habitacion libre en un rango, con el valor de la estadia ya calculado. */
    public record HabitacionDisponible(Long idHabitacion, String numeroHabitacion, Long idAlojamiento,
                                       String alojamiento, String municipio, String tipoHabitacion,
                                       Integer capacidadMaxima, BigDecimal valorNoche,
                                       BigDecimal valorEstadia) {
    }

    public record Servicio(Long idServicio, String nombre, String tipoServicio, BigDecimal valorServicio) {
    }

    public record Temporada(Long idTemporada, String nombre, String descripcion, BigDecimal porcentaje,
                            LocalDate fechaInicio, LocalDate fechaFin) {
    }

    /** Noches de la estadia agrupadas por la temporada en que caen. */
    public record TramoTemporada(String temporada, BigDecimal porcentaje, LocalDate desde, LocalDate hasta,
                                 Integer noches, BigDecimal valorNoche, BigDecimal subtotal) {
    }

    public record Cotizacion(Long idHabitacion, LocalDate checkin, LocalDate checkout, Integer noches,
                             BigDecimal valorBase, BigDecimal valorEstadia, List<TramoTemporada> detalle) {
    }
}
