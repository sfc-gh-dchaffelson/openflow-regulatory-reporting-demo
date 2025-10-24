# Snowflake Setup

Complete database setup for the BOE Gaming Report demo.

---

## Prerequisites

- Snowflake account with permissions to create databases, schemas, tables, functions, and procedures
- Worksheet or SQL client connected to Snowflake

---

## Database and Schema Names

**Default names:** `BOEGAMINGREPORT.DEMO`

**To customize:** Change `BOEGAMINGREPORT` and `DEMO` throughout this setup, then update OpenFlow parameters:
- `Snowflake Database` → YOUR_DATABASE_NAME
- `Snowflake Schema` → YOUR_SCHEMA_NAME

The OpenFlow flow uses parameter references `#{Snowflake Database}` and `#{Snowflake Schema}`, so names must match.

---

## Step 1: Create OpenFlow Service User

OpenFlow requires a Snowflake service user with RSA key pair authentication for BYOC deployments.
If using Openflow on SPCS you can skip this step.

### Generate RSA Key Pair

```bash
# Generate unencrypted private key
openssl genrsa -out openflow_rsa_key.pem 2048

# Generate public key
openssl rsa -in openflow_rsa_key.pem -pubout -out openflow_rsa_key.pub

# Extract public key value (remove header/footer for Snowflake)
grep -v "BEGIN PUBLIC" openflow_rsa_key.pub | grep -v "END PUBLIC" | tr -d '\n'
```

**Save the output** of the last command - this is your RSA_PUBLIC_KEY value.

**Save the private key** in `openflow_rsa_key.pem` - you'll need the entire contents for the **Snowflake Private Key** parameter in OpenFlow.

### Create Service User and Role

```sql
USE ROLE ACCOUNTADMIN;

-- Create service user for OpenFlow
CREATE OR REPLACE USER OPENFLOWSERVICE
  TYPE = SERVICE
  COMMENT = 'Service user for automated access of OpenFlow';

-- Grant SYSADMIN role and set as default
GRANT ROLE SYSADMIN TO USER OPENFLOWSERVICE;
ALTER USER OPENFLOWSERVICE SET DEFAULT_ROLE = SYSADMIN;

-- Set RSA public key (replace with your generated public key)
ALTER USER OPENFLOWSERVICE SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

-- Create role for regulatory batch operations
CREATE OR REPLACE ROLE OPENFLOWREPLICATE;
GRANT ROLE OPENFLOWREPLICATE TO USER OPENFLOWSERVICE;

-- Optional: Grant to your user for testing
-- GRANT ROLE OPENFLOWREPLICATE TO USER YOUR_USERNAME;
```

**Replace the `RSA_PUBLIC_KEY` value** with your generated public key from the previous step.

### Verify Service User

```sql
SHOW USERS LIKE 'OPENFLOWSERVICE';
SHOW GRANTS TO USER OPENFLOWSERVICE;
```

Expected grants: SYSADMIN, OPENFLOWREPLICATE

---

## Step 2: Create Database

```sql
CREATE DATABASE IF NOT EXISTS BOEGAMINGREPORT;
```

---

## Step 3: Grant Permissions for Setup (Optional)

If you're using a role other than ACCOUNTADMIN to create objects (e.g., for Cursor IDE or a setup service account), grant the necessary permissions:

```sql
-- Replace YOUR_SETUP_ROLE with your role name (e.g., SVC_CURSOR_ROLE, SYSADMIN, etc.)
USE ROLE ACCOUNTADMIN;

-- Grant database-level permissions
GRANT USAGE ON DATABASE BOEGAMINGREPORT TO ROLE YOUR_SETUP_ROLE;
GRANT CREATE SCHEMA ON DATABASE BOEGAMINGREPORT TO ROLE YOUR_SETUP_ROLE;

-- Switch to setup role for remaining steps
USE ROLE YOUR_SETUP_ROLE;
```

**Note:** If you're using ACCOUNTADMIN, skip this step.

---

## Step 4: Create Schema

```sql
CREATE SCHEMA IF NOT EXISTS BOEGAMINGREPORT.DEMO;
```

