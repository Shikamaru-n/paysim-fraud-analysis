/*
===============================================================================
DDL Script: Create Silver Tables
===============================================================================
Script Purpose:
    This script creates tables in the 'silver' schema, dropping existing tables
    if they already exist.
	  Run this script to re-define the DDL structure of 'silver' Tables

    The silver table holds the same 6,362,620 rows as bronze. Nothing is deleted.
    Columns are renamed to snake_case, money is stored as DECIMAL, two time
    columns are derived from the step, and problem rows are marked with flags.
===============================================================================
*/

IF OBJECT_ID('silver.paysim_transactions', 'U') IS NOT NULL
    DROP TABLE silver.paysim_transactions;
GO

-- transaction_id: the source file has no id, so one is created at load time.
-- It numbers the rows in order of step, origin account and destination account.
-- That combination is unique in the data, so every reload gives each row the
-- same number.
--
-- day_number and hour_slot are derived from step. Each step is one hour.
--
-- transaction_type is the bronze column 'type', renamed so the name says what
-- kind of type it is.
--
-- The money columns are DECIMAL(18,2). Bronze holds them as FLOAT because some
-- source values are in scientific notation. Profiling confirmed no value has
-- more than 2 decimal places, so the cast rounds nothing.
--
-- The flag columns hold 1 for yes and 0 for no. They are TINYINT rather than BIT
-- so that SUM() works on them directly.
--
-- The four balance columns and the two balance mismatch flags are for profiling
-- and cleaning only. They must not be used in fraud detection rules, because
-- they leak the outcome.
CREATE TABLE silver.paysim_transactions (
    transaction_id                  INT,
    step                            INT,
    day_number                      INT,
    hour_slot                       INT,
    transaction_type                NVARCHAR(50),
    amount                          DECIMAL(18,2),
    origin_account                  NVARCHAR(50),
    origin_old_balance              DECIMAL(18,2),
    origin_new_balance              DECIMAL(18,2),
    destination_account             NVARCHAR(50),
    destination_old_balance         DECIMAL(18,2),
    destination_new_balance         DECIMAL(18,2),
    is_fraud                        TINYINT,
    is_flagged_fraud                TINYINT,
    is_merchant_destination         TINYINT,
    is_zero_amount                  TINYINT,
    is_origin_balance_mismatch      TINYINT,
    is_destination_balance_mismatch TINYINT,
    dwh_create_date                 DATETIME2 DEFAULT GETDATE()
);
GO
