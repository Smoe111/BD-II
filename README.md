# TurismoUQ

Sistema de reservas de alojamiento turístico para el Quindío (municipios,
alojamientos, habitaciones, clientes, reservas, servicios y pagos).
Proyecto de la asignatura Bases de Datos II — Entrega 1: modelo
entidad-relación, carga de datos y consultas analíticas sobre Oracle.

## Stack

- **Backend:** Spring Boot 4.1.1 · Java 17+ · API REST sobre JDBC (`JdbcClient`) que
  llama los paquetes PL/SQL; ver [`API.md`](API.md)
- **Frontend:** Angular 21 (componentes standalone, signals, carga diferida); ver
  [`frontend/README.md`](frontend/README.md)
- **Base de datos:** Oracle Database XE 21c, en contenedor Docker
  (`gvenzl/oracle-xe`)

## Estructura del repo

```
src/                    API REST Spring Boot (ver API.md)
frontend/               Aplicacion web Angular (ver frontend/README.md)
API.md                  Endpoints, decisiones y codigos de error de la API
api.http                Solicitudes listas para probar cada endpoint
sql/
  01_tablespaces.sql    Tablespaces, cuotas y permisos de diagnostico (corre como SYS)
  02_ddl.sql            Esquema: secuencias, 17 tablas, indices, comentarios
  03_carga.sql          Carga de datos: 12 municipios, 60 alojamientos,
                        400 habitaciones, 3.000 clientes, 25.000 reservas
                        (2024-2026), ~47.000 lineas de servicio
  04_consultas.sql      Entrega 1: 8 consultas analiticas (a mano)
  05_auditoria_estructuras.sql  Entrega 2: temporadas 2027 y AUDITORIA_TARIFA
  06_liquidacion_tabla.sql      Entrega 2: tabla LIQUIDACION_MENSUAL
  07_pkg_turismo.sql            Entrega 2: paquete PKG_TURISMO
  08_triggers.sql               Entrega 2: trg_rh_no_solape y trg_tarifa_auditoria
  09_liquidacion_pruebas.sql    Entrega 2: liquidacion y cuadres (a mano)
  10_pruebas.sql                Entrega 2: pruebas automaticas (a mano)
  11_pkg_transacciones.sql      Entrega 3: reserva + pago atomicos (SAVEPOINT)
  12_transacciones_demo.sql     Entrega 3: demo de rollback parcial/total (a mano)
  13_pkg_concurrencia.sql       Entrega 3: paquete y vista del experimento
  14_concurrencia_preparar.sql  Entrega 3: prepara cada escenario (a mano)
  15_concurrencia_sesion.sql    Entrega 3: lo que corre cada sesion (a mano)
  16_concurrencia_monitor.sql   Entrega 3: quien bloquea a quien (a mano)
  17_indices.sql                Entrega 3: indices, planes y medicion (a mano)
ENTREGA3.md             Documentacion y resultados de la Entrega 3
docker-compose.yml      Contenedor de Oracle XE
```

Los scripts que crean objetos (`01`-`03`, `05`-`08`, `11` y `13`) se
ejecutan **automáticamente** la primera vez que se crea el contenedor (ver
sección siguiente). Los marcados "a mano" se ejecutan después, como
`turismouq`; ver `ENTREGA3.md` para los de la Entrega 3.

## Requisitos

- Docker y Docker Compose
- JDK 17 o superior (con `javac`; no basta con el JRE)
- Node.js 22.12+ o 24 y npm (solo para el frontend)

## Cómo levantar el proyecto

1. **Base de datos** (primera vez tarda 2-5 minutos: crea la BD y corre
   `01_tablespaces.sql` → `02_ddl.sql` → `03_carga.sql`):
   ```bash
   docker compose up -d
   ```
   Verificar que quedó lista:
   ```bash
   docker ps --filter name=turismouq-db --format '{{.Status}}'   # debe decir "healthy"
   ```

2. **Aplicación Spring Boot:**
   ```bash
   ./mvnw spring-boot:run
   ```
   Queda escuchando en `http://localhost:8080`. Los endpoints están en
   [`API.md`](API.md) y se prueban con `api.http`.

3. **Frontend Angular** (en otra terminal):
   ```bash
   cd frontend
   npm install        # solo la primera vez
   npm start          # http://localhost:4200
   ```
   `ng serve` reenvía `/api` al backend (`proxy.conf.json`).

4. **Para detener:**
   - La app y el frontend: `Ctrl+C` en su terminal.
   - La base de datos: `docker compose down` (conserva los datos) o
     `docker compose down -v` (borra el volumen también).

### Recargar los datos desde cero

Los scripts de `sql/` solo se ejecutan la **primera vez** que se crea el
volumen de datos. Si los editas y quieres que Docker los vuelva a correr:

```bash
docker compose down -v
docker compose up -d
```

## Conexión a la base de datos

| Parámetro     | Valor                          |
|---------------|---------------------------------|
| Host          | `localhost`                     |
| Puerto        | `1521`                          |
| Service name  | `XEPDB1` (no es un SID)         |
| Usuario       | `turismouq`                     |
| Password      | `TurismoUQ2026*`                |

```bash
sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1
```

## Cómo ejecutar las consultas analíticas

**Opción A — las 8 de una sola vez:**
```bash
sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @sql/04_consultas.sql
```

**Opción B — una consulta a la vez:**
Abre `sql/04_consultas.sql` en SQL Developer, DBeaver o la extensión SQL
de tu editor, conéctate con las credenciales de arriba, selecciona el
bloque de la consulta que quieras (desde su comentario `-- N.` hasta el
`;` final) y ejecuta solo esa selección.

Detalles a tener en cuenta:

- **Consulta 5** usa variables de enlace (`VARIABLE` + `EXEC`), sintaxis
  propia de SQL*Plus. En una herramienta gráfica sin soporte de bind
  variables, reemplaza `:fecha_inicio` / `:fecha_fin` por fechas
  literales en el `WHERE`.
- **Consulta 6** crea la vista materializada `mv_ocupacion_mensual`. Si
  vuelves a correr el script completo una segunda vez, ese `CREATE
  MATERIALIZED VIEW` fallará porque ya existe — primero
  `DROP MATERIALIZED VIEW mv_ocupacion_mensual;` o comenta ese bloque.
  Para refrescarla con datos nuevos sin recrearla:
  ```sql
  EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
  ```
