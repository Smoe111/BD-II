package com.uniquindio.turismo.comun;

import java.sql.SQLException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.http.converter.HttpMessageNotReadableException;

import jakarta.servlet.http.HttpServletRequest;

/**
 * Traduce los errores a HTTP.
 *
 * Los errores de negocio los decide la base de datos: los procedimientos
 * lanzan RAISE_APPLICATION_ERROR(-200xx, mensaje) y aqui cada codigo se
 * convierte en el estado HTTP que le corresponde, con el mensaje tal cual
 * lo escribio el PL/SQL.
 */
@RestControllerAdvice
public class ManejadorErrores {

    private static final Logger log = LoggerFactory.getLogger(ManejadorErrores.class);

    /** Codigo ORA (sin signo) -> estado HTTP. */
    private static final Map<Integer, HttpStatus> ESTADOS = Map.ofEntries(
            // datos de entrada invalidos
            Map.entry(20020, HttpStatus.BAD_REQUEST),   // fn_valor_estadia: rango invalido
            Map.entry(20030, HttpStatus.BAD_REQUEST),   // sp_liquidar_mes: periodo invalido
            Map.entry(20031, HttpStatus.BAD_REQUEST),   // sp_liquidar_mes: mes no cerrado
            Map.entry(20040, HttpStatus.BAD_REQUEST),   // sp_crear_reserva: fechas
            Map.entry(20043, HttpStatus.BAD_REQUEST),   // huespedes
            Map.entry(20044, HttpStatus.BAD_REQUEST),   // lista de habitaciones
            Map.entry(20050, HttpStatus.BAD_REQUEST),   // valor del pago
            Map.entry(20051, HttpStatus.BAD_REQUEST),   // metodo de pago
            Map.entry(20053, HttpStatus.BAD_REQUEST),   // anticipo insuficiente
            // no existe
            Map.entry(20021, HttpStatus.NOT_FOUND),     // habitacion
            Map.entry(20032, HttpStatus.NOT_FOUND),     // alojamiento
            Map.entry(20041, HttpStatus.NOT_FOUND),     // cliente
            Map.entry(20054, HttpStatus.NOT_FOUND),     // sp_registrar_abono: reserva
            // regla de negocio que impide la operacion
            Map.entry(20022, HttpStatus.UNPROCESSABLE_CONTENT), // noche sin temporada
            Map.entry(20042, HttpStatus.UNPROCESSABLE_CONTENT), // usuario inexistente/inactivo/ajeno
            Map.entry(20045, HttpStatus.UNPROCESSABLE_CONTENT), // alojamiento inactivo o mezclado
            Map.entry(20046, HttpStatus.UNPROCESSABLE_CONTENT), // capacidad excedida
            Map.entry(20055, HttpStatus.UNPROCESSABLE_CONTENT), // reserva cancelada: no recibe pagos
            Map.entry(2290, HttpStatus.UNPROCESSABLE_CONTENT),  // CHECK
            Map.entry(2291, HttpStatus.UNPROCESSABLE_CONTENT),  // FK: el padre no existe
            // conflicto con el estado actual (otra reserva / otra sesion)
            Map.entry(20003, HttpStatus.CONFLICT),      // trigger de solape
            Map.entry(20047, HttpStatus.CONFLICT),      // habitacion no disponible
            Map.entry(20060, HttpStatus.CONFLICT),      // la reserva otra sesion
            Map.entry(54, HttpStatus.CONFLICT),         // NOWAIT
            Map.entry(1, HttpStatus.CONFLICT),          // UNIQUE
            // objetos que se crean a mano (04_consultas.sql)
            Map.entry(942, HttpStatus.SERVICE_UNAVAILABLE),
            Map.entry(12003, HttpStatus.SERVICE_UNAVAILABLE));

