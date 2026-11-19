package com.uniquindio.turismo.catalogo;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.catalogo.Modelos.Alojamiento;
import com.uniquindio.turismo.catalogo.Modelos.AlojamientoDetalle;
import com.uniquindio.turismo.catalogo.Modelos.Cotizacion;
import com.uniquindio.turismo.catalogo.Modelos.HabitacionDisponible;
import com.uniquindio.turismo.catalogo.Modelos.Municipio;
import com.uniquindio.turismo.catalogo.Modelos.Servicio;
import com.uniquindio.turismo.catalogo.Modelos.Temporada;
import com.uniquindio.turismo.catalogo.Modelos.TipoAlojamiento;
import com.uniquindio.turismo.comun.ErrorNegocio;
import com.uniquindio.turismo.comun.Fechas;

/** Oferta de alojamiento: lo que consulta un cliente antes de reservar. */
@RestController
@RequestMapping("/api")
public class CatalogoController {

    private final CatalogoRepositorio repo;

    public CatalogoController(CatalogoRepositorio repo) {
        this.repo = repo;
    }

    @GetMapping("/municipios")
    public List<Municipio> municipios() {
        return repo.municipios();
    }

    @GetMapping("/tipos-alojamiento")
    public List<TipoAlojamiento> tiposAlojamiento() {
        return repo.tiposAlojamiento();
    }

    @GetMapping("/alojamientos")
    public List<Alojamiento> alojamientos(@RequestParam(required = false) Long municipio,
                                          @RequestParam(required = false) Long tipo) {
        return repo.alojamientos(municipio, tipo);
    }

    @GetMapping("/alojamientos/{id}")
    public AlojamientoDetalle alojamiento(@PathVariable long id) {
        Alojamiento a = repo.alojamiento(id)
                .orElseThrow(() -> ErrorNegocio.noEncontrado("El alojamiento " + id + " no existe"));
        return new AlojamientoDetalle(a, repo.habitaciones(id));
    }

    /** Busqueda de disponibilidad: GET /api/habitaciones/disponibles?checkin=...&checkout=...&huespedes=2 */
    @GetMapping("/habitaciones/disponibles")
    public List<HabitacionDisponible> disponibles(
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate checkin,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate checkout,
            @RequestParam(defaultValue = "1") int huespedes,
            @RequestParam(required = false) Long municipio,
            @RequestParam(required = false) Long alojamiento) {
        Fechas.validarRango(checkin, checkout, "checkin", "checkout");
        if (huespedes < 1) {
            throw ErrorNegocio.solicitudInvalida("huespedes debe ser al menos 1");
        }
        return repo.disponibles(checkin, checkout, huespedes, municipio, alojamiento);
    }

    /**
     * Cotizacion con pkg_turismo.fn_valor_estadia y el desglose por
     * temporada (las noches de cada temporada con su recargo).
     */
    @GetMapping("/habitaciones/{id}/cotizacion")
    public Cotizacion cotizacion(@PathVariable long id,
                                 @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate checkin,
                                 @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate checkout) {
        Fechas.validarRango(checkin, checkout, "checkin", "checkout");
        BigDecimal valor = repo.valorEstadia(id, checkin, checkout);   // -20021 / -20022 si aplica
        int noches = (int) ChronoUnit.DAYS.between(checkin, checkout);
        BigDecimal base = repo.valorNoche(id).orElseThrow().multiply(BigDecimal.valueOf(noches));
        return new Cotizacion(id, checkin, checkout, noches, base, valor, repo.tramos(id, checkin, checkout));
    }

    @GetMapping("/servicios")
    public List<Servicio> servicios() {
        return repo.servicios();
    }

    @GetMapping("/temporadas")
    public List<Temporada> temporadas(@RequestParam(required = false) Integer anio) {
        return repo.temporadas(anio);
    }
}
