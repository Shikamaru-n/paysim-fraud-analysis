/*
===============================================================================
Data Profiling: Bronze Layer
===============================================================================
Script Purpose:
    This script profiles the raw PaySim data in 'bronze.paysim_transactions'
    before any cleaning is done. It answers:
    - How big is the table and are there NULLs or duplicates?
    - What values do the text columns hold?
    - How rare is fraud, and how well does the existing flag catch it?
    - How are amounts distributed?
    - How are fraud and normal transactions spread across the 31 days?
      (This decides the build and test cutoff for the detection rule.)
    - Do the balance columns add up?

Usage Notes:
    - Run this script after loading the Bronze Layer.
    - Nothing is changed here. Every query is a SELECT.
    - The findings decide what the Silver Layer has to clean and flag.
    - The balance columns are profiled here, but they must not be used in
      fraud detection rules, because they leak the outcome.
    - This is synthetic data.
===============================================================================
*/

-- ====================================================================
-- 1. Size and Shape
-- ====================================================================
-- Row count and step range
-- Expectation: 6,362,620 rows, steps 1 to 743 with none missing
SELECT
    COUNT(*)             AS total_rows,
    MIN(step)            AS min_step,
    MAX(step)            AS max_step,
    COUNT(DISTINCT step) AS distinct_steps
FROM bronze.paysim_transactions;

-- Check for NULLs in every column
-- Expectation: all zeros
SELECT
    SUM(CASE WHEN step           IS NULL THEN 1 ELSE 0 END) AS null_step,
    SUM(CASE WHEN type           IS NULL THEN 1 ELSE 0 END) AS null_type,
    SUM(CASE WHEN amount         IS NULL THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN nameOrig       IS NULL THEN 1 ELSE 0 END) AS null_nameOrig,
    SUM(CASE WHEN oldbalanceOrg  IS NULL THEN 1 ELSE 0 END) AS null_oldbalanceOrg,
    SUM(CASE WHEN newbalanceOrig IS NULL THEN 1 ELSE 0 END) AS null_newbalanceOrig,
    SUM(CASE WHEN nameDest       IS NULL THEN 1 ELSE 0 END) AS null_nameDest,
    SUM(CASE WHEN oldbalanceDest IS NULL THEN 1 ELSE 0 END) AS null_oldbalanceDest,
    SUM(CASE WHEN newbalanceDest IS NULL THEN 1 ELSE 0 END) AS null_newbalanceDest,
    SUM(CASE WHEN isFraud        IS NULL THEN 1 ELSE 0 END) AS null_isFraud,
    SUM(CASE WHEN isFlaggedFraud IS NULL THEN 1 ELSE 0 END) AS null_isFlaggedFraud
FROM bronze.paysim_transactions;

-- Check for fully duplicated rows
-- The file has no transaction id, so a duplicate means all 11 columns match.
-- Expectation: No Results
SELECT
    step, type, amount, nameOrig, oldbalanceOrg, newbalanceOrig,
    nameDest, oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud,
    COUNT(*) AS copies
FROM bronze.paysim_transactions
GROUP BY
    step, type, amount, nameOrig, oldbalanceOrg, newbalanceOrig,
    nameDest, oldbalanceDest, newbalanceDest, isFraud, isFlaggedFraud
HAVING COUNT(*) > 1;

-- ====================================================================
-- 2. Text Columns
-- ====================================================================
-- Check for Unwanted Spaces
-- Expectation: No Results
SELECT
    type, nameOrig, nameDest
FROM bronze.paysim_transactions
WHERE type     != TRIM(type)
   OR nameOrig != TRIM(nameOrig)
   OR nameDest != TRIM(nameDest);

-- Data Standardization & Consistency: transaction types
SELECT
    type,
    COUNT(*) AS total_rows,
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_rows
FROM bronze.paysim_transactions
GROUP BY type
ORDER BY total_rows DESC;

-- Account name format: first letter and length
-- 'C' is a customer and 'M' is a merchant.
-- Expectation: origin is always 'C', destination is 'C' or 'M'
SELECT
    LEFT(nameOrig, 1) AS orig_prefix,
    MIN(LEN(nameOrig)) AS min_length,
    MAX(LEN(nameOrig)) AS max_length,
    COUNT(*)           AS total_rows
FROM bronze.paysim_transactions
GROUP BY LEFT(nameOrig, 1);

SELECT
    LEFT(nameDest, 1) AS dest_prefix,
    MIN(LEN(nameDest)) AS min_length,
    MAX(LEN(nameDest)) AS max_length,
    COUNT(*)           AS total_rows
