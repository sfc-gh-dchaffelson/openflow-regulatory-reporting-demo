# Deployment Guide

Step-by-step deployment of the BOE Gaming regulatory compliance demo.

---

## Prerequisites

### Required Before Starting

These must already be in place before beginning this deployment:

| Prerequisite | Description | Where to Get |
|--------------|-------------|--------------|
| **Snowflake Account** | With ACCOUNTADMIN access | Your organization |
| **OpenFlow Runtime** | Deployed and accessible (SPCS or BYOC) | OpenFlow deployment skill |
| **External Access Integration** | Attached to OpenFlow, allows PyPI access | OpenFlow SPCS skill |
| **AWS Account** | With Transfer Family and S3 permissions | Your organization |
| **AWS CLI** | Configured with appropriate profile | AWS documentation |

### OpenFlow on SPCS Specifics

If using OpenFlow on Snowpark Container Services (SPCS), verify:

1. **OpenFlow is running** - The OpenFlow Runtime service is in READY state
2. **External Access Integration exists** - With PyPI endpoints allowed for custom processor dependencies
3. **You know your runtime role** - Find it with: `SHOW ROLES LIKE '%OPENFLOW%';`

The EAI must include at minimum:
```
pypi.org:443
files.pythonhosted.org:443
```

Additional endpoints are added during deployment (Postgres, SFTP, SharePoint, etc.) - see Step 4.

### Checklist

- [ ] Snowflake account with ACCOUNTADMIN access
- [ ] OpenFlow Runtime deployed and accessible
- [ ] OpenFlow EAI exists (SPCS) or direct internet access (BYOC)
- [ ] Your OpenFlow runtime role name (e.g., `OPENFLOWRUNTIMEROLE_SPCS1_RUNTIME1`)
- [ ] AWS account with Transfer Family permissions
- [ ] AWS CLI configured

---

## Deployment Phases

```
PHASE 0: SPECIFICATION EXTRACTION
  0a. Configure Fetch_Regulatory_References  → Downloads PDFs from boe.es to SharePoint
  0b. Configure SharePoint connector         → Replicates PDFs from SharePoint to Snowflake stage
  0c. Run specification extraction           → AI_PARSE_DOCUMENT + CORTEX.COMPLETE

PHASE 1: INFRASTRUCTURE
  1. sql/00_set_variables.sql             → Set RUNTIME_ROLE, ADMIN_ROLE
  2. sql/01_database_schema.sql           → Create database and schema
  3. sql/02_grants.sql                    → Initial grants
  4. sql/03_tables.sql                    → Base tables
  5. sql/04_functions.sql (--stage-upload)→ JavaScript UDF
  6. sql/05_procedures.sql (--stage-upload)→ Stored procedure
  7. Deploy Postgres instance              → SQL + network policy
  8. Deploy AWS SFTP                       → AWS CLI
  9. Update SPCS egress rules              → Allow OpenFlow to reach services

PHASE 2: DATA GENERATION
  10. Import all OpenFlow flows            → flow/*.json
  11. Start Generate_Transactions flow     → Populates Postgres with test data

PHASE 3: REPLICATION
  12. Start CDC connector                  → Creates DEDEMO.TOURNAMENTS.POKER
  13. sql/06_cdc_setup.sql                 → CDC grants + change tracking

PHASE 4: CDC-DEPENDENT OBJECTS
  14. sql/07_dynamic_table.sql             → DT_POKER_FLATTENED
  15. sql/08_stream.sql                    → POKER_TRANSACTIONS_STREAM
  16. sql/09_views.sql                     → Observability views

PHASE 5: PROCESSING FLOWS
  17. Start Batch_Processing flow          → Reads stream, creates batches
  18. Start BoeGamingReport flow           → Signs, encrypts, uploads to SFTP
  19. snow streamlit deploy                → Monitoring dashboard
```

**Network Rules Summary:**
| Rule Type | Purpose | When |
|-----------|---------|------|
| Postgres INGRESS | Allow your IP to connect to Postgres | Step 2 |
| SPCS EGRESS | Allow OpenFlow to reach Postgres/SFTP/GitHub | Step 4 |

