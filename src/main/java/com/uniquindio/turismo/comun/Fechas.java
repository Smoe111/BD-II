package com.uniquindio.turismo.comun;

import java.time.LocalDate;

public final class Fechas {

    private Fechas() {
    }

    /** checkout debe ser posterior a checkin (misma regla que la base). */
    public static void validarRango(LocalDate desde, LocalDate hasta, String nombreDesde, String nombreHasta) {
        if (desde == null || hasta == null) {
            throw ErrorNegocio.solicitudInvalida(nombreDesde + " y " + nombreHasta + " son obligatorios");
        }
        if (!hasta.isAfter(desde)) {
            throw ErrorNegocio.solicitudInvalida(nombreHasta + " (" + hasta + ") debe ser posterior a "
                    + nombreDesde + " (" + desde + ")");
        }
    }
}