FROM bronze.paysim_transactions
GROUP BY LEFT(nameDest, 1);

-- Which transaction types go to merchants, and is any of it fraud?
SELECT
    type,
    LEFT(nameDest, 1) AS dest_prefix,
    COUNT(*)          AS total_rows,
    SUM(isFraud)      AS fraud_rows
FROM bronze.paysim_transactions
GROUP BY type, LEFT(nameDest, 1)
ORDER BY type, dest_prefix;

-- How many different accounts are there?
-- If distinct origins is close to the row count, most customers send only once,
-- so rules based on a customer's sending history will have little to work with.
SELECT
    COUNT(DISTINCT nameOrig) AS distinct_origins,
    COUNT(DISTINCT nameDest) AS distinct_destinations
FROM bronze.paysim_transactions;

-- ====================================================================
-- 3. Fraud Flags
-- ====================================================================
-- Check the flag columns only hold 0 or 1, and how they overlap
-- isFraud is the true label. isFlaggedFraud is the existing rule's verdict.
SELECT
    isFraud,
    isFlaggedFraud,
    COUNT(*) AS total_rows
FROM bronze.paysim_transactions
GROUP BY isFraud, isFlaggedFraud
ORDER BY isFraud, isFlaggedFraud;

-- Overall fraud rate
SELECT
    COUNT(*)     AS total_rows,
    SUM(isFraud) AS fraud_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(6,4)) AS fraud_pct
FROM bronze.paysim_transactions;

-- Fraud by transaction type
SELECT
    type,
    COUNT(*)            AS total_rows,
    SUM(isFraud)        AS fraud_rows,
    SUM(isFlaggedFraud) AS flagged_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(6,4)) AS fraud_pct
FROM bronze.paysim_transactions
GROUP BY type
ORDER BY fraud_rows DESC;

-- What the existing flag looks like
-- The dataset description says it flags transfers of more than 200,000.
-- This compares that description with what the flag actually did.
SELECT
    COUNT(*)            AS transfers_over_200k,
    SUM(isFraud)        AS fraud_rows,
    SUM(isFlaggedFraud) AS flagged_rows
FROM bronze.paysim_transactions
WHERE type = 'TRANSFER'
  AND amount > 200000;

SELECT
    type,
    MIN(amount) AS min_flagged_amount,
    MAX(amount) AS max_flagged_amount,
    COUNT(*)    AS flagged_rows
FROM bronze.paysim_transactions
WHERE isFlaggedFraud = 1
GROUP BY type;

-- ====================================================================
-- 4. Amounts
-- ====================================================================
-- Check for NULL, zero or negative amounts
-- Expectation: no negatives. Zero amounts are flagged in silver, not deleted.
SELECT
    SUM(CASE WHEN amount < 0 THEN 1 ELSE 0 END) AS negative_amounts,
    SUM(CASE WHEN amount = 0 THEN 1 ELSE 0 END) AS zero_amounts,
    SUM(CASE WHEN amount = 0 THEN isFraud ELSE 0 END) AS zero_amounts_that_are_fraud
FROM bronze.paysim_transactions;

-- Check no money value uses more than 2 decimal places
-- Silver casts FLOAT to DECIMAL(18,2), so this confirms the cast rounds nothing.
-- Expectation: all zeros
SELECT
    SUM(CASE WHEN ABS(amount         - ROUND(amount, 2))         > 0.000001 THEN 1 ELSE 0 END) AS amount_over_2dp,
    SUM(CASE WHEN ABS(oldbalanceOrg  - ROUND(oldbalanceOrg, 2))  > 0.000001 THEN 1 ELSE 0 END) AS oldbalanceOrg_over_2dp,
    SUM(CASE WHEN ABS(newbalanceOrig - ROUND(newbalanceOrig, 2)) > 0.000001 THEN 1 ELSE 0 END) AS newbalanceOrig_over_2dp,
    SUM(CASE WHEN ABS(oldbalanceDest - ROUND(oldbalanceDest, 2)) > 0.000001 THEN 1 ELSE 0 END) AS oldbalanceDest_over_2dp,
    SUM(CASE WHEN ABS(newbalanceDest - ROUND(newbalanceDest, 2)) > 0.000001 THEN 1 ELSE 0 END) AS newbalanceDest_over_2dp
FROM bronze.paysim_transactions;

