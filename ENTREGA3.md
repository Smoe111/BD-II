# TurismoUQ · Entrega 3 · Transacciones, concurrencia e índices

> **Alcance.** Esta entrega cubre **transacciones**, **concurrencia** e **índices**.
> La parte de **seguridad** (roles, vistas para recepción y perfil) **no se incluye**:
> el tema no se alcanzó a ver en clase y no hace parte de esta entrega.

| Requerimiento | Dónde está | Cómo se ejecuta |
|---|---|---|
| Reserva + pago atómicos con `SAVEPOINT` | `sql/11_pkg_transacciones.sql` (`pkg_transacciones.sp_reservar_y_pagar`) | Docker lo instala solo |
| Demostración de rollback parcial | `sql/12_transacciones_demo.sql` | A mano (§1.4) |
| Experimento de concurrencia con dos sesiones | `sql/13_pkg_concurrencia.sql` + `14`, `15`, `16` | A mano, 3 terminales (§2.3) |
| 3 consultas lentas, plan antes y después, índices compuesto y basado en función | `sql/17_indices.sql` (Q1, Q2, Q3) | A mano (§3) |
| Caso en el que el índice no ayuda | `sql/17_indices.sql` (Q4) | A mano (§3.4) |
| Permisos de diagnóstico (`V$SESSION`, `V$LOCK`, planes) | `sql/01_tablespaces.sql` (final) | Docker los otorga solo |

Cambio sobre la Entrega 2: `pkg_turismo.sp_crear_reserva` recibe un parámetro nuevo,
`p_confirmar BOOLEAN DEFAULT TRUE` (ver §1.2). Con el valor por defecto se comporta igual
que antes: las 59 pruebas de `10_pruebas.sql` siguen pasando.

---

## 0. Orden de ejecución

| Script | Qué hace | ¿Lo corre Docker al crear el contenedor? |
|---|---|---|
| `01` … `08` | Entregas 1 y 2 (más los permisos de diagnóstico al final de `01`) | Sí |
| `09`, `10` | Pruebas de la Entrega 2 | No: fallan sin efecto en `CDB$ROOT` |
| `11_pkg_transacciones.sql` | Tabla `LOG_TRANSACCION` y paquete `PKG_TRANSACCIONES` | **Sí** |
| `12_transacciones_demo.sql` | Demostración de transacciones | No: se corre a mano |
| `13_pkg_concurrencia.sql` | Vista `V_MONITOR_BLOQUEOS` y paquete `PKG_CONCURRENCIA` | **Sí** |
| `14_concurrencia_preparar.sql` | Prepara cada escenario del experimento | No: se corre a mano |
| `15_concurrencia_sesion.sql` | Lo que ejecuta cada sesión (A y B) | No: se corre a mano |
| `16_concurrencia_monitor.sql` | Tercera sesión: muestra quién bloquea a quién | No: se corre a mano |
| `17_indices.sql` | Medición antes y después y creación de los índices | No: se corre a mano |

Los scripts manuales (`12`, `14`–`17`) empiezan con una guarda: si los ejecuta Docker
(como `SYS` en `CDB$ROOT`), se detienen en la primera línea sin tocar nada. Todos se
corren con el `sqlplus` del contenedor, porque usan comandos de SQL*Plus:

```bash
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/<script>.sql [parametros]
```

---

## 1. Transacciones

### 1.1 Diseño de `sp_reservar_y_pagar`

Registrar una reserva paga son varias escrituras en cuatro tablas (`RESERVA`,
`RESERVA_HABITACION`, `RESERVA_SERVICIO`, `PAGO`). Deben quedar todas o ninguna:
una reserva confirmada sin su pago, o un pago sin reserva, deja la base inconsistente.

```
SAVEPOINT sp_inicio ───────────────────────────────────────────┐
  1. reserva + habitaciones  (pkg_turismo.sp_crear_reserva,     │
                              p_confirmar => FALSE: sin COMMIT) │
  SAVEPOINT sp_servicios ──────────────┐                        │
  2. servicios complementarios         │ si un servicio falla:  │
     (opcionales)                      └ ROLLBACK TO sp_servicios
                                         → ROLLBACK PARCIAL: la │
                                           reserva sigue viva   │
  3. pago APROBADO + reserva CONFIRMADA                         │
     (anticipo mínimo del 30 %)          si el pago falla:      │
                                         ROLLBACK TO sp_inicio ─┘
                                         → ROLLBACK TOTAL
COMMIT  ← uno solo, al final
```

