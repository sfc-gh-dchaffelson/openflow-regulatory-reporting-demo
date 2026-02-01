-- BOE Gaming Demo - CDC Setup
-- ============================================================================
-- Grants for CDC-created schema and enables change tracking.
-- 
-- PREREQUISITE: The CDC connector must have already created DEDEMO.TOURNAMENTS.POKER
-- Run after: CDC connector has replicated data to Snowflake
-- Run before: 07_dynamic_table.sql (DT requires change tracking)
-- ============================================================================

USE ROLE IDENTIFIER($ADMIN_ROLE);

-- Grant access to CDC-created schema
GRANT ALL PRIVILEGES ON SCHEMA DEDEMO.TOURNAMENTS TO ROLE IDENTIFIER($RUNTIME_ROLE);
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA DEDEMO.TOURNAMENTS TO ROLE IDENTIFIER($RUNTIME_ROLE);

-- Enable change tracking on CDC table (required for Dynamic Table)
-- The Dynamic Table performs incremental refreshes by reading the change log.
-- Without change tracking, the DT would only do expensive full refreshes.
ALTER TABLE DEDEMO.TOURNAMENTS.POKER SET CHANGE_TRACKING = TRUE;

-- Verify
SELECT 'CDC setup complete' AS status;
SELECT 
    TABLE_NAME,
    CHANGE_TRACKING
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'TOURNAMENTS' AND TABLE_CATALOG = 'DEDEMO';