**Required SPCS Egress Domains:**
| Domain | Purpose |
|--------|---------|
| `<postgres-hostname>:5432` | CDC replication source |
| `<sftp-hostname>:22` | Regulatory file delivery |
| `login.microsoftonline.com:443`, `login.microsoft.com:443` | Azure AD authentication |
| `graph.microsoft.com:443`, `*.sharepoint.com:443` | SharePoint document storage |
| `github.com:443`, `api.github.com:443` | OpenFlow flow registry (version control) |
| `boe.es:443`, `*.boe.es:443` | Spain (DGOJ) regulatory documents |
| `spillemyndigheden.dk:443`, `*.spillemyndigheden.dk:443` | Denmark regulatory documents |
| `adm.gov.it:443`, `*.adm.gov.it:443` | Italy (ADM) regulatory documents |
| `anj.fr:443`, `*.anj.fr:443` | France (ANJ) regulatory documents |
| `srij.turismodeportugal.pt:443`, `*.srij.turismodeportugal.pt:443` | Portugal (SRIJ) regulatory documents |
| `kansspelautoriteit.nl:443`, `*.kansspelautoriteit.nl:443` | Netherlands (KSA) regulatory documents |
| `mga.org.mt:443`, `*.mga.org.mt:443` | Malta (MGA) regulatory documents |
| `*.gibraltar.gov.gi:443` | Gibraltar regulatory documents |

---

## Phase 0: Specification Extraction

This phase extracts technical specifications from the Spanish gaming regulatory PDF (BOE-A-2024-12639) using Snowflake AI. The extracted specifications guide the demo implementation.

**Workflow:**
```
boe.es (Spanish gov site)
    │ Fetch_Regulatory_References flow
    ▼
SharePoint (document storage)
    │ SharePoint connector
    ▼
Snowflake Stage (@DEDEMO.GAMING.REGULATORY_DOCS)
    │ AI_PARSE_DOCUMENT + CORTEX.COMPLETE
    ▼
Extracted Specifications (specifications/*.md)
```

### Step 0a: Configure Fetch Regulatory References Flow

This flow downloads regulatory PDFs from boe.es and uploads them to SharePoint.

**Prerequisites:**
- Azure AD App Registration with `Files.ReadWrite.All` permission
- SharePoint site with a document library
- BOE truststore for SSL (boe.es uses specific certificates)

**Network Rules (SPCS):**
```sql
-- Add to your EAI network rule
ALTER NETWORK RULE OPENFLOW.OPENFLOW.<your_rule> SET VALUE_LIST = (
    -- Existing rules...
    'boe.es:443',
    '*.boe.es:443',
    'login.microsoftonline.com:443',
    'login.microsoft.com:443',
    'graph.microsoft.com:443',
    '*.sharepoint.com:443'
);
```

**Parameters (Fetch Regulatory References context):**

| Parameter | Description |
|-----------|-------------|
| `boe.truststore` | Asset: SSL truststore for boe.es |
| `boe.truststore.password` | Truststore password (sensitive) |
| `Sharepoint Tenant ID` | Azure AD tenant ID |
| `Sharepoint Client ID` | App registration client ID |
| `Sharepoint Client Secret` | App registration secret (sensitive) |
| `Sharepoint Hostname` | e.g., `contoso.sharepoint.com` |
| `Sharepoint Site Name` | e.g., `Compliance` |
| `Sharepoint Source Folder` | Target folder, e.g., `/regulatory` |

**Generate BOE Truststore:**
```bash
# Extract boe.es certificate
openssl s_client -connect boe.es:443 -showcerts </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > boe_cert.pem

# Create truststore
keytool -import -trustcacerts -alias boe -file boe_cert.pem \
  -keystore boe_truststore.jks -storepass <password> -noprompt
```

**Start the flow** after configuring parameters. It will download PDFs to SharePoint on schedule.

---

### Step 0b: Configure SharePoint Connector

Configure the SharePoint connector to replicate PDFs from SharePoint to a Snowflake stage.

**Prerequisites:**
- SharePoint connector already deployed to runtime (`unstructured-sharepoint-to-stage-no-cortex-no-acl`)
- Azure AD App Registration with `Sites.Read.All` or `Files.Read.All` permission
- Runtime role has required grants (see below)

**Required Grants:**
```sql
-- The runtime role needs these grants on the destination schema
GRANT USAGE ON SCHEMA DEDEMO.GAMING TO ROLE <runtime_role>;
GRANT CREATE TABLE ON SCHEMA DEDEMO.GAMING TO ROLE <runtime_role>;
GRANT CREATE STAGE ON SCHEMA DEDEMO.GAMING TO ROLE <runtime_role>;
GRANT CREATE SEQUENCE ON SCHEMA DEDEMO.GAMING TO ROLE <runtime_role>;
```

