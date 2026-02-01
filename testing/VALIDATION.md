# Pipeline Validation Procedure

Agent-executable validation for the BOE Gaming regulatory compliance demo. Run this procedure to verify the complete pipeline is operational from transaction generation through SFTP delivery.

**Estimated runtime**: 5-10 minutes (includes wait times for data propagation)

---

## Prerequisites

Before running validation:
- Snowflake CLI configured with a connection (replace `<connection>` in commands below)
- SFTP credentials available in `credentials/` directory (gaming_sftp_key)
- All flows should be running (if not, start them first)
- `uv` installed for Python script execution (Steps 11b, 12b)
- Run all commands from the project root directory (`BoeGamingReport/`)

**SFTP Connection Details**: See `credentials/DEPLOYMENT_VALUES.md` for hostname, username, and credentials.

---

## Validation Steps

Execute these steps in order. Each step includes expected output and pass/fail criteria.

### Step 1: Verify Snowflake Objects Exist

**Note**: Use `USE DATABASE DEDEMO;` first, then query INFORMATION_SCHEMA. Dynamic tables must use SHOW command.

```bash
snow sql -c <connection> -q "USE DATABASE DEDEMO; SELECT 'TABLES' as type, COUNT(*) as count FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'GAMING' UNION ALL SELECT 'VIEWS', COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'GAMING' UNION ALL SELECT 'PROCEDURES', COUNT(*) FROM INFORMATION_SCHEMA.PROCEDURES WHERE PROCEDURE_SCHEMA = 'GAMING' UNION ALL SELECT 'FUNCTIONS', COUNT(*) FROM INFORMATION_SCHEMA.FUNCTIONS WHERE FUNCTION_SCHEMA = 'GAMING';"
```

For Dynamic Tables (separate query):
```bash
snow sql -c <connection> -q "SHOW DYNAMIC TABLES IN SCHEMA DEDEMO.GAMING;"
```

**Expected**:
- TABLES >= 6 (BATCH_STAGING, REGULATORY_BATCHES, DOC_METADATA, FILE_HASHES, BOE_DOCUMENT_EXTRACTED, AI_OUTPUTS)
- VIEWS >= 4 (PIPELINE_LATENCY_ANALYSIS, PIPELINE_LATENCY_DETAIL, OPENFLOW_LOGS, OPENFLOW_ERROR_SUMMARY)
- PROCEDURES >= 1 (PROCESS_STAGED_BATCH)
- FUNCTIONS >= 1 (GENERATE_POKER_XML_JS, FETCH_BATCHES_FOR_PROCESSING)
- Dynamic Table: DT_POKER_FLATTENED exists

**Pass criteria**: All counts meet or exceed expected values.

---

### Step 1b: Verify Specification Document in Stage

```bash
snow sql -c <connection> -q "LIST @DEDEMO.GAMING.DOCUMENTS;" --format json
```

**Expected**: At least one file (the regulatory PDF from SharePoint):
- `BOE-A-2024-12639.pdf` or similar regulatory document

**Pass criteria**: Stage contains the source specification document.

---

### Step 1c: Verify AI Extraction Completed

```bash
snow sql -c <connection> -q "SELECT 'BOE_DOCUMENT_EXTRACTED' as TBL, COUNT(*) as CNT FROM DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED UNION ALL SELECT 'AI_OUTPUTS', COUNT(*) FROM DEDEMO.GAMING.AI_OUTPUTS;" --format json
```

**Expected**:
- BOE_DOCUMENT_EXTRACTED: 1 row (the parsed PDF)
- AI_OUTPUTS: 4 rows (JSON + Markdown for Sections 3 & 4)

**Pass criteria**: AI extraction has processed the specification document.

---

### Step 1d: Verify OpenFlow Flows Are Running

Check that all demo flows are running with no stopped processors.

```bash
# Check status of each demo flow
nipyapi --profile <profile> ci get_status --process_group_name "Generate Transactions"
nipyapi --profile <profile> ci get_status --process_group_name "Batch Processing"
nipyapi --profile <profile> ci get_status --process_group_name "Boe Gaming Report"
nipyapi --profile <profile> ci get_status --process_group_name "PostgreSQL"
```

**Expected for each flow**:
- `running_processors` > 0
- `stopped_processors` = 0
- `invalid_processors` = 0

