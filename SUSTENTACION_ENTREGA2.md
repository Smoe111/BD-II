# Guía de sustentación · Entrega 2 (PL/SQL) · TurismoUQ

Paso a paso para preparar el ambiente, demostrar cada requerimiento en vivo desde
**DBeaver** y responder las preguntas más probables.

| Requerimiento | Dónde está | Cómo se demuestra |
|---|---|---|
| `fn_valor_estadia` (tarifa por temporada, noche por noche) | `sql/07_pkg_turismo.sql:70` | Paso 4.1 |
| `sp_crear_reserva` con `RAISE_APPLICATION_ERROR` | `sql/07_pkg_turismo.sql:370` | Paso 4.2 |
| Cursor explícito con parámetros (liquidación mensual) | `sql/07_pkg_turismo.sql:159` (`c_estadias`), `OPEN` en `:240` | Paso 4.3 |
| Todo en un paquete (`PKG_TURISMO`) | `sql/07_pkg_turismo.sql:30` (spec) y `:65` (body) | Paso 4.4 |
| Trigger de sentencia: auditoría de `TARIFA` | `sql/08_triggers.sql:115` (`trg_tarifa_auditoria`) | Paso 4.5 |
| Trigger de fila: no solapar reservas | `sql/08_triggers.sql:31` (`trg_rh_no_solape`) | Paso 4.6 |
| Pruebas automáticas | `sql/10_pruebas.sql` | Paso 3 (terminal) |
| Cuadres de la liquidación | `sql/09_liquidacion_pruebas.sql` | Paso 5 (terminal) |

> **¿Por qué hay dos herramientas?** La demo en vivo (paso 4) se hace en DBeaver.
> Los scripts `09` y `10` usan comandos de SQL*Plus (`SET`, `VARIABLE`, `PROMPT`), que
> DBeaver no entiende (`SQL Error 922: missing or invalid option`). Por eso esos dos se
> corren con **un comando** desde la terminal, usando el `sqlplus` del contenedor.

---

## 0. Qué ejecuta cada script

| Script | Qué hace | ¿Corre solo al crear el contenedor? |
|---|---|---|
| `01_tablespaces.sql` | Tablespaces `ts_turismo_datos/idx/hist` y cuotas | Sí |
| `02_ddl.sql` | 17 tablas, secuencias e índices | Sí |
| `03_carga.sql` | 25.000 reservas 2024-2026 (fecha de corte de los datos: **2026-09-24**) | Sí (tarda 1-3 min) |
| `04_consultas.sql` | Consultas de la Entrega 1 + vista materializada | **No**: falla sin efecto (ver nota) → a mano |
| `05_auditoria_estructuras.sql` | Temporadas 2027 + tabla `AUDITORIA_TARIFA` | Sí |
| `06_liquidacion_tabla.sql` | Tabla `LIQUIDACION_MENSUAL` | Sí |
| `07_pkg_turismo.sql` | Paquete `PKG_TURISMO` | Sí |
| `08_triggers.sql` | Los 2 triggers | Sí |
| `09_liquidacion_pruebas.sql` | Ejecuta la liquidación y la cuadra | **No** → a mano |
| `10_pruebas.sql` | Pruebas automáticas `[PASS]/[FAIL]` | **No** → a mano |

> **Nota:** Docker corre *todos* los `.sql` de `./sql` como `SYS` en `CDB$ROOT`.
> `01-03` y `05-08` hacen `ALTER SESSION SET CONTAINER = XEPDB1` y por eso funcionan.
> `04`, `09` y `10` no lo hacen: al crear el contenedor fallan con `ORA-00942`/`ORA-06550`
> sin tocar nada. Es **esperado**.

---

## 1. Validar el ambiente (el día anterior, y otra vez antes de entrar)

### 1.1 Herramientas

```bash
docker --version
docker compose version
```

Y tener **DBeaver** instalado (Community sirve).

### 1.2 Puerto 1521 libre

```bash
ss -ltnp | grep 1521        # no debe salir nada antes de levantar el contenedor
```

### 1.3 Levantar la base de datos desde cero

```bash
cd "/home/nata/Documentos/Base de datos II/BD-II"
git status                  # limpio y en main, actualizado (git pull)
docker compose down -v      # borra contenedor y volumen (si existían)
docker compose up -d
docker logs -f turismouq-db # esperar "DATABASE IS READY TO USE!" (Ctrl+C para salir)
docker ps --filter name=turismouq-db --format '{{.Status}}'   # debe decir "healthy"
```

> Si DBeaver dice `ORA-12541: TNS:no listener`, la BD aún no termina de arrancar: espera.

### 1.4 Revisar que la carga no tuvo errores reales

```bash
docker logs turismouq-db 2>&1 | grep -nE "CONTAINER: running|ORA-|PLS-"
```

- Los `ORA-` que salen después de `04_consultas.sql`, `09_liquidacion_pruebas.sql` y
  `10_pruebas.sql` son los esperados (ver nota del paso 0).
- En `02_ddl.sql` sale **un** `ORA-00942 ... at line 15` en el bloque de limpieza
  inicial: también es esperado en una BD nueva y el resto del script corre normal.
- En `07_pkg_turismo.sql` el log dice `no rows selected` bajo "Estado del paquete":
  es porque Docker corre como `SYS`. El estado real se mira en el paso 1.6.
- Cualquier otro `ORA-`/`PLS-` en `01`, `02`, `03`, `05`, `06`, `07` u `08` **es un problema**.

### 1.5 Configurar DBeaver

**Conexión** (*Database → New Database Connection → Oracle*):

| Campo | Valor |
|---|---|
| Host | `localhost` |
| Port | `1521` |
| Database | `XEPDB1`, con el selector en **Service Name** (no SID) |
| Authentication | Oracle Database Native |
| Username / Password | `turismouq` / `TurismoUQ2026*` |
| Role | Normal |