| Desenlace | Qué se deshace | Qué queda confirmado |
|---|---|---|
| Todo bien | nada | reserva, habitaciones, servicios y pago |
| Falla un servicio (no existe, repetido o mal escrito) | **solo** los servicios: `ROLLBACK TO sp_servicios` | reserva, habitaciones y pago |
| Falla el pago (valor inválido, anticipo < 30 %, método inválido) | **todo**: `ROLLBACK TO sp_inicio` | nada (solo la bitácora) |
| Falla la reserva (fechas, capacidad, habitación ocupada) | **todo**: `ROLLBACK TO sp_inicio` | nada (solo la bitácora) |

**¿Por qué los servicios admiten rollback parcial y el pago no?** Los servicios son un
extra: si el tour pedido no existe, lo razonable es guardar la reserva y avisar.
El pago, en cambio, es lo que confirma la reserva. Una reserva sin pago bloquearía la
habitación sin garantía, así que la regla es todo o nada.

**¿Por qué `ROLLBACK TO sp_inicio` y no `ROLLBACK`?** `ROLLBACK` a secas desharía también
el trabajo pendiente que tuviera el llamador antes de invocar el procedimiento.
`ROLLBACK TO sp_inicio` deshace solo lo que hizo el procedimiento y libera los bloqueos
que tomó desde ese punto, entre ellos el `FOR UPDATE` sobre la habitación.

### 1.2 Cambio en `sp_crear_reserva`: `p_confirmar`

En la Entrega 2, `sp_crear_reserva` terminaba con `COMMIT`. Si `sp_reservar_y_pagar` lo
llamara así, la reserva quedaría confirmada **antes** del pago, y un pago fallido ya no
podría deshacerla. Esto rompería la atomicidad. Por eso:

```sql
PROCEDURE sp_crear_reserva (..., p_id_reserva OUT NUMBER,
                            p_confirmar IN BOOLEAN DEFAULT TRUE);
...
IF p_confirmar THEN COMMIT; END IF;
```

Así se aplica la buena práctica vista en clase: *"evitar que los procedimientos
almacenados confirmen transacciones que pertenecen a procesos más grandes"*. Quien
controla la transacción es el proceso de negocio completo (`sp_reservar_y_pagar`).

### 1.3 Bitácora con transacción autónoma

`pkg_transacciones.sp_log` escribe en `LOG_TRANSACCION` con `PRAGMA AUTONOMOUS_TRANSACTION`
y su propio `COMMIT`. Si la bitácora se escribiera dentro de la transacción principal,
el `ROLLBACK TO sp_inicio` que deshace una reserva fallida borraría también el registro
del fallo. Con la transacción autónoma, el intento fallido queda guardado aunque la
reserva no. La tabla no tiene FK a `RESERVA` a propósito, porque guarda intentos cuya
reserva ya no existe.

### 1.4 Demostración (`12_transacciones_demo.sql`)

```bash
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/12_transacciones_demo.sql
```

Salida real de una corrida. Los ids de reserva, pago y bitácora cambian de una corrida a
otra.

**Parte A: SAVEPOINT paso a paso**, mirando la transacción en `V$TRANSACTION`.
Un recepcionista crea la reserva, registra un pago, nota que el valor está mal y
deshace **solo el pago**:

```
--- A1. Reserva creada SIN confirmar (p_confirmar => FALSE)
STATUS           REGISTROS_UNDO
ACTIVE                        8          ← transacción abierta, 8 registros de UNDO
--- A2. SAVEPOINT sp_reserva_ok
--- A3. Pago y actualizacion de la reserva (valor mal digitado)
--- A4. Dentro de la transaccion se ve todo
ID_RESERVA ESTADO      VALOR_TOTAL VALOR_PAGADO      PAGOS
     25017 CONFIRMADA       703800         1000          1
REGISTROS_UNDO
            12                           ← +4 registros: el INSERT y el UPDATE
--- A5. ROLLBACK TO sp_reserva_ok: se deshace SOLO el pago
     25017 PENDIENTE        703800            0          0
STATUS           REGISTROS_UNDO
ACTIVE                        8          ← sigue ACTIVA; el UNDO vuelve a 8
--- A6. ROLLBACK completo: nunca se confirmo nada
RESERVA_EXISTE
             0
(sin transaccion activa: la consulta a V$TRANSACTION no devuelve filas)
```

**Parte B: los cuatro desenlaces del procedimiento**:

```
--- B1. Todo bien: reserva + 2 servicios + pago del 60 % del hospedaje -> COMMIT
  [1] Reserva 25018 creada (sin confirmar)
  [2] Servicios agregados por 304,000
  [3] Pago 44059 por 422,300 -> reserva CONFIRMADA
  COMMIT: total 1,007,800, pagado 422,300                       → COMPLETA

--- B2. Servicio 999 no existe -> ROLLBACK TO sp_servicios (PARCIAL)
  [1] Reserva 25019 creada (sin confirmar)
  [2] ROLLBACK TO sp_servicios: ORA-20052: El servicio 999 no existe.
      la reserva continua sin servicios
  [3] Pago 44060 por 351,900 -> reserva CONFIRMADA
  COMMIT: total 703,800, pagado 351,900                         → ROLLBACK_PARCIAL
  (servicios = 0: también se deshizo la línea del servicio 3, que sí existía)

--- B3. Anticipo de 1.000 pesos (< 30 %) -> ROLLBACK TO sp_inicio (TOTAL)
  [1] Reserva 25020 creada (sin confirmar)
  [2] Servicios agregados por 160,000
  ROLLBACK TO sp_inicio (paso PAGO): ORA-20053: Anticipo insuficiente: se pagan 1,000
                                     y el minimo (30 %) es 259,140.
  RESERVAS_EN_H3 = 0                                            → nada quedó

--- B4. Reservar otra vez la habitacion de B1 -> -20047, ROLLBACK TOTAL
  ROLLBACK TO sp_inicio (paso RESERVA): ORA-20047: La habitacion 2 (No. 102) no esta disponible ...
```

La bitácora conserva los cuatro intentos, también los dos que hicieron rollback:

```
ID_LOG HABITACIONES ID_RESERVA ID_PAGO RESULTADO        PASO      CODIGO_ERROR
     3 2                 25018   44059 COMPLETA
     4 3                 25019   44060 ROLLBACK_PARCIAL SERVICIOS
     5 7                                ROLLBACK_TOTAL   PAGO            -20053
     6 2                                ROLLBACK_TOTAL   RESERVA         -20047
```

Al final, la parte C borra todo lo que creó la demostración, así que el script se puede
repetir.

### 1.5 Códigos de error nuevos

| Código | Dónde | Significado |
|---|---|---|
| -20050 | `sp_reservar_y_pagar`, `sp_registrar_abono` | Valor de pago ≤ 0 o mayor que el total (o que el saldo, en un abono) |
| -20051 | `sp_reservar_y_pagar`, `sp_registrar_abono` | Método de pago inválido |
| -20052 | `agregar_servicios` (interno) | Servicio inexistente, repetido o mal escrito → rollback parcial |
| -20053 | `sp_reservar_y_pagar`, `sp_registrar_abono` | Anticipo menor al 30 % |
| -20054 | `sp_registrar_abono` | La reserva no existe |
| -20055 | `sp_registrar_abono` | La reserva está cancelada: no recibe pagos |
| -20060 | `pkg_concurrencia` | La habitación la está reservando otra sesión (`NOWAIT`/`WAIT`) |

### 1.6 Abonos al saldo: `sp_registrar_abono`

Registra el pago total o un abono de una reserva ya creada (`pkg_transacciones`):

1. `SAVEPOINT sp_abono`.
2. `SELECT … FROM reserva … FOR UPDATE`: bloquea la fila **antes** de leer el saldo.
3. Valida método, saldo (-20050) y, si la reserva está PENDIENTE, que lo acumulado cubra el
   30 % (-20053). Con el anticipo cubierto, la reserva pasa a CONFIRMADA.
4. `INSERT` del pago, `UPDATE` de `valor_pagado` y `COMMIT`.
5. Cualquier error hace `ROLLBACK TO sp_abono`: deshace lo hecho y libera el bloqueo.

Sin el `FOR UPDATE`, dos cajeros que abonan a la vez leerían el mismo saldo y entre los dos
podrían cobrar más que el total (actualización perdida). Con el bloqueo, el segundo espera y
valida contra el saldo ya descontado. Prueba por la API: saldo de 84.000 y dos abonos
simultáneos de 200.000. Uno respondió 201 y el otro 400, *"no superar el saldo pendiente de
84.000"*. La demostración en SQL es la Parte D de `12_transacciones_demo.sql` (casos D0–D6).

---

## 2. Concurrencia: dos sesiones reservando la misma habitación

### 2.1 El problema

Reservar es **leer → verificar → escribir**:

1. **Leer:** ¿hay otra reserva activa de la habitación que se cruce? (`SELECT COUNT(*)`)
2. **Pensar:** el cliente confirma y la pasarela responde (pueden pasar segundos).
3. **Escribir:** `INSERT` de la reserva y `COMMIT`.

En `READ COMMITTED`, el nivel por defecto de Oracle, cada sentencia ve solo lo
**confirmado** (MVCC con UNDO: no hay lecturas sucias). Si A y B hacen el paso 1 antes
de que la otra confirme, las dos ven la habitación libre y las dos insertan. Ninguna
constraint lo impide, porque son dos filas de `RESERVA_HABITACION` con PK distinta.
Es el caso de clase *"dos clientes reservando el último cupo"*.

`pkg_concurrencia` tiene las dos versiones. Para que el cruce sea reproducible a mano,
el paso 2 se simula con `DBMS_SESSION.SLEEP(10)`:

- `sp_reservar_sin_control`: el paso 1 es un `SELECT` normal (**antes**).
- `sp_reservar_con_bloqueo`: antes del paso 1 hace `SELECT ... FROM habitacion WHERE
  id_habitacion = :h FOR UPDATE`. La fila de `HABITACION` funciona como candado: solo quien
  la tiene puede verificar y escribir reservas de esa habitación (**después**,
  bloqueo pesimista).

Datos fijos del experimento: habitación 2, del 24 al 27 de marzo de 2027 (Semana Santa).
La sesión A reserva para el cliente 10 y la sesión B para el cliente 20.

### 2.2 Escenarios

| # | Procedimiento | Trigger `trg_rh_no_solape` | Qué se demuestra |
|---|---|---|---|
| 1 | sin control | apagado | **Antes:** doble reserva |
| 2 | `FOR UPDATE` | apagado | **Después:** B **espera** el bloqueo y luego es rechazada |
| 3 | `FOR UPDATE NOWAIT` | apagado | B falla al instante (`ORA-00054`) en vez de esperar |
| 4 | sin control | **encendido** | El trigger de la Entrega 2 es la segunda línea de defensa |
| 0 | — | encendido | Restaurar al terminar |

**¿Por qué se apaga el trigger en los escenarios 1 a 3?** `trg_rh_no_solape` (Entrega 2)
ya bloquea la habitación con `FOR UPDATE WAIT 10` antes de verificar. Si estuviera
encendido, el escenario "antes" no mostraría el problema. Se apaga para medir cada
mecanismo por separado, y el escenario 4 lo vuelve a encender.

### 2.3 Cómo correrlo (3 terminales)

```bash
# Terminal 1: preparar el escenario (1, 2, 3 o 4)
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/14_concurrencia_preparar.sql 2

# Terminal 1: sesión A
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/15_concurrencia_sesion.sql 2 A

# Terminal 2: sesión B, 2-3 segundos después (mientras A "piensa")
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/15_concurrencia_sesion.sql 2 B

# Terminal 3: mientras B espera, ver quién bloquea a quién
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/16_concurrencia_monitor.sql

# Al terminar TODOS los escenarios: restaurar (borra las reservas de prueba, trigger ENABLED)
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/14_concurrencia_preparar.sql 0
```

La sesión que llega primero al paso 1 es la que gana; da igual si es A o B. Las horas que
se ven abajo son del contenedor (UTC).

### 2.4 Resultados

Salida real de una corrida; los ids de reserva y los SID cambian en cada una.

**Escenario 1 (ANTES): doble reserva.** Las dos sesiones leen al mismo tiempo, las dos ven
la habitación libre y las dos confirman:

```
[A 01:35:24.1] Inicio SIN control. Consulto disponibilidad de la habitacion 2
[A 01:35:24.1] La veo LIBRE. Confirmando con el cliente (10 s)...
[B 01:35:24.1] Inicio SIN control. Consulto disponibilidad de la habitacion 2
[B 01:35:24.1] La veo LIBRE. Confirmando con el cliente (10 s)...
[A 01:35:34.1] COMMIT. Reserva 25021 guardada para el cliente 10
[B 01:35:34.1] COMMIT. Reserva 25022 guardada para el cliente 20
Reservas activas de la habitacion 2 entre 2027-03-24 y 2027-03-27:
  reserva 25021  cliente 10  creada 01:35:34
  reserva 25022  cliente 20  creada 01:35:34
  => ERROR: DOBLE RESERVA de la misma habitacion
```

En el monitor, las dos sesiones aparecen en `PL/SQL lock timer` (el `SLEEP`), **sin
bloqueos**. Nada las coordina.

**Escenario 2 (DESPUÉS): `SELECT ... FOR UPDATE`.** B obtiene el candado primero; A se
detiene en el `FOR UPDATE` y espera los 10 segundos hasta el `COMMIT` de B. Cuando
continúa, su consulta ya ve la reserva de B:

```
[B 01:37:47.9] Inicio CON bloqueo (ESPERAR). Pido la fila de la habitacion 2
[B 01:37:47.9] Bloqueo OBTENIDO tras 0.0 s de espera
[B 01:37:47.9] La veo LIBRE. Confirmando con el cliente (10 s)...
[A 01:37:47.9] Inicio CON bloqueo (ESPERAR). Pido la fila de la habitacion 2
                 ... A esta detenida aqui ...
[B 01:37:57.9] COMMIT. Reserva 25023 guardada para el cliente 20
[A 01:37:57.9] Bloqueo OBTENIDO tras 10.0 s de espera
[A 01:37:57.9] RECHAZADA: ORA-20047: La habitacion 2 (No. 102) no esta disponible:
               otra sesion la reservo primero.
  => CORRECTO: una sola reserva
```

