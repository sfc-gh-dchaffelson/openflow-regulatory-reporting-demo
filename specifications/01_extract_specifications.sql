-- ============================================================================
-- BOE Gaming Report - Snowflake Document AI Specification Extraction
-- ============================================================================
-- This file demonstrates Snowflake's Document AI and Cortex AI capabilities
-- to extract and process technical specifications from the Spanish gaming
-- regulatory PDF (BOE-A-2024-12639).
--
-- Workflow:
-- 1. Upload PDF to Snowflake stage
-- 2. Extract text with AI_PARSE_DOCUMENT (LAYOUT mode)
-- 3. Extract specifications with CORTEX.COMPLETE (Claude Sonnet 4.5)
-- 4. Validate JSON output and generate markdown documentation
--
-- This extraction process produces the specifications that guide the demo
-- implementation in this project.
-- ============================================================================

-- ============================================================================
-- Step 1: Create Database and Schema (if needed)
-- ============================================================================
-- These commands allow this file to be run standalone before the full demo setup.
-- The IF NOT EXISTS clauses ensure no errors if you've already run setup/01_snowflake_setup.sql

CREATE DATABASE IF NOT EXISTS BOEGAMINGREPORT
    COMMENT = 'BOE Gaming Regulatory Reporting - Proof of Concept';

CREATE SCHEMA IF NOT EXISTS BOEGAMINGREPORT.DEMO
    COMMENT = 'Demo implementation of Spanish gaming regulation BOE-A-2024-12639';

USE DATABASE BOEGAMINGREPORT;
USE SCHEMA DEMO;

SELECT CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_ROLE();

-- ============================================================================
-- Step 2: Create Stage (if needed)
-- ============================================================================
-- Create the stage for Document AI processing with required server-side encryption.
-- The IF NOT EXISTS clause ensures no errors if you've already run setup/01_snowflake_setup.sql

CREATE STAGE IF NOT EXISTS BOEGAMINGREPORT.DEMO.boe_documents
    DIRECTORY = (ENABLE = true)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Stage for BOE regulatory documents and Document AI processing';

-- Verify the stage was created
SHOW STAGES IN BOEGAMINGREPORT.DEMO;

-- ============================================================================
-- Step 3: Upload PDF to Stage
-- ============================================================================
-- Upload the BOE-A-2024-12639.pdf file to the stage
--
-- IMPORTANT: This PUT command uses a relative path and must be run from the project root directory.
--
-- If running via snow sql:
--   cd /path/to/BoeGamingReport  # Change to project root first
--   snow sql -f specifications/01_extract_specifications.sql
--
-- Or run the PUT command separately from the project root:
PUT file://source_documents/BOE-A-2024-12639.pdf @BOEGAMINGREPORT.DEMO.boe_documents AUTO_COMPRESS=FALSE;

-- Verify the file was uploaded
LIST @BOEGAMINGREPORT.DEMO.boe_documents;

-- ============================================================================
-- Step 4: Extract Text Using Document AI
-- ============================================================================
-- Use Snowflake's AI_PARSE_DOCUMENT function to extract text from the PDF
-- Reference: https://docs.snowflake.com/en/user-guide/snowflake-cortex/parse-document
-- Using LAYOUT mode for high-fidelity extraction with structure preservation

-- Create a table to store the extracted document
CREATE OR REPLACE TABLE BOEGAMINGREPORT.DEMO.boe_document_extracted (
    document_name VARCHAR(500),
    extracted_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    page_count INT,
    full_content VARIANT
);

-- Extract and store the document content
INSERT INTO BOEGAMINGREPORT.DEMO.boe_document_extracted (document_name, page_count, full_content)
SELECT
    'BOE-A-2024-12639.pdf' AS document_name,
    parsed_doc:metadata:pageCount::INT AS page_count,
    parsed_doc AS full_content
FROM (
    SELECT SNOWFLAKE.CORTEX.AI_PARSE_DOCUMENT(
        TO_FILE('@BOEGAMINGREPORT.DEMO.boe_documents', 'BOE-A-2024-12639.pdf'),
        {'mode': 'LAYOUT'}
    ) AS parsed_doc
);

-- Verify the extraction
SELECT document_name, page_count, extracted_at
FROM BOEGAMINGREPORT.DEMO.boe_document_extracted;

-- ============================================================================
-- Step 5: Verify Document Structure and Length
-- ============================================================================
-- Before extracting specifications, verify the document structure
-- Document has 167K characters and uses markdown section headers