**Configure parameters using nipyapi CLI:**

```bash
# Dry run first to verify parameter routing
nipyapi --profile <profile> ci configure_inherited_params \
  --process_group_id "<pg-id>" \
  --parameters '{
    "Sharepoint Site URL": "https://<tenant>.sharepoint.com/sites/<sitename>",
    "Sharepoint Tenant ID": "<azure-tenant-id>",
    "Sharepoint Client ID": "<app-client-id>",
    "Sharepoint Client Secret": "<client-secret>",
    "Sharepoint Source Folder": "/compliance",
    "File Extensions To Ingest": "pdf",
    "Sharepoint Document Library Name": "Documents",
    "Destination Database": "DEDEMO",
    "Destination Schema": "GAMING",
    "Snowflake Role": "<runtime-role>",
    "Snowflake Warehouse": "COMPUTE_WH",
    "Snowflake Authentication Strategy": "SNOWFLAKE_SESSION_TOKEN"
  }' \
  --dry_run

# Execute (remove --dry_run)
nipyapi --profile <profile> ci configure_inherited_params \
  --process_group_id "<pg-id>" \
  --parameters '{...}'
```

**Parameter Reference:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `Sharepoint Site URL` | Yes | Full URL: `https://<tenant>.sharepoint.com/sites/<sitename>` |
| `Sharepoint Tenant ID` | Yes | Azure AD tenant ID (from Entra Admin Center) |
| `Sharepoint Client ID` | Yes | App registration client ID |
| `Sharepoint Client Secret` | Yes | App registration secret (sensitive) |
| `Sharepoint Source Folder` | No | Folder path to ingest (default: `/` for root) |
| `File Extensions To Ingest` | No | Comma-separated extensions (default: all files) |
| `Sharepoint Document Library Name` | No | Library name (default: `Documents`) |
| `Destination Database` | Yes | `DEDEMO` |
| `Destination Schema` | Yes | `GAMING` |
| `Snowflake Role` | Yes | Runtime role name |
| `Snowflake Warehouse` | Yes | `COMPUTE_WH` |
| `Snowflake Authentication Strategy` | Yes | `SNOWFLAKE_SESSION_TOKEN` (SPCS) or `KEY_PAIR` (BYOC) |

**Verify and start:**
```bash
nipyapi --profile <profile> ci verify_config --process_group_id "<pg-id>" --only_failures
nipyapi --profile <profile> ci start_flow --process_group_id "<pg-id>"
nipyapi --profile <profile> ci get_status --process_group_id "<pg-id>"
```

Expect: `running_processors` > 0, `bulletin_errors` = 0

**Verify data ingested:**
```sql
-- Check stage was created and has files
LIST @DEDEMO.GAMING.DOCUMENTS;

-- Check metadata table
SELECT * FROM DEDEMO.GAMING.DOC_METADATA;
```

**Note:** The connector creates these objects automatically:
- `@DEDEMO.GAMING.DOCUMENTS` - Internal stage for files
- `DEDEMO.GAMING.DOC_METADATA` - Document metadata table
- `DEDEMO.GAMING.FILE_HASHES` - Deduplication table

---

### Step 0c: Run Specification Extraction

Extract specifications from the SharePoint-replicated PDF using Snowflake Document AI and Cortex LLM.

**Run the extraction SQL:**
```bash
snow sql -c <connection> -f specifications/01_extract_specifications.sql
```

This script:
1. Refreshes stage directory and verifies PDF exists
2. Extracts text with `AI_PARSE_DOCUMENT` (LAYOUT mode) → `BOE_DOCUMENT_EXTRACTED`
3. Extracts Section 3 (Data Model) specs with `CORTEX.COMPLETE` (claude-sonnet-4-5)
4. Extracts Section 4 (Technical Model) specs with `CORTEX.COMPLETE`
5. Validates JSON and generates markdown documentation

**Output tables in DEDEMO.GAMING:**
- `BOE_DOCUMENT_EXTRACTED` - Raw document text (65 pages, ~165K chars)
- `AI_OUTPUTS` - JSON extractions and markdown specs (4 rows)