*Test Connection*: la primera vez DBeaver descarga el driver de Oracle (necesita
internet, por eso hay que hacerlo el día anterior).

**Tres ajustes obligatorios antes de la demo:**

1. **Commit manual.** DBeaver trabaja en *auto-commit* por defecto, y la demo de
   auditoría (4.5) necesita poder hacer `ROLLBACK`. Cámbialo en la barra de
   herramientas con el botón de modo de transacción (pasa de *Auto* a *Manual*), o en
   *Edit Connection → Connection settings → Initialization → desmarcar Auto-commit*.
   Los bloques de 4.6 ya traen su propio `ROLLBACK`, así que esos son seguros en cualquier modo.
2. **Salida de `DBMS_OUTPUT`.** En el editor SQL, **`Ctrl+Shift+O`** (*Show server
   output console*). Se abre un panel *Output*: ahí aparecen los `PUT_LINE`. Actívalo
   **antes** de ejecutar.
3. **Cómo ejecutar:**
   - Una consulta `SELECT`: cursor encima y **`Ctrl+Enter`**.
   - Un bloque PL/SQL (`BEGIN ... END;` o `DECLARE ... END;`): **selecciona el bloque
     completo** con el mouse y luego `Ctrl+Enter`. Si no lo seleccionas, DBeaver lo
     corta en el primer `;` y da error.
   - Los errores salen en el panel de resultados como
     `SQL Error [20047] [72000]: ORA-20047: ...`: eso es lo que queremos mostrar.

> En DBeaver **no** uses `SET ...`, `EXEC`, `VARIABLE`, `PRINT`, `DEFINE`, `&variable`,
> `PROMPT` ni `@script.sql`: son de SQL*Plus. Todos los bloques de esta guía ya vienen sin ellos.

### 1.6 Chequeo de objetos (en DBeaver)

```sql
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name IN ('PKG_TURISMO','TRG_RH_NO_SOLAPE','TRG_TARIFA_AUDITORIA')
 ORDER BY 1, 2;
```

```sql
SELECT trigger_name, trigger_type, triggering_event, status
  FROM user_triggers;
```

```sql
SELECT (SELECT COUNT(*) FROM reserva)             AS reservas,      -- 25000
       (SELECT COUNT(*) FROM alojamiento)         AS alojamientos,  -- 60
       (SELECT COUNT(*) FROM habitacion)          AS habitaciones,  -- 400
       (SELECT MAX(fecha_fin) FROM temporada)     AS ultima_temp,   -- 2027-12-31
       (SELECT COUNT(*) FROM auditoria_tarifa)    AS auditoria,     -- 0
       (SELECT COUNT(*) FROM liquidacion_mensual) AS liquidaciones  -- 0 (se llena en el paso 5)
  FROM dual;
```

Esperado: 4 objetos `VALID`, 2 triggers `COMPOUND` y `ENABLED` (ver pregunta 1 del paso 7).

---

## 2. Orden recomendado para la sustentación (~15 min)

1. Mostrar el ambiente en DBeaver (paso 1.6), 1 min.
2. Correr las pruebas automáticas en la terminal (paso 3): impresiona, 1 min.
3. Demo en vivo en DBeaver, requerimiento por requerimiento (paso 4), 8 min.
4. Liquidación masiva y cuadres en la terminal (paso 5), 2 min.
5. Preguntas (paso 7).

Ten abiertos en DBeaver (o en el editor) `07_pkg_turismo.sql` y `08_triggers.sql`
para mostrar el código mientras explicas. Prepara un editor SQL con todos los bloques
del paso 4 ya pegados, en orden.

---

## 3. Pruebas automáticas (terminal)

```bash
echo exit | docker exec -i turismouq-db sqlplus -s 'turismouq/TurismoUQ2026*@localhost:1521/XEPDB1' @/docker-entrypoint-initdb.d/10_pruebas.sql
```

Qué revisa: objetos válidos, temporadas sin huecos, `fn_valor_estadia` (cruces de
temporada, de año, fronteras, errores), las 13 validaciones de `sp_crear_reserva`, caso
feliz, disponibilidad, el trigger de solape (INSERT, UPDATE, INSERT...SELECT) y la
auditoría (UPDATE masivo, INSERT, DELETE, `id_sentencia`, quién/cuándo).

**Resultado esperado** (verificado el 2026-10-27):

```
PASS: 59   FAIL: 0   OMITIDAS: 0
Reservas de prueba eliminadas: 4
```

> Las fechas de prueba son hoy+10..hoy+22 y las temporadas llegan a 2027-12-31:
> funciona hasta ~10-dic-2027.

---

## 4. Demostración en vivo (DBeaver)

Recuerda: **commit manual** activado, panel **Output** abierto (`Ctrl+Shift+O`),
`SELECT` con `Ctrl+Enter`, bloques PL/SQL **seleccionados** + `Ctrl+Enter`.

### 4.0 Habitación de la demo

Los bloques usan la **habitación 1** (capacidad 1, tarifa 146.000), que en una BD
recién cargada está libre en feb-mar 2027. Para confirmarlo:

```sql
SELECT h.id_habitacion, th.capacidad_maxima, t.valor AS tarifa
  FROM habitacion h
  JOIN alojamiento a      ON a.id_alojamiento      = h.id_alojamiento
  JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
  JOIN tarifa t           ON t.id_tarifa           = h.id_tarifa
 WHERE h.activo = 'S' AND a.activo = 'S'
   AND NOT EXISTS (SELECT 1
                     FROM reserva_habitacion rh
                     JOIN reserva r ON r.id_reserva = rh.id_reserva
                    WHERE rh.id_habitacion = h.id_habitacion
                      AND r.estado <> 'CANCELADA'
                      AND rh.fecha_checkin  < DATE '2027-04-01'
                      AND rh.fecha_checkout > DATE '2027-02-01')
 ORDER BY h.id_habitacion
 FETCH FIRST 5 ROWS ONLY;
```

