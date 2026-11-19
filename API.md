# TurismoUQ · API REST

Backend en Spring Boot 4 que expone como servicios HTTP las consultas y la lógica
PL/SQL de las tres entregas. Base: `http://localhost:8080`.

## Decisión de diseño: la lógica se queda en Oracle

Las reglas de negocio viven en la base de datos: paquetes, triggers y constraints.
La API **no las duplica**. Llama a los procedimientos (`pkg_turismo`,
`pkg_transacciones`) y a las consultas SQL con variables de enlace, y traduce el
resultado a JSON:

- **Validaciones:** las hace el PL/SQL (`RAISE_APPLICATION_ERROR`). La API convierte cada
  código ORA-200xx al estado HTTP que le corresponde y devuelve el mismo mensaje.
- **Transacciones:** la atomicidad de reserva + pago la garantiza `sp_reservar_y_pagar`
  con sus SAVEPOINT. La API no abre transacciones propias.
- **Concurrencia:** dos solicitudes simultáneas por la misma habitación las serializa el
  `SELECT ... FOR UPDATE` de `sp_crear_reserva`. Una responde `201` y la otra `409`
  (comprobado con dos `curl` en paralelo).
- **Hibernate no toca el esquema** (`spring.jpa.hibernate.ddl-auto=none`): el esquema lo
  crean los scripts de `sql/`. Antes estaba en `update`, que podía alterar las tablas.
- **Acceso a datos:** `JdbcClient` para consultas y `CallableStatement` para los
  procedimientos. No hay entidades JPA, porque la mayoría de respuestas son reportes y
  resultados de PL/SQL, no filas para editar.
- **DBMS_OUTPUT:** los procedimientos informan sus pasos con `DBMS_OUTPUT.PUT_LINE`. La API
  los lee en la misma conexión y los devuelve en el campo `salida`, también cuando hay
  error. Así se ve, por ejemplo, en qué paso se hizo el `ROLLBACK TO sp_inicio`.

## Cómo ejecutarlo

```bash
docker compose up -d              # Oracle con el esquema y los datos
./mvnw spring-boot:run            # API en http://localhost:8080
```

El frontend Angular (`frontend/`) llama la API por el proxy de `ng serve`. Si se sirve
aparte, su origen debe estar en `turismo.cors.origenes` (por defecto `http://localhost:4200`).

`api.http` tiene una solicitud lista para cada endpoint. Se ejecuta desde IntelliJ
o VS Code (extensión REST Client).

## Endpoints

### Catálogo (consulta antes de reservar)

| Método | Ruta | Qué hace | Objeto de BD |
|---|---|---|---|
| GET | `/api/municipios` | Municipios con su número de alojamientos | `MUNICIPIO` |
| GET | `/api/tipos-alojamiento` | Tipos de alojamiento | `TIPO_ALOJAMIENTO` |
| GET | `/api/alojamientos?municipio=&tipo=` | Alojamientos, con filtros opcionales | `ALOJAMIENTO` |
| GET | `/api/alojamientos/{id}` | Alojamiento con sus habitaciones y tarifas | `HABITACION`, `TARIFA` |
| GET | `/api/habitaciones/disponibles?checkin=&checkout=&huespedes=&municipio=&alojamiento=` | Habitaciones libres en el rango, con el valor de la estadía | `fn_valor_estadia` + condición de solape |
| GET | `/api/habitaciones/{id}/cotizacion?checkin=&checkout=` | Valor de la estadía y **desglose por temporada** | `pkg_turismo.fn_valor_estadia` |
| GET | `/api/servicios` | Servicios complementarios | `SERVICIO` |
| GET | `/api/temporadas?anio=` | Temporadas y su porcentaje | `TEMPORADA` |

La cotización muestra la decisión de diseño 2, una estadía que atraviesa dos temporadas:

```json
GET /api/habitaciones/2/cotizacion?checkin=2026-12-29&checkout=2027-01-03
{ "noches": 5, "valorBase": 1020000, "valorEstadia": 1438200,
  "detalle": [
    { "temporada": "Temporada decembrina", "porcentaje": 45, "desde": "2026-12-29",
      "hasta": "2027-01-01", "noches": 3, "valorNoche": 295800, "subtotal": 887400 },
    { "temporada": "Vacaciones de enero", "porcentaje": 35, "desde": "2027-01-01",
      "hasta": "2027-01-03", "noches": 2, "valorNoche": 275400, "subtotal": 550800 } ] }
```

### Clientes

