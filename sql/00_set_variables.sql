-- BOE Gaming Demo - Session Variables
-- ============================================================================
-- IMPORTANT: Run this file FIRST before any other SQL files in this directory.
-- Other scripts depend on these session variables and will fail without them.
-- ============================================================================

-- Step 1: Set your OpenFlow runtime role name
-- Find it with: SHOW ROLES LIKE '%OPENFLOW%';
-- For deployed value, see: credentials/DEPLOYMENT_VALUES.md
SET RUNTIME_ROLE = 'YOUR_OPENFLOW_RUNTIME_ROLE';

-- Step 2: Set the admin role (typically ACCOUNTADMIN)
SET ADMIN_ROLE = 'ACCOUNTADMIN';

-- Step 3: Set the warehouse name
SET WAREHOUSE_NAME = 'COMPUTE_WH';

-- ============================================================================
-- Verification (run to confirm variables are set)
-- ============================================================================
SELECT
    $RUNTIME_ROLE AS runtime_role,
    $ADMIN_ROLE AS admin_role,
    $WAREHOUSE_NAME AS warehouse_name;
