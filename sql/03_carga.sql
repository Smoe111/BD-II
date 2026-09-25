-- =====================================================================
-- TurismoUQ · Bases de Datos II · Entrega 1
-- Script 03 · Carga de datos
-- ---------------------------------------------------------------------
-- EJECUTAR COMO: turismouq       Duracion aproximada: 1 a 3 minutos
--
--   sqlplus turismouq/TurismoUQ2026*@localhost:1521/XEPDB1 @03_carga.sql
--
-- Volumen minimo exigido           Generado por este script
--   12 municipios                    12
--   60 alojamientos                  60
--   400 habitaciones                 400
--   3.000 clientes                   3.000
--   25.000 reservas 2024-2026        25.000
--   40.000 lineas de servicios       ~47.000
--
-- Reglas que respeta la generacion (y que las consultas aprovechan):
--   * Ninguna habitacion tiene dos reservas activas que se solapen.
--     Las canceladas no bloquean, como en la vida real.
--   * El valor de una estadia se calcula NOCHE POR NOCHE:
--         tarifa.valor * (1 + temporada.porcentaje / 100)
--     con la temporada en que cae cada noche. Es la misma regla que
--     debera reproducir fn_valor_estadia en la Entrega 2, asi que los
--     valores guardados aqui son la respuesta correcta esperada.
--   * Estacionalidad: se llega mas en temporada alta y los viernes y
--     sabados, y la demanda crece de 2024 a 2026.
--   * En temporada alta se reserva con mas anticipacion y se cancela
--     mas (lo explota la consulta 8).
--
-- FECHA DE CORTE: los datos se generan como si "hoy" fuera c_corte.
-- Lo anterior queda FINALIZADA, lo que cruza el corte EN_CURSO y lo
-- posterior CONFIRMADA o PENDIENTE. Es fija para que la carga sea
-- reproducible sin importar el dia en que se ejecute.
--
-- SEMILLA: con la misma semilla salen exactamente los mismos datos.
-- El enunciado anula dos proyectos con los mismos datos:
-- CAMBIEN ESTE NUMERO por uno propio del equipo antes de entregar.
-- =====================================================================

-- Ejecutado por Docker: la sesion conecta AS SYSDBA en CDB$ROOT. Hay que
-- pasar a la PDB de la aplicacion y actuar como turismouq (sin conocer su
-- password) para que los datos queden en su esquema, no en SYS.
ALTER SESSION SET CONTAINER = XEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = turismouq;

SET SERVEROUTPUT ON SIZE UNLIMITED
SET TIMING ON

EXEC DBMS_RANDOM.SEED(20260924);

-- ---------------------------------------------------------------------
-- 0. Limpieza de datos (hijos antes que padres)
-- ---------------------------------------------------------------------
BEGIN
  DELETE FROM resena;
  DELETE FROM pago;
  DELETE FROM reserva_servicio;
  DELETE FROM reserva_habitacion;
  DELETE FROM reserva;
  DELETE FROM usuario_sistema;
  DELETE FROM cliente;
  DELETE FROM servicio;
  DELETE FROM habitacion;
  DELETE FROM alojamiento;
  DELETE FROM tarifa;
  DELETE FROM temporada;
  DELETE FROM tipo_servicio;
  DELETE FROM tipo_habitacion;
  DELETE FROM tipo_alojamiento;
  DELETE FROM tipo_documento;
  DELETE FROM municipio;
  COMMIT;
END;
/

-- =====================================================================
-- 1. CATALOGOS
--    UNISTR escribe las tildes por su codigo Unicode para que el texto
--    llegue bien sin importar la codificacion del cliente SQL.
-- =====================================================================
INSERT INTO tipo_documento VALUES (1, UNISTR('C\00E9dula de ciudadan\00EDa'));
INSERT INTO tipo_documento VALUES (2, UNISTR('C\00E9dula de extranjer\00EDa'));
INSERT INTO tipo_documento VALUES (3, 'Pasaporte');
INSERT INTO tipo_documento VALUES (4, UNISTR('Permiso por protecci\00F3n temporal'));
INSERT INTO tipo_documento VALUES (5, 'Tarjeta de identidad');

INSERT INTO municipio VALUES ( 1, 'Armenia');
INSERT INTO municipio VALUES ( 2, 'Buenavista');
INSERT INTO municipio VALUES ( 3, UNISTR('Calarc\00E1'));
INSERT INTO municipio VALUES ( 4, 'Circasia');
INSERT INTO municipio VALUES ( 5, UNISTR('C\00F3rdoba'));
INSERT INTO municipio VALUES ( 6, 'Filandia');
INSERT INTO municipio VALUES ( 7, UNISTR('G\00E9nova'));
INSERT INTO municipio VALUES ( 8, 'La Tebaida');
INSERT INTO municipio VALUES ( 9, 'Montenegro');
INSERT INTO municipio VALUES (10, 'Pijao');
INSERT INTO municipio VALUES (11, 'Quimbaya');
INSERT INTO municipio VALUES (12, 'Salento');

INSERT INTO tipo_alojamiento VALUES (1, 'Finca cafetera');
INSERT INTO tipo_alojamiento VALUES (2, 'Hotel');
INSERT INTO tipo_alojamiento VALUES (3, 'Glamping');
INSERT INTO tipo_alojamiento VALUES (4, 'Hostal');
INSERT INTO tipo_alojamiento VALUES (5, 'Ecohotel');

INSERT INTO tipo_habitacion VALUES (1, 'Sencilla', 1);
INSERT INTO tipo_habitacion VALUES (2, 'Doble',    2);
INSERT INTO tipo_habitacion VALUES (3, 'Triple',   3);
INSERT INTO tipo_habitacion VALUES (4, 'Familiar', 5);
INSERT INTO tipo_habitacion VALUES (5, 'Suite',    2);
INSERT INTO tipo_habitacion VALUES (6, 'Domo',     2);

INSERT INTO tipo_servicio VALUES (1, UNISTR('Alimentaci\00F3n'));
INSERT INTO tipo_servicio VALUES (2, 'Tours y experiencias');
INSERT INTO tipo_servicio VALUES (3, 'Transporte');
INSERT INTO tipo_servicio VALUES (4, 'Bienestar');
INSERT INTO tipo_servicio VALUES (5, UNISTR('Recreaci\00F3n'));

INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (1, 3, 90000, UNISTR('Traslado aeropuerto El Ed\00E9n'));
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (2, 2, 120000, 'Tour Valle de Cocora');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (3, 2, 95000, UNISTR('Tour del caf\00E9 con cataci\00F3n'));
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (4, 5, 110000, UNISTR('Entrada Parque del Caf\00E9'));
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (5, 5, 95000, 'Entrada PANACA');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (6, 5, 50000, 'Cabalgata');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (7, 2, 80000, 'Avistamiento de aves');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (8, 5, 220000, 'Vuelo en parapente');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (9, 4, 90000, 'Spa y sauna');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (10, 5, 60000, 'Canopy');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (11, 3, 70000, 'Recorrido en Willys');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (12, 2, 85000, 'Tour Filandia y Salento');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (13, 1, 55000, UNISTR('Cena t\00EDpica regional'));
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (14, 5, 130000, UNISTR('Rafting r\00EDo Barrag\00E1n'));
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (15, 3, 250000, UNISTR('Alquiler de veh\00EDculo'));
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (16, 1, 32000, 'Desayuno campesino');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (17, 4, 120000, 'Masaje relajante');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (18, 2, 45000, 'Recorrido por el cafetal');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (19, 1, 85000, 'Cena bajo las estrellas');
INSERT INTO servicio (id_servicio, id_tipo_servicio, valor_servicio, nombre) VALUES (20, 5, 40000, 'Alquiler de bicicleta');

COMMIT;

-- =====================================================================
-- 2. TEMPORADAS · 9 por anio, 27 en total, cubren 2024-2026 sin huecos
--    porcentaje = ajuste sobre la tarifa base de la habitacion
-- =====================================================================
DECLARE
  v_id NUMBER := 0;
  TYPE t_fechas IS TABLE OF DATE INDEX BY PLS_INTEGER;
  ss_ini t_fechas;
  ss_fin t_fechas;

  FUNCTION f(p_anio PLS_INTEGER, p_mmdd VARCHAR2) RETURN DATE IS
  BEGIN
    RETURN TO_DATE(p_anio || '-' || p_mmdd, 'YYYY-MM-DD');
  END;

  PROCEDURE ins(p_nombre VARCHAR2, p_desc VARCHAR2, p_pct NUMBER,
                p_ini DATE, p_fin DATE) IS
  BEGIN
    v_id := v_id + 1;
    INSERT INTO temporada (id_temporada, nombre, descripcion, porcentaje,
                           fecha_inicio, fecha_fin)
    VALUES (v_id, p_nombre, p_desc, p_pct, p_ini, p_fin);
  END;
BEGIN
  -- Semana Santa: del Domingo de Ramos al Domingo de Resurreccion
  ss_ini(2024) := DATE '2024-03-24';  ss_fin(2024) := DATE '2024-03-31';
  ss_ini(2025) := DATE '2025-04-13';  ss_fin(2025) := DATE '2025-04-20';
  ss_ini(2026) := DATE '2026-03-29';  ss_fin(2026) := DATE '2026-04-05';

  FOR y IN 2024 .. 2026 LOOP
    ins('Vacaciones de enero',  'Cierre de las vacaciones escolares ' || y,
        35, f(y,'01-01'), f(y,'01-15'));
    ins('Temporada baja',       'Enero a marzo ' || y,
         0, f(y,'01-16'), ss_ini(y) - 1);
    ins('Semana Santa',         'Domingo de Ramos a Resurreccion ' || y,
        40, ss_ini(y), ss_fin(y));
    ins('Temporada baja',       'Abril a junio ' || y,
         0, ss_fin(y) + 1, f(y,'06-14'));
    ins('Vacaciones de mitad',  'Receso escolar de junio y julio ' || y,
        30, f(y,'06-15'), f(y,'07-31'));
    ins('Temporada baja',       'Agosto y septiembre ' || y,
         0, f(y,'08-01'), f(y,'10-04'));
    ins('Receso de octubre',    'Semana de receso escolar ' || y,
        15, f(y,'10-05'), f(y,'10-18'));
    ins('Temporada baja',       'Octubre a diciembre ' || y,
         0, f(y,'10-19'), f(y,'12-14'));
    ins('Temporada decembrina', 'Navidad y fin de anio ' || y,
        45, f(y,'12-15'), f(y,'12-31'));
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Temporadas: ' || v_id);
END;
/

-- =====================================================================
-- 3. ALOJAMIENTOS · 60, repartidos segun el peso turistico del municipio
-- =====================================================================
DECLARE
  TYPE t_vc IS TABLE OF VARCHAR2(40);
  TYPE t_n  IS TABLE OF NUMBER;

  v_nombres t_vc := t_vc(
    'El Cafetal','La Palma de Cera','Los Guaduales','El Mirador','La Cascada',
    'Bosque de Niebla','El Yarumo','La Esperanza','Las Heliconias','El Roble',
    'La Granadilla','Los Arrieros','Vista al Valle','La Estrella','El Guamo',
    'Las Veraneras','El Barranquero','La Pradera','Santa Elena','El Refugio',
    'Las Acacias','Casa Blanca','El Nogal','La Floresta','Los Naranjos',
    'El Encanto','La Primavera','Las Brisas','El Descanso','La Arboleda',
    'Tierra Querida','El Retiro','Villa Clara','La Fortuna','Los Laureles',
    'El Portal','Monte Verde','La Aurora','Los Cerezos','El Mango',
    'La Samaria','Las Palmas','El Tambo','La Ceiba','Loma Linda',
    'El Ocaso','La Nubia','Los Pinos','El Bosque','La Colina',
    'Agua Clara','El Remanso','La Quinta','Los Almendros','El Alto',
    'La Cumbre','Cielo Abierto','El Manantial','Piedra Grande','Luna Llena');

  v_veredas t_vc := t_vc('El Placer','La Julia','Boquia','Pinares',
                         'Cocora','La Palmilla','El Rosario','Morelia');

  -- Alojamientos por municipio (Armenia .. Salento)
  v_cantidad t_n := t_n(8, 3, 5, 4, 2, 7, 2, 4, 7, 3, 6, 9);

  -- Tipo de cada alojamiento en orden de id:
  -- 1 finca · 2 hotel · 3 glamping · 4 hostal · 5 ecohotel
  -- Totales: 20 fincas, 12 hoteles, 10 glampings, 10 hostales, 8 ecohoteles
  c_tipos CONSTANT VARCHAR2(60) :=
    '222421541311213413511543125131521152123241141213145443231543';

  v_id          NUMBER := 0;
  v_tipo        NUMBER;
  v_calificacion NUMBER;
  v_prefijo     VARCHAR2(10);
  v_direccion   VARCHAR2(150);
