# Building the Processor NAR

## Prerequisites

```bash
pip install hatch hatch-datavolo-nar
```

## Build

```bash
cd custom_processors/PrepareRegulatoryFile
hatch build --target nar
```

Output: `dist/prepare_regulatory_file-0.0.1.nar` (~4KB)

The NAR contains only the processor code. Dependencies (lxml, signxml, cryptography, pyzipper) are installed by OpenFlow from PyPI when the processor is first loaded.

## OpenFlow on SPCS: External Access Integration Required

If deploying to OpenFlow on Snowpark Container Services (SPCS), you must configure an External Access Integration for PyPI access. Without this, the processor will load onto the canvas but will not show properties, and OpenFlow Runtime logs will show "Failed to download dependencies for Python Processor".

See [01_SNOWFLAKE_SETUP.md](../../setup/01_SNOWFLAKE_SETUP.md) for External Access Integration setup.

## Upload to OpenFlow

1. Open OpenFlow in web browser
2. Click main menu in top-right corner (your username)
3. Select **Controller Settings**
4. Navigate to **Local Extensions** tab
5. Upload `dist/prepare_regulatory_file-0.0.1.nar`
6. Installation takes a few seconds
7. You may need to manually refresh your browser

See [PROCESSOR_SETUP.md](../../PROCESSOR_SETUP.md) for complete deployment instructions.
