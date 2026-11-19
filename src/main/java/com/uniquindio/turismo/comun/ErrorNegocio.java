package com.uniquindio.turismo.comun;

import org.springframework.http.HttpStatus;

/** Error detectado en la API antes de llegar a la base de datos. */
public class ErrorNegocio extends RuntimeException {

    private final HttpStatus estado;

    public ErrorNegocio(HttpStatus estado, String mensaje) {
        super(mensaje);
        this.estado = estado;
    }

    public static ErrorNegocio noEncontrado(String mensaje) {
        return new ErrorNegocio(HttpStatus.NOT_FOUND, mensaje);
    }

    public static ErrorNegocio solicitudInvalida(String mensaje) {
        return new ErrorNegocio(HttpStatus.BAD_REQUEST, mensaje);
    }

    public HttpStatus getEstado() {
        return estado;
    }
}
