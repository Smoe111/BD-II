package com.uniquindio.turismo.usuario;

import java.sql.Types;
import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Cuentas del personal (recepcion, administradores, gerencia, auditoria).
 * El frontend las usa para elegir quien registra una reserva
 * (reserva.id_usuario_sistema) o quien cambia una tarifa. Nunca devuelve
 * la columna contrasena.
 */
@RestController
@RequestMapping("/api/usuarios")
public class UsuarioController {

    public record Usuario(Long idUsuarioSistema, String usuario, String rol, String activo) {
    }

    private final JdbcClient jdbc;

    public UsuarioController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    public List<Usuario> personal(@RequestParam(required = false) String rol) {
        return jdbc.sql("""
                SELECT id_usuario_sistema, usuario, rol, activo
                  FROM usuario_sistema
                 WHERE rol <> 'CLIENTE'
                   AND (:rol IS NULL OR rol = UPPER(:rol))
                 ORDER BY rol, usuario
                """).param("rol", rol == null || rol.isBlank() ? null : rol.strip(), Types.VARCHAR)
                .query(Usuario.class).list();
    }
}
