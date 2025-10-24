# OpenFlow Configuration and Flow Import

Configure parameters, upload credentials, and import the BOE Gaming Report flow.

---

## Prerequisites

- OpenFlow (Apache NiFi) instance running
- PrepareRegulatoryFile processor installed (see [04_PROCESSOR_SETUP.md](04_PROCESSOR_SETUP.md))
- Credentials generated (see [02_CREDENTIALS_SETUP.md](02_CREDENTIALS_SETUP.md))
- Snowflake database configured (see [01_SNOWFLAKE_SETUP.md](01_SNOWFLAKE_SETUP.md))
- AWS SFTP server created (see [03_SFTP_SETUP.md](03_SFTP_SETUP.md))

---

## Step 1: Create Parameter Context

### 1.1 Navigate to Parameter Contexts

1. Click main menu (Username) → **Controller Settings**
2. Select **Parameter Contexts** tab
3. Click **+** (Create Parameter Context)

### 1.2 Create Context

- **Name:** `BoEGamingReport`
- **Description:** BOE Gaming Report compliance demo parameters

---

## Step 2: Upload File Assets

Add these files as parameter assets (file type parameters):

| Parameter Name | Upload File | Location |
|----------------|-------------|----------|
| **BOE XSD** | DGOJ_Monitorizacion_3.3.xsd | Project root |
| **DGOJ Cert** | dgoj_demo_cert.pem | credentials/ |
| **DGOJ Private Key** | dgoj_demo_key.pem | credentials/ |
| **SFTP Private Key** | sftp_key | credentials/ |

### How to Upload File Parameters

1. In Parameter Context, click **+** (Add Parameter)
2. **Name:** (from table above)
3. Click **Referencing Assets**
4. Click **Upload** to upload the file as a new asset
5. Select the file from the location shown in table above
6. Check the box next to the uploaded asset to connect it to this parameter
7. **Sensitive:** No (for all file uploads)
8. Click **Apply**

Repeat for each file parameter.

---

## Step 3: Configure Sensitive String Parameters

Add these as **sensitive** string parameters:

| Parameter Name | Example Value | Source |
|----------------|---------------|--------|
| **DGOJ Private Key Password** | yourSecurePassword123 | From CREDENTIALS_SETUP Step 1 |
| **DGOJ Zip Password** | AB12...wx#$&! | From CREDENTIALS_SETUP Step 2 |
| **Snowflake Private Key** | -----BEGIN PRIVATE KEY-----... | From SNOWFLAKE_SETUP Step 1 (PEM format, unencrypted) |

### How to Add Sensitive Parameters

1. In Parameter Context, click **+** (Add Parameter)
2. **Name:** (from table above)
3. **Value:** Paste the sensitive value
4. **Sensitive:** Check ☑️
5. Click **Apply**

---

## Step 4: Configure Connection Parameters

**Note:** This flow is designed for BYOC (Bring Your Own Cloud) OpenFlow deployments and requires Snowflake account connection information. SPCS (Snowpark Container Services) deployments may not require all these parameters as OpenFlow can inherit Snowflake connectivity.

Add these as **non-sensitive** string parameters:

| Parameter Name | Example Value | Notes |
|----------------|---------------|-------|
| **Snowflake Account Identifier** | MYORG-MYACCOUNT | Your Snowflake account locator |
| **Snowflake Username** | OPENFLOWSERVICE | Service account username (from SNOWFLAKE_SETUP Step 1) |
| **Snowflake Role** | OPENFLOWREPLICATE | Role with database access (from SNOWFLAKE_SETUP Step 1) |
| **Snowflake Database** | BOEGAMINGREPORT | From SNOWFLAKE_SETUP (customizable) |
| **Snowflake Schema** | DEMO | From SNOWFLAKE_SETUP (customizable) |
| **Snowflake Warehouse** | COMPUTE_WH | Your compute warehouse |

### How to Add Non-Sensitive Parameters

