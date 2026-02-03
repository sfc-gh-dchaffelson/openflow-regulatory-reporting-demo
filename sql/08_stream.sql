-- BOE Gaming Demo - Stream
-- ============================================================================
-- Stream on Dynamic Table for tracking unprocessed rows.
--
-- PREREQUISITE: DT_POKER_FLATTENED must exist
-- Run after: 07_dynamic_table.sql
-- ============================================================================

USE ROLE IDENTIFIER($RUNTIME_ROLE);
USE SCHEMA DEDEMO.GAMING;

CREATE OR REPLACE STREAM DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM
    ON DYNAMIC TABLE DEDEMO.GAMING.DT_POKER_FLATTENED
    SHOW_INITIAL_ROWS = FALSE;

-- Verify
SELECT 'Stream created' AS status;
SHOW STREAMS LIKE 'POKER_TRANSACTIONS_STREAM' IN SCHEMA DEDEMO.GAMING;