**Grant schema-level permissions** (if using setup role):

```sql
-- If using setup role, grant additional schema permissions
GRANT USAGE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
GRANT CREATE TABLE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
GRANT CREATE FUNCTION ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
GRANT CREATE PROCEDURE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
GRANT CREATE TASK ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
GRANT CREATE STAGE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE YOUR_SETUP_ROLE;
```

---

## Step 5: Create Stage for Document AI

```sql
CREATE STAGE IF NOT EXISTS BOEGAMINGREPORT.DEMO.boe_documents
DIRECTORY = (ENABLE = true)
ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
COMMENT = 'Stage for BOE regulatory documents and Document AI processing';
```

This stage will be used to:
- Store the source BOE regulatory PDF
- Process documents through Snowflake's Document AI
- Support the automated specification extraction workflow

**Important:** The stage must use server-side encryption (`SNOWFLAKE_SSE`) as required by the `AI_PARSE_DOCUMENT` function. Client-side encryption is not supported.

---

## Step 6: Create Source Table

```sql
CREATE TABLE IF NOT EXISTS BOEGAMINGREPORT.DEMO.poker_tournaments (
    transaction_id VARCHAR(50),
    transaction_data VARIANT,
    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

This table stores source JSON transaction data from poker tournaments.

---

## Step 7: Create Audit Table

```sql
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
```

This table provides complete audit trail:
- **batch_id**: Unique identifier for each batch
- **operator_id, warehouse_id**: DGOJ identifiers (OP01, ALM01)
- **batch_timestamp**: When batch was created
- **source_json_data**: Original transaction data preserved for audit
- **generated_xml**: Complete XML content ready for upload
- **status**: Lifecycle tracking (READY → UPLOADED)
- **upload_timestamp**: When OpenFlow successfully uploaded (set by ExecuteSQL processor)
- **generated_filename**: Target filename per DGOJ spec
- **sftp_directory_path**: Target directory per DGOJ spec

---

## Step 8: Create XML Generation Function

```sql
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
```

**XML Generation with Transaction Data:**

This function iterates over the `json_array` parameter to include transaction data:
- Aggregates transactions from the database (last 15 minutes)
- Preserves source data in `source_json_data` column for audit trail
- Generates a `<Jugador>` section for each transaction in the XML

**Fields included per transaction:**
- Player ID (`player_id` from transaction data)
- Bet amount (`bet_amount` as Participacion)
- Win amount (`win_amount` as Premios)
- Unique device ID (using transaction_id)
- Number of participants (actual transaction count)

**Note:** This implementation is simplified for demonstration. Production deployment would require additional fields per DGOJ XSD (see [../specifications/05_COMPLIANCE.md](../specifications/05_COMPLIANCE.md)).

---

## Step 9: Create Batch Generation Procedure

```sql
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
```

**Design Notes:**
- Aggregates last 15 minutes of transactions (BOE spec requirement)
- Generates filename per spec: `OP01_ALM01_JU_JUC_POT_YYYYMMDDHHMMSS_BatchId.zip`
- Generates directory per spec: `CNJ/OP01/JU/YYYYMMDD/POT/`
- Sets status to READY for OpenFlow pickup

**Triggering Options:**
1. Manual: `CALL generate_regulatory_batch();` (for testing)
2. Snowflake Task: Schedule every 15 minutes
3. External scheduler: Call via Snowflake API

OpenFlow polls every 1 minute for READY batches, ensuring quick pickup.

---

## Step 10: Insert Sample Transaction Data

```sql
-- Generate sample poker tournament transactions
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
```

This creates 50 sample transactions with current timestamps for testing batch generation.

---

## Step 11: Generate Initial Test Batch

```sql
CALL BOEGAMINGREPORT.DEMO.generate_regulatory_batch();
```

This creates one batch with status='READY' for testing the OpenFlow integration.

---

## Verification

### Check Tables

```sql
SELECT TABLE_NAME
FROM BOEGAMINGREPORT.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'DEMO';