**Verify extraction:**
```sql
-- Check document extracted
SELECT document_name, page_count, LENGTH(full_content:content::STRING) AS chars
FROM DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED;

-- Check AI outputs (should have 4 rows: 2 JSON, 2 markdown)
SELECT output_id, section_id, output_type, content_length
FROM DEDEMO.GAMING.AI_OUTPUTS ORDER BY output_id;

-- Validate JSON extractions parsed correctly
SELECT section_id, CASE WHEN parsed_json IS NULL THEN 'INVALID' ELSE 'VALID' END
FROM DEDEMO.GAMING.AI_OUTPUTS WHERE output_type = 'json_extraction';
```

**Compare with reference specs:**
The extracted specs should match the reference files in `specifications/`:
- Section 3: Information types (RUD, RUR, RUG, RUT, CJD, CJT, OPT, ORT, BOT, JUC, JUA, CEV)
- Section 4: XAdES-BES 1.3.2 signatures, AES-256 encryption, batch rules, file naming conventions

---

## Phase 1: Infrastructure

### Step 1: Initial SQL Setup

Run the SQL scripts in order using the wrapper script:

```bash
cd sql

# 1. Edit 00_set_variables.sql - set your RUNTIME_ROLE
#    Find it with: SHOW ROLES LIKE '%OPENFLOW%';

# 2. Run the initialization scripts
./run_sql.sh <connection> 00_set_variables.sql
./run_sql.sh <connection> 01_database_schema.sql
./run_sql.sh <connection> 02_grants.sql
./run_sql.sh <connection> 03_tables.sql

# 3. Run stage-upload scripts (required for JavaScript UDF)
./run_sql.sh <connection> 04_functions.sql --stage-upload
./run_sql.sh <connection> 05_procedures.sql --stage-upload
```

See `sql/README.md` for detailed script descriptions.

---

### Step 2: Postgres Instance

**First, create the network policy** (required for Postgres ingress):

```sql
USE ROLE ACCOUNTADMIN;

-- Step 1: Create ingress rule (MODE = POSTGRES_INGRESS is required)
CREATE NETWORK RULE DEDEMO.GAMING.POSTGRES_INGRESS_RULE_GAMING_TXNS
  TYPE = IPV4
  VALUE_LIST = ('<YOUR_IP>/32')  -- Get your IP: curl -s ifconfig.me
  MODE = POSTGRES_INGRESS;

-- Step 2: Create network policy (account-level object)
CREATE NETWORK POLICY POSTGRES_INGRESS_POLICY_GAMING_TXNS
  ALLOWED_NETWORK_RULE_LIST = ('DEDEMO.GAMING.POSTGRES_INGRESS_RULE_GAMING_TXNS');
```

**Then create the Postgres instance with the policy attached:**

```sql
-- AWS accounts use STANDARD_M, Azure accounts use STANDARD_L
CREATE POSTGRES INSTANCE GAMING_TXNS
  COMPUTE_FAMILY = 'STANDARD_L'   -- Use STANDARD_M on AWS
  STORAGE_SIZE_GB = 20
  AUTHENTICATION_AUTHORITY = POSTGRES
  POSTGRES_VERSION = 17
  NETWORK_POLICY = 'POSTGRES_INGRESS_POLICY_GAMING_TXNS'
  COMMENT = 'BOE Gaming demo transaction source';
```

| Setting | Value |
|---------|-------|
| Name | GAMING_TXNS |
| Compute Family | STANDARD_L (Azure) / STANDARD_M (AWS) |
| Storage | 20 GB |
| Version | PostgreSQL 17 |

**Wait 3-5 minutes** for instance to reach READY state:
```sql
DESCRIBE POSTGRES INSTANCE GAMING_TXNS;
```

**Save credentials** from the `access_roles` column in the CREATE output.