**Alternative**: Check via OpenFlow UI
1. Open OpenFlow in browser
2. Navigate to "DE Demo - Gaming Pipeline" process group
3. Verify each flow shows green "running" status
4. Check for any yellow warning or red error bulletins

**Pass criteria**: All demo flows running, no stopped/invalid processors, no active error bulletins.

**If flows are stopped**: Start them before continuing validation:
```bash
nipyapi --profile <profile> ci start_flow --process_group_name "<flow_name>"
```

---

### Step 2: Verify CDC Source Has Data

```bash
snow sql -c <connection> -q "
SELECT
    'CDC_TABLE' as stage,
    COUNT(*) as row_count,
    MAX(CREATED_TIMESTAMP) as latest_timestamp,
    DATEDIFF('minute', MAX(CREATED_TIMESTAMP), CURRENT_TIMESTAMP()) as minutes_since_last
FROM DEDEMO.TOURNAMENTS.POKER;
"
```

**Expected**:
- row_count > 0
- minutes_since_last < 15 (if transaction generator is running)

**Pass criteria**: Data exists. If minutes_since_last > 15, transaction generator may not be running.

---

### Step 3: Verify Dynamic Table Is Refreshing

```bash
snow sql -c <connection> -q "
SELECT
    'DYNAMIC_TABLE' as stage,
    COUNT(*) as row_count,
    MAX(CREATED_TIMESTAMP) as latest_timestamp,
    DATEDIFF('minute', MAX(CREATED_TIMESTAMP), CURRENT_TIMESTAMP()) as minutes_since_last
FROM DEDEMO.GAMING.DT_POKER_FLATTENED;
"
```

**Expected**:
- row_count approximately equals CDC table row count
- minutes_since_last within 2-3 minutes of CDC table (1-minute DT lag)

**Pass criteria**: DT has data and is within expected lag of CDC source.

---

### Step 4: Check Stream State

```bash
snow sql -c <connection> -q "
SELECT
    'STREAM' as stage,
    SYSTEM\$STREAM_HAS_DATA('DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM') as has_pending_data;
"
```

**Expected**: TRUE or FALSE (both are valid states)
- TRUE = unprocessed records waiting for batch processing
- FALSE = all records have been consumed by Batch_Processing flow

**Pass criteria**: Query executes without error.

---

### Step 5: Verify Batch Processing

```bash
snow sql -c <connection> -q "
SELECT
    STATUS,
    COUNT(*) as batch_count,
    MAX(BATCH_TIMESTAMP) as latest_batch,
    DATEDIFF('minute', MAX(BATCH_TIMESTAMP), CURRENT_TIMESTAMP()) as minutes_since_last
FROM DEDEMO.GAMING.REGULATORY_BATCHES
GROUP BY STATUS
ORDER BY STATUS;
"
```

**Expected**:
- UPLOADED status should have batches if pipeline is running
- GENERATED status may have batches waiting for SFTP upload
- minutes_since_last < 20 for recent activity

**Pass criteria**: At least one batch exists with UPLOADED status.

---

### Step 6: Sample Batch Details

```bash
snow sql -c <connection> -q "SELECT BATCH_ID, STATUS, TRANSACTION_COUNT, BATCH_TIMESTAMP, GENERATED_FILENAME, SFTP_DIRECTORY_PATH FROM DEDEMO.GAMING.REGULATORY_BATCHES WHERE STATUS = 'UPLOADED' ORDER BY BATCH_TIMESTAMP DESC LIMIT 3;"
```

**Expected**: Recent uploaded batches with:
- TRANSACTION_COUNT > 0 (typically 500-700 per batch)
- GENERATED_FILENAME matching pattern: `OP01_WH001_<uuid>.zip`
- SFTP_DIRECTORY_PATH matching pattern: `uploads/YYYY/MM/DD`

**Pass criteria**: At least one valid uploaded batch exists with transaction count > 0.

---

### Step 7: Check Pipeline Latency

```bash
snow sql -c <connection> -q "SELECT * FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS LIMIT 5;"
```

**Expected**: Latency metrics by stage:
- `CDC Replication`: avg ~40 sec
- `Dynamic Table Refresh`: avg ~60 sec (matches 1-min target lag)
- `Batch to SFTP Upload`: avg ~10-15 sec
- `TOTAL END-TO-END`: avg ~110 sec (~2 minutes)

**Pass criteria**: View returns stage-based latency metrics with reasonable values (end-to-end < 5 minutes).

---

### Step 8: Check OpenFlow Error Summary