-- Expected: poker_tournaments, regulatory_batches
```

### View Sample Transactions

```sql
SELECT transaction_id, transaction_data, created_timestamp
FROM BOEGAMINGREPORT.DEMO.poker_tournaments
LIMIT 3;
```

### Check Test Batch

```sql
SELECT
  batch_id,
  operator_id,
  warehouse_id,
  batch_timestamp,
  status,
  LENGTH(generated_xml) as xml_length,
  ARRAY_SIZE(source_json_data) as record_count,
  generated_filename,
  sftp_directory_path
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
WHERE status = 'READY';

-- Expected: 1 row with status='READY', record_count=20
```

### View Generated XML

```sql
SELECT generated_xml
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
WHERE status = 'READY'
LIMIT 1;
```

---

## Step 12: Grant Permissions for OpenFlow (Required for Runtime)

OpenFlow needs read access to query batches and write access to update status. Grant these permissions to the OPENFLOWREPLICATE role (created in Step 1):

```sql
USE ROLE ACCOUNTADMIN;

-- Grant database and schema access
GRANT USAGE ON DATABASE BOEGAMINGREPORT TO ROLE OPENFLOWREPLICATE;
GRANT USAGE ON SCHEMA BOEGAMINGREPORT.DEMO TO ROLE OPENFLOWREPLICATE;

-- Grant table permissions (read batches, update status)
GRANT SELECT ON TABLE BOEGAMINGREPORT.DEMO.regulatory_batches TO ROLE OPENFLOWREPLICATE;
GRANT UPDATE ON TABLE BOEGAMINGREPORT.DEMO.regulatory_batches TO ROLE OPENFLOWREPLICATE;

-- Optional: Grant SELECT on source table if OpenFlow needs to query it
GRANT SELECT ON TABLE BOEGAMINGREPORT.DEMO.poker_tournaments TO ROLE OPENFLOWREPLICATE;
```

**What OpenFlow needs:**
- **Database:** USAGE (to connect and access)
- **Schema:** USAGE (to see objects)
- **regulatory_batches table:** SELECT (read ready batches), UPDATE (mark as uploaded)
- **Functions/Procedures:** Inherited via schema USAGE (called by stored procedures)

**Security Note:** OpenFlow does NOT need:
- CREATE privileges (objects already exist)
- INSERT or DELETE on tables (only reads and updates status)
- Ownership of any objects

---

## Ongoing Usage

### Generate New Batches

```sql
-- Insert new transactions (simulates 15-minute window)
INSERT INTO BOEGAMINGREPORT.DEMO.poker_tournaments (transaction_id, transaction_data)
SELECT
    'TXN_NEW_' || SEQ4() as transaction_id,
    OBJECT_CONSTRUCT(
        'tournament_id', 'TOUR_NEW_' || SEQ4(),
        'player_id', 'PLAYER_' || UNIFORM(1000, 9999, RANDOM()),
        'bet_amount', ROUND(UNIFORM(10, 500, RANDOM()), 2),
        'win_amount', ROUND(UNIFORM(0, 1000, RANDOM()), 2),
        'timestamp', CURRENT_TIMESTAMP()
    ) as transaction_data
FROM TABLE(GENERATOR(ROWCOUNT => 10));

-- Generate batch
CALL BOEGAMINGREPORT.DEMO.generate_regulatory_batch();
```

### Monitor Batch Status

```sql
SELECT
  batch_id,
  status,
  batch_timestamp,
  upload_timestamp,
  generated_filename
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
ORDER BY batch_timestamp DESC;
```

Status flow: READY → UPLOADED (updated by OpenFlow after successful upload)

---

## Optional: Snowflake Task Automation

To automatically generate batches every 15 minutes:

```sql
CREATE TASK generate_batches_task
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '15 MINUTE'
AS
  CALL BOEGAMINGREPORT.DEMO.generate_regulatory_batch();

-- Start the task
ALTER TASK generate_batches_task RESUME;
```

---

## Next Step

Proceed to [02_CREDENTIALS_SETUP.md](02_CREDENTIALS_SETUP.md) to generate security credentials.
