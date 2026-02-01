# Building the Processor NAR

A pre-built NAR is included at `dist/prepare_regulatory_file-0.0.3.nar`. Only rebuild if you've modified the processor code.

## Prerequisites

```bash
pip install hatch hatch-datavolo-nar
```

## Build

```bash
cd custom_processors/PrepareRegulatoryFile
hatch build --target nar
```

Output: `dist/prepare_regulatory_file-0.0.3.nar` (~4KB)

The NAR contains only the processor code. Dependencies (lxml, signxml, cryptography, pyzipper) are installed by OpenFlow from PyPI when the processor is first loaded.

## Upload and Deployment

See [README.md](README.md) for upload instructions, troubleshooting, and SPCS considerations.
