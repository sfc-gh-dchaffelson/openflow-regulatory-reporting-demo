# Credentials Setup

Generate all security credentials needed for the BOE Gaming Report demo.

---

## Overview

You need to generate:
1. **DGOJ Signing Credentials** - Certificate and private key for XAdES-BES signatures
2. **ZIP Encryption Password** - 50-character password for AES-256 encryption
3. **SFTP Credentials** - SSH key pair for AWS Transfer Family authentication

All credentials are stored in the `credentials/` folder and excluded from git via `.gitignore`.

---

## Prerequisites

- OpenSSL installed
- Command-line access
- Write permissions in project directory

---

## Step 1: DGOJ Signing Certificate and Private Key

### Generate Private Key

```bash
cd credentials/

# Generate 2048-bit RSA private key with password protection
openssl genrsa -aes256 -out dgoj_demo_key.pem 2048
```

**Enter a password** when prompted (e.g., `yourSecurePassword123`). You'll need this for the `DGOJ Private Key Password` parameter in OpenFlow.

### Generate Self-Signed Certificate

```bash
# Generate certificate valid for 365 days
openssl req -new -x509 -key dgoj_demo_key.pem \
  -out dgoj_demo_cert.pem -days 365 \
  -subj "/CN=DemoOperator/O=Demo Organization/C=ES"
```

You'll be prompted for the private key password you just created.

### Set Permissions

```bash
chmod 600 dgoj_demo_key.pem
chmod 644 dgoj_demo_cert.pem
```

### Files Created

- `credentials/dgoj_demo_key.pem` - Private key (password-protected)
- `credentials/dgoj_demo_cert.pem` - Public certificate

**Important:** Remember the password you entered - you'll need it for OpenFlow configuration!

---

## Step 2: ZIP Encryption Password

Generate a 50-character password containing digits, letters, and special characters:

```bash
openssl rand -base64 48 | tr -d '/+=' | head -c 46 && echo "#\$&!"
```

**Copy the entire output** (50 characters ending in `#$&!`). You'll need this for the `DGOJ Zip Password` parameter.

Example output:
```
AB12cd34EF56gh78IJ90kl12MN34op56QR78st90UV12wx#$&!
```

**Save this password** - you'll need it for OpenFlow configuration!

---

## Step 3: SFTP SSH Key Pair

Generate SSH key pair for AWS Transfer Family authentication:

```bash
# Still in credentials/ directory
ssh-keygen -t rsa -b 2048 -f sftp_key -N ""
```

This creates:
- `credentials/sftp_key` - Private key (no passphrase)
- `credentials/sftp_key.pub` - Public key

### Set Permissions

```bash
chmod 600 sftp_key
chmod 644 sftp_key.pub
```

---

## Verification

Check that all files were created:

```bash
ls -la credentials/
```

You should see:
```
-rw-r--r--  dgoj_demo_cert.pem
-rw-------  dgoj_demo_key.pem
-rw-------  sftp_key
-rw-r--r--  sftp_key.pub
```

---

## Credentials Summary

| Credential | File | Used In | Sensitive |
|------------|------|---------|-----------|
| DGOJ Certificate | dgoj_demo_cert.pem | OpenFlow file parameter | No |
| DGOJ Private Key | dgoj_demo_key.pem | OpenFlow file parameter | Yes |
| DGOJ Key Password | (from Step 1) | OpenFlow string parameter | Yes |
| ZIP Password | (from Step 2) | OpenFlow string parameter | Yes |
| SFTP Private Key | sftp_key | OpenFlow file parameter | Yes |
| SFTP Public Key | sftp_key.pub | AWS SFTP user config | No |

---

## Production vs. Demo

**Demo credentials (what we just created):**
- ✅ Self-signed certificate
- ✅ Simple password
- ✅ SSH key without passphrase
- ✅ Suitable for proof-of-concept

**Production credentials (requirements):**
- 🔒 CA-issued certificate from trusted authority
- 🔒 Complex password meeting enterprise standards
- 🔒 Hardware Security Module (HSM) for key storage
- 🔒 Certificate and key rotation policies
- 🔒 Enterprise secrets management
- 🔒 Audit logging for key access

---

## Next Steps

1. **If you haven't already:** Complete [03_SFTP_SETUP.md](03_SFTP_SETUP.md) to create the AWS Transfer Family server
   - You'll need `credentials/sftp_key.pub` for AWS user configuration

2. **Then proceed to:** [04_PROCESSOR_SETUP.md](04_PROCESSOR_SETUP.md) to build the custom processor

3. **Finally:** [05_OPENFLOW_SETUP.md](05_OPENFLOW_SETUP.md) to upload these credentials as parameters