SELECT
    LENGTH(full_content:content::STRING) AS total_characters,
    page_count,
    LEFT(full_content:content::STRING, 1000) AS content_sample
FROM
    BOEGAMINGREPORT.DEMO.boe_document_extracted;

-- ============================================================================
-- Step 6: SYSTEMATIC Specification Extraction by Document Section
-- ============================================================================
-- Strategy: Extract ALL technical specifications systematically and comprehensively
-- 1. Process major document sections (Section 3: Data Model, Section 4: Technical Model)
-- 2. Let Claude discover ALL specifications without pre-defining what to find
-- 3. Store results in unified table for validation and markdown generation
--
-- Approach: Given 200K token context and 167K char document (~42K tokens),
-- we can process entire major sections at once rather than breaking into
-- prescriptive subsections, however Cortex has an 8k token limit, so we need to
-- break down the sections into smaller chunks to get the full specifications.
--
-- STRATEGY TO PREVENT TRUNCATION:
-- Explicitly instruct Claude about the 8192 token output limit and require
-- COMPLETE, VALID JSON output. For Section 3, use compact array format for
-- enumerations to fit within token limits while maintaining completeness.

-- Create unified table for all AI outputs
-- Store both JSON extractions and markdown generations in one place
CREATE OR REPLACE TABLE BOEGAMINGREPORT.DEMO.ai_outputs (
    output_id INT AUTOINCREMENT,
    section_id VARCHAR(20),
    output_type VARCHAR(50),        -- 'json_extraction' or 'markdown_specs'
    content VARCHAR(16777216),      -- Holds both JSON and markdown
    ai_model VARCHAR(100),
    generated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    content_length INT,
    is_complete BOOLEAN,            -- Check if output is truncated
    parsed_json VARIANT             -- Only populated for JSON extractions
);

-- ============================================================================
-- Step 7: Extract ALL Specifications from Section 3 (Modelo de datos funcional)
-- ============================================================================
-- Extract without pre-defining what to look for - let Claude discover everything
-- Use compact format for enumerations to stay within token limits

INSERT INTO BOEGAMINGREPORT.DEMO.ai_outputs (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '3',
    'json_extraction',
    'claude-sonnet-4-5',
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            SNOWFLAKE.CORTEX.COMPLETE(
                'claude-sonnet-4-5',
                [
                    {
                        'role': 'system',
                        'content': 'You are a technical specification extraction expert. Output ONLY valid JSON without markdown formatting.'
                    },
                    {
                        'role': 'user',
                        'content': 'Read Section 3 "Modelo de datos funcional" from this Spanish gaming regulatory document.

Extract ALL technical specifications you find. Be comprehensive but EXTREMELY CONCISE.

CRITICAL CONSTRAINTS:
- You have exactly 8000 tokens for output
- Output MUST be COMPLETE, VALID JSON (no truncation)
- For enumerations (codes, types, etc.): Use compact arrays, not verbose objects
- Example efficient format: "payment_methods": ["1:Cash", "2:Prepaid", "3:BankTransfer", ...]
- Prioritize: Information types, record types, field definitions, validation rules, periodicities
- Use abbreviations where clear
- NO markdown code blocks, NO explanations, ONLY the JSON object

Extract specifications in English.

Full document text: ' || full_content:content::STRING
                    }
                ],
                {
                    'max_tokens': 8192
                }
            ):choices[0]:messages::STRING,
            '^```json\\s*', ''
        ),
        '```$', ''
    ) AS content,
    LENGTH(content) AS content_length,
    NOT CONTAINS(content, '}
}') AS is_complete  -- Basic completeness check
FROM BOEGAMINGREPORT.DEMO.boe_document_extracted;

-- ============================================================================
-- Step 8: Extract ALL Specifications from Section 4 (Modelo técnico)
-- ============================================================================
-- Extract without pre-defining what to look for - let Claude discover everything
-- Store raw output first to handle potential truncation