Si la 1 no aparece, usa otra de la lista y reemplaza el `1` de la habitación en los
bloques (en `sp_crear_reserva` va entre comillas: `'1'`).

### 4.1 `fn_valor_estadia`: la función más difícil

**Qué explicar:**
- Genera **una fila por noche** con `CONNECT BY LEVEL <= noches` y la cruza con
  `TEMPORADA` (`noche BETWEEN fecha_inicio AND fecha_fin`).
- Cada noche vale `tarifa * (1 + porcentaje/100)`; el total es la suma.
- El check-out es **exclusivo** (esa noche no se cobra).
- Si alguna noche no tiene temporada, falla con `-20022` en vez de cobrarla en $0.
- Es la misma regla con la que `03_carga.sql` llenó `valor_reserva`: la función
  reproduce las 29.351 estadías cargadas sin una sola diferencia (paso 5).

**Estadía que cruza dos temporadas** (19 y 20 de marzo en temporada baja, 21 y 22 en Semana Santa +40 %):

```sql
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2027-03-19', DATE '2027-03-23') AS valor,
       (SELECT t.valor * 4.8
          FROM habitacion h JOIN tarifa t ON t.id_tarifa = h.id_tarifa
         WHERE h.id_habitacion = 1) AS esperado          -- 1 + 1 + 1.4 + 1.4
  FROM dual;
```

Esperado: `VALOR = 700800`, `ESPERADO = 700800`.

**Desglose noche por noche** (lo mismo que hace la función por dentro):

```sql
SELECT n.noche, te.nombre AS temporada, te.porcentaje,
       t.valor * (1 + te.porcentaje / 100) AS valor_noche
  FROM (SELECT DATE '2027-03-19' + LEVEL - 1 AS noche
          FROM dual CONNECT BY LEVEL <= 4) n
  JOIN temporada te ON n.noche BETWEEN te.fecha_inicio AND te.fecha_fin
 CROSS JOIN (SELECT t.valor
               FROM habitacion h JOIN tarifa t ON t.id_tarifa = h.id_tarifa
              WHERE h.id_habitacion = 1) t
 ORDER BY n.noche;
```

Esperado: 146.000, 146.000, 204.400, 204.400.

**Cruce de año** (30 y 31 dic decembrina +45 %, 1 ene vacaciones +35 %). Esperado: 620.500.

```sql
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2026-12-30', DATE '2027-01-02') AS valor FROM dual;
```

**Errores** (uno por uno, `Ctrl+Enter` en cada línea):

```sql
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2027-03-19', DATE '2027-03-19') FROM dual;      -- ORA-20020
```

```sql
SELECT pkg_turismo.fn_valor_estadia(999999, DATE '2027-03-19', DATE '2027-03-20') FROM dual; -- ORA-20021
```

```sql
SELECT pkg_turismo.fn_valor_estadia(1, DATE '2027-12-30', DATE '2028-01-02') FROM dual;      -- ORA-20022
```

### 4.2 `sp_crear_reserva` con excepciones propias

**Qué explicar:** valida fechas → cliente → usuario → huéspedes → habitaciones;
bloquea cada habitación con `FOR UPDATE` (en orden de id, para que no haya deadlock),
verifica disponibilidad, calcula el valor con `fn_valor_estadia`, inserta cabecera +
detalle y hace `COMMIT`. Ante cualquier error hace `ROLLBACK TO SAVEPOINT` y re-lanza.

**Caso feliz** (cliente 1, usuario 1 = recepción). Seleccionar todo el bloque + `Ctrl+Enter`;
el id sale en el panel *Output*:

```sql
DECLARE
  v_r NUMBER;
BEGIN
  pkg_turismo.sp_crear_reserva(1, 1, DATE '2027-02-15', DATE '2027-02-18', 1, '1', v_r);
  DBMS_OUTPUT.PUT_LINE('Reserva creada: ' || v_r);
END;
```

Ver lo que quedó guardado:

```sql
SELECT id_reserva, estado, fecha_checkin, fecha_checkout, num_huespedes,
       valor_total, valor_pagado, valor_pendiente
  FROM reserva
 WHERE id_cliente = 1 AND fecha_checkin = DATE '2027-02-15';
```

```sql
SELECT rh.*
  FROM reserva_habitacion rh JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE r.id_cliente = 1 AND r.fecha_checkin = DATE '2027-02-15';
```

Esperado: estado `PENDIENTE`, `valor_total = 438000` (3 noches de temporada baja ×
146.000), `valor_pagado = 0`.

**Las 3 excepciones que pide el enunciado**, una por una (cada bloque seleccionado +
`Ctrl+Enter`; el error aparece en rojo en el panel de resultados):

```sql
-- a) Habitación no disponible (16-17 feb cae dentro de la reserva 15-18) -> ORA-20047
DECLARE v_r NUMBER;
BEGIN
  pkg_turismo.sp_crear_reserva(2, 1, DATE '2027-02-16', DATE '2027-02-17', 1, '1', v_r);
END;
```

```sql
-- b) Checkout igual al checkin -> ORA-20040
DECLARE v_r NUMBER;
BEGIN
  pkg_turismo.sp_crear_reserva(2, 1, DATE '2027-02-25', DATE '2027-02-25', 1, '1', v_r);
END;
```

```sql
-- b') Checkout anterior al checkin -> ORA-20040
DECLARE v_r NUMBER;
BEGIN
  pkg_turismo.sp_crear_reserva(2, 1, DATE '2027-02-25', DATE '2027-02-20', 1, '1', v_r);
END;
```

