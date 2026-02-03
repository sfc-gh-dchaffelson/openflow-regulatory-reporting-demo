# Pipeline Monitor Streamlit App

Multi-tab narrative dashboard for demonstrating the BOE Gaming regulatory pipeline.

## Demo Narrative

The app is structured as a progressive walkthrough of the data pipeline, designed for live demonstrations:

| Tab | Purpose | Key Points |
|-----|---------|------------|
| **Overview** | Pipeline health at a glance | Stage counts, key metrics, data freshness |
| **CDC Replication** | External data landing in Snowflake | Replication metrics, raw JSONB, CDC metadata |
| **Dynamic Table** | Automatic transformation | JSON to columns, 1-minute lag, before/after comparison |
| **Stream** | Processing throughput | Batch activity, transaction volume over time |
| **Batches** | Regulatory submission | Batch lifecycle, XML preview, processing stats |
| **Observability** | Operational visibility | Health indicators, latency summary, volume timeline |
| **Logs** | Pipeline logs | Error summary, warnings, filterable log viewer |
| **Ask Cortex** | Natural language analytics | Cortex Agent with semantic model for ad-hoc queries |

## Demo Flow

1. Start at **Overview** - "Here's the entire pipeline at a glance"
2. **CDC Replication** - "Data flows from external Postgres via OpenFlow CDC"
3. **Dynamic Table** - "Snowflake automatically flattens JSON to columns"
4. **Stream** - "Processing throughput and batch activity"
5. **Batches** - "Here's the generated XML for regulatory submission"
6. **Observability** - "Health summary and latency metrics"
7. **Logs** - "Detailed error and warning investigation"
8. **Ask Cortex** - "Analysts can query with natural language"

Tip: The Ask Cortex tab works well with speech-to-text for impressive demos.

## Features

- 8-tab progressive narrative structure
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
| `DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS` | SELECT |
| `DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY` | SELECT |
| `DEDEMO.GAMING.OPENFLOW_LOGS` | SELECT |
| `@DEDEMO.GAMING.CORTEX_MODELS` | READ (semantic model stage) |

## Cortex Agent Integration

The Ask Cortex tab uses the Cortex Agent API with `claude-opus-4-5` and a semantic model:

**Semantic Model Location:**
```
@DEDEMO.GAMING.CORTEX_MODELS/semantic_models/gaming_pipeline_analytics_semantic_model.yaml
```

**How it works:**
1. User asks a natural language question
2. Cortex Agent uses `cortex_analyst_text_to_sql` tool with the semantic model
3. Agent generates and executes SQL against pipeline tables
4. Results are displayed with the generated SQL available for review

Sample questions are provided as quick-start buttons.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "N/A" metrics | Pipeline objects may not exist yet - check deployment |
| Stream errors | Stream may be empty (normal after processing) |
| Cortex errors | Verify semantic model exists at stage path and role has READ access |
| Missing data | Ensure CDC connector and flows are running |
| Log viewer empty | Check OPENFLOW_LOGS view exists and has data |