Monitor (`16_concurrencia_monitor.sql`) tomado mientras A esperaba:

```
=== 1. Sesiones y quien bloquea a quien ===
 SID SESION STATUS BLOQUEADA_POR EVENTO                        SEG_ESPERANDO TABLA_ESPERADA
  47 A      ACTIVE            45 enq: TX - row lock contention             4 HABITACION
  45 B      ACTIVE               PL/SQL lock timer                         4

=== 2. Bloqueos TX/TM de esas sesiones (BLOCK = 1: bloquea a otra) ===
 SID SESION TIPO MODO_TENIDO      MODO_PEDIDO  SEGUNDOS BLOCK
  45 B      TM   3 row exclusive  -                   4     0
  45 B      TX   6 exclusive      -                   4     1   ← B tiene la fila y bloquea
  47 A      TM   3 row exclusive  -                   4     0
  47 A      TX   -                6 exclusive         4     0   ← A pide la misma fila

=== 3. Objetos con filas bloqueadas ===
 SID SESION OBJETO      MODO_TENIDO
  45 B      HABITACION  row exclusive
  47 A      HABITACION  row exclusive
```

Cómo se lee:

- `BLOQUEADA_POR = 45`: la sesión A (SID 47) espera a la sesión B (SID 45).
- El evento `enq: TX - row lock contention` significa que A espera el bloqueo de una
  fila (TX) que tiene otra transacción.
- `TM row exclusive`: las dos sesiones tienen el bloqueo de **tabla** compatible (modo 3),
  que Oracle toma automáticamente con el `FOR UPDATE`. A la tabla `HABITACION` la pueden usar otros
  sin problema. El conflicto es solo por la **fila** de la habitación 2.

**Escenario 3: `FOR UPDATE NOWAIT`.** Quien llega segundo no espera: recibe `ORA-00054` al
instante y la aplicación muestra un mensaje claro. Es útil en una interfaz web, donde
dejar al usuario esperando no tiene sentido.

```
[B 01:39:37.1] Bloqueo OBTENIDO tras 0.0 s de espera
[A 01:39:37.1] RECHAZADA: ORA-00054: resource busy and acquire with NOWAIT specified or timeout expired
[A 01:39:37.1] -20060 la habitacion la esta reservando otra sesion; intente en unos segundos.
[B 01:39:47.1] COMMIT. Reserva 25024 guardada para el cliente 20
  => CORRECTO: una sola reserva
```

(Con `p_modo => 'WAIT'` se usa `FOR UPDATE WAIT 5`: espera hasta 5 s y, si no obtiene el
bloqueo, falla con `ORA-30006`, que también se traduce a -20060.)

**Escenario 4: el procedimiento sin control, pero con el trigger encendido.** Las dos
sesiones ven la habitación libre, como en el escenario 1. Al insertar, el
`AFTER STATEMENT` del trigger bloquea la habitación con `FOR UPDATE WAIT 10` y verifica
**después** de obtener el bloqueo, cuando ya ve la reserva confirmada de A:

```
[A 01:41:21.4] La veo LIBRE. Confirmando con el cliente (10 s)...
[B 01:41:21.5] La veo LIBRE. Confirmando con el cliente (10 s)...
[A 01:41:31.5] COMMIT. Reserva 25025 guardada para el cliente 10
[B 01:41:31.5] RECHAZADA: ORA-20003: La habitacion 102 ya tiene la reserva activa 25025
               que se cruza con las fechas 2027-03-24 a 2027-03-27
  => CORRECTO: una sola reserva
```

### 2.5 Comparación antes y después

| | Escenario 1 (antes) | Escenario 2 (`FOR UPDATE`) | Escenario 3 (`NOWAIT`) |
|---|---|---|---|
| Reservas guardadas | **2 (incorrecto)** | 1 | 1 |
| ¿La segunda sesión se bloquea? | No | Sí: espera 10 s en `enq: TX - row lock contention` | No: falla al instante |
| Error de la segunda sesión | ninguno | -20047 (no disponible) | `ORA-00054` → -20060 |
| Cuándo usarlo | nunca | proceso interno o batch | interfaz con usuario |

### 2.6 Cómo se aplica en el proyecto

- `pkg_turismo.sp_crear_reserva` (Entrega 2) ya usa `SELECT ... FOR UPDATE OF h.id_habitacion`
  antes de verificar disponibilidad. Este experimento muestra por qué hace falta.
- **Prevención de deadlocks:** `sp_crear_reserva` ordena por id las habitaciones pedidas
  antes de bloquearlas (`ORDER BY 1`). Si una sesión pide "5,9" y otra "9,5", las dos
  bloquean primero la 5, así que nunca se forma la espera circular (`ORA-00060`). Es la
  recomendación de clase *"acceder a los registros siempre en un orden consistente"*.
