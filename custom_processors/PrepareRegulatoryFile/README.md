# PrepareRegulatoryFile - NiFi Python Processor

## Overview

Custom Apache NiFi Python processor that prepares XML data for Spanish DGOJ (Dirección General de Ordenación del Juego) regulatory submission as required by BOE-A-2024-12639.

## Purpose

Standard NiFi processors do not support:
- XAdES-BES digital signature format (required by BOE-A-2024-12639)
- AES-256 encrypted ZIP files with passwords (WinZip-compatible format required by specifications)

This custom processor handles these specific requirements by performing three transformations:

1. **XAdES-BES Digital Signature** - Signs XML using X.509 certificates with SHA-256 hash
2. **ZIP Compression** - Compresses using Deflate algorithm
3. **AES-256 Encryption** - Password-protects ZIP with WinZip-compatible AES-256

## Features

- Supports both "enveloped" (signature embedded in XML) and "enveloping" (separate signature file) methods
- Uses industry-standard Python libraries (signxml, pyzipper)
- Sensitive properties for secure credential management
- Expression Language support for dynamic configuration
- Comprehensive error handling and logging

## Properties

### Required Properties

| Property | Description | Sensitive | Expression Language |
|----------|-------------|-----------|---------------------|
| Certificate Path | Path to X.509 certificate file (.pem or .crt) | No | Yes |
| Private Key Path | Path to private key file (.pem) | No | Yes |
| ZIP Encryption Password | 50-character password for AES-256 | Yes | Yes |

### Optional Properties

| Property | Description | Default | Sensitive |
|----------|-------------|---------|-----------|
| Private Key Password | Password for encrypted private key | (empty) | Yes |
| Signature Method | 'enveloped' or 'enveloping' | enveloped | No |
| XML Filename | Filename for XML inside ZIP | enveloped.xml | No |

## Dependencies

The processor declares these dependencies which OpenFlow installs from PyPI:

- `lxml` - XML processing
- `signxml` - XAdES-BES signature implementation
- `cryptography` - Cryptographic operations
- `pyzipper` - AES-256 ZIP encryption

Dependencies are NOT bundled in the NAR. OpenFlow downloads them from PyPI when the processor is first loaded.

## Installation

### Build the NAR Package

See **[BUILD.md](BUILD.md)** for complete build instructions.

Quick build:
```bash
cd PrepareRegulatoryFile
hatch build --target nar
```

### Deploy to OpenFlow

Upload `dist/prepare_regulatory_file-0.0.1.nar` via OpenFlow UI: Controller Settings > Local Extensions

See **[PROCESSOR_SETUP.md](../../PROCESSOR_SETUP.md)** for detailed deployment instructions.

## Usage

### Input

- **FlowFile Content**: Valid XML conforming to DGOJ XSD schema
- **FlowFile Attributes**: Used for Expression Language evaluation in properties

### Output

#### Success Relationship
- **FlowFile Content**: Encrypted ZIP file containing signed XML
- **Attributes Added**:
  - `mime.type`: application/zip
  - `dgoj.signed`: true
  - `dgoj.encrypted`: true
  - `dgoj.signature.method`: enveloped or enveloping

#### Failure Relationship
- **Original FlowFile** with error attribute:
  - `error.message`: Description of failure

## Credentials Setup

See **[CREDENTIALS_SETUP.md](../../CREDENTIALS_SETUP.md)** for generating demo certificates.

## Integration with Demo Flow

This processor fits into the regulatory reporting flow as follows:

```
GenerateFlowFile (1-min timer)
  → ExecuteSQLRecord (query Snowflake for READY batches)
  → ExtractMetadata (EvaluateJsonPath - extract metadata to meta.* attributes)
  → ExtractXML (EvaluateJsonPath - extract XML to content)
  → SetMimeTypeAndFilename (UpdateAttribute - set filename and mime.type)
  → ValidateXml (validate against DGOJ XSD)
  → PrepareRegulatoryFile (THIS PROCESSOR - sign, compress, encrypt)
  → PutSFTP (upload to AWS Transfer Family SFTP)
  → ExecuteSQL (update Snowflake status to UPLOADED)
```

**Parameter Configuration:**
- Certificate Path: `#{DGOJ Cert}`
- Private Key Path: `#{DGOJ Private Key}`
- Private Key Password: `#{DGOJ Private Key Password}`
- ZIP Encryption Password: `#{DGOJ Zip Password}`
- Signature Method: `enveloped`
- XML Filename: `enveloped.xml`

## Technical Details

### Requirements

- Python 3.11 or higher
- OpenFlow (Apache NiFi 2025.10.14+)

### What This Processor Does

1. Reads XML from flowfile content
2. Signs with XAdES-BES 1.3.2 using provided certificate/key
3. Creates ZIP archive with Deflate compression
4. Encrypts ZIP with AES-256 (WinZip-compatible format)
5. Writes encrypted ZIP to flowfile content
6. Sets attributes: `mime.type=application/zip`, `dgoj.signed=true`, `dgoj.encrypted=true`
