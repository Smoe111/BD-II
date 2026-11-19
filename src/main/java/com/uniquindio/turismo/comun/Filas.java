package com.uniquindio.turismo.comun;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Convierte filas genericas (reportes con columnas dinamicas, como el
 * PIVOT) a un formato comodo para JSON: nombres en camelCase
 * (ID_RESERVA -> idReserva) y DATE de Oracle como fecha ISO.
 */
public final class Filas {

    private Filas() {
    }

    public static List<Map<String, Object>> json(List<Map<String, Object>> filas) {
        return filas.stream().map(Filas::json).toList();
    }

    public static Map<String, Object> json(Map<String, Object> fila) {
        Map<String, Object> salida = new LinkedHashMap<>();
        fila.forEach((columna, valor) -> salida.put(camel(columna), valor(valor)));
        return salida;
    }

    static String camel(String columna) {
        StringBuilder sb = new StringBuilder();
        boolean mayuscula = false;
        for (char c : columna.toLowerCase().toCharArray()) {
            if (c == '_') {
                mayuscula = true;
            } else {
                sb.append(mayuscula ? Character.toUpperCase(c) : c);
                mayuscula = false;
            }
        }
        return sb.toString();
    }

    static Object valor(Object v) {
        // El driver entrega DATE como Timestamp; si no tiene hora es una fecha
        if (v instanceof Timestamp ts) {
            LocalDateTime ldt = ts.toLocalDateTime();
            return ldt.toLocalTime().equals(LocalTime.MIDNIGHT) ? ldt.toLocalDate() : ldt;
        }
        if (v instanceof java.sql.Date d) {
            return d.toLocalDate();
        }
        return v;
    }
}