BEGIN
  FOR m IN 1 .. 12 LOOP
    FOR k IN 1 .. v_cantidad(m) LOOP
      v_id   := v_id + 1;
      v_tipo := TO_NUMBER(SUBSTR(c_tipos, v_id, 1));

      v_prefijo := CASE v_tipo WHEN 1 THEN 'Finca'    WHEN 2 THEN 'Hotel'
                               WHEN 3 THEN 'Glamping' WHEN 4 THEN 'Hostal'
                               ELSE 'Ecohotel' END;

      v_calificacion := CASE v_tipo
                          WHEN 1 THEN 2 + TRUNC(DBMS_RANDOM.VALUE(0, 3))
                          WHEN 2 THEN 3 + TRUNC(DBMS_RANDOM.VALUE(0, 3))
                          WHEN 3 THEN 3 + TRUNC(DBMS_RANDOM.VALUE(0, 3))
                          WHEN 4 THEN 1 + TRUNC(DBMS_RANDOM.VALUE(0, 3))
                          ELSE        3 + TRUNC(DBMS_RANDOM.VALUE(0, 2)) END;

      IF v_tipo IN (1, 3, 5) THEN
        v_direccion := 'Vereda ' || v_veredas(MOD(v_id, 8) + 1) ||
                       ', km ' || TRUNC(DBMS_RANDOM.VALUE(1, 16));
      ELSE
        v_direccion := 'Calle ' || TRUNC(DBMS_RANDOM.VALUE(1, 40)) ||
                       ' # ' || TRUNC(DBMS_RANDOM.VALUE(1, 30)) ||
                       '-' || TRUNC(DBMS_RANDOM.VALUE(10, 99));
      END IF;

      INSERT INTO alojamiento (id_alojamiento, id_municipio, id_tipo_alojamiento,
                               nombre, direccion, calificacion, activo)
      VALUES (v_id, m, v_tipo, v_prefijo || ' ' || v_nombres(v_id),
              v_direccion, v_calificacion, 'S');
    END LOOP;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Alojamientos: ' || v_id);
END;
/

-- =====================================================================
-- 4. TARIFAS Y HABITACIONES
--    Una tarifa por alojamiento y tipo de habitacion: las habitaciones
--    iguales del mismo establecimiento comparten precio base, y subir
--    el precio de las dobles de una finca es UNA sola fila que cambiar
--    (y un solo registro de auditoria en la Entrega 2).
--    Precio base = base del tipo de alojamiento x tipo de habitacion
--                  x calificacion en estrellas
-- =====================================================================
DECLARE
  TYPE t_n  IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
  TYPE t_vc IS TABLE OF VARCHAR2(40) INDEX BY PLS_INTEGER;

  v_mult_hab  t_n;    -- multiplicador por tipo de habitacion
  v_base_aloj t_n;    -- precio base de una doble por tipo de alojamiento
  v_nom_hab   t_vc;   -- nombre del tipo de habitacion
  v_tarifa_de t_n;    -- alojamiento * 10 + tipo habitacion -> id_tarifa

  v_id_hab   NUMBER := 0;
  v_id_tar   NUMBER := 0;
  v_hoteles  NUMBER := 0;
  v_n        NUMBER;
  v_patron   VARCHAR2(20);
  v_tipo_hab NUMBER;
  v_clave    NUMBER;
  v_valor    NUMBER;
BEGIN
  v_mult_hab(1) := 0.70;  v_mult_hab(2) := 1.00;  v_mult_hab(3) := 1.30;
  v_mult_hab(4) := 1.75;  v_mult_hab(5) := 1.90;  v_mult_hab(6) := 1.00;

  v_base_aloj(1) := 180000;   -- finca
  v_base_aloj(2) := 200000;   -- hotel
  v_base_aloj(3) := 280000;   -- glamping
  v_base_aloj(4) :=  90000;   -- hostal
  v_base_aloj(5) := 240000;   -- ecohotel

  FOR t IN (SELECT id_tipo_habitacion, nombre FROM tipo_habitacion) LOOP
    v_nom_hab(t.id_tipo_habitacion) := t.nombre;
  END LOOP;

  FOR a IN (SELECT id_alojamiento, id_tipo_alojamiento, calificacion, nombre
              FROM alojamiento ORDER BY id_alojamiento) LOOP

    -- Numero de habitaciones y mezcla de tipos segun el alojamiento.
    -- Los 4 primeros hoteles tienen 13 para sumar exactamente 400.
    CASE a.id_tipo_alojamiento
      WHEN 1 THEN v_n := 5;  v_patron := '22342';
      WHEN 2 THEN v_hoteles := v_hoteles + 1;
                  v_n := CASE WHEN v_hoteles <= 4 THEN 13 ELSE 12 END;
                  v_patron := '1222352421235';
      WHEN 3 THEN v_n := 4;  v_patron := '6664';
      WHEN 4 THEN v_n := 8;  v_patron := '12234123';
      ELSE        v_n := 4;  v_patron := '2452';
    END CASE;

    FOR k IN 1 .. v_n LOOP
      v_tipo_hab := TO_NUMBER(SUBSTR(v_patron, MOD(k - 1, LENGTH(v_patron)) + 1, 1));
      v_clave    := a.id_alojamiento * 10 + v_tipo_hab;

      -- La tarifa se crea la primera vez que aparece el tipo en el alojamiento
      IF NOT v_tarifa_de.EXISTS(v_clave) THEN
        v_valor := ROUND(v_base_aloj(a.id_tipo_alojamiento)
                       * v_mult_hab(v_tipo_hab)
                       * (0.8 + 0.1 * a.calificacion)
                       * DBMS_RANDOM.VALUE(0.92, 1.08), -3);
        v_id_tar := v_id_tar + 1;
        INSERT INTO tarifa (id_tarifa, nombre, descripcion, valor)
        VALUES (v_id_tar,
                a.nombre || ' - ' || v_nom_hab(v_tipo_hab),
                'Tarifa base por noche, habitacion ' ||
                LOWER(v_nom_hab(v_tipo_hab)) || ' de ' || a.nombre,
                v_valor);
        v_tarifa_de(v_clave) := v_id_tar;
      END IF;

      v_id_hab := v_id_hab + 1;
      INSERT INTO habitacion (id_habitacion, id_alojamiento, id_tipo_habitacion,
                              id_tarifa, numero_habitacion, activo)
      VALUES (v_id_hab, a.id_alojamiento, v_tipo_hab, v_tarifa_de(v_clave),
              TO_CHAR(100 + k), 'S');
    END LOOP;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Tarifas: ' || v_id_tar || ' - Habitaciones: ' || v_id_hab);
END;
/

-- =====================================================================
-- 5. CLIENTES · 3.000
-- =====================================================================
DECLARE
  TYPE t_vc IS TABLE OF VARCHAR2(30);
  v_mujer t_vc := t_vc('Maria','Laura','Valentina','Camila','Sara','Natalia',
                       'Daniela','Paula','Carolina','Andrea','Juliana','Mariana',
                       'Isabella','Gabriela','Diana','Catalina','Manuela','Luisa',
                       'Alejandra','Adriana');
  v_hombre t_vc := t_vc('Juan','Carlos','Luis','Jorge','Daniel','Santiago','Mateo',
                        'Samuel','David','Felipe','Diego','Alejandro','Camilo',
                        'Esteban','Pablo','Ricardo','Mauricio','Fernando','Sergio',
                        'Alberto');
  v_apellido t_vc := t_vc('Castro','Vargas','Rojas','Torres','Ortiz','Moreno','Herrera',
                          'Medina','Aguirre','Restrepo','Osorio','Cardona','Valencia',
                          'Giraldo','Arango','Zapata','Ospina','Salazar','Quintero',
                          'Montoya','Echeverri','Villegas','Henao','Duque','Correa',
                          'Buitrago','Franco','Mora','Serna','Ocampo','Botero','Uribe',
                          'Alzate','Hoyos','Posada','Toro');
  v_dominio t_vc := t_vc('gmail.com','hotmail.com','outlook.com','yahoo.com');

  v_es_mujer BOOLEAN;
  v_nombre   VARCHAR2(60);
  v_primero  VARCHAR2(30);
  v_ape1     VARCHAR2(30);
  v_ape2     VARCHAR2(30);
  v_tdoc     NUMBER;
  v_ndoc     VARCHAR2(20);
  v_correo   VARCHAR2(100);
  v_tel      VARCHAR2(20);
  v_fnac     DATE;
  v_freg     DATE;

  FUNCTION al_azar(p_lista t_vc) RETURN VARCHAR2 IS
  BEGIN
    RETURN p_lista(TRUNC(DBMS_RANDOM.VALUE(1, p_lista.COUNT + 1)));
  END;