    @ExceptionHandler(ErrorBaseDatos.class)
    public ResponseEntity<RespuestaError> baseDatos(ErrorBaseDatos e, HttpServletRequest req) {
        return desdeOracle(e.getCausa(), e.getSalida(), req);
    }

    @ExceptionHandler(org.springframework.dao.DataAccessException.class)
    public ResponseEntity<RespuestaError> dataAccess(org.springframework.dao.DataAccessException e,
                                                     HttpServletRequest req) {
        SQLException sql = buscarSql(e);
        if (sql == null) {
            log.error("Error de acceso a datos", e);
            return responder(HttpStatus.INTERNAL_SERVER_ERROR, e.getMostSpecificCause().getMessage(),
                    null, req, null);
        }
        return desdeOracle(sql, null, req);
    }

    @ExceptionHandler(ErrorNegocio.class)
    public ResponseEntity<RespuestaError> negocio(ErrorNegocio e, HttpServletRequest req) {
        return responder(e.getEstado(), e.getMessage(), null, req, null);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<RespuestaError> validacion(MethodArgumentNotValidException e, HttpServletRequest req) {
        String mensaje = e.getBindingResult().getFieldErrors().stream()
                .map(f -> f.getField() + ": " + f.getDefaultMessage())
                .collect(Collectors.joining("; "));
        return responder(HttpStatus.BAD_REQUEST, mensaje, null, req, null);
    }

    @ExceptionHandler({MissingServletRequestParameterException.class,
                       MethodArgumentTypeMismatchException.class,
                       HttpMessageNotReadableException.class})
    public ResponseEntity<RespuestaError> parametros(Exception e, HttpServletRequest req) {
        String mensaje;
        if (e instanceof MissingServletRequestParameterException m) {
            mensaje = "Falta el parametro '" + m.getParameterName() + "'";
        } else if (e instanceof MethodArgumentTypeMismatchException m) {
            mensaje = "Valor invalido para '" + m.getName() + "': " + m.getValue()
                    + " (las fechas van en formato AAAA-MM-DD)";
        } else {
            mensaje = "Cuerpo de la solicitud invalido o mal formado";
        }
        return responder(HttpStatus.BAD_REQUEST, mensaje, null, req, null);
    }

    // ------------------------------------------------------------------

    private ResponseEntity<RespuestaError> desdeOracle(SQLException sql, List<String> salida,
                                                       HttpServletRequest req) {
        int codigo = Math.abs(sql.getErrorCode());
        HttpStatus estado = ESTADOS.getOrDefault(codigo, HttpStatus.INTERNAL_SERVER_ERROR);
        String mensaje = limpiar(sql.getMessage());
        if (codigo == 942 || codigo == 12003) {
            mensaje += " (este recurso usa objetos de 04_consultas.sql: ejecute ese script)";
        }
        if (estado.is5xxServerError()) {
            log.error("Error Oracle no esperado", sql);
        }
        return responder(estado, mensaje, codigo, req, salida);
    }

    /** "ORA-20047: La habitacion...\nORA-06512: at ..." -> "La habitacion..." */
    static String limpiar(String mensaje) {
        if (mensaje == null) {
            return null;
        }
        String primera = mensaje.lines().findFirst().orElse(mensaje).strip();
        return primera.replaceFirst("^ORA-\\d{5}:\\s*", "");
    }

    private static SQLException buscarSql(Throwable t) {
        while (t != null) {
            if (t instanceof SQLException s) {
                return s;
            }
            t = t.getCause();
        }
        return null;
    }

    private static ResponseEntity<RespuestaError> responder(HttpStatus estado, String mensaje, Integer codigo,
                                                            HttpServletRequest req, List<String> salida) {
        RespuestaError cuerpo = new RespuestaError(LocalDateTime.now(), estado.value(),
                estado.getReasonPhrase(), mensaje, codigo, req.getRequestURI(),
                salida == null || salida.isEmpty() ? null : salida);
        return ResponseEntity.status(estado).body(cuerpo);
    }
}
