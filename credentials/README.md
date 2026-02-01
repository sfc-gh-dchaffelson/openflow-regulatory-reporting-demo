# Credentials Setup

This directory stores security credentials for the BOE Gaming demo. All credential files are excluded from version control via `.gitignore`.

---

## Overview

You need to generate the following credentials:

1. **DGOJ Signing Credentials** - Certificate and private key for XAdES-BES signatures
2. **ZIP Encryption Password** - 50-character password for AES-256 encryption
3. **SFTP Credentials** - SSH key pair for AWS Transfer Family authentication
4. **Regulatory Truststores** - CA certificates for European regulatory authority websites

---

## Truststores

The `truststores/` subdirectory contains CA certificates for connecting to European gambling regulatory authority websites. The SPCS OpenFlow runtime may not include these in its default Java truststore.

See `truststores/README.md` for details.

| File | Purpose |
|------|---------|
| `truststores/regulatory_truststore.jks` | JKS truststore with 13 CA certificates |
| `truststores/regulatory_ca_bundle.pem` | PEM bundle of all CA certificates |

---

## Signing and Encryption Credentials

You need to generate three types of credentials:

1. **DGOJ Signing Credentials** - Certificate and private key for XAdES-BES signatures
2. **ZIP Encryption Password** - 50-character password for AES-256 encryption
3. **SFTP Credentials** - SSH key pair for AWS Transfer Family authentication

---

## Prerequisites

- OpenSSL installed
- Command-line access
- Write permissions in this directory

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

**Save this password** - you'll need it for OpenFlow configuration.

---

## Step 3: SFTP SSH Key Pair

Generate SSH key pair for AWS Transfer Family authentication:

```bash
# Still in credentials/ directory
ssh-keygen -t rsa -b 4096 -f gaming_sftp_key -N ""
```

This creates:
- `gaming_sftp_key` - Private key (no passphrase)
- `gaming_sftp_key.pub` - Public key

### Set Permissions

```bash
chmod 600 gaming_sftp_key
chmod 644 gaming_sftp_key.pub
```

The public key is added to AWS Transfer Family when creating the SFTP user (see `setup/02_DEPLOYMENT.md` Step 3d).

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
-rw-------  gaming_sftp_key
-rw-r--r--  gaming_sftp_key.pub
```

---

## Required Files Summary

| File | Purpose | Sensitive | Uploaded To |
|------|---------|-----------|-------------|
| `dgoj_demo_cert.pem` | XAdES-BES signing certificate | No | OpenFlow asset |
| `dgoj_demo_key.pem` | XAdES-BES signing private key | Yes | OpenFlow asset |
| `gaming_sftp_key` | SSH private key for AWS Transfer | Yes | OpenFlow asset |
| `gaming_sftp_key.pub` | SSH public key | No | AWS SFTP user config |

---

## OpenFlow Asset References

In the OpenFlow parameter context `Boe Gaming Report`, credential files are referenced as:

```
/nifi/configuration_resources/assets/<context-id>/gaming_sftp_key
/nifi/configuration_resources/assets/<context-id>/dgoj_demo_cert.pem
/nifi/configuration_resources/assets/<context-id>/dgoj_demo_key.pem
/nifi/configuration_resources/assets/<context-id>/DGOJ_Monitorizacion_3.3.xsd
```

Upload assets using nipyapi (see `setup/02_DEPLOYMENT.md` Step 15b).

---

## Security Notes

**Demo credentials (what we create here):**
- Self-signed certificate
- Simple password
- SSH key without passphrase
- Suitable for proof-of-concept

**Production credentials (requirements):**
- CA-issued certificate from trusted authority
- Complex password meeting enterprise standards
- Hardware Security Module (HSM) for key storage
- Certificate and key rotation policies
- Enterprise secrets management
- Audit logging for key access

**NEVER commit credential files** - They are excluded via `.gitignore`.

---

## Deployed Values

For the current demo deployment values (passwords, hostnames, etc.), see:

```
credentials/DEPLOYMENT_VALUES.md
```

This file is gitignored and contains the actual configuration for the running demo environment.

**For new deployments:** Generate credentials using the steps above, then create your own `DEPLOYMENT_VALUES.md` with your deployment-specific configuration.

See `../setup/FLOW_PARAMETERS.md` for complete parameter context structure.
