-- BOE Gaming Demo - Database and Schema
-- ============================================================================
-- Creates the DEDEMO database and GAMING schema.
-- Requires: ACCOUNTADMIN role (or role with CREATE DATABASE privilege)
-- Run after: 00_set_variables.sql
-- ============================================================================

USE ROLE IDENTIFIER($ADMIN_ROLE);

-- Create database
CREATE DATABASE IF NOT EXISTS DEDEMO
    COMMENT = 'BOE Gaming regulatory compliance demo';

-- Create processing schema
CREATE SCHEMA IF NOT EXISTS DEDEMO.GAMING
    COMMENT = 'Processing objects for regulatory pipeline';

-- Verify
SELECT 'Database and schema created' AS status;
SHOW SCHEMAS IN DATABASE DEDEMO;
