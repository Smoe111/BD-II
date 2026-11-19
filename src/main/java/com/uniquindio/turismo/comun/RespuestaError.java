package com.uniquindio.turismo.comun;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Cuerpo de toda respuesta de error.
 *
 * @param codigoOracle codigo ORA (20047, 1, 2291...) o null si el error no vino de Oracle
 * @param salida       lineas de DBMS_OUTPUT del procedimiento, si las hubo
 */
public record RespuestaError(
        LocalDateTime fecha,
        int estado,
        String error,
        String mensaje,
        Integer codigoOracle,
        String ruta,
        List<String> salida) {
}