```bash
snow sql -c <connection> -q "
SELECT * FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
WHERE HOUR > DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY HOUR DESC
LIMIT 10;
"
```

**Expected**:
- Ideally: No rows (no errors in last 24 hours)
- Acceptable: Low error counts, no sustained error patterns

**Pass criteria**: No critical error patterns in recent hours.

---

### Step 9: Verify SFTP Delivery (via Snowflake)

```bash
snow sql -c <connection> -q "SELECT COUNT(*) as total_uploaded, SUM(TRANSACTION_COUNT) as total_transactions, MIN(BATCH_TIMESTAMP) as first_batch, MAX(BATCH_TIMESTAMP) as last_batch FROM DEDEMO.GAMING.REGULATORY_BATCHES WHERE STATUS = 'UPLOADED';" --format json
```

**Expected**: total_uploaded > 0, recent last_batch timestamp

**Pass criteria**: Batches confirmed as uploaded.

---

### Step 10: List Files on SFTP Server

Connect to SFTP and list recent files:

```bash
# List files in uploads directory (get SFTP hostname from credentials/DEPLOYMENT_VALUES.md)
sftp -i credentials/gaming_sftp_key -o StrictHostKeyChecking=no -o BatchMode=yes \
  <sftp-username>@<sftp-hostname> <<EOF
cd uploads
ls -la
bye
EOF
```

**Expected**: Directory listing showing date-organized folders with `.zip` files.

**Pass criteria**: SFTP connection succeeds and files are visible.

---

### Step 11: Download Latest Report from SFTP

```bash
# Get the latest batch filename from Snowflake
LATEST_FILE=$(snow sql -c <connection> -q "SELECT SFTP_DIRECTORY_PATH || '/' || GENERATED_FILENAME FROM DEDEMO.GAMING.REGULATORY_BATCHES WHERE STATUS = 'UPLOADED' ORDER BY BATCH_TIMESTAMP DESC LIMIT 1;" --format csv | tail -1)

echo "Downloading: $LATEST_FILE"

# Download via SFTP (get SFTP hostname from credentials/DEPLOYMENT_VALUES.md)
sftp -i credentials/gaming_sftp_key -o StrictHostKeyChecking=no -o BatchMode=yes \
  <sftp-username>@<sftp-hostname> <<EOF
get "$LATEST_FILE" /tmp/latest_report.zip
bye
EOF

# Verify download
ls -la /tmp/latest_report.zip
file /tmp/latest_report.zip
```

**Expected**:
- File downloads successfully
- `file` command shows: `Zip archive data` (encrypted ZIP)
- File size > 0 bytes

**Pass criteria**: Encrypted ZIP file successfully downloaded from SFTP.

---

### Step 11b: Unpack and Verify Report Contents

```bash
# Extract AES-encrypted ZIP with pyzipper (macOS unzip doesn't support AES-256)
# Get ZIP password from credentials/DEPLOYMENT_VALUES.md
uv run --with pyzipper python -c "
import pyzipper
import os

ZIP_PASSWORD = b'<zip-password-from-DEPLOYMENT_VALUES.md>'

os.makedirs('/tmp/latest_report', exist_ok=True)
with pyzipper.AESZipFile('/tmp/latest_report.zip', 'r') as zf:
    print('Files:', zf.namelist())
    zf.extractall('/tmp/latest_report', pwd=ZIP_PASSWORD)
    print('Extracted successfully')
"

# Verify XML structure (XML is minified, use grep instead of head)
grep -o '<Lote xmlns="[^"]*"' /tmp/latest_report/*.xml | head -1
grep -c '<Jugador>' /tmp/latest_report/*.xml
grep -c '<ds:Signature' /tmp/latest_report/*.xml
```

**Expected**:
- ZIP extracts successfully with demo password
- Contains XML file with regulatory data
- `<Lote>` with namespace `http://cnjuego.gob.es/sci/v3.3.xsd`
- `<Jugador>` count > 0 (matches transaction count)
- `<ds:Signature>` count >= 1 (XAdES-BES signature present)

**Pass criteria**: XML contains valid signed regulatory data.

---

### Step 12: Verify Semantic View

```bash
snow sql -c <connection> -q "SHOW SEMANTIC VIEWS IN SCHEMA DEDEMO.GAMING;"
```

**Expected**: `GAMING_PIPELINE_ANALYTICS` semantic view listed with `extension: ["CA"]`.

**Pass criteria**: Semantic view exists.

---