-- Largest values, to confirm DECIMAL(18,2) is wide enough
SELECT
    CAST(MAX(amount)         AS DECIMAL(18,2)) AS max_amount,
    CAST(MAX(oldbalanceOrg)  AS DECIMAL(18,2)) AS max_oldbalanceOrg,
    CAST(MAX(newbalanceOrig) AS DECIMAL(18,2)) AS max_newbalanceOrig,
    CAST(MAX(oldbalanceDest) AS DECIMAL(18,2)) AS max_oldbalanceDest,
    CAST(MAX(newbalanceDest) AS DECIMAL(18,2)) AS max_newbalanceDest
FROM bronze.paysim_transactions;

-- Amount summary: fraud against normal
SELECT
    isFraud,
    COUNT(*)                           AS total_rows,
    CAST(MIN(amount) AS DECIMAL(18,2)) AS min_amount,
    CAST(AVG(amount) AS DECIMAL(18,2)) AS avg_amount,
    CAST(MAX(amount) AS DECIMAL(18,2)) AS max_amount,
    CAST(SUM(amount) AS DECIMAL(18,2)) AS total_amount
FROM bronze.paysim_transactions
GROUP BY isFraud
ORDER BY isFraud;

-- Amount summary by type, fraud against normal
SELECT
    type,
    isFraud,
    COUNT(*)                           AS total_rows,
    CAST(MIN(amount) AS DECIMAL(18,2)) AS min_amount,
    CAST(AVG(amount) AS DECIMAL(18,2)) AS avg_amount,
    CAST(MAX(amount) AS DECIMAL(18,2)) AS max_amount
FROM bronze.paysim_transactions
GROUP BY type, isFraud
ORDER BY type, isFraud;

-- Amount bands: fraud against normal
SELECT
    amount_band,
    COUNT(*)     AS total_rows,
    SUM(isFraud) AS fraud_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_pct
FROM (
    SELECT
        isFraud,
        CASE
            WHEN amount = 0          THEN '0: zero'
            WHEN amount < 1000       THEN '1: under 1k'
            WHEN amount < 10000      THEN '2: 1k to 10k'
            WHEN amount < 100000     THEN '3: 10k to 100k'
            WHEN amount < 200000     THEN '4: 100k to 200k'
            WHEN amount < 500000     THEN '5: 200k to 500k'
            WHEN amount < 1000000    THEN '6: 500k to 1m'
            WHEN amount < 10000000   THEN '7: 1m to 10m'
            ELSE                          '8: 10m and over'
        END AS amount_band
    FROM bronze.paysim_transactions
) t
GROUP BY amount_band
ORDER BY amount_band;

-- Is the largest fraud amount a hard cap?
-- Counts how many fraud rows sit exactly on the maximum fraud amount.
SELECT
    CAST(amount AS DECIMAL(18,2)) AS amount,
    COUNT(*)                      AS fraud_rows
FROM bronze.paysim_transactions
WHERE isFraud = 1
  AND amount = (SELECT MAX(amount) FROM bronze.paysim_transactions WHERE isFraud = 1)
GROUP BY amount;

-- ====================================================================
-- 5. Time: Fraud and Normal Transactions per Day
-- ====================================================================
-- Each step is one hour. Day number is (step - 1) / 24 + 1.
-- Steps run 1 to 743, so day 31 has only 23 hours.
-- This is the table that decides the build and test cutoff.
SELECT
    (step - 1) / 24 + 1  AS day_number,
    COUNT(DISTINCT step) AS hours_in_day,
    COUNT(*)             AS total_rows,
    COUNT(*) - SUM(isFraud) AS normal_rows,
    SUM(isFraud)         AS fraud_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_pct
FROM bronze.paysim_transactions
GROUP BY (step - 1) / 24 + 1
ORDER BY day_number;

-- Compare the candidate cutoffs
-- For each cutoff: how many normal and fraud rows land in the build period
-- and in the test period?
SELECT
    'days 1-20 / 21-31' AS cutoff,
    SUM(CASE WHEN step <= 480 THEN 1 - isFraud ELSE 0 END) AS build_normal,
    SUM(CASE WHEN step <= 480 THEN isFraud     ELSE 0 END) AS build_fraud,
    SUM(CASE WHEN step >  480 THEN 1 - isFraud ELSE 0 END) AS test_normal,
    SUM(CASE WHEN step >  480 THEN isFraud     ELSE 0 END) AS test_fraud
FROM bronze.paysim_transactions
UNION ALL
SELECT
    'days 1-15 / 16-31',
    SUM(CASE WHEN step <= 360 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step <= 360 THEN isFraud     ELSE 0 END),
    SUM(CASE WHEN step >  360 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step >  360 THEN isFraud     ELSE 0 END)