- **Bloqueo corto:** se bloquea solo la fila de la habitación (no la tabla) y solo hasta el
  `COMMIT`. El `SLEEP` del experimento exagera a propósito el tiempo de espera.
- **Por qué no `SERIALIZABLE`:** en `SERIALIZABLE`, B tampoco vería el `INSERT` de A
  (porque A lo confirma después de que B empezó), y como las dos insertan filas
  **distintas** no hay conflicto de escritura sobre la misma fila (`ORA-08177`). La doble
  reserva seguiría pasando. El problema no es el aislamiento de las lecturas sino que dos
  transacciones se pongan de acuerdo sobre un recurso, y eso lo resuelve el bloqueo
  explícito de la fila que lo representa.

### 2.7 Demostración básica de bloqueo (DBeaver, dos conexiones)

Es el ejemplo de clase "concurrencia utilizando dos sesiones", con datos del proyecto.
Se abren **dos** conexiones (en DBeaver: dos editores con *Open separate connection*,
auto-commit **desactivado**):

```sql
-- Sesión A
UPDATE tarifa SET valor = valor + 1000 WHERE id_tarifa = 1;   -- sin COMMIT

-- Sesión B: se queda "pensando" (esperando el bloqueo de la fila)
UPDATE tarifa SET valor = valor + 5000 WHERE id_tarifa = 1;

-- Terminal 3: 16_concurrencia_monitor.sql muestra B bloqueada por A en TARIFA

-- Sesión A
ROLLBACK;            -- B continúa en ese instante
-- Sesión B
ROLLBACK;            -- dejar la tarifa como estaba
```

---

## 3. Índices

```bash
docker exec -it turismouq-db sqlplus turismouq/TurismoUQ2026*@XEPDB1 @/docker-entrypoint-initdb.d/17_indices.sql
```

El script es idempotente. Borra los índices del experimento, recoge estadísticas, mide sin
índices, los crea y vuelve a medir. Al terminar, los índices quedan creados y los números
quedan en la tabla `MEDICION_INDICE`.

**Método.** Para cada consulta y cada fase se registra:

1. `EXPLAIN PLAN`: costo estimado y operaciones de acceso.
2. **200 ejecuciones reales**: lecturas lógicas (*buffers*) y milisegundos **por
   ejecución**, tomados de `V$MYSTAT`.
3. `DBMS_XPLAN.DISPLAY_CURSOR(..., 'ALLSTATS LAST')`: el plan que **de verdad** se ejecutó,
   con filas reales (`A-Rows`) y *buffers* por paso.

Números tomados sobre una base recién creada (`docker compose down -v && docker compose up -d`).
Los milisegundos cambian un poco en cada corrida; las lecturas lógicas y los costos no,
porque la carga usa una semilla fija (`DBMS_RANDOM.SEED`).

La medida principal son las **lecturas lógicas**. No dependen de la caché ni de la carga
del equipo, a diferencia de los milisegundos, que con este volumen son pequeños en los dos
casos. Las estadísticas se recogen con **histograma en `RESERVA.ESTADO`**: sus valores
están muy desbalanceados (82 % `FINALIZADA`) y, sin histograma, el optimizador supondría
un 20 % para cada uno.

### 3.1 Resultados

| Consulta | Índice | Costo antes → después | Buffers antes → después | ms antes → después | Mejora |
|---|---|---|---|---|---|
| Q1 Llegadas del día | `ix_reserva_estado_checkin (estado, fecha_checkin)` **compuesto** | 70 → 5 | 341 → 142 | 1,19 → 0,35 | 2,4× |
| Q2 Cierre de caja | `ix_pago_dia (TRUNC(fecha_pago))` **basado en función** | 104 → 38 | 316 → 60 | 6,08 → 0,05 | 5,3× |
| Q3 Agenda de servicios | `ix_rs_fecha_servicio (fecha_servicio, id_servicio, cantidad)` **compuesto que cubre** | 72 → 5 | 255 → 10 | 0,85 → 0,14 | 25,5× |
| Q4 Total FINALIZADAS | (el de Q1) | 68 (full) vs 19.446 (índice) | 247 vs **19.306** | 1,0 vs 9,5 | **78× peor** con índice |

### 3.2 Q1: Llegadas del día → índice compuesto

Recepción abre cada mañana la lista de reservas `CONFIRMADA` que llegan ese día, con el
nombre y el teléfono del huésped. Se mide con el 18-dic-2026, un día pico de la
temporada decembrina (50 llegadas).

```sql
SELECT r.id_reserva, r.num_huespedes, c.nombres, c.apellidos, c.telefono
  FROM reserva r JOIN cliente c ON c.id_cliente = r.id_cliente
 WHERE r.estado = 'CONFIRMADA' AND r.fecha_checkin = DATE '2026-12-18';
```