INSERT INTO BOEGAMINGREPORT.DEMO.ai_outputs (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '4',
    'json_extraction',
    'claude-sonnet-4-5',
    REGEXP_REPLACE(
        REGEXP_REPLACE(
            SNOWFLAKE.CORTEX.COMPLETE(
                'claude-sonnet-4-5',
                [
                    {
                        'role': 'system',
                        'content': 'You are a technical specification extraction expert. Output ONLY valid JSON without markdown formatting.'
                    },
                    {
                        'role': 'user',
                        'content': 'Read Section 4 "Modelo técnico" from this Spanish gaming regulatory document.

Extract ALL technical specifications you find. Be comprehensive and systematic.

CRITICAL CONSTRAINTS:
- You have an 8000 token budget for your response
- Output must be COMPLETE, VALID JSON (not truncated)
- Organize specifications by the topics/categories you discover in the document
- Be concise but precise - extract exact values, algorithms, versions, patterns, rules
- Use efficient JSON structure (arrays, nested objects)
- NO markdown code blocks, NO explanations, ONLY the JSON object

Extract specifications in English.

Full document text: ' || full_content:content::STRING
                    }
                ],
                {
                    'max_tokens': 8192
                }
            ):choices[0]:messages::STRING,
            '^```json\\s*', ''
        ),
        '```$', ''
    ) AS content,
    LENGTH(content) AS content_length,
    NOT CONTAINS(content, '}
}') AS is_complete  -- Check if JSON is complete
FROM BOEGAMINGREPORT.DEMO.boe_document_extracted;

-- ============================================================================
-- Step 9: Inspect Extraction Outputs
-- ============================================================================
-- Check if outputs are complete and inspect quality

SELECT
    output_id,
    section_id,
    output_type,
    ai_model,
    generated_at,
    content_length,
    is_complete,
    LEFT(content, 500) AS content_start,
    RIGHT(content, 200) AS content_end
FROM BOEGAMINGREPORT.DEMO.ai_outputs
WHERE output_type = 'json_extraction'
ORDER BY section_id;

-- ============================================================================
-- Step 10: Parse and Validate JSON Outputs
-- ============================================================================
-- Parse the JSON extractions into VARIANT for querying
-- Check for truncation indicators and JSON validity

UPDATE BOEGAMINGREPORT.DEMO.ai_outputs
SET parsed_json = TRY_PARSE_JSON(content)
WHERE output_type = 'json_extraction';

-- Comprehensive validation check
SELECT
    output_id,
    section_id,
    ai_model,
    generated_at,
    content_length,
    CASE
        WHEN parsed_json IS NULL THEN '❌ Invalid JSON - Re-run extraction'
        WHEN CONTAINS(LOWER(content), 'truncat') THEN '❌ Truncation detected - Re-run with compact format'
        WHEN CONTAINS(LOWER(content), '[truncated]') THEN '❌ Explicit truncation - Re-run'
        WHEN CONTAINS(LOWER(content), '[incomplete]') THEN '❌ Marked incomplete - Re-run'
        WHEN CONTAINS(content, '...') THEN '⚠️  Valid but abbreviated (ellipsis)'
        ELSE '✅ Valid and Complete'
    END AS validation_status,
    -- Check for common truncation patterns at end of content
    CASE
        WHEN CONTAINS(LOWER(RIGHT(content, 100)), 'truncat') THEN 'Warning: Truncation text at end'
        WHEN RTRIM(content, ' \t\n\r') NOT LIKE '%}' THEN 'Warning: No closing brace'
        ELSE 'OK'
    END AS end_check,
    LEFT(content, 200) AS preview,
    RIGHT(content, 100) AS ending
FROM BOEGAMINGREPORT.DEMO.ai_outputs
WHERE output_type = 'json_extraction'
ORDER BY section_id;

-- ============================================================================
-- Step 11: View All AI Outputs Summary
-- ============================================================================
-- Review the extraction results before generating markdown

SELECT
    output_id,
    section_id,
    output_type,
    ai_model,
    generated_at,
    content_length,
    is_complete,
    CASE WHEN parsed_json IS NULL THEN 'Invalid/N-A' ELSE 'Valid JSON' END AS json_status
FROM BOEGAMINGREPORT.DEMO.ai_outputs
WHERE output_type = 'json_extraction'
ORDER BY section_id;

-- ============================================================================
-- Step 12a: Generate Markdown for Section 3 (Data Model)
-- ============================================================================
-- Convert Section 3 JSON into formal markdown documentation
-- Store in same table with output_type = 'markdown_specs'
--
-- NOTE: Only run this after verifying Section 3 JSON is valid (Step 11)

INSERT INTO BOEGAMINGREPORT.DEMO.ai_outputs (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '3',
    'markdown_specs',
    'claude-sonnet-4-5',
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-sonnet-4-5',
        [
            {
                'role': 'system',
                'content': 'You are a technical documentation expert. Create clear, formal specification documents.'
            },
            {
                'role': 'user',
                'content': 'Convert these extracted technical specifications from JSON into a formal markdown document.

Structure:
- You have an 8000 token budget for your response
- Start with document header (title: "Data Model Specifications", source: Section 3, extraction date)
- Organize by major categories (Information Types, Register Types, Field Definitions, Validation Rules, etc.)
- Use clear section headers (##)
- Include all technical details (codes, field names, types, validation rules, periodicities)
- Format for clarity and professional documentation
- NO markdown code blocks in output, just clean markdown text

Extracted specifications from Section 3 (Functional Data Model):
' || content || '

Create the markdown document now:'
            }
        ],
        {
            'max_tokens': 8192
        }
    ):choices[0]:messages::STRING AS content,
    LENGTH(content) AS content_length,
    TRUE AS is_complete
FROM BOEGAMINGREPORT.DEMO.ai_outputs
WHERE section_id = '3' AND output_type = 'json_extraction' AND parsed_json IS NOT NULL;

-- ============================================================================
-- Step 12b: Generate Markdown for Section 4 (Technical Model)
-- ============================================================================
-- Convert Section 4 JSON into formal markdown documentation
--
-- NOTE: Only run this after verifying Section 4 JSON is valid (Step 11)

INSERT INTO BOEGAMINGREPORT.DEMO.ai_outputs (section_id, output_type, ai_model, content, content_length, is_complete)
SELECT
    '4',
    'markdown_specs',
    'claude-sonnet-4-5',
    SNOWFLAKE.CORTEX.COMPLETE(
        'claude-sonnet-4-5',
        [
            {
                'role': 'system',
                'content': 'You are a technical documentation expert. Create clear, formal specification documents.'
            },
            {
                'role': 'user',
                'content': 'Convert these extracted technical specifications from JSON into a formal markdown document.

Structure:
- You have an 8000 token budget for your response
- Start with document header (title: "Technical Specifications", source: Section 4, extraction date)
- Organize by major categories (Digital Signature, Encryption, File Naming, Batch Rules, etc.)
- Use clear section headers (##)
- Include all technical details (algorithms, versions, exact formats, patterns, rules)
- Format for clarity and professional documentation
- NO markdown code blocks in output, just clean markdown text

Extracted specifications from Section 4 (Technical Model):
' || content || '

Create the markdown document now:'
            }
        ],
        {
            'max_tokens': 8192
        }
    ):choices[0]:messages::STRING AS content,
    LENGTH(content) AS content_length,
    TRUE AS is_complete
FROM BOEGAMINGREPORT.DEMO.ai_outputs
WHERE section_id = '4' AND output_type = 'json_extraction' AND parsed_json IS NOT NULL;

-- ============================================================================
-- Step 13: View Final Outputs
-- ============================================================================

SELECT
    output_id,
    section_id,
    output_type,
    ai_model,
    content_length,
    LEFT(content, 200) AS preview
FROM BOEGAMINGREPORT.DEMO.ai_outputs
ORDER BY output_id;

-- ============================================================================
-- Step 14: Check for Other Relevant Sections (Optional)
-- ============================================================================
-- Review the full document to see if there are other sections with specifications
-- This query shows a sample to help identify if we've missed important sections

SELECT
    LEFT(full_content:content::STRING, 3000) AS document_start,
    LENGTH(full_content:content::STRING) AS total_length
FROM BOEGAMINGREPORT.DEMO.boe_document_extracted;

-- If you identify other relevant sections (e.g., Section 2, Section 5, Annexes),
-- add additional extraction steps following the pattern in Steps 7-8.

-- ============================================================================
-- Step 15: Download Markdown Specifications to Local Files
-- ============================================================================
-- To save the markdown specifications to local files, run these commands from
-- terminal (from project root):

-- Download Section 3 (Data Model) specifications:
-- snow sql -q "SELECT content FROM BOEGAMINGREPORT.DEMO.ai_outputs WHERE section_id = '3' AND output_type = 'markdown_specs' ORDER BY output_id DESC LIMIT 1;" > specifications/02a_DATA_MODEL.md

-- Download Section 4 (Technical Model) specifications:
-- snow sql -q "SELECT content FROM BOEGAMINGREPORT.DEMO.ai_outputs WHERE section_id = '4' AND output_type = 'markdown_specs' ORDER BY output_id DESC LIMIT 1;" > specifications/02b_TECHNICAL_SPECS.md

-- Then clean up any Snowflake formatting from the output files to get clean markdown.
-- These combined specifications guide the demo implementation.
