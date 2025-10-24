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

## Upload to OpenFlow

1. Open OpenFlow in web browser
2. Click main menu in top-right corner (your username)
3. Select **Controller Settings**
4. Navigate to **Local Extensions** tab
5. Upload `dist/prepare_regulatory_file-0.0.1.nar`
6. Installation takes a few seconds
7. You may need to manually refresh your browser

See [PROCESSOR_SETUP.md](../../PROCESSOR_SETUP.md) for complete deployment instructions.
