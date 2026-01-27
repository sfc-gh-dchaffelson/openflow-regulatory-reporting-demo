# PrepareRegulatoryFile - NiFi Python Processor

## Overview

Custom Apache NiFi Python processor that prepares XML data for Spanish DGOJ (Dirección General de Ordenación del Juego) regulatory submission as required by BOE-A-2024-12639.

Standard NiFi processors do not support:
- **XAdES-BES digital signature format** - Required by BOE-A-2024-12639 specifications
- **AES-256 encrypted ZIP files** - WinZip-compatible password-protected archives required by DGOJ

This custom processor handles these three critical security transformations:

1. **XAdES-BES 1.3.2 Digital Signature** with SHA-256 hash
2. **ZIP Compression** using Deflate algorithm
3. **AES-256 Encryption** with 50-character password

---

## Pre-Built NAR

The NAR is already built and included in the repository:

```
dist/prepare_regulatory_file-0.0.3.nar
```

File size: ~4KB (thin NAR containing only processor code)

**Skip to "Upload to OpenFlow" section below** unless you need to rebuild.

---

## Building from Source (Optional)

If you've made changes to the processor code or need to rebuild:

### Install Build Tools

```bash
pip install hatch hatch-datavolo-nar
```

### Build NAR

```bash
cd custom_processors/PrepareRegulatoryFile
hatch build --target nar
```

Output: `dist/prepare_regulatory_file-0.0.3.nar` (~4KB)

**Note:** The NAR contains only the processor code. Dependencies (lxml, signxml, cryptography, pyzipper) are installed by OpenFlow from PyPI when the processor is first loaded.

---

## Upload to OpenFlow

### Via Web UI

1. Open OpenFlow in web browser
2. Click main menu (Username) in top-right corner
3. Select **Controller Settings**
4. Navigate to **Local Extensions** tab
5. Click **Upload Extension** or drag-and-drop the NAR file
6. Select `dist/prepare_regulatory_file-0.0.3.nar`
7. Click **Upload**
8. Installation takes a few seconds
9. You may need to manually refresh your browser

### Via CLI

```bash
nipyapi --profile <profile> ci upload_nar --file_path custom_processors/PrepareRegulatoryFile/dist/prepare_regulatory_file-0.0.3.nar
```

---

## Verify Installation

1. In OpenFlow canvas, click **Add Processor** (+)
2. Search for `PrepareRegulatoryFile`
3. You should see the processor with tags: xml, signature, encryption, xades, regulatory, dgoj, spain
4. Add the processor to the canvas
5. Right-click the processor → **Configure**
6. Verify **Properties** tab shows all properties listed below
7. Verify **Relationships** tab shows: success, failure, original

If properties or relationships are not showing, see Troubleshooting section below.

---

## Properties Reference

The processor supports two input modes for certificates and keys:
- **File path mode**: Non-sensitive properties for asset-based workflows
- **PEM content mode**: Sensitive properties for AWS Secrets Manager integration

For each credential type (certificate and private key), configure exactly one property.

### Certificate Properties (configure one)

| Property | Description | Sensitive | Expression Language |
|----------|-------------|-----------|---------------------|
| Certificate Path | File path to X.509 certificate (.pem/.crt) | No | Yes |
| Certificate | X.509 certificate as PEM content | Yes | Yes |

### Private Key Properties (configure one)

| Property | Description | Sensitive | Expression Language |
|----------|-------------|-----------|---------------------|
| Private Key Path | File path to private key (.pem) | No | Yes |
| Private Key | Private key as PEM content | Yes | Yes |

### Other Required Properties

| Property | Description | Sensitive | Expression Language | Default |
|----------|-------------|-----------|---------------------|---------|
| ZIP Encryption Password | 50-character password for AES-256 | Yes | Yes | - |
| Signature Method | 'enveloped' or 'enveloping' | No | No | enveloped |
| XML Filename | Filename for XML inside ZIP | No | Yes | enveloped.xml |

### Optional Properties

| Property | Description | Default | Sensitive |
|----------|-------------|---------|-----------|
| Private Key Password | Password for encrypted private key | (empty) | Yes |

**Note:** Properties support Expression Language for dynamic configuration (e.g., `#{DGOJ Cert Path}` parameter references).

---

## Configuration Workflows

### Workflow A: Asset-Based (File Paths)

Use this approach when certificates are stored as files in parameter context assets.

