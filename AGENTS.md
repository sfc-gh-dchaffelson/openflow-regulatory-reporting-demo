# AGENTS.md

Agent guidance for the BOE Gaming regulatory compliance demo.

## Quick Context

Spanish gaming regulations require operators to submit encrypted, signed XML reports via SFTP. This demo implements a complete pipeline: Postgres (OLTP) → CDC → Snowflake → Dynamic Table → Stream → Batch Processing → SFTP delivery.

**Database**: `DEDEMO`
**Schema**: `DEDEMO.GAMING`
**Runtime Role**: User's existing OpenFlow role (set in `sql/00_set_variables.sql`)

---

## Intent Routing

| If you want to... | Go to |
|-------------------|-------|
| **Deploy from scratch** | `setup/02_DEPLOYMENT.md` |
| **Understand the architecture** | `setup/01_ARCHITECTURE.md` |
| **Run SQL setup scripts** | `sql/README.md` (numbered scripts, run in order) |
| **Configure OpenFlow parameters** | `setup/FLOW_PARAMETERS.md` |
| **Look up object details** | `setup/03_INFRASTRUCTURE_INVENTORY.md` |
| **Generate credentials** | `credentials/README.md` |
| **Monitor the pipeline** | `streamlit/README.md` |
| **Extract specifications from PDF** | `specifications/01_extract_specifications.sql` |
| **Deploy semantic view** | `semantic_view_creation/` (use cortex-code-skills upload script) |
| **Validate the pipeline end-to-end** | `testing/VALIDATION.md` |

---

## Deployment Order

### Phase 0: Specification Extraction (one-time setup)
```
1. Start Fetch_Regulatory_References flow → Downloads PDF from boe.es to SharePoint
2. Start SharePoint CDC connector         → Replicates PDF to @DEDEMO.GAMING.DOCUMENTS stage
3. specifications/01_extract_specifications.sql → Document AI + Cortex LLM extraction
```
**Output**: Creates BOE_DOCUMENT_EXTRACTED, AI_OUTPUTS tables with extracted specifications.

### Phase 1: Infrastructure
```
1. sql/00_set_variables.sql     → Set RUNTIME_ROLE, ADMIN_ROLE, WAREHOUSE_NAME
2. sql/01_database_schema.sql   → Create DEDEMO database and GAMING schema
3. sql/02_grants.sql            → Initial and object grants
4. sql/03_tables.sql            → BATCH_STAGING, REGULATORY_BATCHES tables
5. sql/04_functions.sql         → GENERATE_POKER_XML_JS (use --stage-upload)
6. sql/05_procedures.sql        → PROCESS_STAGED_BATCH (use --stage-upload)
```

### Phase 2: External Services + OpenFlow
```
7. Deploy Postgres instance     → See setup/02_DEPLOYMENT.md
8. Deploy AWS SFTP              → See setup/02_DEPLOYMENT.md
9. Import OpenFlow flows        → flow/*.json
10. Start Generate_Transactions → Populates Postgres with test data
```

### Phase 3: CDC Replication
```
11. Start CDC connector         → Creates DEDEMO.TOURNAMENTS.POKER
12. sql/06_cdc_setup.sql        → CDC grants + enable CHANGE_TRACKING
```
**Note**: Wait for CDC to create `DEDEMO.TOURNAMENTS.POKER` before step 12.

### Phase 4: CDC-Dependent Objects
```
13. sql/07_dynamic_table.sql    → DT_POKER_FLATTENED
14. sql/08_stream.sql           → POKER_TRANSACTIONS_STREAM
15. sql/09_views.sql            → Observability views
```

### Phase 5: Processing Flows
```
16. Start Batch_Processing flow → Reads stream, creates batches
17. Start BoeGamingReport flow  → Signs, encrypts, uploads to SFTP
18. snow streamlit deploy       → Monitoring dashboard
```

### SQL Script Execution

Use the wrapper script for consistent execution:
```bash
cd sql
./run_sql.sh <connection> <script.sql> [--stage-upload]
```

Scripts 04 and 05 require `--stage-upload` due to JavaScript escape sequences.

See `sql/README.md` for full details.

---

## Health Check

```sql
-- Pipeline latency
SELECT * FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS;

-- Recent batches
SELECT BATCH_ID, STATUS, TRANSACTION_COUNT, BATCH_TIMESTAMP
FROM DEDEMO.GAMING.REGULATORY_BATCHES
WHERE BATCH_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
ORDER BY BATCH_TIMESTAMP DESC;

-- Errors
SELECT * FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
WHERE HOUR > DATEADD(day, -1, CURRENT_TIMESTAMP());

-- Stage counts
SELECT 'CDC' as stage, COUNT(*) FROM DEDEMO.TOURNAMENTS.POKER
UNION ALL SELECT 'DT', COUNT(*) FROM DEDEMO.GAMING.DT_POKER_FLATTENED
UNION ALL SELECT 'Stream', COUNT(*) FROM DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM
UNION ALL SELECT 'Batches', COUNT(*) FROM DEDEMO.GAMING.REGULATORY_BATCHES;
```

---

## OpenFlow Process Groups

The `DE Demo - Gaming Pipeline` contains multiple nested process groups. Only start the **demo flows** - the others are administrative utilities.

### Demo Flows (start these)

