# AWS Transfer Family SFTP Server Setup

This guide walks you through creating an AWS Transfer Family SFTP server backed by S3 storage for DGOJ file delivery. The SFTP credentials created in [02_CREDENTIALS_SETUP.md](02_CREDENTIALS_SETUP.md) will be used here.

---

## Prerequisites

- AWS CLI installed and configured
- AWS account with permissions to create:
  - S3 buckets
  - IAM roles and policies
  - Transfer Family servers and users
- Completed [02_CREDENTIALS_SETUP.md](02_CREDENTIALS_SETUP.md) (need `sftp_key.pub`)

---

## Architecture Overview

**What we're building:**
1. S3 bucket - Backend storage for uploaded files
2. IAM role - Allows Transfer Family to access S3
3. Transfer Family server - Provides SFTP endpoint
4. SFTP user - Authenticates with SSH key from previous step

**Flow:** OpenFlow → SFTP Server → S3 Bucket

---

## Step 1: Choose Your Configuration Values

Before starting, decide on these values. We'll use our demo values as examples throughout:

| Component | Example (this demo) | Your value |
|-----------|-------------------|------------|
| S3 Bucket Name | `dch-dgoj-demo-sftp` | _____________ |
| AWS Region | `us-west-2` | _____________ |
| IAM Role Name | `dch-dgoj-demo-sftp-role` | _____________ |
| SFTP Username | `dgoj-demo` | _____________ |

**Note:** S3 bucket names must be globally unique. Choose something specific to your organization.

---

## Step 2: Create S3 Bucket

```bash
# Set your values (replace with your own)
export BUCKET_NAME="dch-dgoj-demo-sftp"
export AWS_REGION="us-west-2"

# Create bucket
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION
```

**Verification:**
```bash
aws s3 ls | grep $BUCKET_NAME
```

---

## Step 3: Create IAM Role for Transfer Family

### Create Trust Policy

Create a file named `transfer-trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "transfer.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Create S3 Access Policy

Create a file named `s3-access-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR-BUCKET-NAME",
        "arn:aws:s3:::YOUR-BUCKET-NAME/*"
      ]
    }
  ]
}
```

**Replace `YOUR-BUCKET-NAME`** with your actual bucket name (e.g., `dch-dgoj-demo-sftp`).

### Create and Configure Role

```bash
# Set role name (replace with your own)
export ROLE_NAME="dch-dgoj-demo-sftp-role"

# Create role with trust policy
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://transfer-trust-policy.json \
  --region $AWS_REGION

# Attach S3 access policy
aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name s3-access \
  --policy-document file://s3-access-policy.json
```

### Get Role ARN

```bash
aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text
```

**Save this ARN** - you'll need it in the next step.

Example output: `arn:aws:iam::913524911227:role/dch-dgoj-demo-sftp-role`

---

## Step 4: Create Transfer Family Server

```bash
# Create SFTP server with public endpoint
aws transfer create-server \
  --endpoint-type PUBLIC \
  --protocols SFTP \
  --region $AWS_REGION

# Output includes ServerID - save this!
```

**Example output:**
```json
{
  "ServerId": "s-d5c0fe27772648908"
}
```

**Save the `ServerId`** - you'll need it for user creation and OpenFlow configuration.

### Get Server Endpoint

```bash
# Set your server ID (replace with yours)
export SERVER_ID="s-d5c0fe27772648908"

# Get server details
aws transfer describe-server \
  --server-id $SERVER_ID \
  --region $AWS_REGION \
  --query 'Server.EndpointDetails'
```

**Server endpoint format:** `<ServerID>.server.transfer.<region>.amazonaws.com`

Example: `s-d5c0fe27772648908.server.transfer.us-west-2.amazonaws.com`

**Save this endpoint** - you'll use it in OpenFlow PutSFTP configuration.

---

## Step 5: Create SFTP User

### Prepare SSH Public Key

```bash
# Read your public key (created in CREDENTIALS_SETUP.md)
cat credentials/sftp_key.pub
```

Copy the entire output (starts with `ssh-rsa`).

### Create User

```bash
# Set username (replace with your own)
export SFTP_USERNAME="dgoj-demo"

# Get your IAM role ARN from Step 3
export ROLE_ARN="arn:aws:iam::913524911227:role/dch-dgoj-demo-sftp-role"

# Create user with SSH key authentication
aws transfer create-user \
  --server-id $SERVER_ID \
  --user-name $SFTP_USERNAME \
  --role $ROLE_ARN \
  --home-directory /$BUCKET_NAME \
  --ssh-public-key-body "$(cat credentials/sftp_key.pub)" \
  --region $AWS_REGION