| Método | Ruta | Qué hace |
|---|---|---|
| GET | `/api/clientes?apellido=` o `?documento=` | Busca clientes (máximo 50) |
| GET | `/api/clientes/{id}` | Datos del cliente y su cuenta de usuario |
| GET | `/api/clientes/{id}/reservas` | Historial de reservas del cliente |
| GET | `/api/usuarios?rol=` | Personal (no clientes) sin contraseña; el frontend lo usa como funcionario en turno |

### Reservas (Entregas 2 y 3)

| Método | Ruta | Qué hace | Objeto de BD |
|---|---|---|---|
| POST | `/api/reservas` | Crea una reserva `PENDIENTE` (una o varias habitaciones) | `pkg_turismo.sp_crear_reserva` |
| POST | `/api/reservas/con-pago` | Reserva + servicios + pago en **una transacción** | `pkg_transacciones.sp_reservar_y_pagar` |
| POST | `/api/reservas/{id}/pagos` `{"valor":50000,"metodoPago":"EFECTIVO"}` | Pago total o abono al saldo pendiente | `pkg_transacciones.sp_registrar_abono` |
| GET | `/api/reservas/{id}` | Cabecera, habitaciones, servicios y pagos | — |

```json
POST /api/reservas/con-pago
{ "idCliente": 30, "idUsuarioSistema": 1,
  "checkin": "2027-02-10", "checkout": "2027-02-13", "numHuespedes": 2,
  "habitaciones": [50],
  "servicios": [ { "idServicio": 2, "cantidad": 2 }, { "idServicio": 16, "cantidad": 2 } ],
  "valorPago": 800000, "metodoPago": "PSE" }
```

| Situación | Respuesta |
|---|---|
| Todo bien | `201`, `"resultado": "COMPLETA"` |
| Un servicio no existe (`ROLLBACK TO sp_servicios`) | `201`, `"resultado": "ROLLBACK_PARCIAL"`: reserva y pago guardados, sin servicios |
| Anticipo < 30 % o pago inválido (`ROLLBACK TO sp_inicio`) | `400`; no queda nada guardado. `salida` muestra los pasos |
| Habitación ocupada | `409` |

`POST /api/reservas/{id}/pagos` bloquea la reserva con `SELECT … FOR UPDATE` antes de validar
el saldo. Si dos cajeros pagan a la vez la misma reserva, el segundo espera y valida contra el saldo
ya descontado; nunca se cobra de más (probado con dos solicitudes simultáneas: 201 y 400).
Si la reserva está PENDIENTE, lo acumulado debe cubrir el 30 % y entonces pasa a CONFIRMADA.
Errores: 400 (valor fuera del saldo, método, anticipo), 404 (no existe, ORA-20054) y
422 (reserva cancelada, ORA-20055).

Ejemplo de rollback total (`salida` viene del `DBMS_OUTPUT` del procedimiento):

```json
{ "estado": 400, "codigoOracle": 20053,
  "mensaje": "Anticipo insuficiente: se pagan 1.000 y el minimo (30 %) es 217.800.",
  "salida": [ "[1] Reserva 25022 creada (sin confirmar)",
              "ROLLBACK TO sp_inicio (paso PAGO): ORA-20053: Anticipo insuficiente: ..." ] }
```

### Liquidación mensual (Entrega 2)

| Método | Ruta | Qué hace | Objeto de BD |
|---|---|---|---|
| POST | `/api/liquidaciones` `{"anio":2026,"mes":8,"idAlojamiento":5}` | Ejecuta (o repite) la liquidación de un mes cerrado; `idAlojamiento` es opcional | `pkg_turismo.sp_liquidar_mes` (cursor explícito con parámetros) |
| GET | `/api/liquidaciones?anio=&mes=&alojamiento=` | Consulta los cortes ya liquidados | `LIQUIDACION_MENSUAL` |

### Tarifas y auditoría (Entrega 2)

| Método | Ruta | Qué hace | Objeto de BD |
|---|---|---|---|
| GET | `/api/tarifas` | Tarifas y cuántas habitaciones las usan | `TARIFA` |
| PUT | `/api/tarifas/{id}` `{"valor":181000,"usuario":"admin01"}` | Cambia el valor; responde con la auditoría | `trg_tarifa_auditoria` |
| GET | `/api/tarifas/{id}/auditoria` | Quién, cuándo, valor anterior y valor nuevo | `AUDITORIA_TARIFA` |

El usuario de la aplicación llega al trigger por `DBMS_APPLICATION_INFO.SET_CLIENT_INFO`,
en el mismo bloque que el `UPDATE`, y queda en `usuarioApp`.

### Reportes: las 8 consultas de la Entrega 1

