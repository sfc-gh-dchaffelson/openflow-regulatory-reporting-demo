# Infrastructure Inventory

Reference document listing all objects and resources created by this demo. For deployment instructions, see `02_DEPLOYMENT.md`. For SQL DDL, see `../sql/`.

**Deployment-specific values** (hostnames, credentials, account details) are in `../credentials/DEPLOYMENT_VALUES.md` (gitignored).

---

## Snowflake Objects

### Database and Schemas

| Object | Purpose |
|--------|---------|
| `DEDEMO` | Demo database |
| `DEDEMO.GAMING` | Processing objects |
| `DEDEMO.TOURNAMENTS` | CDC-replicated tables (created by connector) |

### Tables

| Table | Schema | Purpose |
|-------|--------|---------|
| `POKER` | DEDEMO.TOURNAMENTS | CDC-replicated source (from Postgres) |
| `BATCH_STAGING` | DEDEMO.GAMING | Temporary batch storage |
| `REGULATORY_BATCHES` | DEDEMO.GAMING | Audit trail (GENERATED -> UPLOADED) |
| `DOC_METADATA` | DEDEMO.GAMING | SharePoint file metadata (CDC) |
| `FILE_HASHES` | DEDEMO.GAMING | File deduplication tracking (CDC) |
| `BOE_DOCUMENT_EXTRACTED` | DEDEMO.GAMING | Document AI parsed content |
| `AI_OUTPUTS` | DEDEMO.GAMING | Cortex LLM extraction results |

### Stages

| Stage | Schema | Purpose |
|-------|--------|---------|
| `DOCUMENTS` | DEDEMO.GAMING | Regulatory PDFs from SharePoint connector |
| `CORTEX_MODELS` | DEDEMO.GAMING | Semantic model YAML files for Cortex Analyst |

### Dynamic Tables

| Dynamic Table | Source | Lag |
|---------------|--------|-----|
| `DT_POKER_FLATTENED` | DEDEMO.TOURNAMENTS.POKER | 1 minute |

### Streams

| Stream | Source | Purpose |
|--------|--------|---------|
| `POKER_TRANSACTIONS_STREAM` | DT_POKER_FLATTENED | Tracks unprocessed rows |

### Views

| View | Purpose |
|------|---------|
| `PIPELINE_LATENCY_ANALYSIS` | End-to-end latency by stage (summary) |
| `PIPELINE_LATENCY_DETAIL` | Per-record latency detail (used by summary) |
| `OPENFLOW_LOGS` | Parsed OpenFlow event logs |
| `OPENFLOW_ERROR_SUMMARY` | Error aggregation by hour |

### Functions and Procedures

| Object | Type | Purpose |
|--------|------|---------|
| `GENERATE_POKER_XML_JS(VARIANT, VARCHAR, VARCHAR, VARCHAR)` | UDF | XML generation (JavaScript) |
| `PROCESS_STAGED_BATCH(VARCHAR)` | Procedure | Transform staging to audit table |
| `FETCH_BATCHES_FOR_PROCESSING(NUMBER)` | UDTF | Fetch batches for reporting flow |

### Semantic Views

| Semantic View | Tables | VQRs |
|---------------|--------|------|
| `GAMING_PIPELINE_ANALYTICS` | REGULATORY_BATCHES, PIPELINE_LATENCY_ANALYSIS, OPENFLOW_ERROR_SUMMARY | 5 |

### Streamlit Apps

| App | Schema | Purpose |
|-----|--------|---------|
| `PIPELINE_MONITOR` | DEDEMO.GAMING | Pipeline monitoring dashboard |

---

## External Resources

These resources are provisioned outside Snowflake. See `../credentials/DEPLOYMENT_VALUES.md` for actual hostnames and credentials.

| Resource | Type | Purpose |
|----------|------|---------|
| Postgres Instance | Snowflake Managed | Source OLTP database |
| SFTP Server | AWS Transfer Family | Regulatory file delivery |
| SharePoint Site | Microsoft 365 | Regulatory document storage |

---

## OpenFlow Components

### Process Groups

