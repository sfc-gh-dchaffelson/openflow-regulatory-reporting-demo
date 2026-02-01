# OpenFlow Parameter Contexts

This document describes the parameter context structure for OpenFlow flows. For actual deployed values, see `../credentials/DEPLOYMENT_VALUES.md` (gitignored).

**Account-Specific Values**: When deploying to a new account, update:
- `Snowflake Account Identifier` - your account locator
- `Snowflake Username` - your OpenFlow service user
- `Snowflake Role` - your OpenFlow runtime role (apply grants from `sql/02_grants.sql`)
- `Snowflake Warehouse` - your available warehouse
- `PostgreSQL Connection URL` - your Postgres instance hostname

---

## Parameter Context: Boe Gaming Report

The main context for the Boe Gaming Report flow.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `Custom Flow Name` | `BoeGamingReport` | No |
| `Snowflake Database` | `DEDEMO` | No |
| `Snowflake Schema` | `GAMING` | No |
| `Snowflake Warehouse` | (see DEPLOYMENT_VALUES.md) | No |
| `Snowflake Role` | (see DEPLOYMENT_VALUES.md) | No |
| `DGOJ Cert` | `/nifi/configuration_resources/assets/.../dgoj_demo_cert.pem` | No |
| `DGOJ Private Key` | `/nifi/configuration_resources/assets/.../dgoj_demo_key.pem` | No |
| `DGOJ Private Key Password` | (see DEPLOYMENT_VALUES.md) | Yes |
| `DGOJ Zip Password` | (see DEPLOYMENT_VALUES.md) | Yes |
| `BOE XSD` | `/nifi/configuration_resources/assets/.../DGOJ_Monitorizacion_3.3.xsd` | No |
| `SFTP Private Key` | `/nifi/configuration_resources/assets/.../gaming_sftp_key` | No |

**Note:** File-based parameters point to assets uploaded to OpenFlow. The source files are in:
- `source_documents/DGOJ_Monitorizacion_3.3.xsd`
- `credentials/gaming_sftp_key`
- Certificates generated per `../credentials/README.md`

**SPCS Authentication:** The `Snowflake Role` parameter is required for SPCS deployments. The SnowflakeConnectionService uses `SNOWFLAKE_SESSION_TOKEN` authentication (automatic) - do not configure KEY_PAIR.

---

## Parameter Context: Batch Processing

Used by the Batch Processing flow for reading from stream and writing batches.

**SPCS Deployment:** Uses `SNOWFLAKE_SESSION_TOKEN` authentication (automatic). No account identifier, username, or private key required.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `Snowflake Database` | `DEDEMO` | No |
| `Snowflake Schema` | `GAMING` | No |
| `Snowflake Role` | (see DEPLOYMENT_VALUES.md) | No |
| `Snowflake Warehouse` | (see DEPLOYMENT_VALUES.md) | No |
| `Custom Flow Name` | `BoeGamingReport` | No |

---

## Parameter Context: Generate Transactions

Used by the Generate_Transactions flow for populating Postgres with test data.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `PostgreSQL Driver` | `/nifi/configuration_resources/assets/.../postgresql-42.7.4.jar` | No |

**Controller Services** (created in-flow, not parameterized):
- `Postgres Connection Pool` - DBCP connection to Snowflake Postgres
- `JSON Reader` - JsonTreeReader for parsing generated records
- `JSON Writer` - JsonRecordSetWriter for batching

