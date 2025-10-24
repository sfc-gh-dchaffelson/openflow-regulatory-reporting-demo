# Custom Processor Setup

Build and deploy the PrepareRegulatoryFile custom processor to Snowflake OpenFlow.

---

## Overview

The PrepareRegulatoryFile processor is required because standard NiFi processors do not support:
- **XAdES-BES digital signature format** - Required by BOE-A-2024-12639 specifications
- **AES-256 encrypted ZIP files** - WinZip-compatible password-protected archives required by DGOJ

This custom processor handles the three critical security transformations:

1. **XAdES-BES 1.3.2 Digital Signature** with SHA-256 hash
2. **ZIP Compression** using Deflate algorithm
3. **AES-256 Encryption** with 50-character password

---

## Prerequisites

- Python 3.11 or higher
- `hatch` and `hatch-datavolo-nar` packages (for building from source)
- OpenFlow instance (Apache NiFi 2025.10.14+)
- Completed [02_CREDENTIALS_SETUP.md](02_CREDENTIALS_SETUP.md) to generate certificate and keys

---

## Option A: Use Pre-Built NAR (Recommended)

The NAR is already built and included in the repository:

```
custom_processors/PrepareRegulatoryFile/dist/prepare_regulatory_file-0.0.1.nar
```

File size: ~4KB (thin NAR containing only processor code)

Skip to **Upload NAR to OpenFlow** section below.

---

## Option B: Build from Source

If you've made changes to the processor code or want to rebuild:

### Install Build Tools

```bash
pip install hatch hatch-datavolo-nar
```

### Build NAR

```bash
cd custom_processors/PrepareRegulatoryFile
hatch build --target nar
```

Output: `dist/prepare_regulatory_file-0.0.1.nar` (~4KB)

**Note:** The NAR contains only the processor code. Dependencies (lxml, signxml, cryptography, pyzipper) are installed by OpenFlow from PyPI when the processor is first loaded.

---

## Upload NAR to OpenFlow

1. Open OpenFlow in web browser
2. Click main menu (Username) in top-right corner
3. Select **Controller Settings**
4. Navigate to **Local Extensions** tab
5. Click **Upload Extension** or drag-and-drop the NAR file
6. Select `custom_processors/PrepareRegulatoryFile/dist/prepare_regulatory_file-0.0.1.nar`
7. Click **Upload**
8. Installation takes a few seconds
9. You may need to manually refresh your browser

---

## Verify Installation

1. In OpenFlow canvas, click **Add Processor** (+)
2. Search for `PrepareRegulatoryFile`
3. You should see the processor with tags: xml, signature, encryption, xades, regulatory, dgoj, spain
4. Add the processor to the canvas
5. Right-click the processor → **Configure**
6. Verify **Properties** tab shows: Certificate Path, Private Key Path, Private Key Password, ZIP Encryption Password, Signature Method, XML Filename
7. Verify **Relationships** tab shows: success, failure, original

If properties or relationships are not showing, see Troubleshooting section below.

---

## Processor Properties Reference

| Property | Required | Sensitive | Default | Description |
|----------|----------|-----------|---------|-------------|
| Certificate Path | Yes | No | - | Path to X.509 certificate file |
| Private Key Path | Yes | No | - | Path to private key file |
| Private Key Password | No | Yes | - | Password for encrypted private key |
| ZIP Encryption Password | Yes | Yes | - | 50-char password for AES-256 |
| Signature Method | Yes | No | enveloped | enveloped or enveloping |
| XML Filename | Yes | No | enveloped.xml | Filename for XML inside ZIP |

**Note:** Properties support Expression Language for dynamic configuration (e.g., `#{DGOJ Cert}` parameter references).

---

## Processor Relationships

**Input:** XML content in flowfile

**Output Relationships:**
- **success** → Signed, compressed, encrypted ZIP file
- **failure** → Original flowfile with `error.message` attribute
- **original** → Original unsigned content (typically auto-terminated)

---

## Troubleshooting

### Processor Not Appearing After Upload

Verify NAR structure:
```bash
unzip -l custom_processors/PrepareRegulatoryFile/dist/prepare_regulatory_file-0.0.1.nar
```
Should show `prepare_regulatory_file/PrepareRegulatoryFile.py` and `META-INF/MANIFEST.MF`.

### Processor Properties or Relationships Not Showing

If properties or relationships are not visible in the Configure dialog, the processor failed to load properly.

**Common Cause - OpenFlow on SPCS:** Missing External Access Integration for PyPI.

**Symptoms:**
- Processor appears on canvas after upload
- No properties displayed in Configure dialog
- OpenFlow Runtime logs show: "Failed to download dependencies for Python Processor"

**Solution:** Configure External Access Integration for PyPI access. See [01_SNOWFLAKE_SETUP.md](01_SNOWFLAKE_SETUP.md) Step 1.

**Other causes:**
- Syntax errors in `PrepareRegulatoryFile.py` (if modified)
- Invalid processor class structure
- Browser cache (try Ctrl+F5 / Cmd+F5)

### Dependency Installation

When you first add the processor to canvas, OpenFlow installs dependencies from PyPI (lxml, signxml, cryptography, pyzipper).

**Requirements:**
- **OpenFlow BYOC:** Direct internet connectivity to PyPI (usually available by default)
- **OpenFlow SPCS:** External Access Integration configured for PyPI (see above)

Dependencies install automatically on first use. Wait a few moments if you see temporary errors during initial processor load

---

## What This Processor Does

1. Reads XML from flowfile content
2. Signs with XAdES-BES 1.3.2 using provided certificate/key
3. Creates ZIP archive with Deflate compression
4. Encrypts ZIP with AES-256 (WinZip-compatible format)
5. Writes encrypted ZIP to flowfile content
6. Sets attributes: `mime.type=application/zip`, `dgoj.signed=true`, `dgoj.encrypted=true`

---

## Next Step

Proceed to [05_OPENFLOW_SETUP.md](05_OPENFLOW_SETUP.md) to configure parameters and import the flow.
