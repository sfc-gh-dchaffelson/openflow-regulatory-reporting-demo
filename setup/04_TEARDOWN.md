# BOE Gaming Demo Teardown Guide

This document describes the **process** for tearing down the BOE Gaming regulatory compliance demo. It references `02_DEPLOYMENT.md` as the authoritative source for object inventories.

**Source of Truth**: All object names, hosts, and configurations are defined in `02_DEPLOYMENT.md`. This document provides the teardown process and dependency ordering.

---

## Pre-Teardown Checklist

- [ ] Review `02_DEPLOYMENT.md` to understand what was deployed
- [ ] Confirm the target database matches the demo database (Section "Step 1" in deployment guide)
- [ ] Confirm the Postgres instance name matches the demo instance (Section "Step 2" in deployment guide)
- [ ] Export any flows or data you want to preserve

---

## Tool Dependencies

| Tool | Used For | Installation |
|------|----------|--------------|
| Snowflake CLI (`snow`) | Database and Snowflake object operations | `pip install snowflake-cli` |
| nipyapi | OpenFlow flow management | `pip install nipyapi` |
| AWS CLI | SFTP cleanup (S3-backed) | `pip install awscli` or system package |

**Cortex Code Users**: Before executing OpenFlow operations, invoke the `openflow` skill which provides correct command syntax and workflows. Reference `ops-flow-lifecycle.md` within that skill for flow teardown operations.

---

## Dependency Order

Teardown must proceed in this order to avoid failures:

1. **OpenFlow Flows** - Stop and remove (downstream consumers first)
2. **SPCS Egress Network Rule** - Clear demo hosts from VALUE_LIST
3. **Snowflake Database** - Drop entire database (cascades schema objects including ingress network rule)
4. **Postgres Instance** - Drop the instance (must be dropped before its network policy)
5. **Postgres Network Policy** - Drop account-level policy (now safe after instance is gone)
6. **SFTP Cleanup** - Remove uploaded files (external to Snowflake)

---

## Objects to PRESERVE

These are shared OpenFlow infrastructure objects - do NOT remove:

| Object Type | Examples | Why Preserve |
|-------------|----------|--------------|
| OpenFlow database | `OPENFLOW` | Shared by all deployments |
| Runtime roles | `OPENFLOWRUNTIMEROLE_*`, `OPENFLOWADMIN` | Runtime infrastructure |
| Base network rules | `ALLOW_OPENFLOW_DEPLOYMENT_INGRESS`, `PYPI_NETWORK_RULE` | Runtime requirements |
| External Access Integration | `REGULATORYDEMO` | Attached via UI, shared resource |
| Warehouses | `OPENFLOW_WH` | Shared compute |

**Important**: The EAI cannot be removed programmatically once attached to a runtime via the UI. Only update the network rule's VALUE_LIST.

---

## Phase 1: Stop and Remove OpenFlow Flows

**Reference**: `02_DEPLOYMENT.md` Section "Step 5: Deploy Flows" lists all demo flows.

### Process

1. List all deployed flows:
   ```bash
   nipyapi --profile <profile> ci list_flows
   ```

2. Identify demo flows by matching names against `flow/*.json` files in the repository and connector names from the deployment guide.

3. Stop flows in reverse dependency order (downstream first):
   - Report generation and fetch flows (no downstream dependencies)
   - Batch processing (depends on CDC)
   - CDC connectors (depends on source)
   - Data generation (source flow)

4. Stop each flow:
   ```bash
   nipyapi --profile <profile> ci stop_flow --process_group_id "<id>"
   ```

5. If queues have data, purge FlowFiles first:
   ```bash
   nipyapi --profile <profile> ci purge_flowfiles --process_group_id "<id>"
   ```

6. Delete each stopped flow:
   ```bash
   nipyapi --profile <profile> ci cleanup --process_group_id "<id>"
   ```

   **Troubleshooting Deletion Failures**: If cleanup fails due to queued FlowFiles:
   - First try `purge_flowfiles` command above
   - If purge doesn't work, drop the Snowflake database first (Phase 3) to invalidate flow connections
   - For complete reference, see the OpenFlow skill: `references/ops-flow-lifecycle.md`

7. Delete orphaned parameter contexts:
   ```bash
   # List all parameter contexts and identify demo-related ones
   nipyapi --profile <profile> parameters list_all_parameter_contexts | jq -r '.[].component.name'
   
   # Delete each orphaned context by ID
   nipyapi --profile <profile> parameters delete_parameter_context "<context_id>"
   ```
   
   **Note**: CDC connectors create hierarchical contexts (Ingestion, Source, Destination). Delete child contexts before parents if they have inheritance relationships.

8. Verify removal:
   ```bash
   nipyapi --profile <profile> ci list_flows
   nipyapi --profile <profile> parameters list_all_parameter_contexts | jq -r '.[].component.name'
   ```

---

## Phase 2: Update SPCS Egress Network Rule

**Reference**: `02_DEPLOYMENT.md` Section "Step 4: Network Configuration" lists all demo hosts.

### Process

1. Get current rule contents:
   ```sql
   DESCRIBE NETWORK RULE OPENFLOW.OPENFLOW.REGULATORYDEMO;
   ```