FROM bronze.paysim_transactions
UNION ALL
SELECT
    'days 1-10 / 11-31',
    SUM(CASE WHEN step <= 240 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step <= 240 THEN isFraud     ELSE 0 END),
    SUM(CASE WHEN step >  240 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step >  240 THEN isFraud     ELSE 0 END)
FROM bronze.paysim_transactions;

-- TRANSFER and CASH_OUT only, per period, for the same cutoffs
-- If fraud only happens in these two types, they are the rows a rule will
-- actually be judged on, so the test period needs enough of them.
SELECT
    'days 1-20 / 21-31' AS cutoff,
    SUM(CASE WHEN step <= 480 THEN 1 - isFraud ELSE 0 END) AS build_normal,
    SUM(CASE WHEN step <= 480 THEN isFraud     ELSE 0 END) AS build_fraud,
    SUM(CASE WHEN step >  480 THEN 1 - isFraud ELSE 0 END) AS test_normal,
    SUM(CASE WHEN step >  480 THEN isFraud     ELSE 0 END) AS test_fraud
FROM bronze.paysim_transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
UNION ALL
SELECT
    'days 1-15 / 16-31',
    SUM(CASE WHEN step <= 360 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step <= 360 THEN isFraud     ELSE 0 END),
    SUM(CASE WHEN step >  360 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step >  360 THEN isFraud     ELSE 0 END)
FROM bronze.paysim_transactions
WHERE type IN ('TRANSFER', 'CASH_OUT')
UNION ALL
SELECT
    'days 1-10 / 11-31',
    SUM(CASE WHEN step <= 240 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step <= 240 THEN isFraud     ELSE 0 END),
    SUM(CASE WHEN step >  240 THEN 1 - isFraud ELSE 0 END),
    SUM(CASE WHEN step >  240 THEN isFraud     ELSE 0 END)
FROM bronze.paysim_transactions
WHERE type IN ('TRANSFER', 'CASH_OUT');

-- The chosen cutoff: build on days 1 to 15, test on days 16 to 30
-- Day 31 (steps 721 to 743) is kept in the data but left out of rule
-- evaluation, because it holds fraud rows and no normal rows at all.
-- First for all transaction types, then for TRANSFER and CASH_OUT only.
SELECT
    period,
    COUNT(*)                AS total_rows,
    COUNT(*) - SUM(isFraud) AS normal_rows,
    SUM(isFraud)            AS fraud_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_pct
FROM (
    SELECT
        isFraud,
        CASE
            WHEN step <= 360 THEN '1: build, days 1 to 15'
            WHEN step <= 720 THEN '2: test, days 16 to 30'
            ELSE                  '3: excluded, day 31'
        END AS period
    FROM bronze.paysim_transactions
) t
GROUP BY period
ORDER BY period;

SELECT
    period,
    COUNT(*)                AS total_rows,
    COUNT(*) - SUM(isFraud) AS normal_rows,
    SUM(isFraud)            AS fraud_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_pct
FROM (
    SELECT
        isFraud,
        CASE
            WHEN step <= 360 THEN '1: build, days 1 to 15'
            WHEN step <= 720 THEN '2: test, days 16 to 30'
            ELSE                  '3: excluded, day 31'
        END AS period
    FROM bronze.paysim_transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
) t
GROUP BY period
ORDER BY period;

