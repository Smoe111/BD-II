package com.uniquindio.turismo.catalogo;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

import com.uniquindio.turismo.catalogo.Modelos.Alojamiento;
import com.uniquindio.turismo.catalogo.Modelos.Habitacion;
import com.uniquindio.turismo.catalogo.Modelos.HabitacionDisponible;
import com.uniquindio.turismo.catalogo.Modelos.Municipio;
import com.uniquindio.turismo.catalogo.Modelos.Servicio;
import com.uniquindio.turismo.catalogo.Modelos.Temporada;
import com.uniquindio.turismo.catalogo.Modelos.TipoAlojamiento;
import com.uniquindio.turismo.catalogo.Modelos.TramoTemporada;

@Repository
public class CatalogoRepositorio {

    private final JdbcClient jdbc;

    public CatalogoRepositorio(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public List<Municipio> municipios() {
        return jdbc.sql("""
                SELECT m.id_municipio, m.nombre,
                       (SELECT COUNT(*) FROM alojamiento a
                         WHERE a.id_municipio = m.id_municipio) AS alojamientos
                  FROM municipio m
                 ORDER BY m.nombre
                """).query(Municipio.class).list();
    }

    public List<TipoAlojamiento> tiposAlojamiento() {
        return jdbc.sql("SELECT id_tipo_alojamiento, nombre FROM tipo_alojamiento ORDER BY nombre")
                .query(TipoAlojamiento.class).list();
    }

    private static final String SELECT_ALOJAMIENTO = """
            SELECT a.id_alojamiento, a.nombre, a.direccion, a.calificacion, a.activo,
                   m.id_municipio, m.nombre AS municipio,
                   ta.id_tipo_alojamiento, ta.nombre AS tipo_alojamiento,
                   (SELECT COUNT(*) FROM habitacion h
                     WHERE h.id_alojamiento = a.id_alojamiento) AS habitaciones
              FROM alojamiento a
              JOIN municipio m         ON m.id_municipio = a.id_municipio
              JOIN tipo_alojamiento ta ON ta.id_tipo_alojamiento = a.id_tipo_alojamiento
            """;

    public List<Alojamiento> alojamientos(Long idMunicipio, Long idTipo) {
        return jdbc.sql(SELECT_ALOJAMIENTO + """
                 WHERE (:mun  IS NULL OR a.id_municipio = :mun)
                   AND (:tipo IS NULL OR a.id_tipo_alojamiento = :tipo)
                 ORDER BY m.nombre, a.nombre
                """)
                .param("mun", idMunicipio, Types.NUMERIC)
                .param("tipo", idTipo, Types.NUMERIC)
                .query(Alojamiento.class).list();
    }

    public Optional<Alojamiento> alojamiento(long id) {
        return jdbc.sql(SELECT_ALOJAMIENTO + " WHERE a.id_alojamiento = :id")
                .param("id", id).query(Alojamiento.class).optional();
    }

    public List<Habitacion> habitaciones(long idAlojamiento) {
        return jdbc.sql("""
                SELECT h.id_habitacion, h.numero_habitacion, h.activo,
                       th.nombre AS tipo_habitacion, th.capacidad_maxima,
                       t.id_tarifa, t.nombre AS tarifa, t.valor AS valor_noche
                  FROM habitacion h
                  JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
                  JOIN tarifa t           ON t.id_tarifa = h.id_tarifa
                 WHERE h.id_alojamiento = :id
                 ORDER BY h.numero_habitacion
                """).param("id", idAlojamiento).query(Habitacion.class).list();
    }

    /**
     * Habitaciones activas, con capacidad suficiente y sin reservas activas
     * que se crucen con [checkin, checkout). Es la misma condicion de
     * solape que usan sp_crear_reserva y el trigger trg_rh_no_solape. El
     * valor lo calcula pkg_turismo.fn_valor_estadia, noche por noche.
     */
    public List<HabitacionDisponible> disponibles(LocalDate checkin, LocalDate checkout,
                                                  int huespedes, Long idMunicipio, Long idAlojamiento) {
        return jdbc.sql("""
                SELECT h.id_habitacion, h.numero_habitacion, a.id_alojamiento,
                       a.nombre AS alojamiento, m.nombre AS municipio,
                       th.nombre AS tipo_habitacion, th.capacidad_maxima,
                       t.valor AS valor_noche,
                       pkg_turismo.fn_valor_estadia(h.id_habitacion, :checkin, :checkout) AS valor_estadia
                  FROM habitacion h
                  JOIN alojamiento a      ON a.id_alojamiento = h.id_alojamiento
                  JOIN municipio m        ON m.id_municipio = a.id_municipio
                  JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
                  JOIN tarifa t           ON t.id_tarifa = h.id_tarifa
                 WHERE h.activo = 'S' AND a.activo = 'S'
                   AND th.capacidad_maxima >= :huespedes
                   AND (:mun  IS NULL OR a.id_municipio   = :mun)
                   AND (:aloj IS NULL OR a.id_alojamiento = :aloj)
                   AND NOT EXISTS (SELECT 1
                                     FROM reserva_habitacion rh
                                     JOIN reserva r ON r.id_reserva = rh.id_reserva
                                    WHERE rh.id_habitacion  = h.id_habitacion
                                      AND r.estado         <> 'CANCELADA'
                                      AND rh.fecha_checkin  < :checkout
                                      AND rh.fecha_checkout > :checkin)
                 ORDER BY m.nombre, a.nombre, valor_estadia
                """)
                .param("checkin", checkin)
                .param("checkout", checkout)
                .param("huespedes", huespedes)
                .param("mun", idMunicipio, Types.NUMERIC)
                .param("aloj", idAlojamiento, Types.NUMERIC)
                .query(HabitacionDisponible.class).list();
    }

    public BigDecimal valorEstadia(long idHabitacion, LocalDate checkin, LocalDate checkout) {
        return jdbc.sql("SELECT pkg_turismo.fn_valor_estadia(:h, :ci, :co) FROM dual")
                .param("h", idHabitacion).param("ci", checkin).param("co", checkout)
                .query(BigDecimal.class).single();
    }

    /**
     * Desglose de la estadia por temporada: muestra la decision de diseno 2
     * (una estadia que atraviesa dos temporadas se cobra noche por noche).
     */
    public List<TramoTemporada> tramos(long idHabitacion, LocalDate checkin, LocalDate checkout) {
        return jdbc.sql("""
                SELECT te.nombre AS temporada, te.porcentaje,
                       MIN(n.noche) AS desde, MAX(n.noche) + 1 AS hasta,
                       COUNT(*) AS noches,
                       ROUND(t.valor * (1 + te.porcentaje / 100), 2) AS valor_noche,
                       ROUND(SUM(t.valor * (1 + te.porcentaje / 100)), 2) AS subtotal
                  FROM (SELECT CAST(:ci AS DATE) + LEVEL - 1 AS noche
                          FROM dual
                       -- el driver envia LocalDate como TIMESTAMP: TIMESTAMP - TIMESTAMP
                       -- es un INTERVAL; con CAST a DATE la resta da numero de dias
                       CONNECT BY LEVEL <= CAST(:co AS DATE) - CAST(:ci AS DATE)) n
                  JOIN temporada te ON n.noche BETWEEN te.fecha_inicio AND te.fecha_fin
                  CROSS JOIN (SELECT tf.valor
                                FROM habitacion h
                                JOIN tarifa tf ON tf.id_tarifa = h.id_tarifa
                               WHERE h.id_habitacion = :h) t
                 GROUP BY te.id_temporada, te.nombre, te.porcentaje, t.valor
                 ORDER BY MIN(n.noche)
                """)
                .param("h", idHabitacion).param("ci", checkin).param("co", checkout)
                .query(TramoTemporada.class).list();
    }

    public Optional<BigDecimal> valorNoche(long idHabitacion) {
        return jdbc.sql("""
                SELECT t.valor FROM habitacion h JOIN tarifa t ON t.id_tarifa = h.id_tarifa
                 WHERE h.id_habitacion = :h
                """).param("h", idHabitacion).query(BigDecimal.class).optional();
    }

    public List<Servicio> servicios() {
        return jdbc.sql("""
                SELECT s.id_servicio, s.nombre, ts.nombre AS tipo_servicio, s.valor_servicio
                  FROM servicio s
                  JOIN tipo_servicio ts ON ts.id_tipo_servicio = s.id_tipo_servicio
                 ORDER BY ts.nombre, s.nombre
                """).query(Servicio.class).list();
    }

    public List<Temporada> temporadas(Integer anio) {
        return jdbc.sql("""
                SELECT id_temporada, nombre, descripcion, porcentaje, fecha_inicio, fecha_fin
                  FROM temporada
                 WHERE :anio IS NULL OR EXTRACT(YEAR FROM fecha_inicio) = :anio
                 ORDER BY fecha_inicio
                """).param("anio", anio, Types.NUMERIC).query(Temporada.class).list();
    }
}