**JSON Schema**: The GenerateJSON processor uses a schema with [DataFaker](https://www.datafaker.net/) expressions in the `format` field:
- `Internet.uuid` - generates UUIDs
- `Internet.ipV4Address` - generates IP addresses
- `regexify 'PLR[0-9]{6}'` - generates player IDs matching pattern
- `TimeAndDate.past '30','DAYS','yyyy-MM-dd''T''HH:mm:ss''Z'''` - generates past timestamps

See `flow/schema_GeneratePokerTransactions.json` for the full schema.

---

## Parameter Context: Fetch Regulatory References

Used by the Fetch Regulatory References flow for downloading PDFs from boe.es and uploading to SharePoint.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `boe.truststore` | `/nifi/configuration_resources/assets/.../boe_truststore.jks` | No |
| `boe.truststore.password` | (see DEPLOYMENT_VALUES.md) | Yes |
| `Sharepoint Tenant ID` | (see DEPLOYMENT_VALUES.md) | No |
| `Sharepoint Client ID` | (see DEPLOYMENT_VALUES.md) | No |
| `Sharepoint Client Secret` | (see DEPLOYMENT_VALUES.md) | Yes |
| `Sharepoint Source Folder` | (see DEPLOYMENT_VALUES.md) | No |
| `Sharepoint Hostname` | (see DEPLOYMENT_VALUES.md) | No |
| `Sharepoint Site Name` | (see DEPLOYMENT_VALUES.md) | No |
**Azure AD App Registration**: Register an app with Graph API `Files.ReadWrite.All` permission.

**BOE Truststore**: Generate with:
```bash
keytool -import -trustcacerts -alias boe -file boe_cert.pem -keystore boe_truststore.jks -storepass <password>
```
To get the certificate: `openssl s_client -connect boe.es:443 -showcerts </dev/null 2>/dev/null | openssl x509 -outform PEM > boe_cert.pem`

---

## Parameter Context: PostgreSQL Source Parameters

CDC connector configuration.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `PostgreSQL Connection URL` | (see DEPLOYMENT_VALUES.md) | No |
| `PostgreSQL Username` | (see DEPLOYMENT_VALUES.md) | No |
| `PostgreSQL Password` | (see DEPLOYMENT_VALUES.md) | Yes |
| `PostgreSQL JDBC Driver` | `/nifi/configuration_resources/assets/.../postgresql-42.7.4.jar` | No |
| `Publication Name` | (see DEPLOYMENT_VALUES.md) | No |
| `Replication Slot Name` | (empty) | No |

---

## Parameter Context: PostgreSQL Destination Parameters

Snowflake destination for CDC replication.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `Snowflake Account Identifier` | (see DEPLOYMENT_VALUES.md) | No |
| `Snowflake Username` | (see DEPLOYMENT_VALUES.md) | No |
| `Snowflake Role` | (see DEPLOYMENT_VALUES.md) | No |
| `Snowflake Private Key` | (see DEPLOYMENT_VALUES.md) | Yes |
| `Snowflake Private Key Password` | (see DEPLOYMENT_VALUES.md) | Yes |
| `Snowflake Warehouse` | (see DEPLOYMENT_VALUES.md) | No |
| `Destination Database` | `DEDEMO` | No |
| `Snowflake Connection Strategy` | `STANDARD` | No |
| `Snowflake Authentication Strategy` | `KEY_PAIR` | No |

---

## Parameter Context: PostgreSQL Ingestion Parameters

Table filtering for CDC.

| Parameter | Value | Sensitive |
|-----------|-------|-----------|
| `Included Table Names` | `tournaments.poker` | No |
| `Included Table Regex` | (empty) | No |
| `Ingestion Type` | `full` | No |
| `Concurrent Snapshot Queries` | `2` | No |
| `Object Identifier Resolution` | `CASE_INSENSITIVE` | No |
| `Merge Task Schedule CRON` | `* * * * * ?` | No |
| `Column Filter JSON` | (empty or as needed) | No |

---

## Context Inheritance

The process groups inherit parameters from parent contexts:

```
Root Canvas
├── Generate Transactions (uses Generate Transactions context)
├── Batch Processing (uses Batch Processing context)
├── Boe Gaming Report (uses Boe Gaming Report context)
├── Fetch Regulatory References (uses Fetch Regulatory References context)
└── PostgreSQL CDC (uses PostgreSQL Source/Destination/Ingestion)
```

---

## Asset Files Required

These files must be uploaded as OpenFlow assets:

| Asset | Source Location |
|-------|-----------------|
| `postgresql-42.7.4.jar` | Download from Maven Central |
| `dgoj_demo_cert.pem` | Generate per `../credentials/README.md` |
| `dgoj_demo_key.pem` | Generate per `../credentials/README.md` |
| `DGOJ_Monitorizacion_3.3.xsd` | `source_documents/DGOJ_Monitorizacion_3.3.xsd` |
| `gaming_sftp_key` | `credentials/gaming_sftp_key` |

---

## Deployment Steps

1. **Upload Assets** to OpenFlow configuration resources
2. **Create Parameter Contexts** with values above
3. **Import Flows** from `flow/*.json`
4. **Assign Contexts** to process groups per inheritance diagram
5. **Enable Controller Services**
6. **Start Process Groups**

---

## SFTP Configuration

The SFTP connection uses AWS Transfer Family. See `../credentials/DEPLOYMENT_VALUES.md` for actual hostnames and credentials.

| Setting | Value |
|---------|-------|
| Hostname | (see DEPLOYMENT_VALUES.md) |
| Port | `22` |
| Username | (see DEPLOYMENT_VALUES.md) |
| Private Key | Asset reference to `gaming_sftp_key` |
| Remote Path | `uploads/YYYY/MM/DD` (dynamic) |

---

## Generating New Credentials

For a fresh deployment, generate credentials:

```bash
# Signing certificate (self-signed for demo)
openssl genrsa -aes256 -out dgoj_demo_key.pem 2048
openssl req -new -x509 -key dgoj_demo_key.pem -out dgoj_demo_cert.pem -days 365 \
  -subj "/CN=BOE Gaming Demo/O=Demo/C=ES"

# ZIP password (50 chars)
openssl rand -base64 48 | tr -d '/+=' | head -c 50 > dgoj_zip_password.txt

# SFTP key
ssh-keygen -t rsa -b 2048 -f gaming_sftp_key -N ""

# Snowflake service user key
openssl genrsa -out openflow_rsa_key.pem 2048
openssl rsa -in openflow_rsa_key.pem -pubout -out openflow_rsa_key.pub
```

See `../credentials/README.md` for detailed instructions.