**Connect and create schema/table** via psql or any Postgres client:
```sql
CREATE SCHEMA tournaments;
CREATE TABLE tournaments.poker (
    transaction_id VARCHAR(50) PRIMARY KEY,
    transaction_data JSONB NOT NULL,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Create CDC publication** for the table (required for CDC connector):
```sql
CREATE PUBLICATION gaming_publication FOR TABLE tournaments.poker;
```

Verify:
```sql
SELECT * FROM pg_publication;
```

**Record the Postgres hostname** - needed for SPCS network rules in Step 4.

---

### Step 3: AWS SFTP Infrastructure

**AWS Profile:** Use your AWS profile with Transfer Family permissions

```bash
export AWS_PROFILE=<your-aws-profile>
export AWS_REGION=<your-region>  # e.g., eu-west-2
export BUCKET_NAME=<your-sftp-bucket>-${AWS_REGION}
export ROLE_NAME=<your-sftp-role>
export SFTP_USERNAME=<your-sftp-username>
```

**Step 3a: Create S3 bucket**
```bash
aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
```

**Step 3b: Create IAM role with trust policy**
```bash
# Create trust policy file
cat > /tmp/transfer-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "transfer.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create role
aws iam create-role \
  --role-name ${ROLE_NAME} \
  --assume-role-policy-document file:///tmp/transfer-trust-policy.json

# Create and attach S3 access policy
cat > /tmp/s3-access-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"],
    "Resource": ["arn:aws:s3:::${BUCKET_NAME}", "arn:aws:s3:::${BUCKET_NAME}/*"]
  }]
}
EOF

aws iam put-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-name s3-access \
  --policy-document file:///tmp/s3-access-policy.json

# Get role ARN
export ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)
```

**Step 3c: Create Transfer Family server**
```bash
SERVER_ID=$(aws transfer create-server \
  --endpoint-type PUBLIC \
  --protocols SFTP \
  --tags Key=Project,Value=DEDemo-Gaming \
  --region ${AWS_REGION} \
  --query 'ServerId' --output text)

echo "Server ID: ${SERVER_ID}"
echo "Hostname: ${SERVER_ID}.server.transfer.${AWS_REGION}.amazonaws.com"
```

**Step 3d: Create SFTP user with SSH key**
```bash
# Generate SSH key if not exists
if [ ! -f credentials/gaming_sftp_key ]; then
  ssh-keygen -t rsa -b 4096 -C "dedemo-gaming-sftp" -f credentials/gaming_sftp_key -N ""
fi

# Create user
aws transfer create-user \
  --server-id ${SERVER_ID} \
  --user-name ${SFTP_USERNAME} \
  --role ${ROLE_ARN} \
  --home-directory /${BUCKET_NAME} \
  --ssh-public-key-body "$(cat credentials/gaming_sftp_key.pub)" \
  --region ${AWS_REGION}
```

**Step 3e: Verify connection**
```bash
sftp -i credentials/gaming_sftp_key ${SFTP_USERNAME}@${SERVER_ID}.server.transfer.${AWS_REGION}.amazonaws.com
# Should show: Remote working directory: /dedemo-gaming-sftp-eu-west-2
```

**Record these values for OpenFlow configuration:**
| Parameter | Value |
|-----------|-------|
| SFTP Hostname | `<SERVER_ID>.server.transfer.eu-west-2.amazonaws.com` |
| SFTP Port | `22` |
| SFTP Username | `gaming-demo` |
| Private Key | `credentials/gaming_sftp_key` |

---

### Step 4: SPCS Egress Rules (SPCS Only)

If running OpenFlow on SPCS, update the egress network rules to allow OpenFlow to reach external services.

**Network rule name:** `OPENFLOW.OPENFLOW.REGULATORYDEMO`

```sql
USE ROLE ACCOUNTADMIN;

