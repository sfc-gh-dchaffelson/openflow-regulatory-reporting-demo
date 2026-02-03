# BOE Gaming Demo Architecture

This document describes the deployed architecture of the BOE Gaming regulatory compliance demo.

---

## Prerequisites

This demo requires the following to be in place before deployment:

| Prerequisite | Purpose |
|--------------|---------|
| **Snowflake Account** | Database, compute, and AI services |
| **OpenFlow Runtime** | SPCS or BYOC deployment for data movement |
| **External Access Integration** | SPCS network egress (PyPI, Postgres, SFTP, SharePoint) |
| **AWS Account** | Transfer Family SFTP server for file delivery |

See `02_DEPLOYMENT.md` for detailed prerequisite verification and deployment steps.

---

## Overview

The demo implements a complete regulatory reporting pipeline for Spanish gaming compliance (BOE-A-2024-12639):

### Phase 0: Specification Extraction (one-time setup)
1. **Fetch**: OpenFlow retrieves BOE-A-2024-12639.pdf from boe.es to SharePoint
2. **Ingest**: SharePoint CDC connector replicates PDF to Snowflake stage
3. **Extract**: Document AI parses PDF, Cortex LLM extracts structured requirements
4. **Output**: Specifications inform the demo design (stored in AI_OUTPUTS table)

### Runtime Pipeline
1. **Source**: Snowflake-managed PostgreSQL generates gaming transactions
2. **Replication**: OpenFlow CDC replicates to Snowflake in near-real-time
3. **Processing**: Dynamic Table flattens JSON, Stream tracks unprocessed rows
4. **Batching**: OpenFlow batches records (500 / 15 min), generates XML
5. **Delivery**: Signs (XAdES-BES), encrypts (AES-256), delivers to SFTP

---

## Data Flow

### Specification Extraction Flow (Phase 0)

```
boe.es (regulatory website)
    │
    │ HTTP fetch via OpenFlow (Fetch Regulatory References)
    ▼
SharePoint (document storage)
    │
    │ CDC via OpenFlow (SharePoint Simple Ingest)
    ▼
@DEDEMO.GAMING.DOCUMENTS  (Snowflake stage)
    │
    │ Document AI parsing
    ▼
DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED  (parsed content)
    │
    │ Cortex LLM extraction (claude-sonnet-4-5)
    ▼
DEDEMO.GAMING.AI_OUTPUTS  (structured specifications)
    │
    │ Manual review → specifications/02_FULL_SPECIFICATIONS.md
    ▼
Demo design informed by extracted requirements
```

### Runtime Pipeline Flow

```
Snowflake Postgres (OLTP)
    │
    │ CDC replication via OpenFlow
    ▼
DEDEMO.TOURNAMENTS.POKER  (CDC table, JSONB)
    │
    │ 1-minute lag
    ▼
DEDEMO.GAMING.DT_POKER_FLATTENED  (Dynamic Table, columnar)
    │
    │ Change tracking
    ▼
DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM  (Stream)
    │
    │ OpenFlow consumption
    ▼
DEDEMO.GAMING.BATCH_STAGING  (Staging table)
    │
    │ 500 records / 15 min batching
    ▼
DEDEMO.GAMING.REGULATORY_BATCHES  (Audit table: GENERATED → UPLOADED)
    │
    │ XML + Sign + Encrypt
    ▼
AWS Transfer Family SFTP → S3
```

---

## Design Decisions

### CDC Object Identifier Resolution: CASE_INSENSITIVE

The CDC connector is configured with `Object Identifier Resolution = CASE_INSENSITIVE` to uppercase all schema and table names in Snowflake. This simplifies SQL by avoiding quoted identifiers.

**Warning:** This setting cannot be changed after replication starts without a full reset.

### Source Schema Design: tournaments.poker

Instead of using PostgreSQL's default `public` schema (which would map to Snowflake's reserved `PUBLIC` schema), we create a custom schema in Postgres:

| Layer | Schema.Table | Notes |
|-------|--------------|-------|
| Postgres (source) | `tournaments.poker` | Custom schema avoids PUBLIC conflict |
| Snowflake (CDC target) | `DEDEMO.TOURNAMENTS.POKER` | Clean uppercase, no quoting |
| Snowflake (processing) | `DEDEMO.GAMING.*` | Separate schema for transforms |