```sql
-- c) Capacidad excedida (60 huéspedes en una habitación de capacidad 1, fechas libres) -> ORA-20046
DECLARE v_r NUMBER;
BEGIN
  pkg_turismo.sp_crear_reserva(2, 1, DATE '2027-02-20', DATE '2027-02-22', 60, '1', v_r);
END;
```

**Alternativa: las 3 en un solo bloque**, con los mensajes en el panel *Output*:

```sql
DECLARE
  v_r NUMBER;
  PROCEDURE probar(p_caso VARCHAR2, p_in DATE, p_out DATE, p_hues NUMBER) IS
  BEGIN
    pkg_turismo.sp_crear_reserva(2, 1, p_in, p_out, p_hues, '1', v_r);
    DBMS_OUTPUT.PUT_LINE(p_caso || ' -> no lanzo error');
  EXCEPTION WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(p_caso || ' -> ' || SQLERRM);
  END;
BEGIN
  probar('No disponible        ', DATE '2027-02-16', DATE '2027-02-17', 1);
  probar('Checkout = checkin   ', DATE '2027-02-25', DATE '2027-02-25', 1);
  probar('Checkout < checkin   ', DATE '2027-02-25', DATE '2027-02-20', 1);
  probar('Capacidad excedida   ', DATE '2027-02-20', DATE '2027-02-22', 60);
END;
```

Esperado en *Output*: `ORA-20047`, `ORA-20040`, `ORA-20040`, `ORA-20046`.

Extras si preguntan: check-in en el pasado (`-20040`), cliente inexistente (`-20041`),
usuario inexistente o un cliente reservando a nombre de otro (`-20042`), huéspedes fuera
de 1-60 (`-20043`), lista de habitaciones mal formada (`-20044`), habitaciones de
alojamientos distintos (`-20045`). Todos se prueban en el paso 3.

**Los errores no dejaron basura** (debe dar 1: solo la del caso feliz):

```sql
SELECT COUNT(*) FROM reserva WHERE fecha_checkin >= DATE '2027-02-01';
```

### 4.3 Cursor explícito con parámetros: liquidación mensual

**Qué explicar:**
- `c_estadias(p_aloj, p_ini, p_fin)` se declara **una vez** y se abre con
  `OPEN ... FETCH ... EXIT WHEN %NOTFOUND ... CLOSE` **por cada alojamiento**,
  con parámetros distintos (viajan como bind variables: un solo parse).
- Trae las estadías que **tocan** el mes (solapamiento de rangos); una estadía del
  28-feb al 3-mar se reparte entre los dos meses, **ponderando por la temporada de
  cada noche** (usa `fn_valor_estadia` como peso).
- `SAVEPOINT` por alojamiento: si uno falla, no se cae todo el lote.
- `MERGE` sobre `UNIQUE (id_alojamiento, anio, mes)`: el proceso es **idempotente**.
- Solo liquida meses cerrados (`-20031`).

**Liquidar septiembre de 2026** (el detalle por alojamiento sale en *Output*; al final
`Alojamientos liquidados: 60 - con error: 0`):

```sql
BEGIN
  pkg_turismo.sp_liquidar_mes(2026, 9);
END;
```

```sql
SELECT a.nombre, l.reservas, l.noches_vendidas, l.ingreso_hospedaje,
       l.pct_comision, l.valor_comision, l.neto_alojamiento
  FROM liquidacion_mensual l JOIN alojamiento a ON a.id_alojamiento = l.id_alojamiento
 WHERE l.anio = 2026 AND l.mes = 9
 ORDER BY l.ingreso_hospedaje DESC
 FETCH FIRST 10 ROWS ONLY;
```

Esperado arriba: *Hotel La Aurora*, 56 noches, 17.555.000, comisión 2.106.600, neto 15.448.400.

**Idempotencia:** vuelve a ejecutar el bloque de `sp_liquidar_mes(2026, 9)` y luego:

```sql
SELECT COUNT(*) FROM liquidacion_mensual WHERE anio = 2026 AND mes = 9;   -- sigue en 60
```

**Un solo alojamiento:**

```sql
BEGIN
  pkg_turismo.sp_liquidar_mes(2026, 9, 12);
END;
```

**Errores** (mensajes en *Output*):

```sql
BEGIN
  FOR c IN (SELECT 'Periodo invalido' caso, 2026 a, 13 m, NULL al FROM dual UNION ALL
            SELECT 'Mes sin cerrar', 2026, 10, NULL FROM dual UNION ALL
            SELECT 'Alojamiento inexistente', 2026, 9, 99999 FROM dual) LOOP
    BEGIN
      pkg_turismo.sp_liquidar_mes(c.a, c.m, c.al);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(RPAD(c.caso, 25) || ' -> ' || SQLERRM);
    END;
  END LOOP;
END;
```

Esperado: `ORA-20030`, `ORA-20031`, `ORA-20032`.

### 4.4 Todo agrupado en un paquete

```sql
SELECT object_name, object_type, status FROM user_objects WHERE object_name = 'PKG_TURISMO';
```

```sql
SELECT procedure_name FROM user_procedures
 WHERE object_name = 'PKG_TURISMO' AND procedure_name IS NOT NULL;
-- FN_VALOR_ESTADIA, SP_CREAR_RESERVA, SP_LIQUIDAR_MES
```

También se puede mostrar en el navegador de DBeaver: *turismouq → Packages →
PKG_TURISMO* (pestañas *Declaration* y *Body*).

Puntos a mencionar: especificación (interfaz pública + constante `c_pct_comision = 12`)
separada del cuerpo; rangos de códigos de error por programa (`-20020..22`,
`-20030..32`, `-20040..47`); `sp_crear_reserva` y `sp_liquidar_mes` reusan
`fn_valor_estadia`.