```
ANTES                                                   A-Rows  Buffers
|   0 | SELECT STATEMENT    |         |                     50 |    296
|*  1 |  HASH JOIN          |         |                     50 |    296
|*  2 |   TABLE ACCESS FULL | RESERVA |                     50 |    247   ← 25.000 filas para 50
|   3 |   TABLE ACCESS FULL | CLIENTE |                   3000 |     49

DESPUES
|   0 | SELECT STATEMENT                      |                       50 |     97
|*  1 |  HASH JOIN                            |                       50 |     97
|*  2 |   TABLE ACCESS BY INDEX ROWID BATCHED | RESERVA               50 |     48
|*  3 |    INDEX RANGE SCAN                   | IX_RESERVA_ESTADO_..  50 |      2   ← 2 bloques
|   4 |   TABLE ACCESS FULL                   | CLIENTE             3000 |     49
   3 - access("R"."ESTADO"='CONFIRMADA' AND "R"."FECHA_CHECKIN"=TO_DATE(' 2026-12-18 ...'))
```

**Por qué compuesto y en ese orden:**

- Las dos columnas del filtro aparecen en el `access` del `RANGE SCAN`. El índice llega
  directo a las 50 entradas en 2 bloques y no lee ninguna fila para descartarla después.
- `estado` va primero. Si recepción pide la lista **de la semana** (`=` en estado y un
  **rango** de fechas), las entradas siguen contiguas, porque dentro de `CONFIRMADA`
  están ordenadas por fecha. Con el orden `(fecha_checkin, estado)`, el rango recorrería
  las reservas de la semana de **todos** los estados y filtraría el estado después.
- El índice también sirve para `WHERE estado = ...` sola (columna líder), pero **no** para
  `WHERE fecha_checkin = ...` sola.

La mejora se queda en 2,4× porque lo que domina ahora es el `FULL` de `CLIENTE`
(49 buffers) y la lectura de las 50 filas de `RESERVA`, que están en bloques distintos
(48 buffers).

### 3.3 Q2: Cierre de caja del día → índice basado en función

Al final del día se cuadran los pagos aprobados por método de pago. `FECHA_PAGO` guarda
la hora (los pagos nuevos se registran con `SYSDATE`), así que la forma natural de pedir
"los del día" es `TRUNC(fecha_pago)`.

```sql
SELECT metodo_pago, COUNT(*) AS pagos, SUM(valor) AS total
  FROM pago
 WHERE TRUNC(fecha_pago) = DATE '2025-12-20' AND estado = 'APROBADO'
 GROUP BY metodo_pago;
```

| Fase | Plan | Buffers |
|---|---|---|
| Sin índice | `TABLE ACCESS FULL PAGO` (44.055 filas) | 316 |
| Índice **normal** sobre `fecha_pago` | `TABLE ACCESS FULL PAGO`: **no lo usa** | 316 |
| Índice sobre `TRUNC(fecha_pago)` | `INDEX RANGE SCAN IX_PAGO_DIA` | 60 |

El paso intermedio es la clave. El índice normal está ordenado por `fecha_pago`, no por
`TRUNC(fecha_pago)`, así que cuando la consulta aplica una función a la columna el
optimizador ya no puede buscar en él. El índice basado en función guarda la expresión ya
calculada, y su columna virtual oculta (`SYS_NC00007$` = `TRUNC("FECHA_PAGO")`) necesita
estadísticas propias (`FOR ALL HIDDEN COLUMNS`). La alternativa sería reescribir el
filtro como rango (`fecha_pago >= :dia AND fecha_pago < :dia + 1`). El índice basado en
función permite dejar la consulta como la escriben los usuarios.

### 3.4 Q3: Agenda de servicios del día → índice compuesto "que cubre"

Operaciones necesita saber cuántos cupos programar de cada tour, traslado o spa.
`RESERVA_SERVICIO` tiene 47.248 líneas, y para sacar las 86 del día se recorre entera.

```
ANTES                                                         A-Rows  Buffers
|*  5 |      TABLE ACCESS FULL   | RESERVA_SERVICIO     |          86 |    247
DESPUES
|*  5 |      INDEX RANGE SCAN    | IX_RS_FECHA_SERVICIO |          86 |      2
```

`fecha_servicio` va primero porque es el filtro. `id_servicio` y `cantidad` son lo único
más que la consulta lee de la tabla. Con las tres columnas en el índice, Oracle responde
**sin ir a la tabla** (no aparece `TABLE ACCESS BY INDEX ROWID`): es un índice que cubre la
consulta. De 255 a 10 buffers, 25 veces menos.

### 3.5 Q4: Caso en el que el índice NO ayuda