| Método | Ruta | Consulta |
|---|---|---|
| GET | `/api/reportes/ocupacion?anio=` | 1. Ocupación por municipio y mes (**PIVOT**) |
| GET | `/api/reportes/ingresos` | 2. Ingresos por municipio, tipo y temporada (**CUBE** + `GROUPING`) |
| GET | `/api/reportes/top-alojamientos?top=3` | 3. Top N alojamientos por municipio (**RANK** con `PARTITION BY`) |
| GET | `/api/reportes/variacion-mensual` | 4. Variación mes contra mes (**LAG**) |
| GET | `/api/reportes/reservas?desde=&hasta=` | 5. Reservas por rango de fechas (**variables de enlace**) |
| GET | `/api/reportes/ocupacion-mensual?anio=&municipio=` | 6. **Vista materializada** `MV_OCUPACION_MENSUAL` |
| POST | `/api/reportes/ocupacion-mensual/refresco` | 6. Refresco completo bajo demanda (`DBMS_MVIEW.REFRESH`) |
| GET | `/api/reportes/estado-financiero?reserva=&cliente=&limite=` | 7. **UNPIVOT** del estado financiero |
| GET | `/api/reportes/cartera` | 8. Consulta libre: cartera pendiente por municipio |

La consulta 6 necesita que `04_consultas.sql` se haya ejecutado (es el script que crea
la vista materializada). Si no se ejecutó, la API responde `503` con ese aviso.

### Operación diaria: consultas aceleradas con índices (Entrega 3)

| Método | Ruta | Consulta | Índice (`17_indices.sql`) |
|---|---|---|---|
| GET | `/api/operacion/llegadas?fecha=` | Llegadas del día (recepción) | `ix_reserva_estado_checkin` (compuesto) |
| GET | `/api/operacion/cierre-caja?fecha=` | Pagos aprobados del día por método | `ix_pago_dia` (basado en función) |
| GET | `/api/operacion/agenda-servicios?fecha=` | Cupos por servicio del día | `ix_rs_fecha_servicio` (cubre la consulta) |

El `WHERE` es el mismo que se midió en la Entrega 3. Sin el script 17 las consultas
funcionan igual, pero con `TABLE ACCESS FULL`.

### Monitoreo (Entrega 3)

| Método | Ruta | Qué hace | Objeto de BD |
|---|---|---|---|
| GET | `/api/admin/bloqueos` | Sesiones de `turismouq` y quién bloquea a quién | `V_MONITOR_BLOQUEOS` |
| GET | `/api/admin/log-transacciones?limite=50` | Intentos de reserva + pago, incluidos los revertidos | `LOG_TRANSACCION` (transacción autónoma) |

## Errores

Toda respuesta de error tiene la misma forma:

```json
{ "fecha": "...", "estado": 409, "error": "Conflict",
  "mensaje": "La habitacion 51 (No. 104) no esta disponible entre 2027-02-20 y 2027-02-22.",
  "codigoOracle": 20047, "ruta": "/api/reservas", "salida": null }
```

| HTTP | Cuándo | Códigos ORA |
|---|---|---|
| 400 | Datos inválidos: fechas, huéspedes, lista de habitaciones, pago, mes no cerrado | 20020, 20030, 20031, 20040, 20043, 20044, 20050, 20051, 20053; validaciones de la API |
| 404 | No existe la habitación, el alojamiento, el cliente, la reserva o la tarifa | 20021, 20032, 20041, 20054 |
| 409 | Habitación ocupada u otra sesión la está reservando | 20003, 20047, 20060, 54, 1 |
| 422 | Regla de negocio: capacidad, noche sin temporada, usuario inactivo o ajeno, alojamiento inactivo, pago a reserva cancelada | 20022, 20042, 20045, 20046, 20055, 2290, 2291 |
| 503 | Falta un objeto que crea `04_consultas.sql` | 942, 12003 |

## Estructura

```
src/main/java/com/uniquindio/turismo/
  comun/        Plsql (llamadas con DBMS_OUTPUT), ManejadorErrores (ORA -> HTTP), Filas
  catalogo/     municipios, alojamientos, disponibilidad, cotizacion
  cliente/      busqueda e historial
  reserva/      sp_crear_reserva y sp_reservar_y_pagar
  liquidacion/  sp_liquidar_mes
  tarifa/       cambio de tarifa y auditoria
  reporte/      consultas 1-8 de la Entrega 1
  operacion/    consultas aceleradas con indices (Entrega 3)
  admin/        bloqueos y bitacora de transacciones
```

Pruebas: `./mvnw test`. `FilasTest` y `ManejadorErroresTest` no necesitan la base;
`TurismoApplicationTests` necesita el contenedor arriba.