-- Fraud and normal transactions by hour of the day
-- hour_slot 0 is the first hour of each day (steps 1, 25, 49 and so on).
SELECT
    (step - 1) % 24 AS hour_slot,
    COUNT(*)        AS total_rows,
    SUM(isFraud)    AS fraud_rows,
    CAST(SUM(isFraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_pct
FROM bronze.paysim_transactions
GROUP BY (step - 1) % 24
ORDER BY hour_slot;

-- ====================================================================
-- 6. Balance Columns (profiling and cleaning only)
-- ====================================================================
-- These columns must not be used in detection rules. They are profiled here
-- so that silver can flag the rows where they do not add up.

-- Check for negative balances
-- Expectation: all zeros
SELECT
    SUM(CASE WHEN oldbalanceOrg  < 0 THEN 1 ELSE 0 END) AS negative_oldbalanceOrg,
    SUM(CASE WHEN newbalanceOrig < 0 THEN 1 ELSE 0 END) AS negative_newbalanceOrig,
    SUM(CASE WHEN oldbalanceDest < 0 THEN 1 ELSE 0 END) AS negative_oldbalanceDest,
    SUM(CASE WHEN newbalanceDest < 0 THEN 1 ELSE 0 END) AS negative_newbalanceDest
FROM bronze.paysim_transactions;

-- Origin balance mismatches, by type
-- Money leaves the origin account, except for CASH_IN where it arrives.
-- A row is a mismatch if the new balance is more than 0.01 away from what
-- the old balance and the amount say it should be. A gap of one cent is
-- treated as rounding in the source.
-- The values are cast to DECIMAL(18,2) before they are compared. Many rows are
-- off by exactly one cent, and FLOAT cannot hold 0.01 exactly, so comparing the
-- FLOAT values puts some of those rows on the wrong side of the 0.01 line.
SELECT
    type,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN ABS(expected_newbalanceOrig - newbalanceOrig) > 0.01 THEN 1 ELSE 0 END) AS orig_mismatch_rows,
    CAST(SUM(CASE WHEN ABS(expected_newbalanceOrig - newbalanceOrig) > 0.01 THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS DECIMAL(5,2)) AS orig_mismatch_pct
FROM (
    SELECT
        type,
        CAST(newbalanceOrig AS DECIMAL(18,2)) AS newbalanceOrig,
        CASE WHEN type = 'CASH_IN' THEN CAST(oldbalanceOrg AS DECIMAL(18,2)) + CAST(amount AS DECIMAL(18,2))
             ELSE CAST(oldbalanceOrg AS DECIMAL(18,2)) - CAST(amount AS DECIMAL(18,2))
        END AS expected_newbalanceOrig
    FROM bronze.paysim_transactions
) t
GROUP BY type
ORDER BY type;

-- Destination balance mismatches, by type
-- Money arrives at the destination account, except for CASH_IN where it leaves.
-- Same rule and same cast to DECIMAL(18,2) as the origin check above.
SELECT
    type,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN ABS(expected_newbalanceDest - newbalanceDest) > 0.01 THEN 1 ELSE 0 END) AS dest_mismatch_rows,
    CAST(SUM(CASE WHEN ABS(expected_newbalanceDest - newbalanceDest) > 0.01 THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS DECIMAL(5,2)) AS dest_mismatch_pct
FROM (
    SELECT
        type,
        CAST(newbalanceDest AS DECIMAL(18,2)) AS newbalanceDest,
        CASE WHEN type = 'CASH_IN' THEN CAST(oldbalanceDest AS DECIMAL(18,2)) - CAST(amount AS DECIMAL(18,2))
             ELSE CAST(oldbalanceDest AS DECIMAL(18,2)) + CAST(amount AS DECIMAL(18,2))
        END AS expected_newbalanceDest
    FROM bronze.paysim_transactions
) t
GROUP BY type
ORDER BY type;

-- Merchant destinations: do they carry any balance at all?
-- Expectation: merchant rows have zero in both destination balance columns,
-- which means the destination balances are not recorded for merchants.
SELECT
    LEFT(nameDest, 1) AS dest_prefix,
    COUNT(*)          AS total_rows,
    SUM(CASE WHEN oldbalanceDest = 0 AND newbalanceDest = 0 THEN 1 ELSE 0 END) AS both_dest_balances_zero
FROM bronze.paysim_transactions
GROUP BY LEFT(nameDest, 1);

-- Rows where the origin had less money than the amount sent
-- Shown as fraud against normal, to see how the two groups differ.
-- This is the leak the Data rules warn about: it is profiled, never used in a rule.
-- The values are cast to DECIMAL(18,2) first, so "equals" means exactly equal.
SELECT
    isFraud,
    COUNT(*) AS total_rows,
    SUM(CASE WHEN oldbalanceOrg = 0      THEN 1 ELSE 0 END) AS orig_started_at_zero,
    SUM(CASE WHEN oldbalanceOrg < amount THEN 1 ELSE 0 END) AS orig_balance_below_amount,
    SUM(CASE WHEN oldbalanceOrg = amount THEN 1 ELSE 0 END) AS amount_equals_whole_balance,
    SUM(CASE WHEN ABS(oldbalanceOrg - amount) <= 0.01 THEN 1 ELSE 0 END) AS amount_within_one_cent_of_balance
FROM (
    SELECT
        isFraud,
        CAST(amount        AS DECIMAL(18,2)) AS amount,
        CAST(oldbalanceOrg AS DECIMAL(18,2)) AS oldbalanceOrg
    FROM bronze.paysim_transactions
    WHERE type IN ('TRANSFER', 'CASH_OUT')
) t
GROUP BY isFraud
ORDER BY isFraud;