ALTER NETWORK RULE OPENFLOW.OPENFLOW.REGULATORYDEMO SET VALUE_LIST = (
    '<postgres-hostname>:5432',
    '<sftp-hostname>:22',
    'boe.es:443', '*.boe.es:443',
    'login.microsoftonline.com:443', 'login.microsoft.com:443',
    'graph.microsoft.com:443', '*.sharepoint.com:443',
    'github.com:443', 'api.github.com:443',
    'spillemyndigheden.dk:443', '*.spillemyndigheden.dk:443',
    'adm.gov.it:443', '*.adm.gov.it:443',
    'anj.fr:443', '*.anj.fr:443',
    'srij.turismodeportugal.pt:443', '*.srij.turismodeportugal.pt:443',
    'kansspelautoriteit.nl:443', '*.kansspelautoriteit.nl:443',
    'mga.org.mt:443', '*.mga.org.mt:443',
    '*.gibraltar.gov.gi:443'
);
```

**Example with placeholder hostnames:**
```sql
ALTER NETWORK RULE OPENFLOW.OPENFLOW.REGULATORYDEMO SET VALUE_LIST = (
    '<postgres-hostname>.postgres.snowflake.app:5432',
    '<server-id>.server.transfer.<region>.amazonaws.com:22',
    'boe.es:443', '*.boe.es:443',
    'login.microsoftonline.com:443', 'login.microsoft.com:443',
    'graph.microsoft.com:443', '*.sharepoint.com:443',
    'github.com:443', 'api.github.com:443',
    'spillemyndigheden.dk:443', '*.spillemyndigheden.dk:443',
    'adm.gov.it:443', '*.adm.gov.it:443',
    'anj.fr:443', '*.anj.fr:443',
    'srij.turismodeportugal.pt:443', '*.srij.turismodeportugal.pt:443',
    'kansspelautoriteit.nl:443', '*.kansspelautoriteit.nl:443',
    'mga.org.mt:443', '*.mga.org.mt:443',
    '*.gibraltar.gov.gi:443'
);
```

**Verify:**
```sql
DESCRIBE NETWORK RULE OPENFLOW.OPENFLOW.REGULATORYDEMO;
```

---

## Phase 2: Data Generation

### Step 5: Import All OpenFlow Flows

Import all flows now (but don't start them yet):

1. `flow/GenerateTransactions.json` - Transaction generator
2. `flow/BatchProcessing.json` - Stream consumption and batching
3. `flow/BoeGamingReport.json` - Signing, encryption, SFTP delivery
4. `flow/FetchRegulatoryReferences.json` - SharePoint connector (optional)

Configure parameter contexts per `setup/FLOW_PARAMETERS.md`.

---

### Step 6: Start Generate_Transactions Flow

Start the transaction generator to populate Postgres:

1. Configure Postgres connection parameters
2. Start the `Generate_Transactions` flow
3. Verify data appears in Postgres:
   ```sql
   -- Connect to Postgres
   SELECT COUNT(*) FROM tournaments.poker;
   ```

**Wait for data**: CDC needs rows to replicate. Let it run for a minute or two.

---

## Phase 3: Replication

### Step 7: Start CDC Connector

Start the PostgreSQL CDC connector:

1. Verify CDC connector configuration:
   - Target database: `DEDEMO`
   - Table filter: `tournaments.poker`
   - `Object Identifier Resolution`: `CASE_INSENSITIVE`
2. Start the CDC connector
3. Wait for replication to create `DEDEMO.TOURNAMENTS.POKER`

Verify:
```sql
SELECT COUNT(*) FROM DEDEMO.TOURNAMENTS.POKER;
```

---

### Step 8: CDC Schema Grants

Run the CDC setup script:

```bash
./run_sql.sh <connection> 06_cdc_setup.sql
```

This script:
- Grants access to CDC-created schema (DEDEMO.TOURNAMENTS)
- Enables change tracking on the CDC table (required for Dynamic Table)

---

## Phase 4: CDC-Dependent Objects

These objects depend on the CDC table existing with change tracking enabled.

### Step 9: Dynamic Table, Stream, and Views

Run the remaining SQL scripts:

```bash
cd sql

# Dynamic table (requires CDC table + change tracking)
./run_sql.sh <connection> 07_dynamic_table.sql

# Stream (requires dynamic table)
./run_sql.sh <connection> 08_stream.sql

# Views (some depend on CDC table and other objects)
./run_sql.sh <connection> 09_views.sql
```

**What gets created:**
- `DT_POKER_FLATTENED` - Dynamic table that flattens CDC JSON
- `POKER_TRANSACTIONS_STREAM` - Stream on the dynamic table
- `PIPELINE_LATENCY_ANALYSIS` - Latency metrics view
- `OPENFLOW_LOGS` - Parsed OpenFlow event logs
- `OPENFLOW_ERROR_SUMMARY` - Error aggregation view

**Verify:**
```sql
SHOW DYNAMIC TABLES IN SCHEMA DEDEMO.GAMING;
SHOW STREAMS IN SCHEMA DEDEMO.GAMING;
SHOW VIEWS IN SCHEMA DEDEMO.GAMING;
```

**Note:** The grants in `sql/02_grants.sql` already include object-level grants. If you ran that script earlier, objects should be accessible.

---

## Phase 5: Processing Flows

### Step 14: Start Batch_Processing Flow

1. Verify configuration:
   - Stream: `DEDEMO.GAMING.POKER_TRANSACTIONS_STREAM`
   - MergeRecord: 500 records / 15 min
   - Post-Query: `CALL DEDEMO.GAMING.PROCESS_STAGED_BATCH('${uuid}')`
2. Enable controller services
3. Start the flow

---

### Step 15: Start BoeGamingReport Flow

This flow requires a custom processor NAR and several assets. Follow these steps in order:

**Step 15a: Upload Custom Processor NAR**

The PrepareRegulatoryFile processor handles XAdES-BES signing and AES-256 ZIP encryption. Upload the NAR before importing or starting the flow:

```bash
nipyapi --profile <profile> ci upload_nar --file_path custom_processors/PrepareRegulatoryFile/dist/prepare_regulatory_file-0.0.1.nar
```

If the NAR is missing, all processor properties will show as `sensitive: true` and validation will fail with cryptic errors.

**Step 15b: Upload Assets to Parameter Context**

Get the parameter context ID:
```bash
nipyapi --profile <profile> canvas get_process_group "Boe Gaming Report" | jq -r '.component.parameter_context.id'
```

Upload required assets:
```bash
CTX_ID="<context-id-from-above>"

