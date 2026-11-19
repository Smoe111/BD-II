package com.uniquindio.turismo.comun;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class ManejadorErroresTest {

    @Test
    void quitaElCodigoOraYLaPilaDePlsql() {
        String oracle = """
                ORA-20047: La habitacion 51 (No. 104) no esta disponible entre 2027-02-20 y 2027-02-22.
                ORA-06512: at "TURISMOUQ.PKG_TURISMO", line 572
                ORA-06512: at line 1""";
        assertEquals("La habitacion 51 (No. 104) no esta disponible entre 2027-02-20 y 2027-02-22.",
                ManejadorErrores.limpiar(oracle));
    }

    @Test
    void mensajeSinCodigoQuedaIgual() {
        assertEquals("sin codigo", ManejadorErrores.limpiar("sin codigo"));
    }
}