BEGIN
  FOR i IN 1 .. 3000 LOOP
    v_es_mujer := DBMS_RANDOM.VALUE < 0.52;
    IF v_es_mujer THEN v_primero := al_azar(v_mujer);
                  ELSE v_primero := al_azar(v_hombre); END IF;
    v_nombre := v_primero;
    IF DBMS_RANDOM.VALUE < 0.35 THEN
      IF v_es_mujer THEN v_nombre := v_nombre || ' ' || al_azar(v_mujer);
                    ELSE v_nombre := v_nombre || ' ' || al_azar(v_hombre); END IF;
    END IF;
    v_ape1 := al_azar(v_apellido);
    v_ape2 := al_azar(v_apellido);

    -- 84 % nacionales con cedula. El numero depende de i: nunca se repite.
    IF DBMS_RANDOM.VALUE < 0.84 THEN
      v_tdoc := 1;
      v_ndoc := TO_CHAR(10000000 + i * 3001);
    ELSIF DBMS_RANDOM.VALUE < 0.70 THEN
      v_tdoc := 3;
      v_ndoc := DBMS_RANDOM.STRING('U', 2) || LPAD(i, 7, '0');
    ELSE
      v_tdoc := 2;
      v_ndoc := TO_CHAR(500000 + i);
    END IF;

    -- Todo se calcula antes del INSERT: al_azar es local y no puede
    -- usarse dentro de SQL (PLS-00231), y asi el orden de los sorteos
    -- queda fijo y la carga es reproducible con la misma semilla.
    v_correo := LOWER(v_primero || '.' || v_ape1) || i || '@' || al_azar(v_dominio);
    v_tel    := '3' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 999999999)), 9, '0');
    v_fnac   := DATE '1950-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 20000));
    v_freg   := DATE '2023-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 1300));

    INSERT INTO cliente (id_cliente, id_tipo_documento, numero_documento, nombres,
                         apellidos, telefono, correo_electronico, fecha_nacimiento,
                         fecha_registro)
    VALUES (i, v_tdoc, v_ndoc, v_nombre, v_ape1 || ' ' || v_ape2,
            v_tel, v_correo, v_fnac, v_freg);
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Clientes: 3000');
END;
/

-- =====================================================================
-- 6. CUENTAS DE USUARIO
--    Personal con id 1-27 (sin cliente) y cuentas de cliente con
--    id = 100 + id_cliente. Tienen cuenta ~70 % de los clientes,
--    elegidos con ORA_HASH para que el resultado sea siempre el mismo.
--    contrasena guarda el hash SHA-256 en hexadecimal.
-- =====================================================================
INSERT INTO usuario_sistema (id_usuario_sistema, id_cliente, usuario, contrasena,
                             rol, activo, fecha_creacion)
SELECT LEVEL,
       NULL,
       CASE WHEN LEVEL <= 12 THEN 'recep'   || LPAD(LEVEL, 2, '0')
            WHEN LEVEL <= 22 THEN 'admin'   || LPAD(LEVEL - 12, 2, '0')
            WHEN LEVEL <= 25 THEN 'gerente' || TO_CHAR(LEVEL - 22)
            ELSE                  'auditor' || TO_CHAR(LEVEL - 25) END,
       RAWTOHEX(STANDARD_HASH('Turismo' || LEVEL || '*2026', 'SHA256')),
       CASE WHEN LEVEL <= 12 THEN 'RECEPCION'
            WHEN LEVEL <= 22 THEN 'ADMIN_ALOJAMIENTO'
            WHEN LEVEL <= 25 THEN 'GERENTE'
            ELSE                  'AUDITOR' END,
       'S',
       DATE '2023-01-01'
  FROM dual
 CONNECT BY LEVEL <= 27;

INSERT INTO usuario_sistema (id_usuario_sistema, id_cliente, usuario, contrasena,
                             rol, activo, fecha_creacion)
SELECT 100 + c.id_cliente,
       c.id_cliente,
       'cli' || LPAD(c.id_cliente, 4, '0'),
       RAWTOHEX(STANDARD_HASH('Cliente' || c.id_cliente || '*2026', 'SHA256')),
       'CLIENTE',
       'S',
       c.fecha_registro
  FROM cliente c
 WHERE MOD(ORA_HASH(c.id_cliente), 10) < 7;

COMMIT;

