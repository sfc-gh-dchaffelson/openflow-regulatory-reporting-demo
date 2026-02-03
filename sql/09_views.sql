-- BOE Gaming Demo - Views
-- ============================================================================
-- Observability and analytics views.
--
-- IMPORTANT: Views must be created in order due to dependencies:
--   1. OPENFLOW_LOGS (depends on OPENFLOW.OPENFLOW.EVENTS)
--   2. OPENFLOW_ERROR_SUMMARY (depends on OPENFLOW_LOGS)
--   3. PIPELINE_LATENCY_DETAIL (depends on CDC table + REGULATORY_BATCHES)
--   4. PIPELINE_LATENCY_ANALYSIS (depends on PIPELINE_LATENCY_DETAIL)
--   5. PIPELINE_BACKLOG (depends on REGULATORY_BATCHES)
--
-- Latency views use rolling 24-hour window for consistent metrics.
-- Backlog view tracks batches awaiting upload separately from latency.
--
-- Run after: 03_tables.sql, CDC table exists
-- ============================================================================

USE ROLE IDENTIFIER($RUNTIME_ROLE);
USE SCHEMA DEDEMO.GAMING;

-- =============================================================================
-- View 1: OPENFLOW_LOGS
-- Structured OpenFlow log parser
-- Depends on: OPENFLOW.OPENFLOW.EVENTS (managed by OpenFlow runtime)
-- =============================================================================

CREATE OR REPLACE VIEW DEDEMO.GAMING.OPENFLOW_LOGS
AS
SELECT
    TIMESTAMP as EVENT_TIMESTAMP,
    UPPER(TRY_PARSE_JSON(VALUE):level::STRING) as LOG_LEVEL,
    TRY_PARSE_JSON(VALUE):loggerName::STRING as LOGGER,
    TRY_PARSE_JSON(VALUE):mdc:processGroupName::STRING as PROCESS_GROUP,
    TRY_PARSE_JSON(VALUE):mdc:processGroupNamePath::STRING as PROCESS_GROUP_PATH,
    TRY_PARSE_JSON(VALUE):threadName::STRING as THREAD_NAME,
    TRY_PARSE_JSON(VALUE):formattedMessage::STRING as MESSAGE,
    TRY_PARSE_JSON(VALUE):throwable::STRING as EXCEPTION,
    RESOURCE_ATTRIBUTES:"processor.name"::STRING as PROCESSOR_NAME,
    RESOURCE_ATTRIBUTES:"processor.type"::STRING as PROCESSOR_TYPE,
    VALUE as RAW_VALUE
FROM OPENFLOW.OPENFLOW.EVENTS
WHERE RECORD_TYPE = 'LOG'
  AND TRY_PARSE_JSON(VALUE) IS NOT NULL
  AND RESOURCE_ATTRIBUTES:"k8s.namespace.name"::STRING LIKE 'runtime-%'
  AND TIMESTAMP > DATEADD(day, -30, CURRENT_TIMESTAMP())
ORDER BY TIMESTAMP DESC;

-- =============================================================================
-- View 2: OPENFLOW_ERROR_SUMMARY
-- Error summary aggregation
-- Depends on: OPENFLOW_LOGS (must be created first)
-- =============================================================================

CREATE OR REPLACE VIEW DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY
AS
SELECT
    DATE_TRUNC('hour', EVENT_TIMESTAMP) as HOUR,
    LOG_LEVEL,
    COALESCE(PROCESS_GROUP, 'System') as PROCESS_GROUP,
    COUNT(*) as ERROR_COUNT,
    COUNT(DISTINCT LEFT(MESSAGE, 100)) as UNIQUE_ERRORS
FROM DEDEMO.GAMING.OPENFLOW_LOGS
WHERE LOG_LEVEL IN ('ERROR', 'WARN')
GROUP BY 1, 2, 3
ORDER BY HOUR DESC, ERROR_COUNT DESC;

-- =============================================================================
-- View 3: PIPELINE_LATENCY_DETAIL
-- Individual latency records for last 24 hours of pipeline performance
-- Depends on: DEDEMO.TOURNAMENTS.POKER, DEDEMO.GAMING.REGULATORY_BATCHES
-- Note: Dynamic Table uses configured target_lag (60s) since INFORMATION_SCHEMA
--       table functions are not accessible from Streamlit stored procedure context
-- =============================================================================

CREATE OR REPLACE VIEW DEDEMO.GAMING.PIPELINE_LATENCY_DETAIL
AS
-- CDC Replication latency: source timestamp to Snowflake arrival (last 24 hours)
SELECT
    _SNOWFLAKE_INSERTED_AT as RECORD_TIMESTAMP,
    'CDC Replication' as STAGE,
    TIMESTAMPDIFF(second, CREATED_TIMESTAMP, _SNOWFLAKE_INSERTED_AT) as LATENCY_SEC,
    TRANSACTION_ID as RECORD_ID,
    CREATED_TIMESTAMP as SOURCE_TIMESTAMP