Gerencia pide el total facturado de las reservas `FINALIZADA`:

```sql
SELECT COUNT(*), SUM(valor_total) FROM reserva r WHERE r.estado = 'FINALIZADA';
```

`estado` ya está indexado: es la columna líder de `ix_reserva_estado_checkin`, el índice
de Q1. Aun así, el optimizador elige `TABLE ACCESS FULL`, y hace bien. Al forzar el índice
con `/*+ INDEX(r ix_reserva_estado_checkin) */`:

```
|   2 |   TABLE ACCESS BY INDEX ROWID BATCHED| RESERVA                   | 20417 |  19306
|*  3 |    INDEX RANGE SCAN                  | IX_RESERVA_ESTADO_CHECKIN | 20417 |     88
```

| | Full scan (lo que elige Oracle) | Índice forzado |
|---|---|---|
| Buffers por ejecución | **247** | 19.306 |
| Milisegundos | **1,0** | 9,5 |
| Costo estimado | **68** | 19.446 |

**Por qué:**

1. **Selectividad baja.** 20.417 de 25.000 filas (81,7 %) cumplen el filtro. El índice
   casi no descarta nada.
2. **Un acceso por fila.** Por cada una de las 20.417 entradas del índice hay que ir a la
   tabla por ROWID a leer `valor_total`, y cada acceso es un bloque.
3. **Clustering factor alto.** Es 23.699, cerca del número de filas (25.000) y muy lejos
   del número de bloques (244). Las reservas finalizadas están repartidas por toda la
   tabla, así que el índice obliga a leer los mismos 244 bloques una y otra vez: 19.306
   lecturas.
4. El `FULL SCAN` lee los 244 bloques **una sola vez**, en lecturas de varios bloques.

Regla práctica: un índice B-tree conviene cuando la consulta trae una fracción pequeña de
la tabla (en general, unas pocas unidades por ciento). Para el 82 %, recorrer la tabla es
más barato. Además, cada índice tiene un costo: cada `INSERT`/`UPDATE` de reservas debe
mantenerlo. Por eso no se crea un índice "por si acaso" sobre `estado` solo.

Otro caso de índice que no ayuda está en Q2: el índice normal sobre `fecha_pago` cuando la
consulta aplica `TRUNC` a la columna.

---

## 4. Preguntas probables

**¿Qué es una transacción y qué garantiza `sp_reservar_y_pagar`?** Una unidad de trabajo
atómica (ACID). Reserva, habitaciones, servicios y pago se confirman con **un solo
`COMMIT`**. Si el pago falla, `ROLLBACK TO sp_inicio` deshace todo lo que hizo el
procedimiento.

**¿Cuál es la diferencia entre `ROLLBACK` y `ROLLBACK TO SAVEPOINT`?** `ROLLBACK` deshace
toda la transacción y la termina. `ROLLBACK TO` deshace solo lo posterior al savepoint,
libera los bloqueos tomados desde ahí y deja la transacción **activa** (se ve en la
parte A de la demo: el UNDO vuelve de 12 a 8 registros y el estado sigue `ACTIVE`).

**¿Para qué sirve la transacción autónoma?** Para que la bitácora sobreviva al rollback de
la transacción principal. Tiene su propio `COMMIT` y no confirma nada del llamador.

**¿Qué pasa si una sesión bloquea la habitación y nunca hace `COMMIT`?** Las demás
esperan (con `FOR UPDATE`) o fallan (con `NOWAIT`/`WAIT n`). El monitor muestra el SID
bloqueador. Lo normal es que esa sesión termine su transacción; como último recurso, el
DBA puede terminarla con `ALTER SYSTEM KILL SESSION 'sid,serial#'`.

**¿El `FOR UPDATE` bloquea la tabla `HABITACION`?** No. Bloquea **una fila** (TX modo 6)
y toma un bloqueo de tabla compatible (TM modo 3, *row exclusive*), que solo impide
operaciones como `DROP` o `ALTER` de la tabla. Las demás habitaciones se reservan sin
esperar.

**¿Por qué no crear índices en todas las columnas?** Por Q4: un índice sobre una columna
poco selectiva no se usa, o si se fuerza empeora la consulta 78 veces. Y cada índice
encarece los `INSERT`/`UPDATE`/`DELETE`.

**¿Por qué el índice de Q2 necesita la misma expresión que la consulta?** Porque el
optimizador solo usa un índice basado en función si el `WHERE` contiene **exactamente**
la expresión indexada, en este caso `TRUNC(fecha_pago)`.

**¿Cuándo se usa un índice compuesto?** Cuando la consulta filtra por varias columnas. Las
columnas que se comparan con `=` van primero y la de rango al final. Si además el índice
incluye todo lo que la consulta lee, cubre la consulta y evita ir a la tabla (Q3).
