# TurismoUQ · Frontend Angular

Aplicación web para recepción y gerencia de los alojamientos del Quindío. Consume la
API REST del proyecto ([`../API.md`](../API.md)). La lógica de negocio sigue en Oracle:
disponibilidad, tarifas por temporada, anticipo, SAVEPOINT/ROLLBACK y bloqueos.
El frontend solo la muestra y la invoca.

## Ejecutar

```bash
docker compose up -d          # en la raíz: Oracle
./mvnw spring-boot:run        # en la raíz: API en :8080
cd frontend && npm install    # solo la primera vez
npm start                     # http://localhost:4200 (proxy /api -> :8080)
```

```bash
npm test                      # pruebas unitarias (Vitest), no necesitan backend
npm run build                 # compilación de producción en dist/frontend/browser
```

## Pantallas y qué usan de la base de datos

| Pantalla | Ruta | Objeto / consulta |
|---|---|---|
| Panel | `/` | Cartera (consulta 8), variación mensual (4, `LAG`), líder por municipio (3, `RANK`), llegadas de hoy (índice compuesto) |
| Nueva reserva | `/reservar` | Disponibilidad, `fn_valor_estadia` con desglose por temporada, `sp_reservar_y_pagar` (SAVEPOINT) o `sp_crear_reserva` |
| Reserva | `/reservas/:id` | Detalle, estado financiero (consulta 7, `UNPIVOT`) y registro de pagos o abonos (`sp_registrar_abono`) |
| Operación del día | `/operacion` | Llegadas, cierre de caja y agenda: las 3 consultas aceleradas con índices (Entrega 3) |
| Huéspedes | `/huespedes`, `/huespedes/:id` | Búsqueda e historial |
| Destinos | `/destinos`, `/destinos/:id` | Municipios, alojamientos y cotizador por temporada |
| Reportes | `/reportes/*` | Consultas 1 (`PIVOT`), 2 (`CUBE`), 3, 4, 5 (variables de enlace), 6 (vista materializada y refresco), 8 |
| Liquidación | `/administracion/liquidacion` | `sp_liquidar_mes` y su salida `DBMS_OUTPUT` |
| Tarifas | `/administracion/tarifas` | Cambio de tarifa y auditoría del trigger (usuario de la app por `CLIENT_INFO`) |
| Monitor | `/administracion/monitor` | `V_MONITOR_BLOQUEOS` en vivo, `LOG_TRANSACCION` y prueba de concurrencia (dos reservas simultáneas: 201 y 409) |

En la barra superior, **N.º de reserva** abre cualquier reserva por su número. Desde su
detalle se registra el pago del saldo total o un abono.

El selector de la barra superior elige el **funcionario en turno** (`/api/usuarios`).
Su id se envía como `id_usuario_sistema` al reservar y su usuario queda en la
auditoría de tarifas. No hay inicio de sesión, porque la seguridad no entra en esta entrega.

### Demostraciones para la sustentación

- **Transacción completa:** Nueva reserva → habitaciones → huésped → un servicio → *Confirmar y pagar*.
- **ROLLBACK parcial:** en el paso 3, *Agregar servicio por código* → `999`. La reserva y el
  pago se guardan sin servicios, y la pantalla muestra el `DBMS_OUTPUT` con el `ROLLBACK TO sp_servicios`.
- **ROLLBACK total:** baje el valor a pagar por debajo del 30 %. Responde 400 (ORA-20053) y muestra
  los pasos hasta el `ROLLBACK TO sp_inicio`. Nada queda guardado salvo la bitácora (transacción autónoma).
- **Abonos:** busque una reserva por número y registre un abono menor al saldo y luego el
  saldo total. Pagar de más responde ORA-20050; a una reserva cancelada, ORA-20055.
- **Concurrencia:** Monitor → *Lanzar dos reservas a la vez*. Para ver una sesión bloqueada, abra dos
  sesiones con `sql/15_concurrencia_sesion.sql`; el monitor se actualiza cada 3 s.

## Estructura

```
src/app/
  core/
    api/        modelos.ts (contratos de la API) y un servicio HTTP por módulo
    http/       ErrorApi + interceptor: todo error llega con mensaje, código ORA y salida PL/SQL
    estado/     OperadorStore (funcionario en turno, persistido en localStorage)
    util/       consulta() (estado de carga con signals), fechas
  layout/       shell: menú lateral, barra superior
  shared/       pipes (pesos, fecha es-CO), UI (aviso, estado, kpi, salida PL/SQL…), gráficos
  features/     una carpeta por pantalla, todas con carga diferida
```

Prácticas aplicadas:
- Componentes standalone con `OnPush`, `input()`, `signal`/`computed`/`linkedSignal` y sin zone.js.
- Rutas con carga diferida; los parámetros llegan como inputs (`withComponentInputBinding`).
- Formularios reactivos tipados.
- Errores normalizados en un interceptor.
- Cada pantalla maneja sus estados de carga, error y vacío.
- Accesibilidad:
  - El estado nunca se indica solo con color: siempre lleva icono y texto.
  - Enlace para saltar al contenido.
  - Foco visible.
  - `prefers-reduced-motion`.
- Fechas `AAAA-MM-DD` interpretadas como locales, para que en Colombia no se corra el día.
- Identidad visual del paisaje cafetero:
  - Colores: verde cafetal, cereza, ámbar y crema. Las dos series de los gráficos se validaron para daltonismo.
  - Tipografía: Fraunces e Inter, servidas localmente (sin CDN).