nipyapi --profile <profile> parameters upload_asset --context_id "$CTX_ID" \
  --file_path "source_documents/DGOJ_Monitorizacion_3.3.xsd"

nipyapi --profile <profile> parameters upload_asset --context_id "$CTX_ID" \
  --file_path "credentials/gaming_sftp_key"

nipyapi --profile <profile> parameters upload_asset --context_id "$CTX_ID" \
  --file_path "credentials/dgoj_demo_cert.pem"

nipyapi --profile <profile> parameters upload_asset --context_id "$CTX_ID" \
  --file_path "credentials/dgoj_demo_key.pem"
```

**Step 15c: Create Parameters with Asset References**

```python
import nipyapi
nipyapi.profiles.switch('<profile>')

ctx_id = '<context-id>'
ctx = nipyapi.parameters.get_parameter_context(ctx_id, identifier_type='id')

# Get asset IDs from context
assets = {a.asset.name: a.asset.id for a in ctx.component.asset_references}

# Create parameters referencing assets
params = [
    ('BOE XSD', 'DGOJ_Monitorizacion_3.3.xsd'),
    ('SFTP Private Key', 'gaming_sftp_key'),
    ('DGOJ Cert', 'dgoj_demo_cert.pem'),
    ('DGOJ Private Key', 'dgoj_demo_key.pem'),
]

for param_name, asset_name in params:
    param = nipyapi.parameters.prepare_parameter_with_asset(
        name=param_name,
        asset_id=assets[asset_name],
        context_id=ctx_id
    )
    nipyapi.parameters.upsert_parameter_to_context(ctx, param)
```

**Step 15d: Create Sensitive Parameters**

```python
# Snowflake Role (required for SPCS SnowflakeConnectionService)
# Get your role from: SHOW ROLES LIKE '%OPENFLOW%';
# Or see credentials/DEPLOYMENT_VALUES.md for deployed value
param = nipyapi.parameters.prepare_parameter(
    name='Snowflake Role',
    value='<your-runtime-role>',  # From DEPLOYMENT_VALUES.md
    description='Snowflake role for session token authentication'
)
nipyapi.parameters.upsert_parameter_to_context(ctx, param)

# DGOJ Private Key Password (see credentials/README.md for value)
param = nipyapi.parameters.prepare_parameter(
    name='DGOJ Private Key Password',
    value='<your-private-key-password>',  # Generate per credentials/README.md
    sensitive=True
)
nipyapi.parameters.upsert_parameter_to_context(ctx, param)

# DGOJ Zip Password (50-character password, see credentials/README.md)
param = nipyapi.parameters.prepare_parameter(
    name='DGOJ Zip Password',
    value='<your-50-char-zip-password>',  # Generate per credentials/README.md
    sensitive=True
)
nipyapi.parameters.upsert_parameter_to_context(ctx, param)
```

**Step 15e: Verify Configuration**

```bash
nipyapi --profile <profile> ci verify_config --process_group_id "<pg-id>" --only_failures
```

Expected output: `"verified": "true", "failed_count": 0`

**Step 15f: Enable Controllers and Start Flow**

```bash
nipyapi --profile <profile> ci start_flow --process_group_id "<pg-id>"
```

**Step 15g: Verify Flow Running**

```bash
nipyapi --profile <profile> ci get_status --process_group_id "<pg-id>"
```

Expected: `running_processors: 11`, `bulletin_errors: 0`

**SPCS Authentication Note:** On SPCS deployments, the SnowflakeConnectionService uses `SNOWFLAKE_SESSION_TOKEN` authentication (automatic). Do not configure KEY_PAIR authentication - it's not needed and won't work.

---

### Step 16: Deploy Streamlit Dashboard

```bash
cd streamlit
snow streamlit deploy --replace -c default
```

The dashboard will be available at:
`https://app.snowflake.com/<account>/#/streamlit-apps/DEDEMO.GAMING.PIPELINE_MONITOR`

