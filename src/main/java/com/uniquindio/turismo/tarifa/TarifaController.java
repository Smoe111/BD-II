package com.uniquindio.turismo.tarifa;

import java.math.BigDecimal;
import java.sql.CallableStatement;
import java.sql.Types;
import java.time.LocalDateTime;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.uniquindio.turismo.comun.ErrorNegocio;
import com.uniquindio.turismo.comun.Plsql;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * Tarifas y su auditoria. El cambio de valor lo registra el trigger de
 * sentencia trg_tarifa_auditoria (Entrega 2); la API le pasa el usuario de
 * la aplicacion por CLIENT_INFO, que es de donde el trigger lo lee.
 */
@RestController
@RequestMapping("/api/tarifas")
public class TarifaController {

    public record Tarifa(Long idTarifa, String nombre, String descripcion, BigDecimal valor,
                         Integer habitaciones) {
    }

    public record CambioTarifa(@NotNull @Positive BigDecimal valor, @NotBlank String usuario) {
    }

    public record Auditoria(Long idAuditoria, Long idSentencia, Long idTarifa, String operacion,
                            String usuarioBd, String usuarioApp, LocalDateTime fechaCambio,
                            BigDecimal valorAnterior, BigDecimal valorNuevo) {
    }

    private final JdbcClient jdbc;
    private final Plsql plsql;

    public TarifaController(JdbcClient jdbc, Plsql plsql) {
        this.jdbc = jdbc;
        this.plsql = plsql;
    }

    @GetMapping
    public List<Tarifa> tarifas() {
        return jdbc.sql("""
                SELECT t.id_tarifa, t.nombre, t.descripcion, t.valor,
                       (SELECT COUNT(*) FROM habitacion h WHERE h.id_tarifa = t.id_tarifa) AS habitaciones
                  FROM tarifa t
                 ORDER BY t.id_tarifa
                """).query(Tarifa.class).list();
    }

    /**
     * El UPDATE y el SET_CLIENT_INFO van en el MISMO bloque (misma sesion):
     * el trigger lee SYS_CONTEXT('USERENV','CLIENT_INFO'). Al final se
     * limpia para que la conexion vuelva al pool sin ese dato.
     */
    @PutMapping("/{id}")
    public List<Auditoria> cambiarValor(@PathVariable long id, @Valid @RequestBody CambioTarifa cambio) {
        int filas = plsql.ejecutar(con -> {
            try (CallableStatement cs = con.prepareCall("""
                    BEGIN
                      DBMS_APPLICATION_INFO.SET_CLIENT_INFO(?);
                      UPDATE tarifa SET valor = ? WHERE id_tarifa = ?;
                      ? := SQL%ROWCOUNT;
                      DBMS_APPLICATION_INFO.SET_CLIENT_INFO(NULL);
                    END;""")) {
                cs.setString(1, cambio.usuario());
                cs.setBigDecimal(2, cambio.valor());
                cs.setLong(3, id);
                cs.registerOutParameter(4, Types.INTEGER);
                cs.execute();
                return cs.getInt(4);
            }
        }).resultado();
        if (filas == 0) {
            throw ErrorNegocio.noEncontrado("La tarifa " + id + " no existe");
        }
        return auditoria(id);
    }

    @GetMapping("/{id}/auditoria")
    public List<Auditoria> auditoria(@PathVariable long id) {
        return jdbc.sql("""
                SELECT id_auditoria, id_sentencia, id_tarifa, operacion, usuario_bd, usuario_app,
                       CAST(fecha_cambio AS TIMESTAMP) AS fecha_cambio, valor_anterior, valor_nuevo
                  FROM auditoria_tarifa
                 WHERE id_tarifa = :id
                 ORDER BY fecha_cambio DESC, id_auditoria DESC
                """).param("id", id).query(Auditoria.class).list();
    }
}
