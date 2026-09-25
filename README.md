# TurismoUQ

Sistema de reservas de alojamiento turístico para el Quindío (municipios,
alojamientos, habitaciones, clientes, reservas, servicios y pagos).
Proyecto de la asignatura Bases de Datos II — Entrega 1: modelo
entidad-relación, carga de datos y consultas analíticas sobre Oracle.

## Stack

- **Backend:** Spring Boot 4.1.1 · Java 17+ · Spring Data JPA (Hibernate)
- **Base de datos:** Oracle Database XE 21c, en contenedor Docker
  (`gvenzl/oracle-xe`)

## Estructura del repo

```
src/                    Código fuente de la aplicación Spring Boot
sql/
  01_tablespaces.sql    Tablespaces y cuotas (corre como SYS)
  02_ddl.sql            Esquema: secuencias, 17 tablas, índices, comentarios
  03_carga.sql          Carga de datos: 12 municipios, 60 alojamientos,
                        400 habitaciones, 3.000 clientes, 25.000 reservas
                        (2024-2026), ~47.000 líneas de servicio
  04_consultas.sql      8 consultas analíticas (PIVOT, CUBE, RANK, LAG,
                        variables de enlace, vista materializada, UNPIVOT
                        y una consulta de negocio propuesta)
docker-compose.yml      Contenedor de Oracle XE
```

Los scripts `01`, `02` y `03` se ejecutan **automáticamente** la primera
vez que se crea el contenedor (ver sección siguiente). `04_consultas.sql`
se ejecuta a mano, cuando quieras consultar los datos ya cargados.

## Requisitos

- Docker y Docker Compose
- JDK 17 o superior (con `javac`; no basta con el JRE)

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
   Queda escuchando en `http://localhost:8080`.

3. **Para detener:**
   - La app: `Ctrl+C` en su terminal.
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