-- =====================================================================
-- 7. RESERVAS, HABITACIONES, SERVICIOS, PAGOS Y RESENAS
--
-- Algoritmo por cada reserva:
--   1. Fecha de llegada por aceptacion-rechazo: se sortea un dia y se
--      acepta con probabilidad proporcional a su peso (temporada, dia de
--      la semana y anio). Asi aparece la estacionalidad.
--   2. Noches (1 a 8, sesgado a 2-3) y numero de habitaciones (1 a 3).
--   3. Se sortea una habitacion; eso fija el alojamiento y hace que los
--      alojamientos grandes reciban mas reservas.
--   4. Se buscan habitaciones LIBRES en ese alojamiento para todas las
--      noches, consultando un mapa de ocupacion en memoria.
--   5. Valor noche por noche: tarifa base x (1 + porcentaje / 100) de la
--      temporada de cada noche.
--   6. Quien registra: la cuenta del propio cliente si la tiene y
--      reserva en linea, o una recepcion.
-- =====================================================================
DECLARE
  c_inicio   CONSTANT DATE := DATE '2024-01-01';
  c_fin      CONSTANT DATE := DATE '2027-01-01';   -- exclusivo
  c_corte    CONSTANT DATE := DATE '2026-09-24';   -- "hoy" de los datos
  c_meta     CONSTANT PLS_INTEGER := 25000;
  c_peso_max CONSTANT NUMBER := 3 * 1.4 * 1.15;

  TYPE t_n    IS TABLE OF NUMBER  INDEX BY PLS_INTEGER;
  TYPE t_bool IS TABLE OF BOOLEAN INDEX BY PLS_INTEGER;
  TYPE t_d    IS TABLE OF DATE    INDEX BY PLS_INTEGER;
  TYPE t_txt  IS TABLE OF VARCHAR2(100);

  dia_temp   t_n;     -- dia (0..1095)  -> id_temporada
  dia_peso   t_n;     -- dia            -> peso de llegada
  temp_pct   t_n;     -- id_temporada   -> porcentaje
  hab_aloj   t_n;     -- id_habitacion  -> id_alojamiento
  hab_cap    t_n;     -- id_habitacion  -> capacidad maxima
  hab_valor  t_n;     -- id_habitacion  -> tarifa base por noche
  aloj_ini   t_n;     -- id_alojamiento -> primera habitacion
  aloj_cnt   t_n;     -- id_alojamiento -> numero de habitaciones
  cli_cuenta t_n;     -- id_cliente     -> id_usuario_sistema (si tiene)
  serv_valor t_n;     -- id_servicio    -> precio de catalogo
  ocupado    t_bool;  -- id_habitacion * 2000 + dia -> TRUE si esta tomada

  sel_hab   t_n;  sel_huesp t_n;  sel_previo t_n;  sel_valor t_n;
  rs_serv   t_n;  rs_cant   t_n;  rs_previo  t_n;  rs_valor t_n;  rs_fecha t_d;
  usados    t_bool;

  -- Unidad de cada servicio (posicion = id): P persona, S servicio,
  -- H hora, D dia. Define la cantidad que se cobra.
  c_unidad CONSTANT VARCHAR2(20) := 'SPPPPHPSPPSPPPDPSPPD';

  v_coment5 t_txt := t_txt('Un lugar hermoso y muy tranquilo',
                           'Superaron nuestras expectativas, volveremos',
                           'Paisaje espectacular y excelente trato');
  v_coment4 t_txt := t_txt('Muy buena experiencia en general',
                           'Bonito lugar, el desayuno puede mejorar');
  v_coment3 t_txt := t_txt('Estuvo bien, nada especial',
                           'Correcto, aunque la habitacion era pequena');
  v_coment2 t_txt := t_txt('El servicio fue lento',
                           'Esperaba mejor atencion por el precio');
  v_coment1 t_txt := t_txt('Mala experiencia, no lo recomiendo');

  n_dias     PLS_INTEGER := c_fin - c_inicio;
  n_hab      PLS_INTEGER;
  v_intentos PLS_INTEGER := 0;
  v_id_res   PLS_INTEGER := 0;
  v_id_pago  PLS_INTEGER := 0;
  v_id_rsn   PLS_INTEGER := 0;
  v_n_rs     PLS_INTEGER := 0;

  v_fecha     DATE;
  v_peso      NUMBER;
  v_r         NUMBER;
  v_off       PLS_INTEGER;
  v_noches    PLS_INTEGER;
  v_nhab      PLS_INTEGER;
  v_hab0      PLS_INTEGER;
  v_aloj      PLS_INTEGER;
  v_h         PLS_INTEGER;
  v_libre     BOOLEAN;
  v_checkin   DATE;
  v_checkout  DATE;
  v_fcreacion DATE;
  v_pct_temp  NUMBER;
  v_antic     PLS_INTEGER;
  v_estado    VARCHAR2(12);
  v_usuario   PLS_INTEGER;
  v_cliente   PLS_INTEGER;
  v_huespedes PLS_INTEGER;
  v_hosp      NUMBER;
  v_serv_tot  NUMBER;
  v_nserv     PLS_INTEGER;
  v_c         PLS_INTEGER;
  v_serv      PLS_INTEGER;
  v_f_anio    NUMBER;
  v_pct_dia   NUMBER;
  v_anticipo  NUMBER;
  v_pagado    NUMBER;
  v_calif     PLS_INTEGER;
  v_texto     VARCHAR2(100);

  FUNCTION metodo RETURN VARCHAR2 IS
    r NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    RETURN CASE WHEN r < 0.35 THEN 'TARJETA_CREDITO'
                WHEN r < 0.60 THEN 'PSE'
                WHEN r < 0.80 THEN 'TARJETA_DEBITO'
                WHEN r < 0.90 THEN 'TRANSFERENCIA'
                ELSE 'EFECTIVO' END;
  END;

  -- Las funciones locales no se pueden invocar dentro de una sentencia
  -- SQL (PLS-00231), por eso el metodo se resuelve antes del INSERT.
  PROCEDURE pagar(p_fecha DATE, p_valor NUMBER, p_estado VARCHAR2) IS
    v_metodo VARCHAR2(16) := metodo;
  BEGIN
    v_id_pago := v_id_pago + 1;
    INSERT INTO pago (id_pago, id_reserva, valor, fecha_pago, metodo_pago, estado)
    VALUES (v_id_pago, v_id_res, p_valor, p_fecha, v_metodo, p_estado);
  END;

  FUNCTION comentario(p_lista t_txt) RETURN VARCHAR2 IS
  BEGIN
    RETURN p_lista(TRUNC(DBMS_RANDOM.VALUE(1, p_lista.COUNT + 1)));
  END;
