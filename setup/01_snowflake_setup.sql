-- ============================================================================
-- Snowflake Setup for BOE Gaming Report Demo
-- Database: BOEGAMINGREPORT.DEMO
-- ============================================================================
--
-- This SQL file provides the complete database setup for the BOE Gaming
-- Report regulatory compliance demo. See SNOWFLAKE_SETUP.md for detailed
-- explanations and context for each step.
--
-- NOTE: If you've already run specifications/01_extract_specifications.sql,
-- the database, schema, and stage will already exist. The IF NOT EXISTS clauses
-- ensure this setup runs without errors in either order.
--
-- CUSTOMIZATION NOTE:
-- If you want to use different database/schema names, change BOEGAMINGREPORT
-- and DEMO throughout this file, and update the OpenFlow parameters:
--   - Snowflake Database → YOUR_DATABASE_NAME
--   - Snowflake Schema → YOUR_SCHEMA_NAME
--
-- The OpenFlow flow queries use parameter references #{Snowflake Database} and
-- #{Snowflake Schema}, so changing names here requires updating parameters there.
-- ============================================================================

-- ============================================================================
-- Step 1: Create OpenFlow Service User
-- ============================================================================
-- PREREQUISITE: Generate RSA key pair using OpenSSL (see SNOWFLAKE_SETUP.md Step 1)
--   openssl genrsa -out openflow_rsa_key.pem 2048
--   openssl rsa -in openflow_rsa_key.pem -pubout -out openflow_rsa_key.pub
--   grep -v "BEGIN PUBLIC" openflow_rsa_key.pub | grep -v "END PUBLIC" | tr -d '\n'

USE ROLE ACCOUNTADMIN;

-- Create service user for OpenFlow
CREATE OR REPLACE USER OPENFLOWSERVICE
  TYPE = SERVICE
  COMMENT = 'Service user for automated access of OpenFlow';

-- Grant SYSADMIN role and set as default
GRANT ROLE SYSADMIN TO USER OPENFLOWSERVICE;
ALTER USER OPENFLOWSERVICE SET DEFAULT_ROLE = SYSADMIN;

-- Set RSA public key (REPLACE WITH YOUR GENERATED PUBLIC KEY)
ALTER USER OPENFLOWSERVICE SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

-- Create role for regulatory batch operations
CREATE OR REPLACE ROLE OPENFLOWREPLICATE;
GRANT ROLE OPENFLOWREPLICATE TO USER OPENFLOWSERVICE;

-- Optional: Grant to your user for testing
-- GRANT ROLE OPENFLOWREPLICATE TO USER YOUR_USERNAME;

-- Verify service user
SHOW USERS LIKE 'OPENFLOWSERVICE';
SHOW GRANTS TO USER OPENFLOWSERVICE;
-- Expected grants: SYSADMIN, OPENFLOWREPLICATE

-- ============================================================================
-- Step 2: Create Database
-- ============================================================================
CREATE DATABASE IF NOT EXISTS BOEGAMINGREPORT;

-- ============================================================================
-- Step 3: Grant Permissions for Setup (Optional)
-- ============================================================================
-- If you're using a role other than ACCOUNTADMIN to create objects, grant permissions:
-- USE ROLE ACCOUNTADMIN;
-- GRANT USAGE ON DATABASE BOEGAMINGREPORT TO ROLE YOUR_SETUP_ROLE;
-- GRANT CREATE SCHEMA ON DATABASE BOEGAMINGREPORT TO ROLE YOUR_SETUP_ROLE;
-- USE ROLE YOUR_SETUP_ROLE;

-- ============================================================================
-- Step 4: Create Schema
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS BOEGAMINGREPORT.DEMO;

-- Optional: Grant schema-level permissions if using setup role
-- GRANT USAGE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
-- GRANT CREATE TABLE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
-- GRANT CREATE FUNCTION ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
-- GRANT CREATE PROCEDURE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
-- GRANT CREATE TASK ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
-- GRANT CREATE STAGE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;

-- ============================================================================
-- Step 5: Create Stage for Document AI
-- ============================================================================
-- This stage will be used to:
-- - Store the source BOE regulatory PDF
-- - Process documents through Snowflake's Document AI
-- - Support the automated specification extraction workflow
--
-- IMPORTANT: Must use server-side encryption (SNOWFLAKE_SSE) as required by
-- AI_PARSE_DOCUMENT function. Client-side encryption is not supported.

