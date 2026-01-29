# DGOJ XAdES Processor - NiFi Java Processor

NiFi processor for Spanish DGOJ regulatory compliance (BOE-A-2024-12639).
Performs XAdES-BES digital signing and AES-256 ZIP encryption.

## Overview

Pure Java NiFi processor that prepares XML data for Spanish DGOJ regulatory submission. This is a Java alternative to the Python `PrepareRegulatoryFile` processor, eliminating Python runtime dependencies.

### Operations Performed

1. **XAdES-BES 1.3.2 Digital Signature** - RSA-SHA256 enveloped/enveloping signature
2. **ZIP Compression** - Deflate algorithm
3. **AES-256 Encryption** - WinZip-compatible password-protected ZIP

### Why Java Instead of Python?

| Concern | Python Processor | Java Processor |
|---------|-----------------|----------------|
| Runtime dependencies | Requires Python + PyPI access | Self-contained NAR |
| SPCS deployment | Needs External Access Integration | No network access needed |
| Dependency management | Version conflicts possible | Bundled in NAR |
| Maintenance | Python environment upkeep | Standard Java |

---

## Prerequisites

- Java 21 LTS
- Maven 3.8+
- NiFi 2.x / OpenFlow

---

## Build

```bash
cd custom_processors/nifi-dgoj-xades-nar
mvn clean package
```

Output: `target/nifi-dgoj-xades-nar-<version>.nar`

Expected NAR size: ~19 MB (includes EU DSS, Bouncy Castle, Zip4j)

---

## Install

### Via OpenFlow Web UI

1. Open OpenFlow in web browser
2. Click main menu (Username) in top-right corner
3. Select **Controller Settings**
4. Navigate to **Local Extensions** tab
5. Click **Upload Extension** or drag-and-drop the NAR file
6. Select the NAR file from `target/`
7. Click **Upload**
8. Refresh browser after installation

### Via CLI

```bash
nipyapi --profile <profile> ci upload_nar --file_path target/nifi-dgoj-xades-nar-<version>.nar
```

---

## Verify Installation

1. In OpenFlow canvas, click **Add Processor** (+)
2. Search for `DgojXadesProcessor`
3. Tags should show: xml, signature, encryption, xades, regulatory, dgoj, spain
4. Add processor to canvas and configure

---

## Properties

The processor supports dual input modes for credentials: file path OR PEM content. Use path properties for asset-based workflows, or content properties for secrets manager integration.

### Credential Properties (use one mode per credential)

| Property | Description | Sensitive | Expression Language |
|----------|-------------|-----------|---------------------|
| Certificate Path | File path to X.509 certificate (.pem/.crt) | No | Yes |
| Certificate | X.509 certificate as PEM content | Yes | Yes |
| Private Key Path | File path to private key (.pem) | No | Yes |
| Private Key | Private key as PEM content | Yes | Yes |
| Private Key Password | Password for encrypted private key (optional) | Yes | Yes |

### Processing Properties

| Property | Description | Sensitive | Expression Language |
|----------|-------------|-----------|---------------------|
| ZIP Encryption Password | Password for AES-256 encryption | Yes | Yes |
| Signature Method | `enveloped` or `enveloping` | No | No |
| XML Filename | Filename for XML inside ZIP | No | Yes |

### Defaults

| Property | Default Value |
|----------|---------------|
| Signature Method | enveloped |
| XML Filename | enveloped.xml |

### Property Resolution

- If both path and content are provided for a credential, the path takes precedence
- At least one of path or content must be provided for Certificate and Private Key

---

## Relationships

| Relationship | Description |
|--------------|-------------|
| success | Signed, compressed, encrypted ZIP |
| failure | Original FlowFile with `error.message` attribute |

---

## Attributes Set on Success

| Attribute | Value |
|-----------|-------|
| mime.type | application/zip |
| dgoj.signed | true |
| dgoj.encrypted | true |
| dgoj.signature.method | enveloped or enveloping |

---

## Certificate/Key Formats

The processor accepts both file paths and direct PEM content:

### File Path
```
/path/to/certificate.pem
```

### Direct PEM Content
```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAJC1...
-----END CERTIFICATE-----
```

### AWS Secrets Manager Integration

Store PEM content in AWS Secrets Manager and reference via parameter provider:
```
#{your-certificate-parameter}
```

The processor auto-detects PEM content vs file paths by checking for `-----BEGIN`.

### PEM Normalization

The processor handles common formatting issues from secrets managers:
- Escaped newlines (`\n` as literal characters)
- Windows line endings (`\r\n`)
- Missing line wrapping
- Extra whitespace

---

## Drop-in Replacement

This processor is designed as a drop-in replacement for the Python `PrepareRegulatoryFile` processor:

- Compatible property names (same dual-input mode)
- Same relationships
- Same input/output format
- Same attributes set

To migrate:
1. Stop the Python processor
2. Add Java processor to canvas
3. Copy property values from Python to Java processor
4. Reconnect relationships
5. Remove Python processor

---

## Dependencies (Bundled in NAR)

| Library | Purpose | License |
|---------|---------|---------|
| EU DSS 6.0 | XAdES-BES signature | LGPL 2.1 |
| Zip4j 2.11.5 | AES-256 ZIP encryption | Apache 2.0 |
| Bouncy Castle | Cryptographic operations | MIT |

All dependencies are pure Java with no native/JNI code.

---

## Troubleshooting

### Processor Not Appearing

1. Check NiFi/OpenFlow logs for NAR loading errors
2. Verify NAR was uploaded successfully
3. Refresh browser (Ctrl+F5 / Cmd+F5)

### Signature Verification Fails

1. Verify certificate matches private key
2. Check certificate is valid (not expired)
3. Ensure private key password is correct (if encrypted)

### ZIP Decryption Fails

1. Verify password is correct
2. Ensure extraction tool supports WinZip AES-256

### "Invalid PEM format" Error

1. Check PEM has proper BEGIN/END markers
2. If from secrets manager, check for escaped newlines
3. Verify base64 content is valid

---

## Technical Details

### Signature Specification

- **Standard**: XAdES-BES (Baseline-B in DSS terminology)
- **Algorithm**: RSA with SHA-256
- **Canonicalization**: Exclusive XML Canonicalization
- **Packaging**: Enveloped (default) or Enveloping

### Encryption Specification

- **Format**: ZIP with WinZip AES extension
- **Algorithm**: AES-256
- **Compression**: Deflate

---

## License

Apache License 2.0

See LICENSE file in repository root.