BEGIN
  -- ----- Estructuras en memoria ---------------------------------------
  FOR t IN (SELECT id_temporada, porcentaje, fecha_inicio, fecha_fin
              FROM temporada) LOOP
    temp_pct(t.id_temporada) := t.porcentaje;
    FOR d IN (t.fecha_inicio - c_inicio) .. (t.fecha_fin - c_inicio) LOOP
      dia_temp(d) := t.id_temporada;
    END LOOP;
  END LOOP;

  FOR d IN 0 .. n_dias - 1 LOOP
    IF NOT dia_temp.EXISTS(d) THEN
      RAISE_APPLICATION_ERROR(-20001, 'El dia ' || TO_CHAR(c_inicio + d, 'YYYY-MM-DD') ||
                                      ' no pertenece a ninguna temporada');
    END IF;
    v_fecha := c_inicio + d;
    v_peso  := CASE WHEN temp_pct(dia_temp(d)) >= 30 THEN 3
                    WHEN temp_pct(dia_temp(d)) >  0 THEN 1.8
                    ELSE 1 END;
    IF v_fecha - TRUNC(v_fecha, 'IW') IN (4, 5) THEN   -- viernes o sabado, sin depender de NLS
      v_peso := v_peso * 1.4;
    END IF;
    v_peso := v_peso * CASE EXTRACT(YEAR FROM v_fecha) WHEN 2024 THEN 0.85
                                                       WHEN 2025 THEN 1.00
                                                       ELSE 1.15 END;
    dia_peso(d) := v_peso;
  END LOOP;

  FOR h IN (SELECT hb.id_habitacion, hb.id_alojamiento, th.capacidad_maxima, tf.valor
              FROM habitacion hb
              JOIN tipo_habitacion th ON th.id_tipo_habitacion = hb.id_tipo_habitacion
              JOIN tarifa tf          ON tf.id_tarifa          = hb.id_tarifa
             ORDER BY hb.id_habitacion) LOOP
    hab_aloj(h.id_habitacion)  := h.id_alojamiento;
    hab_cap(h.id_habitacion)   := h.capacidad_maxima;
    hab_valor(h.id_habitacion) := h.valor;
    IF NOT aloj_ini.EXISTS(h.id_alojamiento) THEN
      aloj_ini(h.id_alojamiento) := h.id_habitacion;
      aloj_cnt(h.id_alojamiento) := 0;
    END IF;
    aloj_cnt(h.id_alojamiento) := aloj_cnt(h.id_alojamiento) + 1;
  END LOOP;
  n_hab := hab_aloj.COUNT;

  FOR u IN (SELECT id_cliente, id_usuario_sistema FROM usuario_sistema
             WHERE rol = 'CLIENTE') LOOP
    cli_cuenta(u.id_cliente) := u.id_usuario_sistema;
  END LOOP;

  FOR s IN (SELECT id_servicio, valor_servicio FROM servicio) LOOP
    serv_valor(s.id_servicio) := s.valor_servicio;
  END LOOP;

  -- ----- Generacion ----------------------------------------------------
  WHILE v_id_res < c_meta LOOP
    v_intentos := v_intentos + 1;
    IF v_intentos > c_meta * 20 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Demasiados intentos sin cupo: ' || v_id_res);
    END IF;

    -- 1. Llegada con estacionalidad
    LOOP
      v_off := TRUNC(DBMS_RANDOM.VALUE(0, n_dias));
      EXIT WHEN DBMS_RANDOM.VALUE(0, c_peso_max) < dia_peso(v_off);
    END LOOP;

    -- 2. Noches y habitaciones
    v_r := DBMS_RANDOM.VALUE;
    v_noches := CASE WHEN v_r < 0.22 THEN 1 WHEN v_r < 0.52 THEN 2
                     WHEN v_r < 0.75 THEN 3 WHEN v_r < 0.88 THEN 4
                     WHEN v_r < 0.95 THEN 5
                     ELSE 6 + TRUNC(DBMS_RANDOM.VALUE(0, 3)) END;
    IF v_off + v_noches > n_dias THEN v_noches := n_dias - v_off; END IF;

    v_r := DBMS_RANDOM.VALUE;
    v_nhab := CASE WHEN v_r < 0.85 THEN 1 WHEN v_r < 0.97 THEN 2 ELSE 3 END;

    -- 3. Alojamiento a partir de una habitacion al azar
    v_hab0 := TRUNC(DBMS_RANDOM.VALUE(1, n_hab + 1));
    v_aloj := hab_aloj(v_hab0);

    -- 4. Habitaciones libres, empezando por la sorteada
    sel_hab.DELETE;
    FOR k IN 0 .. aloj_cnt(v_aloj) - 1 LOOP
      EXIT WHEN sel_hab.COUNT = v_nhab;
      v_h := aloj_ini(v_aloj) + MOD(v_hab0 - aloj_ini(v_aloj) + k, aloj_cnt(v_aloj));
      v_libre := TRUE;
      FOR d IN v_off .. v_off + v_noches - 1 LOOP
        IF ocupado.EXISTS(v_h * 2000 + d) THEN
          v_libre := FALSE;
          EXIT;
        END IF;
      END LOOP;
      IF v_libre THEN sel_hab(sel_hab.COUNT + 1) := v_h; END IF;
    END LOOP;
    CONTINUE WHEN sel_hab.COUNT = 0;       -- sin cupo: otro intento

    v_checkin  := c_inicio + v_off;
    v_checkout := v_checkin + v_noches;
    v_pct_temp := temp_pct(dia_temp(v_off));
    v_f_anio   := CASE EXTRACT(YEAR FROM v_checkin) WHEN 2024 THEN 0.87
                                                    WHEN 2025 THEN 0.94
                                                    ELSE 1 END;

    -- En temporada alta se reserva con mas anticipacion
    v_r := DBMS_RANDOM.VALUE;
    v_antic := CASE WHEN v_r < 0.20 THEN TRUNC(DBMS_RANDOM.VALUE(0, 4))
                    WHEN v_r < 0.60 THEN TRUNC(DBMS_RANDOM.VALUE(4, 21))
                    WHEN v_r < 0.90 THEN TRUNC(DBMS_RANDOM.VALUE(21, 61))
                    ELSE TRUNC(DBMS_RANDOM.VALUE(61, 121)) END;
    v_antic := ROUND(v_antic * CASE WHEN v_pct_temp >= 30 THEN 1.8
                                    WHEN v_pct_temp >  0 THEN 1.3
                                    ELSE 0.7 END);
    v_fcreacion := v_checkin - v_antic;
    IF v_fcreacion > c_corte THEN             -- nadie reserva en el futuro
      v_fcreacion := c_corte - TRUNC(DBMS_RANDOM.VALUE(0, 45));
    END IF;

    -- Estado segun la fecha de corte; en temporada alta se cancela mas
    IF DBMS_RANDOM.VALUE < CASE WHEN v_pct_temp >= 30 THEN 0.12 ELSE 0.07 END THEN
      v_estado := 'CANCELADA';
    ELSIF v_checkout <= c_corte THEN v_estado := 'FINALIZADA';
    ELSIF v_checkin  <= c_corte THEN v_estado := 'EN_CURSO';
    ELSIF DBMS_RANDOM.VALUE < 0.78 THEN v_estado := 'CONFIRMADA';
    ELSE v_estado := 'PENDIENTE';
    END IF;

    -- El 20 % de los clientes concentra la mitad de las reservas
    IF DBMS_RANDOM.VALUE < 0.5 THEN v_cliente := TRUNC(DBMS_RANDOM.VALUE(1, 601));
    ELSE v_cliente := TRUNC(DBMS_RANDOM.VALUE(1, 3001)); END IF;

    -- Quien registra: el cliente en linea, o una recepcion (id 1 a 12)
    IF cli_cuenta.EXISTS(v_cliente) AND DBMS_RANDOM.VALUE < 0.6 THEN
      v_usuario := cli_cuenta(v_cliente);
    ELSE
      v_usuario := TRUNC(DBMS_RANDOM.VALUE(1, 13));
    END IF;

    -- 5. Valor noche por noche
    v_hosp      := 0;
    v_huespedes := 0;
    FOR i IN 1 .. sel_hab.COUNT LOOP
      v_h := sel_hab(i);
      sel_previo(i) := v_noches * hab_valor(v_h);
      sel_valor(i)  := 0;
      FOR d IN v_off .. v_off + v_noches - 1 LOOP
        sel_valor(i) := sel_valor(i)
                      + hab_valor(v_h) * (1 + temp_pct(dia_temp(d)) / 100);
      END LOOP;
      sel_huesp(i) := hab_cap(v_h) - TRUNC(POWER(DBMS_RANDOM.VALUE, 2) * hab_cap(v_h));
      v_hosp       := v_hosp + sel_valor(i);
      v_huespedes  := v_huespedes + sel_huesp(i);
      IF v_estado <> 'CANCELADA' THEN
        FOR d IN v_off .. v_off + v_noches - 1 LOOP
          ocupado(v_h * 2000 + d) := TRUE;
        END LOOP;
      END IF;
    END LOOP;

    -- Servicios: hasta 4 distintos de los 20 del catalogo
    v_serv_tot := 0;
    v_nserv    := 0;
    IF v_estado <> 'CANCELADA' THEN
      v_r := DBMS_RANDOM.VALUE;
      v_nserv := CASE WHEN v_r < 0.10 THEN 0 WHEN v_r < 0.33 THEN 1
                      WHEN v_r < 0.63 THEN 2 WHEN v_r < 0.86 THEN 3 ELSE 4 END;
      usados.DELETE;
      FOR j IN 1 .. v_nserv LOOP
        LOOP
          v_c := TRUNC(DBMS_RANDOM.VALUE(1, 21));
          EXIT WHEN NOT usados.EXISTS(v_c);
        END LOOP;
        usados(v_c) := TRUE;
        v_serv := v_c;
        rs_serv(j)  := v_serv;
        rs_cant(j)  := CASE SUBSTR(c_unidad, v_serv, 1)
                         WHEN 'P' THEN 1 + TRUNC(DBMS_RANDOM.VALUE(0, v_huespedes))
                         WHEN 'H' THEN 1 + TRUNC(DBMS_RANDOM.VALUE(0, 3))
                         WHEN 'D' THEN LEAST(v_noches, 1 + TRUNC(DBMS_RANDOM.VALUE(0, 2)))
                         ELSE 1 END;
        rs_fecha(j) := v_checkin + TRUNC(DBMS_RANDOM.VALUE(0, v_noches));
        v_pct_dia   := temp_pct(dia_temp(rs_fecha(j) - c_inicio));
        rs_previo(j):= ROUND(rs_cant(j) * serv_valor(v_serv) * v_f_anio, -2);
        rs_valor(j) := ROUND(rs_previo(j) * (1 + v_pct_dia / 100), -2);
        v_serv_tot  := v_serv_tot + rs_valor(j);
      END LOOP;
    END IF;

    -- Pagos: anticipo al reservar y saldo al salir
    v_anticipo := ROUND((v_hosp + v_serv_tot) *
                        CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 0.3 ELSE 0.5 END, -2);
    v_pagado := CASE WHEN v_estado = 'FINALIZADA'               THEN v_hosp + v_serv_tot
                     WHEN v_estado IN ('EN_CURSO','CONFIRMADA') THEN v_anticipo
                     ELSE 0 END;

    -- Insercion de la reserva y su detalle
    v_id_res := v_id_res + 1;
    INSERT INTO reserva (id_reserva, id_cliente, id_usuario_sistema, fecha_creacion,
                         fecha_checkin, fecha_checkout, estado, num_huespedes,
                         valor_total, valor_pagado)
    VALUES (v_id_res, v_cliente, v_usuario, v_fcreacion,
            v_checkin, v_checkout, v_estado, v_huespedes,
            v_hosp + v_serv_tot, v_pagado);

    FOR i IN 1 .. sel_hab.COUNT LOOP
      INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                      fecha_checkout, valor_previo, valor_reserva)
      VALUES (v_id_res, sel_hab(i), v_checkin, v_checkout,
              sel_previo(i), sel_valor(i));
    END LOOP;

    FOR j IN 1 .. v_nserv LOOP
      v_n_rs := v_n_rs + 1;
      INSERT INTO reserva_servicio (id_reserva, id_servicio, fecha_servicio,
                                    cantidad, valor_previo, valor_servicio)
      VALUES (v_id_res, rs_serv(j), rs_fecha(j), rs_cant(j),
              rs_previo(j), rs_valor(j));
    END LOOP;

    IF v_estado IN ('FINALIZADA', 'EN_CURSO', 'CONFIRMADA') THEN
      pagar(LEAST(v_fcreacion + TRUNC(DBMS_RANDOM.VALUE(0, 3)), v_checkin, c_corte),
            v_anticipo, 'APROBADO');
      IF v_estado = 'FINALIZADA' THEN
        pagar(v_checkout, v_hosp + v_serv_tot - v_anticipo, 'APROBADO');
      END IF;
    ELSIF v_estado = 'PENDIENTE' AND DBMS_RANDOM.VALUE < 0.5 THEN
      pagar(v_fcreacion, v_anticipo, 'PENDIENTE');
    ELSIF v_estado = 'CANCELADA' AND DBMS_RANDOM.VALUE < 0.5 THEN
      pagar(v_fcreacion, v_anticipo, 'REEMBOLSADO');
    END IF;

    -- Resena: el 40 % de las estadias terminadas
    IF v_estado = 'FINALIZADA' AND DBMS_RANDOM.VALUE < 0.40 THEN
      v_r := DBMS_RANDOM.VALUE;
      v_calif := CASE WHEN v_r < 0.45 THEN 5 WHEN v_r < 0.75 THEN 4
                      WHEN v_r < 0.88 THEN 3 WHEN v_r < 0.95 THEN 2 ELSE 1 END;
      v_texto := CASE v_calif WHEN 5 THEN comentario(v_coment5)
                              WHEN 4 THEN comentario(v_coment4)
                              WHEN 3 THEN comentario(v_coment3)
                              WHEN 2 THEN comentario(v_coment2)
                              ELSE comentario(v_coment1) END;
      v_id_rsn := v_id_rsn + 1;
      INSERT INTO resena (id_resena, id_reserva, calificacion, comentario, fecha)
      VALUES (v_id_rsn, v_id_res, v_calif, v_texto,
              LEAST(v_checkout + TRUNC(DBMS_RANDOM.VALUE(0, 10)), c_corte));
    END IF;

    IF MOD(v_id_res, 5000) = 0 THEN
      COMMIT;
      DBMS_OUTPUT.PUT_LINE('  ... ' || v_id_res || ' reservas');
    END IF;
  END LOOP;
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Reservas: ' || v_id_res || ' (intentos: ' || v_intentos || ')');
  DBMS_OUTPUT.PUT_LINE('Lineas de servicio: ' || v_n_rs);
  DBMS_OUTPUT.PUT_LINE('Pagos: ' || v_id_pago || ' - Resenas: ' || v_id_rsn);
