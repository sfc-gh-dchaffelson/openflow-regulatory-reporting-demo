-- BOE Gaming Demo - Stored Procedure
-- ============================================================================
-- IMPORTANT: This file should be deployed via stage upload for consistency.
--
-- Deployment method:
--   ./run_sql.sh <connection> 05_procedures.sql --stage-upload
--
-- Run after: 04_functions.sql (procedure calls the function)
-- ============================================================================

USE ROLE IDENTIFIER($RUNTIME_ROLE);
USE SCHEMA DEDEMO.GAMING;

CREATE OR REPLACE PROCEDURE DEDEMO.GAMING.PROCESS_STAGED_BATCH(P_BATCH_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    txn_count NUMBER;
    xml_result VARCHAR;
    filename VARCHAR;
    sftp_path VARCHAR;
    batch_date VARCHAR;
BEGIN
    SELECT COUNT(*) INTO txn_count
    FROM DEDEMO.GAMING.BATCH_STAGING
    WHERE BATCH_ID = :p_batch_id;

    IF (txn_count = 0) THEN
        RETURN 'No transactions found for batch ' || :p_batch_id;
    END IF;

    batch_date := TO_CHAR(CURRENT_TIMESTAMP(), 'YYYY/MM/DD');
    filename := 'OP01_WH001_' || REPLACE(:p_batch_id, '-', '') || '.zip';
    sftp_path := 'uploads/' || :batch_date;

    SELECT DEDEMO.GAMING.GENERATE_POKER_XML_JS(
        ARRAY_AGG(OBJECT_CONSTRUCT(
            'PLAYER_ID', PLAYER_ID,
            'BET_AMOUNT', BET_AMOUNT,
            'REFUND_AMOUNT', REFUND_AMOUNT,
            'WIN_AMOUNT', WIN_AMOUNT,
            'PLAYER_IP', PLAYER_IP,
            'DEVICE_TYPE', DEVICE_TYPE,
            'DEVICE_ID', DEVICE_ID
        )),
        'OP01',
        'WH001',
        :p_batch_id
    ) INTO xml_result
    FROM DEDEMO.GAMING.BATCH_STAGING
    WHERE BATCH_ID = :p_batch_id;

    INSERT INTO DEDEMO.GAMING.REGULATORY_BATCHES (
        BATCH_ID, OPERATOR_ID, WAREHOUSE_ID, BATCH_TIMESTAMP,
        TRANSACTION_COUNT, GENERATED_XML, STATUS,
        GENERATED_FILENAME, SFTP_DIRECTORY_PATH
    ) VALUES (
        :p_batch_id, 'OP01', 'WH001', CURRENT_TIMESTAMP(),
        :txn_count, :xml_result, 'GENERATED',
        :filename, :sftp_path
    );

    DELETE FROM DEDEMO.GAMING.BATCH_STAGING WHERE BATCH_ID = :p_batch_id;

    RETURN 'Processed batch ' || :p_batch_id || ' with ' || :txn_count || ' transactions';
END;
$$;

-- Verify
SELECT 'Procedure created' AS status;
SHOW PROCEDURES LIKE 'PROCESS_STAGED_BATCH' IN SCHEMA DEDEMO.GAMING;