FROM DEDEMO.TOURNAMENTS.POKER
WHERE CREATED_TIMESTAMP > DATEADD(hour, -24, CURRENT_TIMESTAMP())

UNION ALL

-- Dynamic Table: use configured target lag (60 seconds) as estimated latency
-- Note: INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY not accessible from Streamlit
SELECT
    _SNOWFLAKE_INSERTED_AT as RECORD_TIMESTAMP,
    'Dynamic Table Refresh' as STAGE,
    60 as LATENCY_SEC,  -- Configured target lag
    TRANSACTION_ID as RECORD_ID,
    _SNOWFLAKE_INSERTED_AT as SOURCE_TIMESTAMP
FROM DEDEMO.TOURNAMENTS.POKER
WHERE CREATED_TIMESTAMP > DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND MOD(ABS(HASH(TRANSACTION_ID)), 1000) = 0  -- Sample ~0.1% for representative count

UNION ALL

-- Batch to SFTP Upload latency (batches created AND uploaded in last 24 hours)
SELECT
    UPLOAD_TIMESTAMP as RECORD_TIMESTAMP,
    'Batch to SFTP Upload' as STAGE,
    TIMESTAMPDIFF(second, BATCH_TIMESTAMP, UPLOAD_TIMESTAMP) as LATENCY_SEC,
    BATCH_ID as RECORD_ID,
    BATCH_TIMESTAMP as SOURCE_TIMESTAMP
FROM DEDEMO.GAMING.REGULATORY_BATCHES
WHERE STATUS = 'UPLOADED'
  AND BATCH_TIMESTAMP > DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND UPLOAD_TIMESTAMP > DATEADD(hour, -24, CURRENT_TIMESTAMP())

ORDER BY RECORD_TIMESTAMP DESC;

-- =============================================================================
-- View 4: PIPELINE_LATENCY_ANALYSIS
-- Summary view for last 24 hours of pipeline performance
-- Depends on: PIPELINE_LATENCY_DETAIL
-- =============================================================================

CREATE OR REPLACE VIEW DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS
AS
WITH stage_stats AS (
    SELECT
        STAGE,
        ROUND(AVG(LATENCY_SEC), 1) as AVG_SEC,
        ROUND(MAX(LATENCY_SEC), 1) as MAX_SEC,
        COUNT(*) as SAMPLES
    FROM DEDEMO.GAMING.PIPELINE_LATENCY_DETAIL
    GROUP BY STAGE
)
SELECT
    CASE STAGE
        WHEN 'CDC Replication' THEN 1
        WHEN 'Dynamic Table Refresh' THEN 2
        WHEN 'Batch to SFTP Upload' THEN 3
    END as STAGE_ORDER,
    STAGE,
    AVG_SEC,
    MAX_SEC,
    SAMPLES
FROM stage_stats

UNION ALL

SELECT
    4 as STAGE_ORDER,
    'TOTAL END-TO-END' as STAGE,
    (SELECT SUM(AVG_SEC) FROM stage_stats) as AVG_SEC,
    (SELECT SUM(MAX_SEC) FROM stage_stats) as MAX_SEC,
    NULL as SAMPLES

ORDER BY STAGE_ORDER;

-- =============================================================================
-- View 5: PIPELINE_BACKLOG
-- Tracks batches awaiting upload - separate from latency metrics
-- Use this to detect processing delays or flow outages
-- =============================================================================

CREATE OR REPLACE VIEW DEDEMO.GAMING.PIPELINE_BACKLOG
AS
SELECT
    COUNT(*) as BACKLOG_COUNT,
    SUM(TRANSACTION_COUNT) as BACKLOG_TRANSACTIONS,
    MIN(BATCH_TIMESTAMP) as OLDEST_BATCH_TIMESTAMP,
    TIMESTAMPDIFF(minute, MIN(BATCH_TIMESTAMP), CURRENT_TIMESTAMP()) as OLDEST_BATCH_AGE_MIN,
    MAX(BATCH_TIMESTAMP) as NEWEST_BATCH_TIMESTAMP,
    TIMESTAMPDIFF(minute, MAX(BATCH_TIMESTAMP), CURRENT_TIMESTAMP()) as NEWEST_BATCH_AGE_MIN
FROM DEDEMO.GAMING.REGULATORY_BATCHES
WHERE STATUS = 'GENERATED';

-- Verify
SELECT 'Views created' AS status;
SHOW VIEWS IN SCHEMA DEDEMO.GAMING;