```

**What this does:**
- Creates SFTP user with SSH key authentication
- Sets home directory to root of S3 bucket
- Grants role permissions for S3 access

---

## Step 6: Test SFTP Connection

```bash
# Test connection using private key
sftp -i credentials/sftp_key $SFTP_USERNAME@$SERVER_ID.server.transfer.$AWS_REGION.amazonaws.com
```

**Example (with our demo values):**
```bash
sftp -i credentials/sftp_key dgoj-demo@s-d5c0fe27772648908.server.transfer.us-west-2.amazonaws.com
```

**Successful connection:**
```
sftp> pwd
Remote working directory: /dch-dgoj-demo-sftp
sftp> exit
```

If you can connect and see your bucket as the working directory, setup is complete!

---

## Configuration Values for OpenFlow

**Save these values** - you'll need them when configuring the PutSFTP processor in [05_OPENFLOW_SETUP.md](05_OPENFLOW_SETUP.md):

| Parameter | Your Value | Example (this demo) |
|-----------|------------|---------------------|
| **SFTP Hostname** | `<ServerID>.server.transfer.<region>.amazonaws.com` | `s-d5c0fe27772648908.server.transfer.us-west-2.amazonaws.com` |
| **SFTP Port** | `22` | `22` |
| **SFTP Username** | (from Step 5) | `dgoj-demo` |
| **SFTP Private Key** | `credentials/sftp_key` | `credentials/sftp_key` |
| **S3 Bucket** | (from Step 2) | `dch-dgoj-demo-sftp` |

### OpenFlow on SPCS: External Access Integration Required

If using OpenFlow on Snowpark Container Services, you must update the External Access Integration created in [01_SNOWFLAKE_SETUP.md](01_SNOWFLAKE_SETUP.md) to include your SFTP hostname:

```sql
-- Add your SFTP server to the network rule
CREATE OR REPLACE NETWORK RULE sftp_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('<your-sftp-hostname>:22');

-- Update the integration to include SFTP access
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION openflow_external_access
  ALLOWED_NETWORK_RULES = (pypi_rule, sftp_rule)
  ENABLED = TRUE;
```

Replace `<your-sftp-hostname>` with your actual SFTP hostname from above (e.g., `s-d5c0fe27772648908.server.transfer.us-west-2.amazonaws.com`).

Without this, the PutSFTP processor will fail to connect with network or timeout errors.

---

## Verification Commands

### Check Server Status

```bash
aws transfer describe-server \
  --server-id $SERVER_ID \
  --region $AWS_REGION \
  --query 'Server.State'
```

Expected: `"ONLINE"`

### List SFTP Users

```bash
aws transfer list-users \
  --server-id $SERVER_ID \
  --region $AWS_REGION
```

### View Files in S3

After OpenFlow uploads files:

```bash
aws s3 ls s3://$BUCKET_NAME/CNJ/ --recursive
```

Expected directory structure:
```
s3://dch-dgoj-demo-sftp/CNJ/OP01/JU/YYYYMMDD/POT/*.zip
```

---

## Cleanup (When Demo Complete)

When you're done with the demo, remove all AWS resources:

```bash
# Set your values
export SERVER_ID="s-d5c0fe27772648908"
export SFTP_USERNAME="dgoj-demo"
export BUCKET_NAME="dch-dgoj-demo-sftp"
export ROLE_NAME="dch-dgoj-demo-sftp-role"
export AWS_REGION="us-west-2"

# Delete SFTP user
aws transfer delete-user \
  --server-id $SERVER_ID \
  --user-name $SFTP_USERNAME \
  --region $AWS_REGION

# Delete Transfer server (wait ~5 minutes after user deletion)
aws transfer delete-server \
  --server-id $SERVER_ID \
  --region $AWS_REGION

# Empty and delete S3 bucket
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# Delete IAM role policy
aws iam delete-role-policy \
  --role-name $ROLE_NAME \
  --policy-name s3-access

# Delete IAM role
aws iam delete-role \
  --role-name $ROLE_NAME
```

**Note:** If using a different AWS profile, add `--profile YOUR_PROFILE` to each command.

### Cleanup Temporary Files

```bash
# Remove policy files created during setup
rm transfer-trust-policy.json s3-access-policy.json
```

---

## Troubleshooting

### Issue: "Bucket name already exists"
S3 bucket names are globally unique. Choose a different name.

### Issue: "Access Denied" when testing SFTP
- Verify IAM role ARN is correct in user configuration
- Check S3 bucket name matches role policy
- Ensure role has S3 access policy attached

### Issue: Can't connect via SFTP
- Verify server is in `ONLINE` state
- Check you're using the correct private key (`credentials/sftp_key`)
- Verify public key was added correctly to user

### Issue: Files not appearing in S3
- Check OpenFlow PutSFTP configuration matches your values
- Verify remote path doesn't start with `/` (Transfer Family adds bucket automatically)
- Review OpenFlow logs for upload errors

---

## Cost Considerations

**AWS Transfer Family pricing:**
- Server uptime: ~$0.30/hour (~$216/month even if idle)
- Data transfer: Additional costs for uploads

**For demo purposes:** Remember to run cleanup commands when done to avoid ongoing charges.

---

## Next Steps

1. **Proceed to:** [04_PROCESSOR_SETUP.md](04_PROCESSOR_SETUP.md) to build the custom processor
2. **Then:** [05_OPENFLOW_SETUP.md](05_OPENFLOW_SETUP.md) to configure the flow with these SFTP values

---

## Reference: Demo Infrastructure

**Our specific configuration (for reference):**

- **S3 Bucket:** `dch-dgoj-demo-sftp` (Region: us-west-2)
- **IAM Role:** `dch-dgoj-demo-sftp-role` (ARN: `arn:aws:iam::913524911227:role/dch-dgoj-demo-sftp-role`)
- **Transfer Server:** `s-d5c0fe27772648908` (Endpoint: `s-d5c0fe27772648908.server.transfer.us-west-2.amazonaws.com`)
- **SFTP User:** `dgoj-demo`
- **Authentication:** SSH key (`credentials/sftp_key`)

Your values will be different - substitute them throughout this guide.
