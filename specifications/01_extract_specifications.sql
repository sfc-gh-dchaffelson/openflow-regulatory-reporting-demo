-- ============================================================================
-- BOE Gaming Report - Specification Extraction
-- ============================================================================
-- Extracts technical specifications from the BOE regulatory PDF using
-- Snowflake Document AI and Cortex LLM.
--
-- Prerequisites:
-- - SharePoint connector has replicated PDF to @DEDEMO.GAMING.DOCUMENTS
-- - Stage directory refreshed: ALTER STAGE DEDEMO.GAMING.DOCUMENTS REFRESH;
--
-- Output:
-- - DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED - Raw document text
-- - DEDEMO.GAMING.AI_OUTPUTS - Extracted specifications (JSON + markdown)
-- ============================================================================

USE DATABASE DEDEMO;
USE SCHEMA GAMING;

-- ============================================================================
-- Step 1: Verify SharePoint-Replicated PDF
-- ============================================================================
-- Refresh directory table and verify file exists

ALTER STAGE DEDEMO.GAMING.DOCUMENTS REFRESH;

SELECT RELATIVE_PATH, SIZE, LAST_MODIFIED 
FROM DIRECTORY(@DEDEMO.GAMING.DOCUMENTS)
WHERE RELATIVE_PATH LIKE '%BOE%';

-- ============================================================================
-- Step 2: Extract Text Using AI_PARSE_DOCUMENT
-- ============================================================================
-- Use LAYOUT mode for high-fidelity extraction with structure preservation
-- Note: TO_FILE uses RELATIVE_PATH from directory table (no prefix)

CREATE TABLE IF NOT EXISTS DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED (
    document_name VARCHAR(500),
    extracted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    page_count INT,
    full_content VARIANT
);

TRUNCATE TABLE DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED;

INSERT INTO DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED (document_name, page_count, full_content)
SELECT
    d.RELATIVE_PATH AS document_name,
    parsed_doc:metadata:pageCount::INT AS page_count,
    parsed_doc AS full_content
FROM DIRECTORY(@DEDEMO.GAMING.DOCUMENTS) d,
LATERAL (
    SELECT SNOWFLAKE.CORTEX.AI_PARSE_DOCUMENT(
        TO_FILE('@DEDEMO.GAMING.DOCUMENTS', d.RELATIVE_PATH),
        {'mode': 'LAYOUT'}
    ) AS parsed_doc
)
WHERE d.RELATIVE_PATH LIKE '%BOE%';

-- Verify extraction
SELECT document_name, page_count, extracted_at, LENGTH(full_content:content::STRING) AS content_chars
FROM DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED;

-- ============================================================================
-- Step 3: Create AI Outputs Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS DEDEMO.GAMING.AI_OUTPUTS (
    output_id INT AUTOINCREMENT,
    section_id VARCHAR(20),
    output_type VARCHAR(50),
    content VARCHAR(16777216),
    ai_model VARCHAR(100),
    generated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    content_length INT,
    is_complete BOOLEAN,
    parsed_json VARIANT
);

-- ============================================================================
-- Step 4: Extract Section 3 Specifications (Modelo de datos funcional)
-- ============================================================================

INSERT INTO DEDEMO.GAMING.AI_OUTPUTS (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '3',
    'json_extraction',
    'claude-sonnet-4-5',
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            SNOWFLAKE.CORTEX.COMPLETE(
                'claude-sonnet-4-5',
                [
                    {'role': 'system', 'content': 'You are a technical specification extraction expert. Output ONLY valid JSON without markdown formatting.'},
                    {'role': 'user', 'content': 'Read Section 3 "Modelo de datos funcional" from this Spanish gaming regulatory document.

Extract ALL technical specifications. Be comprehensive but CONCISE.

CONSTRAINTS:
- Output MUST be COMPLETE, VALID JSON
- Use compact arrays for enumerations: "codes": ["1:Cash", "2:Card", ...]
- Extract: Information types, record types, field definitions, validation rules, periodicities
- NO markdown code blocks, ONLY the JSON object

Extract in English.

Document: ' || full_content:content::STRING}
                ],
                {'max_tokens': 8192}
            ):choices[0]:messages::STRING,
            '^```json\\s*', ''
        ),
        '```$', ''
    ) AS content,
    LENGTH(content) AS content_length,
    TRUE AS is_complete