---

## Optional: Fetch Regulatory References Flow

Downloads Spanish regulatory PDFs from boe.es and uploads to SharePoint via Microsoft Graph API.

1. Configure BOE Demo Parameters context (see `FLOW_PARAMETERS.md`):
   - `boe.truststore` / `boe.truststore.password` - SSL truststore for boe.es
   - `Sharepoint Tenant ID` / `Client ID` / `Client Secret` - Azure AD app credentials
   - `Sharepoint Hostname` / `Site Name` / `Source Folder` - SharePoint target location
2. Enable controller services (Graph OAuth2 Token Provider, BOE Truststore SSL Context)
3. Start processors

**Azure AD Setup:** Register an app with `Files.ReadWrite.All` application permission and grant admin consent.

---

## Flow Start Order Summary

| Order | Flow | Depends On | Creates/Enables |
|-------|------|------------|-----------------|
| 1 | Generate_Transactions | Postgres table exists | Data in Postgres |
| 2 | CDC Connector | Data in Postgres | DEDEMO.TOURNAMENTS.POKER |
| 3 | Batch_Processing | Stream + Procedure exist | Batches in REGULATORY_BATCHES |
| 4 | BoeGamingReport | SFTP + Batches exist | Signed/encrypted files on SFTP |
| - | Fetch_Regulatory_References | Network rules for boe.es/SharePoint | PDFs in SharePoint |

---

## Verification

```sql
-- Check objects exist
SHOW TABLES IN SCHEMA DEDEMO.GAMING;
SHOW DYNAMIC TABLES IN SCHEMA DEDEMO.GAMING;
SHOW STREAMS IN SCHEMA DEDEMO.GAMING;

-- Check pipeline health
SELECT * FROM DEDEMO.GAMING.PIPELINE_LATENCY_ANALYSIS;

-- Check recent batches
SELECT BATCH_ID, STATUS, TRANSACTION_COUNT, BATCH_TIMESTAMP
FROM DEDEMO.GAMING.REGULATORY_BATCHES
WHERE BATCH_TIMESTAMP > DATEADD(hour, -1, CURRENT_TIMESTAMP())
ORDER BY BATCH_TIMESTAMP DESC;
```

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| CDC not replicating | Postgres network policy, publication exists, data in source |
| Dynamic Table not refreshing | Warehouse running, change tracking enabled |
| Stream empty | DT refresh lag (1 min), DT has data |
| OpenFlow errors | `SELECT * FROM DEDEMO.GAMING.OPENFLOW_ERROR_SUMMARY` |
| All properties show as sensitive | Custom NAR missing - upload `prepare_regulatory_file-0.0.1.nar` |
| "Property references Parameter but context does not have" | Parameter not created - check parameter context |
| "Incorrect password, could not decrypt key" | Wrong `DGOJ Private Key Password` - regenerate credentials |
| SnowflakeConnectionService INVALID on SPCS | Add `Snowflake Role` parameter with runtime role name |

### verify_config Failures

Run verification with `--only_failures` to avoid truncated output:
```bash
nipyapi --profile <profile> ci verify_config --process_group_id "<pg-id>" --only_failures
```

**Common failure patterns:**

| Pattern | Cause | Solution |
|---------|-------|----------|
| All properties `sensitive: true` | NAR/extension missing | Upload the NAR file |
| `references Parameter 'X' but context does not have` | Parameter missing | Create the parameter |
| `is invalid because X is required` | Required property not set | Set the property value |

---

## Reference Documents

| Document | Purpose |
|----------|---------|
| `01_ARCHITECTURE.md` | System overview, data flow, and dependencies |
| `03_INFRASTRUCTURE_INVENTORY.md` | Object reference |
| `../sql/README.md` | SQL script execution order |
| `FLOW_PARAMETERS.md` | OpenFlow parameter configuration |