2. Cross-reference hosts against `02_DEPLOYMENT.md` to identify demo-specific entries:
   - Postgres hostname (from Step 2)
   - SFTP hostname (from Step 3)
   - Regulatory authority domains (from Step 4)
   - SharePoint/Azure AD domains (from Step 4)
   - GitHub domains (from Step 4)

3. Clear all demo hosts from the rule:
   ```sql
   ALTER NETWORK RULE OPENFLOW.OPENFLOW.REGULATORYDEMO SET VALUE_LIST = ();
   ```
   
   Or if non-demo hosts exist, rebuild with only those remaining.

**Constraint**: Do NOT drop the EAI or the network rule itself - only clear the VALUE_LIST.

---

## Phase 3: Drop Snowflake Database

**Reference**: `02_DEPLOYMENT.md` Section "Step 1: Database Setup" defines the database name.

### Process

**Important**: If the database contains an ingress network rule that is referenced by a network policy, you must first clear the rule from the policy. Otherwise `DROP DATABASE` will fail with "Cannot drop database as it includes network rule - policy associations."

```sql
USE ROLE ACCOUNTADMIN;

-- First, clear the ingress network rule from its associated network policy
-- (Find the policy name via SHOW NETWORK POLICIES)
ALTER NETWORK POLICY <policy_name> SET ALLOWED_NETWORK_RULE_LIST = ();

-- Now drop the demo database (cascades all schemas, tables, views, functions, 
-- procedures, streams, dynamic tables, stages, and schema-level network rules)
DROP DATABASE IF EXISTS <demo_database> CASCADE;
```

This automatically removes:
- All schemas defined in the deployment guide
- All objects within those schemas
- The Postgres ingress network rule (schema-level object)

---

## Phase 4: Drop Postgres Instance

**Reference**: `02_DEPLOYMENT.md` Section "Step 2: Postgres Instance" defines the instance name.

### Process

```sql
-- Find demo Postgres instance
SHOW POSTGRES INSTANCES;

-- Drop the instance matching the deployment guide
DROP POSTGRES INSTANCE IF EXISTS <instance_name>;
```

**Note**: The instance must be dropped before its network policy can be removed.

---

## Phase 5: Drop Postgres Network Policy

**Reference**: `02_DEPLOYMENT.md` Section "Step 2: Postgres Instance" defines the network policy.

### Process

```sql
-- Find demo-related network policies
SHOW NETWORK POLICIES;

-- Look for policy name matching pattern from deployment guide
-- Then drop:
DROP NETWORK POLICY IF EXISTS <policy_name>;
```

The policy name typically follows the pattern `POSTGRES_INGRESS_POLICY_<instance_name>`.

---

## Phase 6: SFTP Cleanup (External)

**Reference**: `02_DEPLOYMENT.md` Section "Step 3: SFTP Setup" defines SFTP details.

### Process

1. Empty the S3 bucket backing the SFTP server:
   ```bash
   aws s3 rm s3://<bucket>/ --recursive --profile <your_aws_profile>
   ```

2. Delete the AWS Transfer server:
   ```bash
   aws transfer delete-server --server-id <server_id> --region <region> --profile <your_aws_profile>
   ```

3. Delete the S3 bucket (must be empty first):
   ```bash
   aws s3 rb s3://<bucket> --profile <your_aws_profile>
   ```

4. Delete the IAM role and its inline policy:
   ```bash
   # List inline policies to find the exact name
   aws iam list-role-policies --role-name <role_name> --profile <your_aws_profile>
   
   # Remove the inline policy (name may be s3-access, S3AccessPolicy, etc.)
   aws iam delete-role-policy --role-name <role_name> --policy-name <policy_name> --profile <your_aws_profile>
   
   # Then delete the role
   aws iam delete-role --role-name <role_name> --profile <your_aws_profile>
   ```

**Note**: Using AWS CLI directly is much more efficient than SFTP for bulk cleanup. Use whichever AWS profile has access to the Transfer server.

---

## Optional: Truncate OpenFlow Events Table

For test runs where you want a clean boundary, truncate the events table to clear all demo-related log entries:

```sql
TRUNCATE TABLE OPENFLOW.OPENFLOW.EVENTS;
```

**Note**: This removes ALL OpenFlow events, not just demo-related ones. Only do this if you don't need historical event data from other flows.

---

## Post-Teardown Verification

```sql
-- Verify database removed
SHOW DATABASES LIKE '<demo_database_pattern>';

-- Verify network policy removed
SHOW NETWORK POLICIES LIKE '%<instance_pattern>%';

-- Verify Postgres instance removed
SHOW POSTGRES INSTANCES LIKE '%<instance_pattern>%';

-- Verify egress rule cleared
DESCRIBE NETWORK RULE OPENFLOW.OPENFLOW.REGULATORYDEMO;
-- VALUE_LIST should be empty or contain only non-demo hosts
```

```bash
# Verify flows removed
nipyapi --profile <profile> ci list_flows
# Should not contain any demo flow names from repository

# Verify parameter contexts removed
nipyapi --profile <profile> parameters list_all_parameter_contexts | jq -r '.[].component.name'
# Should not contain any demo-related context names
```

---

## Recovery

If teardown was accidental or incomplete, see `02_DEPLOYMENT.md` for full redeployment instructions.
