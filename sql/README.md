# SQL Scripts

SQL scripts for deploying the BOE Gaming regulatory compliance demo.

## Execution Order

Run scripts in numbered order. Some scripts have dependencies on external systems (CDC, OpenFlow) - see notes below.

| Script | Description | Prerequisites | Method |
|--------|-------------|---------------|--------|
| `00_set_variables.sql` | Set session variables | None | Direct |
| `01_database_schema.sql` | Create database and schema | ACCOUNTADMIN access | Direct |
| `02_grants.sql` | All grants (initial + object + spec extraction) | Database exists | Direct |
| `03_tables.sql` | Create BATCH_STAGING, REGULATORY_BATCHES | Schema exists | Direct |
| `04_functions.sql` | Create GENERATE_POKER_XML_JS | Tables exist | **Stage upload** |
| `05_procedures.sql` | Create PROCESS_STAGED_BATCH | Function exists | Stage upload |
| --- | **WAIT: Start CDC connector, data must replicate** | --- | --- |
| `06_cdc_setup.sql` | CDC grants + change tracking | TOURNAMENTS.POKER exists | Direct |
| `07_dynamic_table.sql` | Create DT_POKER_FLATTENED | Change tracking enabled | Direct |
| `08_stream.sql` | Create POKER_TRANSACTIONS_STREAM | Dynamic table exists | Direct |
| `09_views.sql` | Create observability views | Tables + CDC table exist | Direct |

## Usage

### Using the Wrapper Script

```bash
cd sql

# Set variables first (edit the file, then run)
./run_sql.sh <connection> 00_set_variables.sql

# Run direct execution scripts
./run_sql.sh <connection> 01_database_schema.sql
./run_sql.sh <connection> 02_grants.sql
./run_sql.sh <connection> 03_tables.sql

# Run stage-upload scripts (required for JavaScript UDFs)
./run_sql.sh <connection> 04_functions.sql --stage-upload
./run_sql.sh <connection> 05_procedures.sql --stage-upload
```

Replace `<connection>` with your Snowflake CLI connection name.

### Manual Execution

For scripts that don't require stage upload:
```bash
snow sql -c <connection> -f sql/01_database_schema.sql
```

For scripts with JavaScript UDFs or complex escape sequences:
```bash
# Upload to stage
snow stage copy sql/04_functions.sql @DEDEMO.GAMING.%BATCH_STAGING/sql -c <connection> --overwrite

# Execute from stage
snow sql -c <connection> -q "EXECUTE IMMEDIATE FROM @DEDEMO.GAMING.%BATCH_STAGING/sql/04_functions.sql"
```

## Why Stage Upload?

The JavaScript UDF in `04_functions.sql` uses `$$` delimiters and contains escape sequences that get corrupted when passed through `snow sql -f`. The stage upload method preserves the exact file contents.

Files requiring stage upload are marked in the table above.

## Verification

After running all scripts:

```sql
-- Check all objects exist
SHOW TABLES IN SCHEMA DEDEMO.GAMING;
SHOW DYNAMIC TABLES IN SCHEMA DEDEMO.GAMING;
SHOW STREAMS IN SCHEMA DEDEMO.GAMING;
SHOW VIEWS IN SCHEMA DEDEMO.GAMING;
SHOW USER FUNCTIONS IN SCHEMA DEDEMO.GAMING;
SHOW PROCEDURES IN SCHEMA DEDEMO.GAMING;

-- Test the function
SELECT DEDEMO.GAMING.GENERATE_POKER_XML_JS(
    ARRAY_CONSTRUCT(OBJECT_CONSTRUCT('PLAYER_ID', 'TEST', 'BET_AMOUNT', 10.00)),
    'OP01', 'WH001', 'TEST-BATCH'
);
```

## Session Variables

The `00_set_variables.sql` file sets these session variables used by other scripts:

| Variable | Description | Example |
|----------|-------------|---------|
| `$RUNTIME_ROLE` | OpenFlow runtime role | (see credentials/DEPLOYMENT_VALUES.md) |
| `$ADMIN_ROLE` | Admin role for initial setup | `ACCOUNTADMIN` |
| `$WAREHOUSE_NAME` | Compute warehouse | (see credentials/DEPLOYMENT_VALUES.md) |

**Important:** Session variables persist only within a session. If you run scripts in separate sessions, re-run `00_set_variables.sql` first.