END;
/

-- =====================================================================
-- 8. Ajustes finales
-- =====================================================================

-- Ningun cliente pudo reservar antes de registrarse
UPDATE cliente c
   SET fecha_registro = LEAST(c.fecha_registro,
                              (SELECT TRUNC(MIN(r.fecha_creacion))
                                 FROM reserva r
                                WHERE r.id_cliente = c.id_cliente))
 WHERE EXISTS (SELECT 1 FROM reserva r WHERE r.id_cliente = c.id_cliente);

-- La cuenta no pudo crearse antes que el cliente, ni usarse antes de existir
UPDATE usuario_sistema u
   SET u.fecha_creacion = (SELECT c.fecha_registro FROM cliente c
                            WHERE c.id_cliente = u.id_cliente)
 WHERE u.rol = 'CLIENTE';

UPDATE usuario_sistema u
   SET u.ultimo_acceso = (SELECT TRUNC(MAX(r.fecha_creacion)) FROM reserva r
                           WHERE r.id_usuario_sistema = u.id_usuario_sistema);
COMMIT;

-- Las cargas fijaron los id a mano: cada secuencia debe continuar desde
-- el maximo actual, o el siguiente INSERT sin id fallaria por PK.
DECLARE
  PROCEDURE sincronizar(p_seq VARCHAR2, p_tabla VARCHAR2, p_col VARCHAR2) IS
    v_siguiente NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT NVL(MAX(' || p_col || '), 0) + 1 FROM ' || p_tabla
      INTO v_siguiente;
    EXECUTE IMMEDIATE 'ALTER SEQUENCE ' || p_seq || ' RESTART START WITH ' || v_siguiente;
  END;
