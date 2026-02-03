#!/bin/bash
# BOE Gaming Demo - SQL Execution Wrapper
# ============================================================================
# This script handles SQL file execution, including files that require
# stage upload (like JavaScript UDFs with special escape sequences).
#
# Usage:
#   ./run_sql.sh <connection> <sql_file> [--stage-upload]
#
# Examples:
#   ./run_sql.sh <connection> 01_database_schema.sql
#   ./run_sql.sh <connection> 04_functions.sql --stage-upload
#
# The --stage-upload flag uploads the file to a stage and executes via
# EXECUTE IMMEDIATE, which preserves escape sequences in $$ blocks.
# ============================================================================

set -e

CONNECTION="${1:-}"
SQL_FILE="${2:-}"
STAGE_UPLOAD="${3:-}"

if [ -z "$CONNECTION" ] || [ -z "$SQL_FILE" ]; then
    echo "Usage: ./run_sql.sh <connection> <sql_file> [--stage-upload]"
    echo ""
    echo "Examples:"
    echo "  ./run_sql.sh <connection> 01_database_schema.sql"
    echo "  ./run_sql.sh <connection> 04_functions.sql --stage-upload"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FULL_PATH="${SCRIPT_DIR}/${SQL_FILE}"

if [ ! -f "$FULL_PATH" ]; then
    echo "Error: File not found: $FULL_PATH"
    exit 1
fi

echo "Executing: $SQL_FILE"
echo "Connection: $CONNECTION"

if [ "$STAGE_UPLOAD" == "--stage-upload" ]; then
    echo "Method: Stage upload + EXECUTE IMMEDIATE"
    echo ""

    # Upload to table stage (BATCH_STAGING must exist)
    STAGE_PATH="@DEDEMO.GAMING.%BATCH_STAGING/sql"

    snow stage copy "$FULL_PATH" "$STAGE_PATH" -c "$CONNECTION" --overwrite

    if [ $? -ne 0 ]; then
        echo "Error: Failed to upload to stage"
        exit 1
    fi

    # Execute from stage
    snow sql -c "$CONNECTION" -q "EXECUTE IMMEDIATE FROM ${STAGE_PATH}/${SQL_FILE}"

    if [ $? -ne 0 ]; then
        echo "Error: Execution failed"
        exit 1
    fi
else
    echo "Method: Direct execution"
    echo ""

    snow sql -c "$CONNECTION" -f "$FULL_PATH"

    if [ $? -ne 0 ]; then
        echo "Error: Execution failed"
        exit 1
    fi
fi

echo ""
echo "Success: $SQL_FILE executed"