**Postgres setup:**
```sql
CREATE SCHEMA tournaments;
CREATE TABLE tournaments.poker (
    transaction_id VARCHAR(50) PRIMARY KEY,
    transaction_data JSONB NOT NULL,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**CDC Ingestion Parameter:** `Included Table Names = tournaments.poker`

---

## Deployment Dependencies

Critical ordering constraints for deployment:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 0: SPECIFICATION EXTRACTION (one-time, informs demo design)            │
├─────────────────────────────────────────────────────────────────────────────┤
│ boe.es ──► Fetch_Regulatory_References ──► SharePoint                       │
│                      │                                                       │
│                      ▼                                                       │
│ SharePoint CDC ──► @DOCUMENTS stage ──► Document AI ──► AI_OUTPUTS          │
│                                                                              │
│ Run: specifications/01_extract_specifications.sql                            │
│ Output: specifications/02_FULL_SPECIFICATIONS.md (manual review)             │
└──────────────────────────────────────────────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼────────────────────────────────┐
│ PHASE 1: INFRASTRUCTURE                                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│ Database/Schemas ──► Postgres Instance ──► Postgres Table (tournaments.poker)│
│                                                                              │
│ AWS SFTP Server ◄── Network Rules (need hostnames from Postgres + SFTP)     │
└──────────────────────────────────────────────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼────────────────────────────────┐
│ PHASE 2: DATA GENERATION (must have data before CDC can replicate)           │
├─────────────────────────────────────────────────────────────────────────────┤
│ Generate_Transactions flow ──► Writes TO ──► Postgres tournaments.poker     │
└──────────────────────────────────────────────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼────────────────────────────────┐
│ PHASE 3: REPLICATION                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│ CDC Connector ──► Creates schema + table ──► DEDEMO.TOURNAMENTS.POKER
└──────────────────────────────────────────────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼────────────────────────────────┐
│ PHASE 4: SNOWFLAKE OBJECTS                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ CDC table exists                                                             │
│      │                                                                       │
│      ▼                                                                       │
│ sql/06_cdc_setup.sql ──► CDC grants + CHANGE_TRACKING                       │
│      │                                                                       │
│      ▼                                                                       │
│ sql/07_dynamic_table.sql ──► DT_POKER_FLATTENED                             │
│      │                                                                       │
│      ▼                                                                       │
│ sql/08_stream.sql ──► POKER_TRANSACTIONS_STREAM                             │
│      │                                                                       │
│      ▼                                                                       │
│ sql/09_views.sql ──► OPENFLOW_LOGS, ERROR_SUMMARY, LATENCY_ANALYSIS         │
└──────────────────────────────────────────────────────────────────────────────┘
                                              │
┌─────────────────────────────────────────────▼────────────────────────────────┐
│ PHASE 5: PROCESSING FLOWS                                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Batch_Processing flow ──► Reads STREAM ──► Calls PROCEDURE ──► Writes BATCHES
│      │                                                                       │
│      ▼                                                                       │
│ BoeGamingReport flow ──► Reads BATCHES ──► Signs/Encrypts ──► SFTP          │
└──────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ PHASE 6: ANALYTICS (after pipeline is operational)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│ Semantic View ──► GAMING_PIPELINE_ANALYTICS (requires views + tables)       │
│ Streamlit App ──► PIPELINE_MONITOR (requires views + tables)                │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Why Change Tracking Before Dynamic Table?

The Dynamic Table `DT_POKER_FLATTENED` reads from `DEDEMO.TOURNAMENTS.POKER`. Dynamic Tables perform **incremental refreshes** by reading the change log of their source table. This requires `CHANGE_TRACKING = TRUE` on the source table **before** the Dynamic Table is created. Without it:
- DT creation may fail
- DT would only do full refreshes (expensive, defeats purpose)

---

## Object Dependency Matrix

This matrix shows which objects depend on which. Use this to understand what breaks when modifying objects.

| Object | Depends On | Depended On By |
|--------|------------|----------------|
| `DEDEMO` database | - | All objects |
| `DEDEMO.GAMING` schema | Database | All GAMING objects |
| `DEDEMO.TOURNAMENTS` schema | CDC connector creates | CDC table |
| `DEDEMO.TOURNAMENTS.POKER` | CDC connector, Postgres data | DT, LATENCY view |
| `BATCH_STAGING` | Schema | Procedure, stage upload |
| `REGULATORY_BATCHES` | Schema | Procedure, LATENCY view |
| `GENERATE_POKER_XML_JS` | Schema | Procedure |
| `PROCESS_STAGED_BATCH` | Function, Tables | Batch_Processing flow |
| `DT_POKER_FLATTENED` | CDC table + change tracking | Stream |
| `POKER_TRANSACTIONS_STREAM` | Dynamic table | Batch_Processing flow |
| `OPENFLOW_LOGS` | OPENFLOW.OPENFLOW.EVENTS | ERROR_SUMMARY view |
| `OPENFLOW_ERROR_SUMMARY` | OPENFLOW_LOGS view | Streamlit, Semantic view |
| `PIPELINE_LATENCY_ANALYSIS` | CDC table, REGULATORY_BATCHES | Streamlit, Semantic view |
| `GAMING_PIPELINE_ANALYTICS` | Views, Tables | Cortex Analyst |
| `PIPELINE_MONITOR` | Views, Tables | Users |

### Critical Modification Rules

| If you modify... | You must also... |
|------------------|------------------|
| `DT_POKER_FLATTENED` (CREATE OR REPLACE) | Recreate `POKER_TRANSACTIONS_STREAM` |
| `POKER_TRANSACTIONS_STREAM` | Stop `Batch_Processing` flow first |
| `OPENFLOW_LOGS` view | Recreate `OPENFLOW_ERROR_SUMMARY` view |
| Any table columns | Check dependent views/functions |

### OpenFlow Flow Start Order

All flows can be **imported** together, but must be **started** in sequence:

| Order | Flow | Reason |
|-------|------|--------|
| 0a | Fetch_Regulatory_References | Fetches BOE PDF to SharePoint (Phase 0) |
| 0b | SharePoint CDC | Replicates PDF to Snowflake stage (Phase 0) |
| 1 | Generate_Transactions | Populates Postgres so CDC has data |
| 2 | PostgreSQL CDC Connector | Replicates to Snowflake |
| 3 | Batch_Processing | Reads stream (needs DT refreshing) |
| 4 | BoeGamingReport | Reads batches (needs processing running) |

---

## Key Components

### Snowflake Objects - Runtime Pipeline

| Object | Type | Purpose |
|--------|------|---------|
| `DEDEMO.TOURNAMENTS.POKER` | Table | CDC-replicated source data |
| `DEDEMO.GAMING.DT_POKER_FLATTENED` | Dynamic Table | Flattens JSON to columns |
| `DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM` | Stream | Tracks unprocessed rows |
| `DEDEMO.GAMING.BATCH_STAGING` | Table | Temporary batch storage |
| `DEDEMO.GAMING.REGULATORY_BATCHES` | Table | Audit trail with lifecycle |
| `DEDEMO.GAMING.GENERATE_POKER_XML_JS` | Function | XML generation (JavaScript) |
| `DEDEMO.GAMING.PROCESS_STAGED_BATCH` | Procedure | Batch processing logic |
| `DEDEMO.GAMING.FETCH_BATCHES_FOR_PROCESSING` | UDTF | Fetch batches for reporting |

### Snowflake Objects - Specification Extraction

| Object | Type | Purpose |
|--------|------|---------|
| `@DEDEMO.GAMING.DOCUMENTS` | Stage | Regulatory PDFs from SharePoint |
| `DEDEMO.GAMING.DOC_METADATA` | Table | SharePoint file metadata |
| `DEDEMO.GAMING.FILE_HASHES` | Table | File deduplication |
| `DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED` | Table | Document AI parsed content |
| `DEDEMO.GAMING.AI_OUTPUTS` | Table | Cortex LLM extraction results |

### Analytics and Observability

| Object | Type | Purpose |
|--------|------|---------|
| `DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS` | View | End-to-end latency by stage |
| `DEDEMO.GAMING.PIPELINE_LATENCY_DETAIL` | View | Per-record latency detail |
| `DEDEMO.GAMING.OPENFLOW_LOGS` | View | Parsed OpenFlow event logs |
| `DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY` | View | Error aggregation by hour |
| `DEDEMO.GAMING.GAMING_PIPELINE_ANALYTICS` | Semantic View | Cortex Analyst analytics |
| `DEDEMO.GAMING.PIPELINE_MONITOR` | Streamlit App | Monitoring dashboard |

### OpenFlow Process Groups

| Name | Purpose |
|------|---------|
| Generate Transactions | Transaction generation to Postgres |
| PostgreSQL CDC | CDC replication to Snowflake |
| Batch Processing | Stream consumption, batching, XML |
| Boe Gaming Report | Signing, encryption, SFTP delivery |
| Fetch Regulatory References | BOE document fetch to SharePoint |
| SharePoint (Simple Ingest, No ACL) | SharePoint to Snowflake stage CDC |

### External Resources

See `../credentials/DEPLOYMENT_VALUES.md` for hostnames and connection details.

| Resource | Type |
|----------|------|
| Postgres | Snowflake-managed PostgreSQL instance |
| SFTP | AWS Transfer Family |
| S3 | Backing storage for SFTP |

---

## Roles and Permissions

This demo uses your existing OpenFlow runtime role. Apply the grants from `sql/02_grants.sql` to your runtime role.

**Required Permissions:**
- `USAGE` on DATABASE, SCHEMA, WAREHOUSE
- `CREATE SCHEMA` on DATABASE (for CDC)
- `SELECT, INSERT, UPDATE, DELETE` on processing tables
- `SELECT` on dynamic table, stream, views
- `USAGE` on function and procedure
- `CREATE SEMANTIC VIEW` on SCHEMA (for semantic view deployment)
- `READ` on stage (for specification extraction)

---

## Documentation Structure

| Document | Purpose |
|----------|---------|
| `01_ARCHITECTURE.md` | This document - system design and dependencies |
| `02_DEPLOYMENT.md` | How to deploy/redeploy |
| `03_INFRASTRUCTURE_INVENTORY.md` | Complete object inventory |
| `../sql/README.md` | SQL script execution order |

---

## See Also

- [Infrastructure Inventory](03_INFRASTRUCTURE_INVENTORY.md) - Object reference
- [SQL Scripts](../sql/README.md) - Deployment scripts
- [Specifications](../specifications/) - Regulatory requirement extraction
