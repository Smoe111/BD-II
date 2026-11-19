package com.uniquindio.turismo.comun;

import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Ejecuta bloques PL/SQL capturando DBMS_OUTPUT.
 *
 * Los procedimientos de los paquetes informan su avance con
 * DBMS_OUTPUT.PUT_LINE (por ejemplo "[2] ROLLBACK TO sp_servicios"). Ese
 * buffer es de la SESION, asi que habilitarlo, ejecutar y leerlo tiene que
 * pasar en la misma conexion: por eso todo va dentro de un ConnectionCallback.
 */
@Component
public class Plsql {

    private final JdbcTemplate jdbcTemplate;

    public Plsql(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @FunctionalInterface
    public interface Llamada<T> {
        T ejecutar(Connection conexion) throws SQLException;
    }

    /** Resultado de la llamada mas las lineas de DBMS_OUTPUT. */
    public record ConSalida<T>(T resultado, List<String> salida) {
    }

    public <T> ConSalida<T> ejecutar(Llamada<T> llamada) {
        return jdbcTemplate.execute((ConnectionCallback<ConSalida<T>>) con -> {
            habilitar(con);
            try {
                T resultado = llamada.ejecutar(con);
                return new ConSalida<>(resultado, leer(con));
            } catch (SQLException e) {
                throw new ErrorBaseDatos(e, leer(con));
            } finally {
                deshabilitar(con);   // la conexion vuelve al pool limpia
            }
        });
    }

    private static void habilitar(Connection con) throws SQLException {
        try (CallableStatement cs = con.prepareCall("BEGIN DBMS_OUTPUT.ENABLE(NULL); END;")) {
            cs.execute();
        }
    }

    private static void deshabilitar(Connection con) {
        try (CallableStatement cs = con.prepareCall("BEGIN DBMS_OUTPUT.DISABLE; END;")) {
            cs.execute();
        } catch (SQLException ignorada) {
            // si la conexion quedo inservible, el pool la descarta
        }
    }

    private static List<String> leer(Connection con) throws SQLException {
        List<String> lineas = new ArrayList<>();
        try (CallableStatement cs = con.prepareCall("BEGIN DBMS_OUTPUT.GET_LINE(?, ?); END;")) {
            cs.registerOutParameter(1, Types.VARCHAR);
            cs.registerOutParameter(2, Types.INTEGER);
            while (true) {
                cs.execute();
                if (cs.getInt(2) != 0) {
                    break;               // status 1 = no hay mas lineas
                }
                String linea = cs.getString(1);
                lineas.add(linea == null ? "" : linea.strip());
            }
        }
        return lineas;
    }
}
