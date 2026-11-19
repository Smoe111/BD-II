package com.uniquindio.turismo.comun;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

import org.junit.jupiter.api.Test;

class FilasTest {

    @Test
    void columnasOracleQuedanEnCamelCase() {
        assertEquals("idReserva", Filas.camel("ID_RESERVA"));
        assertEquals("enePct", Filas.camel("ENE_PCT"));
        assertEquals("municipio", Filas.camel("MUNICIPIO"));
    }

    @Test
    void dateSinHoraEsFechaYConHoraEsFechaHora() {
        Map<String, Object> fila = new LinkedHashMap<>();
        fila.put("FECHA_CHECKIN", Timestamp.valueOf("2026-12-18 00:00:00"));
        fila.put("FECHA_PAGO", Timestamp.valueOf("2026-12-18 14:30:00"));

        Map<String, Object> json = Filas.json(fila);

        assertEquals(LocalDate.of(2026, 12, 18), json.get("fechaCheckin"));
        assertEquals(LocalDateTime.of(2026, 12, 18, 14, 30), json.get("fechaPago"));
    }
}