### 4.5 Trigger de sentencia: auditoría de `TARIFA`

**Qué explicar:** `trg_tarifa_auditoria` es un **COMPOUND TRIGGER**:
- `BEFORE STATEMENT`: saca un `id_sentencia` (uno por sentencia).
- `AFTER EACH ROW`: solo **acumula** en memoria `:OLD.valor` y `:NEW.valor`
  (si el valor realmente cambió).
- `AFTER STATEMENT`: escribe la bitácora **una vez por sentencia** con `FORALL`.
- Quién: `SESSION_USER` (usuario Oracle) + `CLIENT_INFO` (usuario de la app). Cuándo: `SYSTIMESTAMP`.

> ⚠️ Esta parte **requiere commit manual** (paso 1.5). Con auto-commit el `UPDATE`
> quedaría confirmado y las tarifas cambiadas para siempre.

Ejecutar en orden, uno por uno:

```sql
BEGIN
  DBMS_APPLICATION_INFO.SET_CLIENT_INFO('sustentacion');   -- el "usuario de la app"
END;
```

```sql
UPDATE tarifa SET valor = valor + 5000 WHERE id_tarifa <= 3;   -- 1 sentencia, 3 filas
```

```sql
SELECT id_sentencia, id_tarifa, operacion, usuario_bd, usuario_app,
       fecha_cambio AS cuando, valor_anterior, valor_nuevo
  FROM auditoria_tarifa
 ORDER BY id_auditoria;
```

Esperado: 3 filas con el **mismo** `id_sentencia`, `UPDATE`, `TURISMOUQ` / `sustentacion`,
146.000 → 151.000, 204.000 → 209.000 y 286.000 → 291.000.

```sql
UPDATE tarifa SET descripcion = descripcion WHERE id_tarifa = 1;   -- no toca valor: no audita
```

```sql
UPDATE tarifa SET valor = valor WHERE id_tarifa = 1;               -- mismo valor: no audita
```

```sql
SELECT COUNT(*) FROM auditoria_tarifa;     -- sigue en 3
```

```sql
ROLLBACK;     -- IMPORTANTE: deja las tarifas como estaban (la auditoría también se revierte)
```

```sql
SELECT COUNT(*) FROM auditoria_tarifa;     -- 0
```

En vez de escribir `ROLLBACK` también sirve el botón *Rollback* de la barra de DBeaver.

**Si por error quedó confirmado** (auto-commit activo), restaura así:

```sql
UPDATE tarifa SET valor = valor - 5000 WHERE id_tarifa <= 3;
COMMIT;
```

**Alternativa sin depender del modo de commit:** todo en un bloque que se deshace solo
(los registros de auditoría salen en *Output*):

```sql
BEGIN
  DBMS_APPLICATION_INFO.SET_CLIENT_INFO('sustentacion');
  UPDATE tarifa SET valor = valor + 5000 WHERE id_tarifa <= 3;
  FOR a IN (SELECT * FROM auditoria_tarifa ORDER BY id_auditoria) LOOP
    DBMS_OUTPUT.PUT_LINE('sentencia ' || a.id_sentencia || ' | tarifa ' || a.id_tarifa ||
                         ' | ' || a.operacion || ' | ' || a.usuario_bd || ' / ' || a.usuario_app ||
                         ' | ' || TO_CHAR(a.fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') ||
                         ' | ' || a.valor_anterior || ' -> ' || a.valor_nuevo);
  END LOOP;
  ROLLBACK;
END;
```

### 4.6 Trigger de fila: no solapar reservas de la misma habitación

**Qué explicar:** `trg_rh_no_solape` también es COMPOUND:
- `AFTER EACH ROW` (nivel de fila) **anota** cada fila insertada/actualizada.
- `AFTER STATEMENT` verifica el cruce contra la tabla. Así se evita
  **ORA-04091 (tabla mutante)**, que saldría si el trigger de fila consultara
  `RESERVA_HABITACION` directamente en un `UPDATE` o `INSERT ... SELECT`.
- Regla del cruce: `checkin_existente < checkout_nuevo AND checkin_nuevo < checkout_existente`
  (intervalos semiabiertos: llegar el mismo día del check-out anterior es válido).
- Las reservas `CANCELADA` no bloquean.
- Bloquea la fila de `HABITACION` (`FOR UPDATE WAIT 10`) para que dos sesiones concurrentes no pasen las dos.

Se prueba **saltándose** `sp_crear_reserva` (INSERT directo), para mostrar que la
regla se cumple aunque alguien no use el paquete. Usa la reserva del paso 4.2 (15 al
18 de feb). Cada bloque termina en `ROLLBACK`: no deja datos en ningún modo de commit.

```sql
-- a) Solape (16 al 19 de feb) -> ORA-20003
DECLARE v_id NUMBER;
BEGIN
  INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_checkin, fecha_checkout,
                       estado, num_huespedes, valor_total)
  VALUES (2, 1, DATE '2027-02-16', DATE '2027-02-19', 'CONFIRMADA', 1, 100000)
  RETURNING id_reserva INTO v_id;

  INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                  fecha_checkout, valor_previo, valor_reserva)
  VALUES (v_id, 1, DATE '2027-02-16', DATE '2027-02-19', 100000, 100000);
  ROLLBACK;
END;
```

Esperado: `ORA-20003: La habitacion 101 ya tiene la reserva activa ... que se cruza con las fechas 2027-02-16 a 2027-02-19`.

```sql
-- b) Back-to-back (llega el 18, el día del check-out) -> se permite
DECLARE v_id NUMBER;
BEGIN
  INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_checkin, fecha_checkout,
                       estado, num_huespedes, valor_total)
  VALUES (2, 1, DATE '2027-02-18', DATE '2027-02-20', 'CONFIRMADA', 1, 100000)
  RETURNING id_reserva INTO v_id;

  INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                  fecha_checkout, valor_previo, valor_reserva)
  VALUES (v_id, 1, DATE '2027-02-18', DATE '2027-02-20', 100000, 100000);
  DBMS_OUTPUT.PUT_LINE('Back-to-back insertada sin error: ' || v_id);
  ROLLBACK;
END;
```

