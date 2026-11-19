package com.uniquindio.turismo.comun;

import java.sql.SQLException;
import java.util.List;

/**
 * Error que viene de Oracle (por ejemplo un RAISE_APPLICATION_ERROR de
 * pkg_turismo) junto con lo que el procedimiento alcanzo a escribir en
 * DBMS_OUTPUT antes de fallar. Asi el cliente ve, por ejemplo, en que paso
 * de sp_reservar_y_pagar se hizo el ROLLBACK.
 */
public class ErrorBaseDatos extends RuntimeException {

    private final transient SQLException causa;
    private final List<String> salida;

    public ErrorBaseDatos(SQLException causa, List<String> salida) {
        super(causa.getMessage(), causa);
        this.causa = causa;
        this.salida = salida;
    }

    public SQLException getCausa() {
        return causa;
    }

    public List<String> getSalida() {
        return salida;
    }
}
