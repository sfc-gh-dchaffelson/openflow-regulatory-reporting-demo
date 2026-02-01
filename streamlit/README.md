# Pipeline Monitor Streamlit App

Multi-tab narrative dashboard for demonstrating the BOE Gaming regulatory pipeline.

## Demo Narrative

The app is structured as a progressive walkthrough of the data pipeline, designed for live demonstrations:

| Tab | Purpose | Key Points |
|-----|---------|------------|
| **Overview** | Pipeline health at a glance | Stage counts, key metrics, data freshness |
| **CDC Replication** | External data landing in Snowflake | Replication metrics, raw JSONB, CDC metadata |
| **Dynamic Table** | Automatic transformation | JSON to columns, 1-minute lag, before/after comparison |
| **Stream** | Pending transactions | Records awaiting batch processing |
| **Batches** | Regulatory submission | Batch lifecycle, XML preview, processing stats |
| **Observability** | Operational visibility | Latency by stage, error summary, timeline |
| **Ask Cortex** | Natural language analytics | Chat interface for ad-hoc queries |

## Demo Flow

1. Start at **Overview** - "Here's the entire pipeline at a glance"
2. **CDC Replication** - "Data flows from external Postgres via OpenFlow CDC"
3. **Dynamic Table** - "Snowflake automatically flattens JSON to columns"
4. **Stream** - "These transactions are waiting to be batched"
5. **Batches** - "Here's the generated XML for regulatory submission"
6. **Observability** - "Full visibility into latency and errors"
7. **Ask Cortex** - "Analysts can query with natural language"

Tip: The Ask Cortex tab works well with speech-to-text for impressive demos.

## Features

- 7-tab progressive narrative structure
- Real-time metrics and data samples
- JSON structure visualization
- XML preview with expandable view
- Cortex Analyst chat interface with sample questions
- Responsive layout for presentations

## Deployment

### Option 1: Snow CLI (Recommended)

```bash
cd streamlit
snow streamlit deploy --database DEDEMO --schema GAMING
```

### Option 2: Snowsight UI

1. Go to Snowsight > Streamlit
2. Click "Create Streamlit App"
3. Name: `PIPELINE_MONITOR`
4. Warehouse: `COMPUTE_WH`
5. Database/Schema: `DEDEMO.GAMING`
6. Paste contents of `pipeline_monitor.py`
7. Click "Run"

### Option 3: SQL

```sql
-- Create stage for Streamlit files
CREATE OR REPLACE STAGE DEDEMO.GAMING.STREAMLIT_STAGE;

-- Upload via Snowsight or PUT
-- PUT file://path/to/pipeline_monitor.py @DEDEMO.GAMING.STREAMLIT_STAGE;

CREATE OR REPLACE STREAMLIT DEDEMO.GAMING.PIPELINE_MONITOR
    ROOT_LOCATION = '@DEDEMO.GAMING.STREAMLIT_STAGE'
    MAIN_FILE = 'pipeline_monitor.py'
    QUERY_WAREHOUSE = 'COMPUTE_WH'
    COMMENT = 'BOE Gaming pipeline monitoring dashboard';

GRANT USAGE ON STREAMLIT DEDEMO.GAMING.PIPELINE_MONITOR TO ROLE <your_role>;
```

## Required Permissions

The app queries these objects:

| Object | Permission |
|--------|------------|
| `DEDEMO.TOURNAMENTS.POKER` | SELECT |
| `DEDEMO.GAMING.DT_POKER_FLATTENED` | SELECT |
| `DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM` | SELECT |
| `DEDEMO.GAMING.REGULATORY_BATCHES` | SELECT |
| `DEDEMO.GAMING.BATCH_STAGING` | SELECT |
| `DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS` | SELECT |
| `DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY` | SELECT |
| `SNOWFLAKE.CORTEX.COMPLETE` | USAGE (for Ask Cortex tab) |

## Cortex Analyst Integration

The Ask Cortex tab uses `SNOWFLAKE.CORTEX.COMPLETE` with `claude-3-5-sonnet` to:

1. Generate SQL from natural language questions
2. Execute the query against pipeline tables
3. Summarize results in plain language

Sample questions are provided as quick-start buttons.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "N/A" metrics | Pipeline objects may not exist yet - check deployment |
| Stream errors | Stream may be empty (normal after processing) |
| Cortex errors | Verify CORTEX.COMPLETE access for your role |
| Missing data | Ensure CDC connector and flows are running |