FROM DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED;

-- ============================================================================
-- Step 5: Extract Section 4 Specifications (Modelo técnico)
-- ============================================================================

INSERT INTO DEDEMO.GAMING.AI_OUTPUTS (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '4',
    'json_extraction',
    'claude-sonnet-4-5',
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            SNOWFLAKE.CORTEX.COMPLETE(
                'claude-sonnet-4-5',
                [
                    {'role': 'system', 'content': 'You are a technical specification extraction expert. Output ONLY valid JSON without markdown formatting.'},
                    {'role': 'user', 'content': 'Read Section 4 "Modelo técnico" from this Spanish gaming regulatory document.

Extract ALL technical specifications. Be comprehensive and systematic.

CONSTRAINTS:
- Output MUST be COMPLETE, VALID JSON
- Extract: Digital signatures, encryption, file naming, batch rules, algorithms, versions
- NO markdown code blocks, ONLY the JSON object

Extract in English.

Document: ' || full_content:content::STRING}
                ],
                {'max_tokens': 8192}
            ):choices[0]:messages::STRING,
            '^```json\\s*', ''
        ),
        '```$', ''
    ) AS content,
    LENGTH(content) AS content_length,
    TRUE AS is_complete
FROM DEDEMO.GAMING.BOE_DOCUMENT_EXTRACTED;

-- ============================================================================
-- Step 6: Validate JSON Outputs
-- ============================================================================

UPDATE DEDEMO.GAMING.AI_OUTPUTS
SET parsed_json = TRY_PARSE_JSON(content)
WHERE output_type = 'json_extraction';

SELECT output_id, section_id, content_length,
    CASE WHEN parsed_json IS NULL THEN 'INVALID JSON' ELSE 'VALID' END AS json_status
FROM DEDEMO.GAMING.AI_OUTPUTS
WHERE output_type = 'json_extraction';

-- ============================================================================
-- Step 7: Generate Markdown for Section 3
-- ============================================================================

INSERT INTO DEDEMO.GAMING.AI_OUTPUTS (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '3',
    'markdown_specs',
    'claude-sonnet-4-5',
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-sonnet-4-5',
        [
            {'role': 'system', 'content': 'You are a technical documentation expert. Create clear, formal specification documents.'},
            {'role': 'user', 'content': 'Convert these extracted specifications into a formal markdown document.

Structure:
- Title: "Data Model Specifications" 
- Organize by categories (Information Types, Record Types, Field Definitions, Validation Rules)
- Use clear section headers (##)
- Include all technical details

Specifications:
' || content}
        ],
        {'max_tokens': 8192}
    ):choices[0]:messages::STRING AS content,
    LENGTH(content) AS content_length,
    TRUE AS is_complete
FROM DEDEMO.GAMING.AI_OUTPUTS
WHERE section_id = '3' AND output_type = 'json_extraction' AND parsed_json IS NOT NULL;

-- ============================================================================
-- Step 8: Generate Markdown for Section 4
-- ============================================================================

INSERT INTO DEDEMO.GAMING.AI_OUTPUTS (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '4',
    'markdown_specs',
    'claude-sonnet-4-5',
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-sonnet-4-5',
        [
            {'role': 'system', 'content': 'You are a technical documentation expert. Create clear, formal specification documents.'},
            {'role': 'user', 'content': 'Convert these extracted specifications into a formal markdown document.

Structure:
- Title: "Technical Specifications"
- Organize by categories (Digital Signature, Encryption, File Naming, Batch Rules)
- Use clear section headers (##)
- Include all technical details

Specifications:
' || content}
        ],
        {'max_tokens': 8192}
    ):choices[0]:messages::STRING AS content,
    LENGTH(content) AS content_length,
    TRUE AS is_complete
FROM DEDEMO.GAMING.AI_OUTPUTS
WHERE section_id = '4' AND output_type = 'json_extraction' AND parsed_json IS NOT NULL;

-- ============================================================================
-- Step 9: View Results
-- ============================================================================

SELECT output_id, section_id, output_type, ai_model, content_length, generated_at
FROM DEDEMO.GAMING.AI_OUTPUTS
ORDER BY output_id;