1. Upload certificate and key files as assets in your parameter context
2. Create non-sensitive parameters that reference the assets
3. Configure processor with path properties:
   - **Certificate Path**: `#{DGOJ Cert Path}`
   - **Private Key Path**: `#{DGOJ Private Key Path}`

### Workflow B: AWS Secrets Manager (PEM Content)

Use this approach when certificates are stored in AWS Secrets Manager.

1. Store the full PEM content (including `-----BEGIN CERTIFICATE-----` header) in your secret
2. Configure the External Parameter Provider to reference the secret
3. Create sensitive parameters in your parameter context
4. Configure processor with PEM properties:
   - **Certificate**: `#{DGOJ Cert}`
   - **Private Key**: `#{DGOJ Private Key}`

The processor normalizes PEM content to handle common formatting issues from secrets managers (escaped newlines, etc.).

---

## Relationships

**Input:** XML content in flowfile

**Output Relationships:**
- **success** → Signed, compressed, encrypted ZIP file
- **failure** → Original flowfile with `error.message` attribute
- **original** → Original unsigned content (typically auto-terminated)

---

## Dependencies

The processor declares these dependencies which OpenFlow installs from PyPI:

- `lxml` - XML processing
- `signxml` - XAdES-BES signature implementation
- `cryptography` - Cryptographic operations
- `pyzipper` - AES-256 ZIP encryption

Dependencies are NOT bundled in the NAR. OpenFlow downloads them from PyPI when the processor is first loaded.

**Requirements:**
- **OpenFlow BYOC:** Direct internet connectivity to PyPI (usually available by default)
- **OpenFlow SPCS:** External Access Integration configured for PyPI access (see below)

---

## Troubleshooting

### Processor Not Appearing After Upload

Verify NAR structure:
```bash
unzip -l custom_processors/PrepareRegulatoryFile/dist/prepare_regulatory_file-0.0.3.nar
```
Should show `prepare_regulatory_file/PrepareRegulatoryFile.py` and `META-INF/MANIFEST.MF`.

### Processor Properties or Relationships Not Showing

If properties or relationships are not visible in the Configure dialog, the processor failed to load properly.

**Common Cause - OpenFlow on SPCS:** Missing External Access Integration for PyPI.

**Symptoms:**
- Processor appears on canvas after upload
- No properties displayed in Configure dialog
- All properties show as `sensitive: true`
- OpenFlow Runtime logs show: "Failed to download dependencies for Python Processor"

**Solution:** Ensure the OpenFlow External Access Integration includes PyPI access:
```sql
-- Check with your OpenFlow administrator or see OpenFlow SPCS documentation
-- PyPI endpoints needed:
--   pypi.org:443
--   files.pythonhosted.org:443
```

**Other causes:**
- Syntax errors in `PrepareRegulatoryFile.py` (if modified)
- Invalid processor class structure
- Browser cache (try Ctrl+F5 / Cmd+F5)

### Dependency Installation

Dependencies install automatically on first use. Wait a few moments if you see temporary errors during initial processor load.

---

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

---

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

**Parameter Configuration (Asset-Based):**
- Certificate Path: `#{DGOJ Cert Path}` (references asset file)
- Private Key Path: `#{DGOJ Private Key Path}` (references asset file)
- Private Key Password: `#{DGOJ Private Key Password}`
- ZIP Encryption Password: `#{DGOJ Zip Password}`
- Signature Method: `enveloped`
- XML Filename: `enveloped.xml`

**Parameter Configuration (Secrets Manager):**
- Certificate: `#{DGOJ Cert}` (PEM content from secrets manager)
- Private Key: `#{DGOJ Private Key}` (PEM content from secrets manager)
- Private Key Password: `#{DGOJ Private Key Password}`
- ZIP Encryption Password: `#{DGOJ Zip Password}`
- Signature Method: `enveloped`
- XML Filename: `enveloped.xml`

---

## Credentials

See `../../credentials/README.md` for generating demo certificates and keys.

---

## Technical Details

### Requirements

- Python 3.11 or higher
- OpenFlow (Apache NiFi 2.5.0+)

### What This Processor Does

1. Reads XML from flowfile content
2. Signs with XAdES-BES 1.3.2 using provided certificate/key
3. Creates ZIP archive with Deflate compression
4. Encrypts ZIP with AES-256 (WinZip-compatible format)
5. Writes encrypted ZIP to flowfile content
6. Sets attributes: `mime.type=application/zip`, `dgoj.signed=true`, `dgoj.encrypted=true`