1. In Parameter Context, click **+** (Add Parameter)
2. **Name:** (from table above)
3. **Value:** Your value
4. **Sensitive:** Leave unchecked ☐
5. Click **Apply**

---

## Step 5: Import Flow

### 5.1 Upload Flow Definition

1. In OpenFlow canvas, click **Upload** or **Import** icon
2. Select `flow/BoeGamingReport.json`
3. Flow imports as a Process Group named **BoeGamingReport**

### 5.2 Apply Parameter Context

1. Right-click the **BoeGamingReport** process group
2. Select **Configure**
3. Go to **General** tab
4. **Parameter Context:** Select `BoEGamingReport`
5. Click **Apply**

---

## Step 6: Configure Controller Services

### 6.1 Open Controller Services

1. Right-click **BoeGamingReport** process group
2. Select **Configure**
3. Go to **Controller Services** tab

### 6.2 Configure Snowflake Private Key Service

1. Find the private key service (name may vary)
2. Click ⚙️ (gear icon) → **Configure**
3. Set **Private Key** property to: `#{Snowflake Private Key}`
4. Click **Apply**

### 6.3 Configure Snowflake Connection Service

1. Find **SnowflakeConnectionService**
2. Click ⚙️ (gear icon) → **Configure**
3. Verify all properties show parameter references:
   - Account: `#{Snowflake Account Identifier}`
   - User: `#{Snowflake Username}`
   - Role: `#{Snowflake Role}`
   - Database Name: `#{Snowflake Database}`
   - Schema: `#{Snowflake Schema}`
   - Warehouse: `#{Snowflake Warehouse}`
   - Private Key Service: (should reference the private key service configured above)
4. Click **Apply**

### 6.4 Enable Controller Services

1. Click ⚡ (lightning bolt) on the **private key service** → **Enable**
2. Click ⚡ on **SnowflakeConnectionService** → **Enable**
3. Find **JsonRecordSetWriter** → Click ⚡ → **Enable**

Verify all services show **Enabled** status.

---

## Step 7: Start the Flow

### 7.1 Enter Process Group

Double-click **BoeGamingReport** process group to open it.

### 7.2 Verify Processor Configuration

Quick check of key processors (optional but recommended):

**GenerateFlowFile:**
- Scheduling: 1 min
- Queries reference parameters: `#{Snowflake Database}`, `#{Snowflake Schema}`

**PrepareRegulatoryFile:**
- Certificate Path: `#{DGOJ Cert}`
- Private Key Path: `#{DGOJ Private Key}`
- All parameters showing values (not `#{...}` in red)

**PutSFTP:**
- Hostname: `s-d5c0fe27772648908.server.transfer.us-west-2.amazonaws.com`
- Username: `dgoj-demo`
- Private Key Path: `#{SFTP Private Key}`

### 7.3 Start All Processors

1. Press **Ctrl+A** (or **Cmd+A** on Mac) to select all
2. Right-click → **Start**
3. Verify all processors show ▶️ (running/green)

---

## Step 8: Verify Flow Operation

### 8.1 Monitor FlowFile Movement

Watch for flowfiles moving through the processors:
- Connections show counts: `0/1` means 1 flowfile waiting
- Processors show throughput stats after processing

### 8.2 Check Processor Flow

Expected flow within 1 minute:
1. **GenerateFlowFile** creates trigger (every 1 min)
2. **ExecuteSQLRecord** queries Snowflake (finds READY batch)
3. **ExtractMetadata** parses batch info to attributes
4. **ExtractXML** pulls XML to content
5. **SetMimeTypeAndFilename** sets attributes
6. **ValidateXml** validates against XSD
7. **PrepareRegulatoryFile** signs, compresses, encrypts
8. **PutSFTP** uploads to AWS
9. **ExecuteSQL** updates Snowflake status to UPLOADED

### 8.3 Verify Snowflake Status Update

```sql
SELECT
  batch_id,
  status,
  generated_filename,
  upload_timestamp
FROM BOEGAMINGREPORT.DEMO.regulatory_batches
ORDER BY batch_timestamp DESC;
```