```sql
-- c) UPDATE que mueve fechas encima de otra (caso de tabla mutante) -> ORA-20003, no ORA-04091
DECLARE v_id NUMBER;
BEGIN
  INSERT INTO reserva (id_cliente, id_usuario_sistema, fecha_checkin, fecha_checkout,
                       estado, num_huespedes, valor_total)
  VALUES (2, 1, DATE '2027-02-25', DATE '2027-02-27', 'CONFIRMADA', 1, 100000)
  RETURNING id_reserva INTO v_id;

  INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                  fecha_checkout, valor_previo, valor_reserva)
  VALUES (v_id, 1, DATE '2027-02-25', DATE '2027-02-27', 100000, 100000);
  DBMS_OUTPUT.PUT_LINE('Insertada sin cruce: ' || v_id);

  UPDATE reserva_habitacion                     -- se mueve encima del 15-18 de feb
     SET fecha_checkin = DATE '2027-02-16', fecha_checkout = DATE '2027-02-18'
   WHERE id_reserva = v_id;
  ROLLBACK;
END;
```

### 4.7 Limpieza después de la demo

```sql
DELETE FROM reserva WHERE id_cliente = 1 AND fecha_checkin = DATE '2027-02-15';  -- el detalle cae por ON DELETE CASCADE
```

```sql
COMMIT;
```

```sql
SELECT COUNT(*) FROM reserva;   -- 25000
```

---

## 5. Liquidación masiva y cuadres (terminal)

```bash
echo exit | docker exec -i turismouq-db sqlplus -s 'turismouq/TurismoUQ2026*@localhost:1521/XEPDB1' @/docker-entrypoint-initdb.d/09_liquidacion_pruebas.sql
```

Liquida todos los meses cerrados desde 2024-01 y verifica:

| Chequeo | Esperado | Verificado el 2026-10-27 |
|---|---|---|
| 2.1 `fn_valor_estadia` vs `valor_reserva` de la carga | `diferencias = 0` | 29.351 estadías, 0 diferencias |
| 2.2 Periodos con alojamientos faltantes | sin filas | `no rows selected` |
| 2.3 Noches liquidadas vs cálculo SQL independiente | `diferencia = 0` | 2024: 20.728 = 20.728 · 2025: 24.005 = 24.005 |
| 2.4 Valor del cursor vs mismo prorrateo en un solo SQL | `descuadres = 0` | 1.980 cortes, 0 descuadres |
| 2.5 / 2.6 Reportes | top 10 de 2026-06 y devengado vs recaudado | — |

Tarda unos 15 segundos. Después, en DBeaver, se pueden mostrar los resultados:

```sql
SELECT anio, mes, SUM(ingreso_hospedaje) AS devengado, SUM(recaudo_caja) AS recaudado,
       SUM(valor_comision) AS comision, SUM(neto_alojamiento) AS neto
  FROM liquidacion_mensual
 GROUP BY anio, mes
 ORDER BY anio, mes;
```

---

## 6. Tabla de códigos de error

| Código | Programa | Significado |
|---|---|---|
| -20003 | `trg_rh_no_solape` | La habitación ya tiene una reserva activa que se cruza |
| -20020 | `fn_valor_estadia` | Check-out no posterior al check-in |
| -20021 | `fn_valor_estadia` | Habitación inexistente |
| -20022 | `fn_valor_estadia` | Noches sin temporada definida |
| -20030 | `sp_liquidar_mes` | Periodo inválido |
| -20031 | `sp_liquidar_mes` | Mes aún no cerrado |
| -20032 | `sp_liquidar_mes` | Alojamiento inexistente |
| -20040 | `sp_crear_reserva` | Fechas: nulas, check-out ≤ check-in, o check-in en el pasado |
| -20041 | `sp_crear_reserva` | Cliente inexistente |
| -20042 | `sp_crear_reserva` | Usuario inexistente/inactivo o reserva a nombre de otro cliente |
| -20043 | `sp_crear_reserva` | Número de huéspedes inválido |
| -20044 | `sp_crear_reserva` | Lista de habitaciones vacía, mal formada, repetida, inexistente o inactiva |
| -20045 | `sp_crear_reserva` | Alojamiento inactivo o habitaciones de distintos alojamientos |
| -20046 | `sp_crear_reserva` | Capacidad excedida |
| -20047 | `sp_crear_reserva` | Habitación no disponible |

---

## 7. Preguntas probables y cómo responderlas

1. **"Pedí un trigger de sentencia y uno de fila, ¿por qué los dos son COMPOUND?"**
   El de auditoría necesita `:OLD` y `:NEW`, que un trigger de sentencia puro no tiene.
   El compound escribe la bitácora en `AFTER STATEMENT` (una vez por sentencia, con un
   `id_sentencia` común) y usa `AFTER EACH ROW` solo para capturar valores. El de solape
   es de fila (`AFTER EACH ROW` por cada fila), pero consultar la propia tabla desde ahí
   da `ORA-04091`, por eso verifica en `AFTER STATEMENT`.

2. **"Si `sp_crear_reserva` ya valida disponibilidad, ¿para qué el trigger?"**
   El SP da un mensaje claro (`-20047`) para el flujo normal. El trigger es la última
   barrera: protege ante INSERT/UPDATE directos (como en 4.6), cargas masivas u otra aplicación.