| Name | Purpose |
|------|---------|
| Generate Transactions | Writes test transactions to Postgres |
| PostgreSQL CDC | CDC connector replicating to Snowflake |
| Batch Processing | Stream consumption, batching, XML generation |
| BoeGamingReport | Signing, encryption, SFTP delivery |
| SharePoint (Simple Ingest, No ACL) | Replicates PDFs from SharePoint to Snowflake stage |
| Fetch Regulatory References | Fetches BOE document from boe.es to SharePoint |

### Parameter Contexts

| Context | Purpose |
|---------|---------|
| Generate Transactions | Transaction generator config |
| Batch Processing | Snowflake connection for batching |
| Boe Gaming Report | Security credentials, SFTP config |
| Fetch Regulatory References | BOE/SharePoint integration |
| PostgreSQL Source Parameters | CDC connector configuration |
| PostgreSQL Destination Parameters | Snowflake destination |
| PostgreSQL Ingestion Parameters | Table filters |
| SharePoint Source/Destination/Ingestion | SharePoint connector config |

See `FLOW_PARAMETERS.md` for parameter structure.

---

## Verification Queries

### Pipeline Health
```sql
SELECT * FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS;
```

### Recent Batches
```sql
SELECT BATCH_ID, STATUS, TRANSACTION_COUNT, BATCH_TIMESTAMP, UPLOAD_TIMESTAMP
FROM DEDEMO.GAMING.REGULATORY_BATCHES
WHERE BATCH_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
ORDER BY BATCH_TIMESTAMP DESC;
```

### Error Summary
```sql
SELECT * FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
WHERE HOUR > DATEADD(day, -1, CURRENT_TIMESTAMP());
```

### Pipeline Stage Counts
```sql
SELECT 'CDC Source' as stage, COUNT(*) as count FROM DEDEMO.TOURNAMENTS.POKER
UNION ALL SELECT 'Dynamic Table', COUNT(*) FROM DEDEMO.GAMING.DT_POKER_FLATTENED
UNION ALL SELECT 'Stream Pending', COUNT(*) FROM DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM
UNION ALL SELECT 'Audit Table', COUNT(*) FROM DEDEMO.GAMING.REGULATORY_BATCHES
UNION ALL SELECT 'Batch Staging', COUNT(*) FROM DEDEMO.GAMING.BATCH_STAGING
ORDER BY 1;
```

### Batch Status Distribution
```sql
SELECT STATUS, COUNT(*) as count, MAX(BATCH_TIMESTAMP) as latest
FROM DEDEMO.GAMING.REGULATORY_BATCHES
GROUP BY STATUS
ORDER BY STATUS;
```

---

## Troubleshooting

### Stuck PROCESSING Batches

If batches are stuck in PROCESSING status (visible in batch status distribution query), they may be orphaned from a previous flow version. The current BoeGamingReport flow only queries `WHERE status = 'GENERATED'`.

**Reset stuck batches to GENERATED:**
```sql
-- First, identify stuck batches (older than 5 minutes in PROCESSING)
SELECT BATCH_ID, STATUS, BATCH_TIMESTAMP, GENERATED_FILENAME
FROM DEDEMO.GAMING.REGULATORY_BATCHES
WHERE STATUS = 'PROCESSING'
  AND BATCH_TIMESTAMP < DATEADD(minute, -5, CURRENT_TIMESTAMP())
ORDER BY BATCH_TIMESTAMP;

-- Reset them to GENERATED for reprocessing
UPDATE DEDEMO.GAMING.REGULATORY_BATCHES
SET STATUS = 'GENERATED'
WHERE STATUS = 'PROCESSING'
  AND BATCH_TIMESTAMP < DATEADD(minute, -5, CURRENT_TIMESTAMP());
```

**Note**: This is safe because PROCESSING batches have not yet been uploaded to SFTP (UPLOAD_TIMESTAMP is NULL).

---

## Related Files

| File | Purpose |
|------|---------|
| `../sql/` | SQL deployment scripts (numbered, run in order) |
| `FLOW_PARAMETERS.md` | OpenFlow parameter structure |
| `../credentials/README.md` | Credential generation instructions |
| `../credentials/DEPLOYMENT_VALUES.md` | Deployment-specific values (gitignored) |
| `../testing/VALIDATION.md` | End-to-end validation procedures |
| `../source_documents/` | XSD schema and regulatory PDF |
| `../specifications/` | Document AI extraction scripts |
| `../semantic_view_creation/` | Semantic view YAML definition |