### Step 12b: Verify Semantic View Configuration

Verify the semantic view is properly configured with tables and dimensions:

```bash
snow sql -c <connection> -q "DESC SEMANTIC VIEW DEDEMO.GAMING.GAMING_PIPELINE_ANALYTICS;" --format json
```

**Expected**:
- `tables`: Contains references to pipeline tables (REGULATORY_BATCHES, PIPELINE_LATENCY_ANALYSIS, etc.)
- `dimensions` and `measures`: Defined for batch status, latency metrics, transaction counts
- No validation errors

**Pass criteria**: Semantic view describes tables and has dimensions/measures defined.

**Manual demo**: To test Cortex Analyst interactively, open Snowsight and navigate to:
`Data > Databases > DEDEMO > GAMING > Semantic Views > GAMING_PIPELINE_ANALYTICS`

Click "Ask a question" and try: "What is the average end-to-end pipeline latency?"

---

### Step 13: Verify Streamlit App

```bash
snow sql -c <connection> -q "SHOW STREAMLITS IN DATABASE DEDEMO;"
```

**Expected**: `PIPELINE_MONITOR` streamlit app listed with status.

**Pass criteria**: Streamlit app exists.

---

## Validation Summary

After completing all steps, summarize results:

| Step | Component | Status |
|------|-----------|--------|
| 1 | Snowflake Objects | |
| 1b | Specification in Stage | |
| 1c | AI Extraction | |
| 1d | OpenFlow Flows Running | |
| 2 | CDC Source Data | |
| 3 | Dynamic Table | |
| 4 | Stream | |
| 5 | Batch Processing | |
| 6 | Batch Details | |
| 7 | Pipeline Latency | |
| 8 | Error Summary | |
| 9 | SFTP Delivery (Snowflake) | |
| 10 | SFTP File Listing | |
| 11 | Report Download (SFTP) | |
| 11b | Report Contents | |
| 12 | Semantic View Exists | |
| 12b | Semantic View Configuration | |
| 13 | Streamlit App | |

**Overall Status**:
- PASS if all steps pass
- **Step 1d is critical**: Verify all flows are running before checking data metrics
- Steps 1b-1c validate the specification extraction pipeline (beginning)
- Steps 10-11b validate the SFTP delivery pipeline (end)
- Use Snowsight UI to demo Cortex Analyst interactively after validation

**Common pitfall**: Data metrics may look healthy (batches exist, latency reasonable) even if a processor is stopped. Always verify flow status in Step 1d before concluding the pipeline is healthy.

---

## Troubleshooting

| Issue | Likely Cause | Resolution |
|-------|--------------|------------|
| Stopped processors in flow | Processor error or manual stop | Check bulletins, fix config, restart processor |
| Batches accumulating in GENERATED | Downstream flow/processor stopped | Check BoeGamingReport flow, verify PutSFTP running |
| Stage empty | SharePoint connector not running | Start SharePoint connector flow |
| AI tables empty | Extraction not run | Run `specifications/01_extract_specifications.sql` |
| CDC table empty | Transaction generator not running | Start Generate_Transactions flow |
| DT not refreshing | Warehouse suspended | Resume warehouse |
| No batches | Batch_Processing flow stopped | Start Batch_Processing flow |
| Batches stuck at GENERATED | BoeGamingReport flow stopped | Start BoeGamingReport flow |
| Batches stuck at PROCESSING | Orphaned from previous flow version | Reset to GENERATED (see `setup/03_INFRASTRUCTURE_INVENTORY.md`) |
| SFTP connection refused | Key permissions wrong | `chmod 600 credentials/gaming_sftp_key` |
| SFTP host key error | First connection to server | Add `-o StrictHostKeyChecking=no` |
| SFTP directory empty | Network/credential issue | Check SFTP parameters, EAI rules |
| ZIP won't decrypt | Wrong password | Verify password in credentials/README.md |
| ZIP extraction fails with "unsupported compression method 99" | macOS unzip doesn't support AES-256 | Use `uv run --with pyzipper` as shown in Step 11b |
| PutSFTP "Failed to rename temporary file" | S3 eventual consistency race with new directories | Transient - NiFi retries automatically (10 attempts). If persistent, disable "Dot Rename" in processor |
| PutSFTP SSH_FX_NO_SUCH_FILE on temp file | New daily directory not propagated before write | Same as above - retry usually succeeds. Check S3 bucket for orphaned `.` prefixed files |