Status should change from `READY` to `UPLOADED`.

### 8.4 Verify SFTP Upload

Check AWS S3 bucket:

```bash
aws s3 ls s3://dch-dgoj-demo-sftp/CNJ/OP01/JU/ --recursive
```

Expected output:
```
2025-10-17 14:30:22       1234 CNJ/OP01/JU/20251017/POT/OP01_ALM01_JU_JUC_POT_20251017143022_abc12345.zip
```

---

## Troubleshooting

### Parameters Not Resolving

**Symptoms:** Properties show `#{Parameter Name}` in red instead of values

**Fixes:**
1. Verify parameter context is applied to process group
2. Check parameter names match exactly (case-sensitive)
3. Verify file assets uploaded successfully
4. Try reapplying parameter context

### Controller Service Won't Enable

**Check:**
1. All parameter references are valid
2. Snowflake credentials are correct
3. Network connectivity to Snowflake
4. Dependent services are enabled first

### No Batches Picked Up

**Check:**
1. GenerateFlowFile is running (should trigger every 1 minute)
2. Snowflake has batches with status='READY'
3. ExecuteSQLRecord query includes database/schema parameters
4. Snowflake connection service is enabled

### XSD Validation Failures

**Check:**
1. BOE XSD parameter uploaded correctly
2. File path accessible by OpenFlow
3. XML namespace matches XSD (http://cnjuego.gob.es/sci/v3.3.xsd)

### Signing/Encryption Failures

**Check:**
1. DGOJ Cert and DGOJ Private Key uploaded
2. DGOJ Private Key Password is correct
3. Certificate and key match (same pair)
4. Files are in PEM format

### SFTP Upload Failures

**Check:**
1. SFTP Private Key uploaded correctly
2. Server hostname matches PutSFTP configuration
3. Username is correct (`dgoj-demo`)
4. SSH key matches public key added to AWS user
5. S3 bucket permissions allow write

### Status Not Updating in Snowflake

**Check:**
1. ExecuteSQL runs after PutSFTP success
2. Query references correct database/schema parameters
3. Snowflake connection has write permissions

---

## Testing Continuous Operation

### Generate New Batch

```sql
-- In Snowflake
INSERT INTO BOEGAMINGREPORT.DEMO.poker_tournaments (transaction_id, transaction_data)
SELECT
    'TXN_TEST_' || SEQ4() as transaction_id,
    OBJECT_CONSTRUCT(
        'tournament_id', 'TOUR_TEST_' || SEQ4(),
        'player_id', 'PLAYER_' || UNIFORM(1000, 9999, RANDOM()),
        'bet_amount', ROUND(UNIFORM(10, 500, RANDOM()), 2),
        'win_amount', ROUND(UNIFORM(0, 1000, RANDOM()), 2),
        'timestamp', CURRENT_TIMESTAMP()
    ) as transaction_data
FROM TABLE(GENERATOR(ROWCOUNT => 5));

CALL BOEGAMINGREPORT.DEMO.generate_regulatory_batch();
```

Watch OpenFlow pick up and process the new batch within 1 minute.

---

## Success!

Your BOE Gaming Report compliance demo is now fully operational:

- ✅ Snowflake generates XML batches
- ✅ OpenFlow polls for ready batches
- ✅ XSD validation ensures structural compliance
- ✅ XAdES-BES signature applied
- ✅ AES-256 encryption protects data
- ✅ Automated SFTP delivery
- ✅ Complete audit trail in Snowflake

---

## Next Steps

- Review [../specifications/05_COMPLIANCE.md](../specifications/05_COMPLIANCE.md) for spec compliance analysis
- Check [../specifications/04_DEMO_SPECIFICATIONS.md](../specifications/04_DEMO_SPECIFICATIONS.md) for demo implementation details
- Monitor batch processing in Snowflake and OpenFlow
- Test with additional data scenarios
