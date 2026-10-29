-- 1. Limpieza inicial (Eliminación de tablas si existen)
BEGIN
    FOR t IN (
        SELECT table_name FROM user_tables 
        WHERE table_name IN ('LOG_MUESTRA', 'MUESTRA', 'CENTRO', 'USUARIO')
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/

-- 2. Creación de Tablas (Modelo Reducido a 4 tablas esenciales)
CREATE TABLE USUARIO (
    usuario_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR2(100) NOT NULL,
    rol         VARCHAR2(50) NOT NULL
);

CREATE TABLE CENTRO (
    centro_id     NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_centro VARCHAR2(150) NOT NULL
);

CREATE TABLE MUESTRA (
    muestra_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    centro_id           NUMBER NOT NULL REFERENCES CENTRO(centro_id),
    usuario_id          NUMBER NOT NULL REFERENCES USUARIO(usuario_id),
    cantidad_individuos NUMBER NOT NULL,
    estado              VARCHAR2(20) DEFAULT 'PENDIENTE',
    fecha_registro      TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE LOG_MUESTRA (
    log_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    muestra_id    NUMBER,
    estado_nuevo  VARCHAR2(20),
    fecha_cambio  TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- 3. Inserción de Datos Mínimos de Prueba
INSERT INTO USUARIO (nombre, rol) VALUES ('Ignacio Roa', 'OPERADOR_MUESTREO');
INSERT INTO USUARIO (nombre, rol) VALUES ('Valentina Aguayo', 'SUPERVISOR_TECNICO');
INSERT INTO CENTRO (nombre_centro) VALUES ('Centro Demo Reloncaví');
COMMIT;

-- 4. Creación del Paquete (Especificación)
CREATE OR REPLACE PACKAGE PKG_MUESTREO AS
    -- Función para calcular el total de individuos por centro
    FUNCTION FN_TOTAL_INDIVIDUOS(p_centro_id NUMBER) RETURN NUMBER;
    
    -- Procedimiento para registrar una nueva muestra
    PROCEDURE SP_REGISTRAR_MUESTRA(
        p_centro_id NUMBER, 
        p_usuario_id NUMBER, 
        p_cantidad NUMBER
    );
END PKG_MUESTREO;
/

-- 5. Creación del Paquete (Cuerpo con Función y Procedimiento)
CREATE OR REPLACE PACKAGE BODY PKG_MUESTREO AS

    FUNCTION FN_TOTAL_INDIVIDUOS(p_centro_id NUMBER) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        SELECT NVL(SUM(cantidad_individuos), 0) 
        INTO v_total
        FROM MUESTRA 
        WHERE centro_id = p_centro_id;
        
        RETURN v_total;
    END FN_TOTAL_INDIVIDUOS;

    PROCEDURE SP_REGISTRAR_MUESTRA(
        p_centro_id NUMBER, 
        p_usuario_id NUMBER, 
        p_cantidad NUMBER
    ) IS
    BEGIN
        INSERT INTO MUESTRA (centro_id, usuario_id, cantidad_individuos)
        VALUES (p_centro_id, p_usuario_id, p_cantidad);
        COMMIT;
    END SP_REGISTRAR_MUESTRA;

END PKG_MUESTREO;
/

-- 6. Triggers (Automatización y validación)

-- Trigger a nivel de fila: Valida reglas de negocio antes de insertar o actualizar
CREATE OR REPLACE TRIGGER TRG_VALIDA_MUESTRA
    BEFORE INSERT OR UPDATE ON MUESTRA
    FOR EACH ROW
BEGIN
    IF :NEW.cantidad_individuos <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'La cantidad de individuos debe ser mayor a cero.');
    END IF;
END;
/

-- Trigger a nivel de fila: Audita automáticamente los cambios de estado
CREATE OR REPLACE TRIGGER TRG_AUDITA_MUESTRA
    AFTER INSERT OR UPDATE OF estado ON MUESTRA
    FOR EACH ROW
BEGIN
    INSERT INTO LOG_MUESTRA (muestra_id, estado_nuevo)
    VALUES (:NEW.muestra_id, :NEW.estado);
END;
/

-- 7. Prueba de Ejecución del Paquete y Triggers
BEGIN
    -- Ejecuta el procedimiento almacenado (dispara los triggers automáticamente)
    PKG_MUESTREO.SP_REGISTRAR_MUESTRA(
        p_centro_id => 1, 
        p_usuario_id => 1, 
        p_cantidad => 150
    );
    
    -- Imprime el resultado usando la función almacenada
    DBMS_OUTPUT.PUT_LINE('Total de individuos en el Centro 1: ' || PKG_MUESTREO.FN_TOTAL_INDIVIDUOS(1));
END;
/

------------------------------------------------------------------------------------------------------------------------------------

--Función Independiente (Calcula datos)
CREATE OR REPLACE FUNCTION FN_TOTAL_INDIVIDUOS(p_centro_id NUMBER) 
RETURN NUMBER IS
    v_total NUMBER;
BEGIN
    SELECT NVL(SUM(cantidad_individuos), 0) 
    INTO v_total
    FROM MUESTRA 
    WHERE centro_id = p_centro_id;
    
    RETURN v_total;
END;
/


--Procedimiento Independiente (Realiza la acción)
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_MUESTRA(
    p_centro_id NUMBER, 
    p_usuario_id NUMBER, 
    p_cantidad NUMBER
) IS
BEGIN
    -- Validamos directamente en el procedimiento
    IF p_cantidad <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Cantidad debe ser mayor a cero.');
    END IF;

    INSERT INTO MUESTRA (centro_id, usuario_id, cantidad_individuos)
    VALUES (p_centro_id, p_usuario_id, p_cantidad);
    
    COMMIT;
END;
/



--Package (Agrupa lógica de negocio)
-- 3A. Especificación del Paquete
CREATE OR REPLACE PACKAGE PKG_REPORTES AS
    PROCEDURE SP_RESUMEN_CENTRO(p_centro_id NUMBER);
END PKG_REPORTES;
/

-- 3B. Cuerpo del Paquete
CREATE OR REPLACE PACKAGE BODY PKG_REPORTES AS
    PROCEDURE SP_RESUMEN_CENTRO(p_centro_id NUMBER) IS
        v_total NUMBER;
    BEGIN
        -- Reutiliza la función independiente creada en el paso 1
        v_total := FN_TOTAL_INDIVIDUOS(p_centro_id);
        DBMS_OUTPUT.PUT_LINE('Resumen del Centro ID ' || p_centro_id);
        DBMS_OUTPUT.PUT_LINE('Total de individuos muestreados: ' || v_total);
    END SP_RESUMEN_CENTRO;
END PKG_REPORTES;
/


--Triggers (Automatización y Control)
-- Trigger 1: Audita los cambios (nivel de fila)
CREATE OR REPLACE TRIGGER TRG_AUDITA_MUESTRA
    AFTER INSERT OR UPDATE OF estado ON MUESTRA
    FOR EACH ROW
BEGIN
    INSERT INTO LOG_MUESTRA (muestra_id, estado_nuevo)
    VALUES (:NEW.muestra_id, :NEW.estado);
END;
/


--Bloque Anónimo para probar todo junto

SET SERVEROUTPUT ON;

BEGIN
    -- 1. Usamos el Procedimiento independiente
    SP_REGISTRAR_MUESTRA(p_centro_id => 1, p_usuario_id => 1, p_cantidad => 200);
    
    -- 2. Usamos el Paquete (que a su vez llama a la Función independiente)
    PKG_REPORTES.SP_RESUMEN_CENTRO(p_centro_id => 1);
END;
/