| Process Group | Purpose |
|---------------|---------|
| `Generate Transactions` | Writes test poker transactions to Postgres |
| `PostgreSQL` | CDC connector replicating to Snowflake |
| `Batch Processing` | Stream consumption, batching, XML generation |
| `BoeGamingReport` | Signing, encryption, SFTP delivery |
| `SharePoint (Simple Ingest, No ACL)` | Fetches regulatory PDF to Snowflake stage |
| `Fetch Regulatory References` | Fetches BOE document from boe.es to SharePoint |

### Administrative Utilities (do NOT start)

| Process Group | Purpose |
|---------------|---------|
| `Create PG Table` | One-time table creation |
| `List PG Tables` | Diagnostic query |
| `Query Transactions` | Ad-hoc data inspection |
| `Postgres Manager` | Contains CDC internals (auto-managed) |

### Stopping Flows

```bash
nipyapi --profile <profile> ci stop_flow --process_group_name "<flow_name>"
```

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| CDC not replicating | Postgres network policy, publication exists |
| Dynamic Table stale | Warehouse running, change tracking enabled on source |
| Stream empty | DT refresh lag (1 min), DT has data |
| Batches stuck at GENERATED | OpenFlow BoeGamingReport flow running, SFTP connectivity |
| Batches stuck at PROCESSING | Orphaned from previous flow version - reset to GENERATED (see `03_INFRASTRUCTURE_INVENTORY.md`) |
| Permission errors | Grants applied to runtime role (`sql/02_grants.sql`) |

### Modification Impact

When modifying pipeline objects, be aware of downstream dependencies:

| If you modify... | Downstream impact |
|------------------|-------------------|
| `DT_POKER_FLATTENED` (CREATE OR REPLACE) | Stream `POKER_TRANSACTIONS_STREAM` becomes invalid - rerun `sql/08_stream.sql` |
| `POKER_TRANSACTIONS_STREAM` | OpenFlow `Batch Processing` flow errors when consuming from invalid/missing stream |

OpenFlow `Batch Processing` consumes from the stream. Manage flow state around changes to avoid errors.

**Remember:** When recreating objects, verify grants and permissions are intact (see `sql/02_grants.sql`).

---

## Key Objects

### Pipeline Objects
| Object | Type | Purpose |
|--------|------|---------|
| `DEDEMO.TOURNAMENTS.POKER` | Table | CDC-replicated source |
| `DEDEMO.GAMING.DT_POKER_FLATTENED` | Dynamic Table | Flattens JSON, 1-min lag |
| `DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM` | Stream | Tracks unprocessed rows |
| `DEDEMO.GAMING.BATCH_STAGING` | Table | Temp batch storage |
| `DEDEMO.GAMING.REGULATORY_BATCHES` | Table | Audit trail |
| `DEDEMO.GAMING.GENERATE_POKER_XML_JS` | Function | XML generation |
| `DEDEMO.GAMING.PROCESS_STAGED_BATCH` | Procedure | Batch processing |
| `DEDEMO.GAMING.FETCH_BATCHES_FOR_PROCESSING` | UDTF | Fetch batches for reporting |

### Specification Extraction Objects
| Object | Type | Purpose |
|--------|------|---------|
| `@DEDEMO.GAMING.DOCUMENTS` | Stage | Regulatory PDFs from SharePoint |
| `DEDEMO.GAMING.DOC_METADATA` | Table | SharePoint file metadata |
| `DEDEMO.GAMING.FILE_HASHES` | Table | File deduplication |
| `DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED` | Table | Document AI parsed content |
| `DEDEMO.GAMING.AI_OUTPUTS` | Table | Cortex LLM extraction results |

### Analytics Objects
| Object | Type | Purpose |
|--------|------|---------|
| `DEDEMO.GAMING.GAMING_PIPELINE_ANALYTICS` | Semantic View | Cortex Analyst analytics |
| `DEDEMO.GAMING.PIPELINE_MONITOR` | Streamlit App | Pipeline monitoring dashboard |

---

## File Structure

```
BoeGamingReport/
├── AGENTS.md                 # This file
├── README.md                 # Project overview
├── setup/
│   ├── 01_ARCHITECTURE.md    # System design and dependencies
│   ├── 02_DEPLOYMENT.md      # Deployment steps
│   ├── 03_INFRASTRUCTURE_INVENTORY.md  # Object reference
│   └── FLOW_PARAMETERS.md    # OpenFlow parameter structure
├── sql/
│   ├── README.md             # Script execution order
│   ├── run_sql.sh            # Wrapper script for execution
│   ├── 00_set_variables.sql  # Session variables (RUNTIME_ROLE, etc.)
│   └── 01-09_*.sql           # Numbered SQL scripts
├── flow/
│   └── *.json                # OpenFlow flow definitions
├── testing/
│   └── VALIDATION.md         # End-to-end pipeline validation procedure
├── specifications/
│   ├── 01_extract_specifications.sql  # Document AI + Cortex LLM script
│   └── 02_FULL_SPECIFICATIONS.md      # Extracted requirements
├── semantic_view_creation/
│   └── gaming_pipeline_analytics_semantic_model.yaml  # Semantic view YAML
├── streamlit/
│   ├── pipeline_monitor.py   # Monitoring dashboard
│   └── README.md             # Deployment instructions
├── credentials/              # Keys and certs (gitignored)
│   └── README.md             # Credential generation instructions
├── custom_processors/
│   └── PrepareRegulatoryFile/  # XAdES-BES + AES-256 processor
└── source_documents/         # Regulatory source PDF and XSD
```
