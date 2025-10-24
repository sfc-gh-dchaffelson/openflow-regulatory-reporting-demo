# Complete Technical Specifications

**Document:** BOE-A-2024-12639 - Modelo de datos del sistema de monitorización de la información
**Source:** Spanish Gaming Regulatory Requirements (DGOJ)
**Extraction Method:** Snowflake Document AI + Cortex AI (Claude Sonnet 4.5)
**Extraction Date:** October 20, 2025
**Version:** 3.3 (Based on RD 176/2023)

---

## Document Structure

This document contains the complete technical specifications extracted from BOE-A-2024-12639, organized into two major parts:

1. **Part A: Data Model Specifications** (Section 3) - Information types, register definitions, field specifications, validation rules
2. **Part B: Technical Specifications** (Section 4) - Digital signatures, encryption, file naming, batch rules, directory structure

Both parts are essential for implementing compliant gaming regulatory reporting systems.

---

# PART A: DATA MODEL SPECIFICATIONS

**Source:** Section 3 - Functional Data Model (Modelo de datos funcional)

This section defines the functional data model including:
- Information types and reporting frequencies
- Register type specifications
- Field definitions and validation rules
- Operator reporting obligations

For complete details, see: [`specifications/02a_DATA_MODEL.md`](02a_DATA_MODEL.md)

## Summary of Information Types

| Type | Description | Periodicity | Demo Implemented |
|------|-------------|-------------|------------------|
| **RU** | User Registration (RUD, RUR, RUG, RUT) | Daily, Monthly | ❌ No |
| **CJ** | Gaming Account (CJD, CJT) | Daily, Monthly | ❌ No |
| **OP** | Operator Account (OPT, ORT, BOT) | Monthly | ❌ No |
| **JUC** | Gaming Records (Real-time) | Real-time | ✅ **Yes** (POT only) |
| **JUA** | Betting Adjustments | Monthly | ❌ No |
| **CEV** | Event Catalog | Daily, Monthly | ❌ No |

## Summary of Game Types (for JUC)

The specification defines 12+ game types. The demo implements:
- **POT** - Poker Tournament ✅ Implemented

Other game types include: ADC, AHC, POC, BLA, BNG, RUL, APD, APS, LOT, RAP, RUV, SES, RAC, RAM, COC, LOP

---

# PART B: TECHNICAL SPECIFICATIONS

**Source:** Section 4 - Technical Model (Modelo técnico)

This section defines the technical implementation requirements including:
- Data structure (registers, subregisters, batches)
- Digital signature requirements (XAdES-BES 1.3.2)
- Encryption and compression (AES-256, Deflate)
- File naming conventions
- Directory structure
- Batch generation rules
- Data retention requirements

For complete details, see: [`specifications/02b_TECHNICAL_SPECS.md`](02b_TECHNICAL_SPECS.md)

## Critical Technical Requirements (100% Compliance Required)

| Requirement | Specification | Demo Status |
|-------------|---------------|-------------|
| **Digital Signature** | XAdES-BES 1.3.2, SHA-256 | ✅ Fully Compliant |
| **Encryption** | AES-256 (WinZip-compatible) | ✅ Fully Compliant |
| **Compression** | Deflate | ✅ Fully Compliant |
| **Password** | 50 chars, mixed types | ✅ Fully Compliant |
| **File Naming** | `<Operator>_<Storage>_JU_JUC_<Game>_<DateTime>_<ID>.zip` | ✅ Fully Compliant |
| **Directory Structure** | `CNJ/<Operator>/JU/<YYYYMMDD>/<GameType>/` | ✅ Fully Compliant |
| **Batch Rules (Real-time)** | 15 min OR 500 subrecords (Priority 1) | ✅ Fully Compliant |
| **Batch Fragmentation** | New batch after 10 subrecords | ⚠️ Simplified (no multi-batch) |
| **XSD Validation** | http://cnjuego.gob.es/sci/v3.3.xsd | ✅ Fully Compliant |
| **Data Retention** | 4 years total, 12 months online | ❌ Not Implemented (out of scope) |

---

## Key Technical Highlights

### Digital Signature Methods
1. **Enveloped** - Signature embedded in XML (Demo uses this)
2. **Enveloping Manifest** - Separate signature file optimized for signing

### Batch Generation Rules

**Real-time Information (JUC):**
- **Priority 1:** 15 minutes OR 500 subrecords (whichever first)
- **Priority 2:** 24 hours OR 5,000 subrecords
- **Priority 3:** 48 hours OR 10,000 subrecords

**Periodic Information (RU, CJ, OP, JUA, CEV):**
- **Fragmentation:** New batch after 10 subrecords
- **Frequency:** Daily or Monthly depending on type

### File Naming Patterns

Different patterns based on information type and periodicity:

| Periodicity | Pattern Example |
|-------------|-----------------|
| Real-time | `OP01_ALM01_JU_JUC_POT_YYYYMMDDHHMMSS_ID.zip` |
| Daily | `OP01_ALM01_RU_RUD_YYYYMMDD_ID.zip` |
| Monthly | `OP01_ALM01_CJ_CJT_YYYYMM_ID.zip` |

---

## Implementation Notes

**What This Demo Proves:**
- ✅ Snowflake AI can extract specifications from complex regulatory PDFs
- ✅ All critical technical requirements can be implemented correctly
- ✅ Real-time reporting pipeline works end-to-end (data → Snowflake → OpenFlow → SFTP)
- ✅ XAdES-BES signing, AES-256 encryption, XSD validation all function correctly

**Demo Scope Limitations:**
- Implements 1 information type (JUC) out of 6 types
- Implements 1 game type (POT) out of 12+ types
- Real-time periodicity only (no daily/monthly batches)
- Simplified XML structure (minimal valid fields)

**For Production:**
- Expand to all required information types per operator obligations
- Implement all game types relevant to operator license
- Add daily and monthly batch generation
- Complete field set per DGOJ XSD schema
- Implement data retention policies
- Add monitoring and alerting for compliance

---

## Related Documents

- **Full Data Model:** [`specifications/02a_DATA_MODEL.md`](02a_DATA_MODEL.md) - Complete Section 3 specifications
- **Full Technical Specs:** [`specifications/02b_TECHNICAL_SPECS.md`](02b_TECHNICAL_SPECS.md) - Complete Section 4 specifications
- **Demo Specifications:** [`specifications/04_DEMO_SPECIFICATIONS.md`](04_DEMO_SPECIFICATIONS.md) - Simplified scope for proof-of-concept
- **Compliance Analysis:** [`specifications/05_COMPLIANCE.md`](05_COMPLIANCE.md) - Detailed comparison of full vs demo implementation
- **Extraction Process:** [`specifications/01_extract_specifications.sql`](01_extract_specifications.sql) - Snowflake AI extraction workflow
- **Quality Assessment:** [`specifications/03_EXTRACTION_ASSESSMENT.md`](03_EXTRACTION_ASSESSMENT.md) - AI extraction validation

---

**Last Updated:** October 20, 2025