3. **"¿Qué pasa si dos usuarios reservan la misma habitación al mismo tiempo?"**
   `FOR UPDATE` sobre `HABITACION` serializa: el segundo espera a que el primero haga
   commit, y luego ve la reserva y falla con `-20047`. Se bloquean en orden de id para no
   provocar deadlocks. (Se puede demostrar con dos editores SQL de DBeaver: cada uno abre
   su propia sesión.)

4. **"¿Por qué la noche del check-out no se cobra?"**
   Intervalos semiabiertos `[checkin, checkout)`: así 3 noches = checkout − checkin, y
   alguien puede llegar el mismo día que otro sale.

5. **"¿Por qué el cursor lleva parámetros?"**
   Se declara una vez y se reabre por cada alojamiento con valores distintos; los
   parámetros van como variables de enlace (una sola sentencia analizada).

6. **"¿Por qué la liquidación usa `valor_reserva` y no recalcula con la tarifa?"**
   Se liquida lo que el cliente pagó. Si la tarifa cambia después, no altera cortes pasados.
   `fn_valor_estadia` solo se usa como **peso** para repartir estadías entre dos meses.

7. **"¿Qué pasa si corro la liquidación dos veces?"**
   `MERGE` + `UNIQUE (id_alojamiento, anio, mes)` → actualiza, no duplica.

8. **"¿Y si falla un alojamiento en medio del lote?"**
   `SAVEPOINT` por alojamiento + `ROLLBACK TO` y se sigue con el siguiente; se cierra el
   cursor si quedó abierto (si no, el siguiente `OPEN` daría `ORA-06511`).

9. **"¿Por qué agregaron temporadas 2027?"**
   La carga cubre 2024-2026. Sin 2027, cualquier reserva a partir del 1-ene-2027 fallaría
   con `-20022`. El enunciado permite agregar tablas/datos pero no quitar.

10. **"¿El ROLLBACK borra la auditoría?"**
    Sí: el trigger escribe en la misma transacción. Es lo correcto: si el cambio no se
    confirmó, no ocurrió. (Para auditar intentos fallidos se usaría `PRAGMA AUTONOMOUS_TRANSACTION`.)

---

## 8. Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| `SQL Error [922]: ORA-00922: missing or invalid option` | Se ejecutó un comando de SQL*Plus (`SET`, `EXEC`, `VARIABLE`...) en DBeaver. Usar los bloques de esta guía. |
| DBeaver pide valores para `:r` o `&hab` | Igual que arriba: son variables de SQL*Plus. Usar los bloques de esta guía. |
| `ORA-06550` / `PLS-00103` al ejecutar un bloque | No se seleccionó el bloque completo antes de `Ctrl+Enter`. |
| No aparece nada de `DBMS_OUTPUT` | Abrir el panel con `Ctrl+Shift+O` **antes** de ejecutar. |
| Tarifas quedaron cambiadas tras 4.5 | Estaba en auto-commit: `UPDATE tarifa SET valor = valor - 5000 WHERE id_tarifa <= 3; COMMIT;` |
| `ORA-12541: TNS:no listener` | La BD aún arranca. Esperar `healthy`. |
| `ORA-12514` / no conecta | En DBeaver se eligió **SID** en vez de **Service Name** para `XEPDB1`. |
| `ORA-01017: invalid username/password` | En la terminal: faltan las comillas simples alrededor de `'turismouq/TurismoUQ2026*@...'`. |
| `port is already allocated` (1521) | Otro Oracle corriendo: `docker ps` y detenerlo. |
| Los triggers o `AUDITORIA_TARIFA` no existen | Volumen viejo. `docker compose down -v && docker compose up -d`. |
| `PKG_TURISMO` `INVALID` | `echo exit \| docker exec -i turismouq-db sqlplus -s 'turismouq/TurismoUQ2026*@localhost:1521/XEPDB1' @/docker-entrypoint-initdb.d/07_pkg_turismo.sql` |
| `ORA-20022` en la demo | Fechas fuera de 2024-2027. |
| `ORA-20047` inesperado en el caso feliz de 4.2 | La reserva ya existía (se corrió dos veces): hacer la limpieza de 4.7, o usar otra habitación del paso 4.0. |

La aplicación Spring Boot (`./mvnw spring-boot:run`) no hace falta para esta entrega.

---

## 9. Checklist final

- [ ] `git pull` en `main` y `git status` limpio
- [ ] `docker compose down -v && docker compose up -d` → `healthy`
- [ ] Logs sin `ORA-` inesperados (paso 1.4)
- [ ] DBeaver: conexión con **Service Name** `XEPDB1`, driver descargado
- [ ] DBeaver: **commit manual** activado y panel **Output** (`Ctrl+Shift+O`) abierto
- [ ] Paso 1.6: paquete y 2 triggers `VALID`/`ENABLED`, temporadas hasta 2027-12-31
- [ ] Terminal: `10_pruebas.sql` → `PASS: 59  FAIL: 0`
- [ ] Editor SQL de DBeaver con todos los bloques del paso 4 pegados en orden
- [ ] `07_pkg_turismo.sql` y `08_triggers.sql` abiertos para mostrar el código
- [ ] Repasar la sección 7

---

## 10. Resultado de cada script

Las cifras son las de una BD recién creada (verificadas el 2026-10-27).

### `01_tablespaces.sql`: tablespaces y cuotas
Crea en la PDB `XEPDB1` los tres tablespaces del proyecto: `TS_TURISMO_DATOS` (catálogos
y maestros), `TS_TURISMO_IDX` (índices) y `TS_TURISMO_HIST` (tablas que crecen con el
tiempo: reservas, pagos, auditoría, liquidación). Le da cuota ilimitada a `turismouq`.
**Resultado:** el mensaje `Tablespaces creados y cuotas asignadas a turismouq.` en el log.
Con el esquema completo quedan 12 tablas en `TS_TURISMO_DATOS` y 7 en `TS_TURISMO_HIST`.