BEGIN
  sincronizar('seq_tipo_documento',   'tipo_documento',   'id_tipo_documento');
  sincronizar('seq_municipio',        'municipio',        'id_municipio');
  sincronizar('seq_tipo_alojamiento', 'tipo_alojamiento', 'id_tipo_alojamiento');
  sincronizar('seq_tipo_habitacion',  'tipo_habitacion',  'id_tipo_habitacion');
  sincronizar('seq_tipo_servicio',    'tipo_servicio',    'id_tipo_servicio');
  sincronizar('seq_tarifa',           'tarifa',           'id_tarifa');
  sincronizar('seq_temporada',        'temporada',        'id_temporada');
  sincronizar('seq_alojamiento',      'alojamiento',      'id_alojamiento');
  sincronizar('seq_habitacion',       'habitacion',       'id_habitacion');
  sincronizar('seq_cliente',          'cliente',          'id_cliente');
  sincronizar('seq_usuario_sistema',  'usuario_sistema',  'id_usuario_sistema');
  sincronizar('seq_servicio',         'servicio',         'id_servicio');
  sincronizar('seq_reserva',          'reserva',          'id_reserva');
  sincronizar('seq_pago',             'pago',             'id_pago');
  sincronizar('seq_resena',           'resena',           'id_resena');
  DBMS_OUTPUT.PUT_LINE('Secuencias sincronizadas.');
END;
/

-- Estadisticas del optimizador: sin ellas los planes de ejecucion de la
-- Entrega 3 no reflejan el volumen real de las tablas.
-- OJO: no se puede usar ownname => USER; la sesion sigue conectada como
-- SYS (CURRENT_SCHEMA solo cambia la resolucion de nombres, no USER).
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(ownname => 'TURISMOUQ', cascade => TRUE);

-- =====================================================================
-- 9. Verificacion
-- =====================================================================
PROMPT
PROMPT === Volumen contra el minimo exigido ===
DECLARE
  PROCEDURE validar(p_tabla VARCHAR2, p_minimo NUMBER) IS
    v NUMBER;
  BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_tabla INTO v;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_tabla, 20) || LPAD(v, 8) ||
      CASE WHEN p_minimo IS NULL THEN ''
           WHEN v >= p_minimo THEN '   OK (minimo ' || p_minimo || ')'
           ELSE '   *** POR DEBAJO DEL MINIMO (' || p_minimo || ')' END);
  END;
BEGIN
  validar('municipio',           12);
  validar('alojamiento',         60);
  validar('habitacion',         400);
  validar('cliente',           3000);
  validar('reserva',          25000);
  validar('reserva_servicio', 40000);
  validar('reserva_habitacion', NULL);
  validar('tarifa',             NULL);
  validar('temporada',          NULL);
  validar('usuario_sistema',    NULL);
  validar('pago',               NULL);
  validar('resena',             NULL);
END;
/

PROMPT
PROMPT === Reservas por anio de llegada y estado ===
SELECT EXTRACT(YEAR FROM fecha_checkin) AS anio, estado, COUNT(*) AS reservas
  FROM reserva
 GROUP BY EXTRACT(YEAR FROM fecha_checkin), estado
 ORDER BY anio, estado;

PROMPT
PROMPT === Temporadas con huecos o cruces (debe dar 0) ===
SELECT COUNT(*) AS problemas
  FROM (SELECT fecha_inicio,
               LAG(fecha_fin) OVER (ORDER BY fecha_inicio) AS fin_anterior
          FROM temporada)
 WHERE fin_anterior IS NOT NULL
   AND fecha_inicio <> fin_anterior + 1;

PROMPT
PROMPT === Reservas activas solapadas en la misma habitacion (debe dar 0) ===
SELECT COUNT(*) AS solapes
  FROM reserva_habitacion a
  JOIN reserva ra ON ra.id_reserva = a.id_reserva
  JOIN reserva_habitacion b
    ON b.id_habitacion = a.id_habitacion
   AND b.id_reserva    > a.id_reserva
   AND b.fecha_checkin  < a.fecha_checkout
   AND a.fecha_checkin  < b.fecha_checkout
  JOIN reserva rb ON rb.id_reserva = b.id_reserva
 WHERE ra.estado <> 'CANCELADA'
   AND rb.estado <> 'CANCELADA';

PROMPT
PROMPT === Habitaciones de una reserva en alojamientos distintos (debe dar 0) ===
SELECT COUNT(*) AS reservas_mezcladas
  FROM (SELECT rh.id_reserva
          FROM reserva_habitacion rh
          JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
         GROUP BY rh.id_reserva
        HAVING COUNT(DISTINCT h.id_alojamiento) > 1);

PROMPT
PROMPT === Cabecera distinta de la suma de su detalle (debe dar 0) ===
SELECT COUNT(*) AS descuadres
  FROM reserva r
 WHERE r.valor_total <> (SELECT NVL(SUM(rh.valor_reserva), 0)
                           FROM reserva_habitacion rh
                          WHERE rh.id_reserva = r.id_reserva)
                      + (SELECT NVL(SUM(rs.valor_servicio), 0)
                           FROM reserva_servicio rs
                          WHERE rs.id_reserva = r.id_reserva);

PROMPT
PROMPT === Valor pagado distinto de los pagos aprobados (debe dar 0) ===
SELECT COUNT(*) AS descuadres_pago
  FROM reserva r
 WHERE r.valor_pagado <> (SELECT NVL(SUM(p.valor), 0)
                            FROM pago p
                           WHERE p.id_reserva = r.id_reserva
                             AND p.estado = 'APROBADO');

PROMPT
PROMPT === Script 03 finalizado. Continue con 04_consultas.sql ===
