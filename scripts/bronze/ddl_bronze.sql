/*
===============================================================================
DDL Script: Create Bronze Tables
===============================================================================
Script Purpose:
    This script creates tables in the 'bronze' schema, dropping existing tables
    if they already exist.
	  Run this script to re-define the DDL structure of 'bronze' Tables

    The table mirrors the PaySim CSV exactly: same 11 columns, same order, same
    column names. Nothing is cleaned or renamed here. That happens in silver.
===============================================================================
*/

IF OBJECT_ID('bronze.paysim_transactions', 'U') IS NOT NULL
    DROP TABLE bronze.paysim_transactions;
GO

-- Column names are kept exactly as they appear in the CSV header, camel case and all,
-- so a reader can line this table up against the source file column by column. The
-- snake_case renaming happens in silver.
--
-- The five money columns are FLOAT rather than DECIMAL on purpose. About 4.1% of rows
-- write their amounts in scientific notation (for example 1.916920493E7), which
-- BULK INSERT cannot parse into a DECIMAL column. Silver casts these to DECIMAL(18,2).
-- A file scan confirmed no value anywhere uses more than 2 decimal places, so that
-- cast rounds nothing. See docs/maxerrors_note.md.
--
-- isFraud and isFlaggedFraud hold 0 or 1 but are INT here, because converting them to
-- BIT would be a type decision, and type decisions belong in silver.
CREATE TABLE bronze.paysim_transactions (
    step            INT,
    type            NVARCHAR(50),
    amount          FLOAT,
    nameOrig        NVARCHAR(50),
    oldbalanceOrg   FLOAT,
    newbalanceOrig  FLOAT,
    nameDest        NVARCHAR(50),
    oldbalanceDest  FLOAT,
    newbalanceDest  FLOAT,
    isFraud         INT,
    isFlaggedFraud  INT
);
GO