### `02_ddl.sql`: esquema
Limpia el esquema y crea las **17 tablas** del modelo, con sus secuencias (usadas como
`DEFAULT` de las PK), llaves foráneas, `CHECK`, índices en tablespace propio y comentarios.
**Resultado:** el esquema vacío y listo para la carga. El único error del log,
`ORA-00942 ... at line 15`, es del bloque de limpieza inicial y es esperado (paso 1.4).

### `03_carga.sql`: datos de prueba
Genera los datos como si "hoy" fuera el 2026-09-24. El precio de cada estadía se calcula
noche por noche con la temporada, la misma regla de `fn_valor_estadia`.
**Resultado:** imprime el volumen contra el mínimo exigido, y todo sale `OK`:

| Tabla | Filas | Tabla | Filas |
|---|---|---|---|
| municipio | 12 | reserva | 25.000 |
| alojamiento | 60 | reserva_habitacion | 29.351 |
| habitacion | 400 | reserva_servicio | 47.248 |
| cliente | 3.000 | pago | 44.055 |
| usuario_sistema | 2.151 | resena | 8.119 |
| tarifa | 204 | temporada | 27 (2024-2026) |

Reservas por estado: 20.417 finalizadas, 2.282 canceladas, 1.789 confirmadas, 470
pendientes y 42 en curso. Termina con 5 autocontroles que **deben dar 0**: temporadas con
huecos, reservas activas solapadas, reservas que mezclan alojamientos, cabeceras que no
cuadran con su detalle y pagos que no cuadran. Los 5 dan 0.

### `04_consultas.sql`: consultas analíticas (Entrega 1)
Ocho consultas: (1) ocupación por municipio y mes con `PIVOT`, (2) ingresos por municipio,
tipo y temporada con `CUBE` (crea la vista `v_rh_temporada`), (3) top 3 de alojamientos
por municipio con `RANK`, (4) variación mes a mes con `LAG`, (5) reservas por rango con
variables de enlace, (6) vista materializada `mv_ocupacion_mensual`, (7) `UNPIVOT` del
estado financiero de la reserva y (8) cartera pendiente por municipio.
**Resultado:** al crear el contenedor no hace nada (corre en `CDB$ROOT`, ver paso 0). A
mano deja creadas la vista y la vista materializada e imprime los ocho reportes. No es
parte de la Entrega 2.

### `05_auditoria_estructuras.sql`: apoyo de la capa PL/SQL
Agrega las **9 temporadas de 2027**, con el mismo calendario de los años anteriores y
Semana Santa del 21 al 28 de marzo, y crea la tabla `AUDITORIA_TARIFA` con sus dos
secuencias (`seq_auditoria_tarifa` y `seq_auditoria_sentencia`).
**Resultado:** 36 temporadas, continuas del 2024-01-01 al 2027-12-31, y la tabla de
auditoría vacía (0 filas). Sin este script no se podría reservar después del 31-dic-2026.

### `06_liquidacion_tabla.sql`: tabla de la liquidación
Crea `LIQUIDACION_MENSUAL` con `UNIQUE (id_alojamiento, anio, mes)`, que hace la
liquidación idempotente, y un `CHECK` que obliga a que `neto = hospedaje − comisión`.
**Resultado:** la tabla vacía; la llena `sp_liquidar_mes` (paso 4.3 y script 09).

### `07_pkg_turismo.sql`: paquete `PKG_TURISMO`
Compila la especificación y el cuerpo con `fn_valor_estadia`, `sp_liquidar_mes` (cursor
explícito con parámetros) y `sp_crear_reserva`.
**Resultado:** `Package created.`, `Package body created.` y `No errors.` en el log. En la
BD: `PACKAGE` y `PACKAGE BODY` en estado `VALID` (paso 1.6).

### `08_triggers.sql`: disparadores
Crea `trg_rh_no_solape` (de fila, sobre `RESERVA_HABITACION`) y `trg_tarifa_auditoria`
(de sentencia, sobre `TARIFA`), los dos como `COMPOUND TRIGGER`.
**Resultado:** `Trigger created.` y `No errors.` dos veces. En la BD: ambos `VALID` y
`ENABLED`. Desde aquí cualquier reserva que se cruce falla con `-20003`, y todo cambio de
tarifa queda en la bitácora.

### `09_liquidacion_pruebas.sql`: liquidación y cuadres (a mano)
Liquida junio de 2026 (todo el mes, un solo alojamiento y una repetición), prueba los 3
errores del procedimiento y después liquida **todos los meses cerrados** desde 2024-01.
Al final cuadra el resultado del cursor contra cálculos independientes en SQL.
**Resultado:** 1.980 cortes (60 alojamientos × 33 meses, de 2024-01 a 2026-09) y todos los
controles en cero: 0 diferencias entre `fn_valor_estadia` y lo cargado (29.351 estadías),
0 periodos incompletos, 0 noches de diferencia en 2024 (20.728) y 2025 (24.005), y 0
descuadres de valor. Termina con el top 10 de junio de 2026 y la tabla de devengado
contra recaudado por mes. Tarda unos 15 s.

### `10_pruebas.sql`: pruebas automáticas (a mano)
Corre 59 pruebas en 8 grupos: prerrequisitos (0), `fn_valor_estadia` (A), validaciones de
`sp_crear_reserva` (B1), caso feliz (B2), disponibilidad (B3), cuenta de cliente (B4),
trigger de solape (C) y auditoría (D). Cada una
imprime `[PASS]` o `[FAIL]`. Todo lo que crea se deshace (savepoints y borrado final).
**Resultado:** `PASS: 59   FAIL: 0   OMITIDAS: 0` y `Reservas de prueba eliminadas: 4`. La
BD queda igual que antes de correrlo (25.000 reservas, auditoría vacía).