CREATE STAGE IF NOT EXISTS BOEGAMINGREPORT.DEMO.boe_documents
DIRECTORY = (ENABLE = true)
ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
COMMENT = 'Stage for BOE regulatory documents and Document AI processing';

-- ============================================================================
-- Step 6: Create Source Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS BOEGAMINGREPORT.DEMO.poker_tournaments (
    transaction_id VARCHAR(50),
    transaction_data VARIANT,
    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================================
-- Step 7: Create Audit Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS BOEGAMINGREPORT.DEMO.regulatory_batches (
    batch_id VARCHAR(50) PRIMARY KEY,
    operator_id VARCHAR(4),
    warehouse_id VARCHAR(10),
    batch_timestamp TIMESTAMP_NTZ,
    source_json_data VARIANT,
    generated_xml VARCHAR(16777216),
    status VARCHAR(20),
    upload_timestamp TIMESTAMP_NTZ,
    generated_filename VARCHAR(500),
    sftp_directory_path VARCHAR(1000)
);

-- ============================================================================
-- Step 8: Create XML Generation Function
-- Note that this would probably work better as a JSON > XML conversion in Openflow to avoid custom XML generation in Snowflake.
-- ============================================================================
CREATE OR REPLACE FUNCTION BOEGAMINGREPORT.DEMO.generate_poker_xml(
    json_array VARIANT,
    p_operator_id VARCHAR,
    p_warehouse_id VARCHAR,
    p_batch_id VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS $$
  '<?xml version="1.0" encoding="UTF-8"?>' ||
  '<Lote xmlns="http://cnjuego.gob.es/sci/v3.3.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' ||
  '<Cabecera>' ||
  '<OperadorId>' || p_operator_id || '</OperadorId>' ||
  '<AlmacenId>' || p_warehouse_id || '</AlmacenId>' ||
  '<LoteId>' || p_batch_id || '</LoteId>' ||
  '<Version>3.3</Version>' ||
  '</Cabecera>' ||
  '<Registro xsi:type="RegistroPoquerTorneo">' ||
  '<Cabecera>' ||
  '<RegistroId>REG_' || p_batch_id || '</RegistroId>' ||
  '<SubregistroId>1</SubregistroId>' ||
  '<SubregistroTotal>1</SubregistroTotal>' ||
  '<Fecha>' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS') || '</Fecha>' ||
  '</Cabecera>' ||
  '<Juego>' ||
  '<JuegoId>TOUR_' || SUBSTRING(p_batch_id, 1, 8) || '</JuegoId>' ||
  '<JuegoDesc>Texas Holdem Demo Tournament</JuegoDesc>' ||
  '<TipoJuego>POT</TipoJuego>' ||
  '<FechaInicio>' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS') || '+0100</FechaInicio>' ||
  '<FechaFin>' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS') || '+0100</FechaFin>' ||
  '<JuegoEnRed>S</JuegoEnRed>' ||
  '<LiquidezInternacional>N</LiquidezInternacional>' ||
  '<Variante>TH</Variante>' ||
  '<VarianteComercial>Texas Holdem No Limit</VarianteComercial>' ||
  '<NumeroParticipantes>' || ARRAY_SIZE(json_array) || '</NumeroParticipantes>' ||
  '</Juego>' ||
  -- Generate Jugador sections for each transaction
  (
    SELECT LISTAGG(
      '<Jugador>' ||
      '<ID><OperadorId>' || p_operator_id || '</OperadorId>' ||
      '<JugadorId>' || txn.value:data:player_id::VARCHAR || '</JugadorId></ID>' ||
      '<Participacion><Linea>' ||
      '<Cantidad>' || ROUND(txn.value:data:bet_amount::FLOAT, 2) || '</Cantidad>' ||
      '<Unidad>EUR</Unidad>' ||
      '</Linea></Participacion>' ||
      '<ParticipacionDevolucion><Linea>' ||
      '<Cantidad>0.00</Cantidad>' ||
      '<Unidad>EUR</Unidad>' ||
      '</Linea></ParticipacionDevolucion>' ||
      '<Premios><Linea>' ||
      '<Cantidad>' || ROUND(txn.value:data:win_amount::FLOAT, 2) || '</Cantidad>' ||
      '<Unidad>EUR</Unidad>' ||
      '</Linea></Premios>' ||
      '<IP>192.168.1.100</IP>' ||
      '<Dispositivo>PC</Dispositivo>' ||
      '<IdDispositivo>DEMO_PC_' || txn.value:transaction_id::VARCHAR || '</IdDispositivo>' ||
      '</Jugador>',
      ''
    )
    FROM TABLE(FLATTEN(json_array)) txn
  ) ||
  '</Registro>' ||
  '</Lote>'
$$;

-- ============================================================================
-- Step 9: Create Batch Generation Procedure
-- ============================================================================
-- This procedure generates filename and SFTP path per DGOJ specifications:
-- Filename: <OperadorId>_<AlmacenId>_JU_JUC_POT_<YYYYMMDDHHMMSS>_<BatchId>.zip
-- Directory: CNJ/<OperadorId>/JU/<YYYYMMDD>/POT/
--
-- DESIGN NOTE: 15-Minute Batching
-- BOE spec requires batches every 15 minutes OR 500 subregistros (whichever first).
-- This procedure aggregates transactions from last 15 minutes.
--
-- Triggering options:
-- 1. Manual: CALL generate_regulatory_batch(); (for testing)
-- 2. Snowflake Task: CREATE TASK...SCHEDULE='15 minute'...
-- 3. External scheduler: Call via stored procedure API every 15 min
--
-- OpenFlow polls every 1 minute for READY batches, ensuring quick pickup.

CREATE OR REPLACE PROCEDURE BOEGAMINGREPORT.DEMO.generate_regulatory_batch()
RETURNS VARCHAR
LANGUAGE SQL
AS $$
DECLARE
  batch_id VARCHAR;
  batch_time TIMESTAMP_NTZ;
  date_yyyymmddhhmmss VARCHAR;
  date_yyyymmdd VARCHAR;
  short_batch_id VARCHAR;
  cutoff_time TIMESTAMP_NTZ;
  txn_array VARIANT;
  generated_xml_content VARCHAR;
BEGIN
  batch_id := UUID_STRING();
  batch_time := CURRENT_TIMESTAMP();
  cutoff_time := DATEADD(minute, -15, batch_time);
  date_yyyymmddhhmmss := TO_CHAR(batch_time, 'YYYYMMDDHH24MISS');
  date_yyyymmdd := TO_CHAR(batch_time, 'YYYYMMDD');
  short_batch_id := SUBSTRING(batch_id, 1, 8);

  -- Aggregate transactions from last 15 minutes
  SELECT ARRAY_AGG(OBJECT_CONSTRUCT('transaction_id', transaction_id, 'data', transaction_data))
  INTO txn_array
  FROM BOEGAMINGREPORT.DEMO.poker_tournaments
  WHERE created_timestamp >= :cutoff_time;

  -- Generate XML from transactions
  generated_xml_content := BOEGAMINGREPORT.DEMO.generate_poker_xml(txn_array, 'OP01', 'ALM01', batch_id);

  -- Insert batch record
  INSERT INTO BOEGAMINGREPORT.DEMO.regulatory_batches (
    batch_id,
    operator_id,
    warehouse_id,
    batch_timestamp,
    source_json_data,
    generated_xml,
    status,
    generated_filename,
    sftp_directory_path
  )
  SELECT
    :batch_id,
    'OP01',
    'ALM01',
    :batch_time,
    :txn_array,
    :generated_xml_content,
    'READY',
    'OP01_ALM01_JU_JUC_POT_' || :date_yyyymmddhhmmss || '_' || :short_batch_id || '.zip',
    'CNJ/OP01/JU/' || :date_yyyymmdd || '/POT/';

  RETURN batch_id;
END;
$$;

-- ============================================================================
-- Step 10: Insert Sample Transaction Data
-- ============================================================================
INSERT INTO BOEGAMINGREPORT.DEMO.poker_tournaments (transaction_id, transaction_data)
SELECT
    'TXN_' || SEQ4() as transaction_id,
    OBJECT_CONSTRUCT(
        'tournament_id', 'TOUR_' || SEQ4(),
        'player_id', 'PLAYER_' || UNIFORM(1000, 9999, RANDOM()),
        'bet_amount', ROUND(UNIFORM(10, 500, RANDOM()), 2),
        'win_amount', ROUND(UNIFORM(0, 1000, RANDOM()), 2),
        'timestamp', CURRENT_TIMESTAMP()
    ) as transaction_data
FROM TABLE(GENERATOR(ROWCOUNT => 50));

-- ============================================================================
-- Step 11: Generate Initial Test Batch
-- ============================================================================
CALL BOEGAMINGREPORT.DEMO.generate_regulatory_batch();

-- ============================================================================
-- Step 12: Grant Permissions for OpenFlow (Required for Runtime)
-- ============================================================================
-- OpenFlow needs read access to query batches and write access to update status.
-- Grant these permissions to the OPENFLOWREPLICATE role (created in Step 1).

USE ROLE ACCOUNTADMIN;

-- Grant database and schema access
GRANT USAGE ON DATABASE BOEGAMINGREPORT TO ROLE OPENFLOWREPLICATE;
GRANT USAGE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE OPENFLOWREPLICATE;

-- Grant table permissions (read batches, update status)
GRANT SELECT ON TABLE BOEGAMINGREPORT.DEMO.regulatory_batches TO ROLE OPENFLOWREPLICATE;
GRANT UPDATE ON TABLE BOEGAMINGREPORT.DEMO.regulatory_batches TO ROLE OPENFLOWREPLICATE;

-- Optional: Grant SELECT on source table if OpenFlow needs to query it
GRANT SELECT ON TABLE BOEGAMINGREPORT.DEMO.poker_tournaments TO ROLE OPENFLOWREPLICATE;

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Verify tables exist
SELECT TABLE_NAME
FROM BOEGAMINGREPORT.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'DEMO';

-- View sample transaction data
SELECT transaction_id, transaction_data, created_timestamp
FROM BOEGAMINGREPORT.DEMO.poker_tournaments
LIMIT 3;

-- View batch summary (verify record_count > 0)
SELECT
  batch_id,
  operator_id,
  warehouse_id,
  batch_timestamp,
  status,
  LENGTH(generated_xml) as xml_length,
  ARRAY_SIZE(source_json_data) as record_count
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
WHERE status = 'READY';
-- Expected: record_count should be 50 (from sample data)

-- View generated XML
SELECT generated_xml
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
WHERE status = 'READY'
LIMIT 1;

-- View filename and directory path (generated per DGOJ specifications)
SELECT
  generated_filename,
  sftp_directory_path
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
WHERE status = 'READY'
LIMIT 1;

-- ============================================================================
-- OpenFlow Integration Queries (Reference)
-- ============================================================================

-- Query to retrieve ready batches (used in OpenFlow ExecuteSQL)
-- Returns XML content, filename, and directory path for upload
SELECT
    batch_id,
    operator_id,
    warehouse_id,
    batch_timestamp,
    generated_xml,
    source_json_data,
    generated_filename,
    sftp_directory_path
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
WHERE status = 'READY'
ORDER BY batch_timestamp ASC;

-- Update query after successful upload (used in OpenFlow ExecuteSQL after PutSFTP)
-- UPDATE BOEGAMINGREPORT.DEMO.regulatory_batches
-- SET
--     status = 'UPLOADED',
--     upload_timestamp = CURRENT_TIMESTAMP()
-- WHERE batch_id = ?;

-- ============================================================================
-- Ongoing Usage: Generate New Test Batches
-- ============================================================================

-- Insert new transactions (simulates 15-minute window)
-- INSERT INTO BOEGAMINGREPORT.DEMO.poker_tournaments (transaction_id, transaction_data)
-- SELECT
--     'TXN_NEW_' || SEQ4() as transaction_id,
--     OBJECT_CONSTRUCT(
--         'tournament_id', 'TOUR_NEW_' || SEQ4(),
--         'player_id', 'PLAYER_' || UNIFORM(1000, 9999, RANDOM()),
--         'bet_amount', ROUND(UNIFORM(10, 500, RANDOM()), 2),
--         'win_amount', ROUND(UNIFORM(0, 1000, RANDOM()), 2),
--         'timestamp', CURRENT_TIMESTAMP()
--     ) as transaction_data
-- FROM TABLE(GENERATOR(ROWCOUNT => 10));
--
-- -- Generate new batch
-- CALL BOEGAMINGREPORT.DEMO.generate_regulatory_batch();
