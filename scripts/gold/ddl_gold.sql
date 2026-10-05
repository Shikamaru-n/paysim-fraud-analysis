/*
===============================================================================
DDL Script: Create Gold Tables and Views
===============================================================================
Script Purpose:
    This script creates the Gold layer in the data warehouse.
    The Gold layer represents the final dimension and fact tables (Star Schema),
    plus one report view for each analysis question.

    - Dimensions : gold.dim_time, gold.dim_transaction_type (tables)
    - Facts      : gold.fact_transactions, gold.fact_transaction_balances (views)
                   gold.fact_destination_history (table)
    - Reports    : gold.report_* (views)

    Why the dimensions are tables and not views:
    The reference project builds every gold object as a view. Here the two
    dimensions are small tables, loaded by the procedure gold.load_gold.
    As views they would have to be rebuilt from the 6.36 million row silver
    table every time a query used them. This was timed on the silver table:
        - one grouped scan of silver                         :  5.5 seconds
        - the same query with both dimensions as views       : 18.6 seconds
    Every report would pay that difference, so the dimensions are stored
    (743 rows and 5 rows). The fact stays a view, so there is no second copy
    of the transactions and it always matches silver.

Usage:
    - Run this script, then run: EXEC gold.load_gold;
    - These views can be queried directly for analytics and reporting.
    - Views have no order of their own. Add an ORDER BY when querying them.
    - This is synthetic data. Every result describes a simulation.
===============================================================================
*/

-- The views are dropped first, because they depend on the dimension tables.
IF OBJECT_ID('gold.report_rule_performance', 'V') IS NOT NULL
    DROP VIEW gold.report_rule_performance;
IF OBJECT_ID('gold.rule_flags', 'V') IS NOT NULL
    DROP VIEW gold.rule_flags;
IF OBJECT_ID('gold.report_fraud_overview', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_overview;
IF OBJECT_ID('gold.report_fraud_by_type', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_by_type;
IF OBJECT_ID('gold.report_fraud_by_day', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_by_day;
IF OBJECT_ID('gold.report_fraud_by_hour', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_by_hour;
IF OBJECT_ID('gold.report_fraud_by_amount_band', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_by_amount_band;
IF OBJECT_ID('gold.report_fraud_destinations', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_destinations;
IF OBJECT_ID('gold.report_existing_rule_performance', 'V') IS NOT NULL
    DROP VIEW gold.report_existing_rule_performance;
IF OBJECT_ID('gold.report_balance_quality', 'V') IS NOT NULL
    DROP VIEW gold.report_balance_quality;
IF OBJECT_ID('gold.report_fraud_by_type_and_hour', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_by_type_and_hour;
IF OBJECT_ID('gold.report_fraud_by_type_and_amount_band', 'V') IS NOT NULL
    DROP VIEW gold.report_fraud_by_type_and_amount_band;
IF OBJECT_ID('gold.report_missed_fraud', 'V') IS NOT NULL
    DROP VIEW gold.report_missed_fraud;
IF OBJECT_ID('gold.fact_transaction_balances', 'V') IS NOT NULL
    DROP VIEW gold.fact_transaction_balances;
IF OBJECT_ID('gold.fact_transactions', 'V') IS NOT NULL
    DROP VIEW gold.fact_transactions;
GO

-- =============================================================================
-- Create Dimension: gold.dim_time
-- =============================================================================
-- One row per step (hour). rule_period is the only place the build and test
-- cutoff is defined:
--     build    : days 1 to 15
--     test     : days 16 to 30
--     excluded : day 31 (fraud rows only, no normal transactions)
IF OBJECT_ID('gold.dim_time', 'U') IS NOT NULL
    DROP TABLE gold.dim_time;
GO

CREATE TABLE gold.dim_time (
    time_key    INT,
    step        INT,
    day_number  INT,
    hour_slot   INT,
    rule_period NVARCHAR(50)
);
GO

-- =============================================================================
-- Create Dimension: gold.dim_transaction_type
-- =============================================================================
IF OBJECT_ID('gold.dim_transaction_type', 'U') IS NOT NULL
    DROP TABLE gold.dim_transaction_type;
GO

CREATE TABLE gold.dim_transaction_type (
    transaction_type_key  INT,
    transaction_type      NVARCHAR(50),
    transaction_type_name NVARCHAR(50)
);
GO

-- =============================================================================
-- Create Fact Table: gold.fact_destination_history
-- =============================================================================
-- One row per transaction. destination_prior_transactions is the number of
-- transactions (of any type) that the destination account had already received
-- in strictly earlier steps. Transactions in the same step are never counted,
-- and neither are later ones, so the value only uses information that existed
-- before the transaction happened. It does not use the fraud label.
-- The count starts from step 1, because that is where the data starts. An
-- account that was active before the month began still shows 0 at first.
-- This is a table, loaded by gold.load_gold, because working it out needs a
-- sort of all 6.36 million rows. It joins to gold.fact_transactions on
-- transaction_id.
IF OBJECT_ID('gold.fact_destination_history', 'U') IS NOT NULL
    DROP TABLE gold.fact_destination_history;
GO

CREATE TABLE gold.fact_destination_history (
    transaction_id                 INT,
    destination_prior_transactions INT
);
GO

-- =============================================================================
-- Create Fact Table: gold.fact_transactions
-- =============================================================================
-- This is the view that detection rules are written against. It has no balance
-- columns and no balance mismatch flags on purpose: those leak the outcome, so
-- leaving them out means a rule cannot use them by accident.
CREATE VIEW gold.fact_transactions AS
SELECT
    tr.transaction_id          AS transaction_id,
    dt.time_key                AS time_key,
    ty.transaction_type_key    AS transaction_type_key,
    tr.origin_account          AS origin_account,
    tr.destination_account     AS destination_account,
    tr.amount                  AS amount,
    tr.is_fraud                AS is_fraud,
    tr.is_flagged_fraud        AS is_flagged_fraud,
    tr.is_merchant_destination AS is_merchant_destination,
    tr.is_zero_amount          AS is_zero_amount
FROM silver.paysim_transactions tr
LEFT JOIN gold.dim_time dt
    ON tr.step = dt.step
LEFT JOIN gold.dim_transaction_type ty
    ON tr.transaction_type = ty.transaction_type;
GO

-- =============================================================================
-- Create Fact Table: gold.fact_transaction_balances
-- =============================================================================
-- The balance columns and balance mismatch flags, kept apart from the main fact.
-- For description only. Do not use this view in a detection rule.
-- It joins back to gold.fact_transactions on transaction_id.
CREATE VIEW gold.fact_transaction_balances AS
SELECT
    tr.transaction_id                  AS transaction_id,
    dt.time_key                        AS time_key,
    ty.transaction_type_key            AS transaction_type_key,
    tr.origin_old_balance              AS origin_old_balance,
    tr.origin_new_balance              AS origin_new_balance,
    tr.destination_old_balance         AS destination_old_balance,
    tr.destination_new_balance         AS destination_new_balance,
    tr.is_merchant_destination         AS is_merchant_destination,
    tr.is_origin_balance_mismatch      AS is_origin_balance_mismatch,
    tr.is_destination_balance_mismatch AS is_destination_balance_mismatch
FROM silver.paysim_transactions tr
LEFT JOIN gold.dim_time dt
    ON tr.step = dt.step
LEFT JOIN gold.dim_transaction_type ty
    ON tr.transaction_type = ty.transaction_type;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_overview
-- =============================================================================
-- Question: How big is the fraud problem, in transactions and in money?
-- One row, all periods together.
-- fraud_rate_pct is fraud's share of the transactions.
-- fraud_amount_pct is fraud's share of the money.
CREATE VIEW gold.report_fraud_overview AS
SELECT
    COUNT(*)                                               AS total_transactions,
    SUM(is_fraud)                                          AS fraud_transactions,
    CAST(SUM(is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct,
    SUM(amount)                                            AS total_amount,
    SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END)     AS fraud_amount,
    CAST(SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END) * 100.0
         / SUM(amount) AS DECIMAL(7,4))                    AS fraud_amount_pct
FROM gold.fact_transactions;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_by_type
-- =============================================================================
-- Question: Which transaction types does fraud happen in, and how much money
-- is involved?
CREATE VIEW gold.report_fraud_by_type AS
SELECT
    ty.transaction_type                                      AS transaction_type,
    ty.transaction_type_name                                 AS transaction_type_name,
    COUNT(*)                                                 AS total_transactions,
    SUM(f.is_fraud)                                          AS fraud_transactions,
    CAST(SUM(f.is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct,
    SUM(f.amount)                                            AS total_amount,
    SUM(CASE WHEN f.is_fraud = 1 THEN f.amount ELSE 0 END)   AS fraud_amount,
    CAST(SUM(CASE WHEN f.is_fraud = 1 THEN f.amount ELSE 0 END) * 100.0
         / SUM(f.amount) AS DECIMAL(7,4))                    AS fraud_amount_pct -- Fraud's share of this type's money
FROM gold.fact_transactions f
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
GROUP BY ty.transaction_type, ty.transaction_type_name;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_by_day
-- =============================================================================
-- Question: How are fraud and normal transactions spread across the days, and
-- which period is each day in?
CREATE VIEW gold.report_fraud_by_day AS
SELECT
    dt.day_number                                            AS day_number,
    dt.rule_period                                           AS rule_period,
    COUNT(DISTINCT dt.step)                                  AS hours_in_day,
    COUNT(*)                                                 AS total_transactions,
    COUNT(*) - SUM(f.is_fraud)                               AS normal_transactions,
    SUM(f.is_fraud)                                          AS fraud_transactions,
    CAST(SUM(f.is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM gold.fact_transactions f
LEFT JOIN gold.dim_time dt
    ON f.time_key = dt.time_key
GROUP BY dt.day_number, dt.rule_period;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_by_hour
-- =============================================================================
-- Question: At what time of day is fraud most concentrated?
-- hour_slot 0 is the first hour of each day. The data does not say which clock
-- hour that is.
CREATE VIEW gold.report_fraud_by_hour AS
SELECT
    dt.hour_slot                                             AS hour_slot,
    COUNT(*)                                                 AS total_transactions,
    SUM(f.is_fraud)                                          AS fraud_transactions,
    CAST(SUM(f.is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM gold.fact_transactions f
LEFT JOIN gold.dim_time dt
    ON f.time_key = dt.time_key
GROUP BY dt.hour_slot;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_by_amount_band
-- =============================================================================
-- Question: What amounts does fraud use, compared with normal transactions?
-- The number at the start of each band keeps the bands in order when sorted.
CREATE VIEW gold.report_fraud_by_amount_band AS
SELECT
    amount_band                                            AS amount_band,
    COUNT(*)                                               AS total_transactions,
    SUM(is_fraud)                                          AS fraud_transactions,
    CAST(SUM(is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM (
    SELECT
        is_fraud,
        CASE
            WHEN amount = 0        THEN '0: zero'
            WHEN amount < 1000     THEN '1: under 1k'
            WHEN amount < 10000    THEN '2: 1k to 10k'
            WHEN amount < 100000   THEN '3: 10k to 100k'
            WHEN amount < 200000   THEN '4: 100k to 200k'
            WHEN amount < 500000   THEN '5: 200k to 500k'
            WHEN amount < 1000000  THEN '6: 500k to 1m'
            WHEN amount < 10000000 THEN '7: 1m to 10m'
            ELSE                        '8: 10m and over'
        END AS amount_band
    FROM gold.fact_transactions
) t
GROUP BY amount_band;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_destinations
-- =============================================================================
-- Question: Do fraud transactions go to the same destination accounts repeatedly?
-- Each row says: this many destination accounts received this many fraud
-- transactions each.
-- Only the fraud rows are grouped. Grouping all 2.7 million destination accounts
-- takes over a minute on this machine, and the question is only about fraud.
-- This is a description, not a rule. It uses is_fraud and looks across the whole
-- month, so it uses information a detection rule is not allowed to use.
CREATE VIEW gold.report_fraud_destinations AS
SELECT
    fraud_transactions_received      AS fraud_transactions_received,
    COUNT(*)                         AS destination_accounts,
    SUM(fraud_transactions_received) AS fraud_transactions
FROM (
    SELECT
        destination_account,
        COUNT(*) AS fraud_transactions_received
    FROM gold.fact_transactions
    WHERE is_fraud = 1
    GROUP BY destination_account
) t
GROUP BY fraud_transactions_received;
GO

-- =============================================================================
-- Create Report: gold.report_existing_rule_performance
-- =============================================================================
-- Question: How badly does the existing fraud flag perform?
-- One row for the build period and one for the test period. Day 31 is excluded
-- from rule evaluation, because it has no normal transactions.
--     precision           : of the rows the rule flagged, the share that are fraud
--     recall              : of the fraud rows, the share the rule flagged
--     false positive rate : of the normal rows, the share the rule flagged
-- Recall and false positive rate do not depend on how common fraud is, so they
-- are the fair comparison between the two periods. Read precision next to the
-- period's fraud rate. Precision is NULL when the rule flagged nothing.
CREATE VIEW gold.report_existing_rule_performance AS
SELECT
    rule_period                                                                  AS rule_period,
    total_transactions                                                           AS total_transactions,
    fraud_transactions                                                           AS fraud_transactions,
    CAST(fraud_transactions * 100.0 / total_transactions AS DECIMAL(7,4))        AS fraud_rate_pct,
    flagged_transactions                                                         AS flagged_transactions,
    true_positives                                                               AS true_positives,
    false_positives                                                              AS false_positives,
    false_negatives                                                              AS false_negatives,
    CAST(true_positives * 100.0 / NULLIF(flagged_transactions, 0) AS DECIMAL(7,4)) AS precision_pct,
    CAST(true_positives * 100.0 / NULLIF(fraud_transactions, 0) AS DECIMAL(7,4))   AS recall_pct,
    CAST(false_positives * 100.0
         / NULLIF(total_transactions - fraud_transactions, 0) AS DECIMAL(7,4))   AS false_positive_rate_pct
FROM (
    SELECT
        dt.rule_period,
        COUNT(*)                AS total_transactions,
        SUM(f.is_fraud)         AS fraud_transactions,
        SUM(f.is_flagged_fraud) AS flagged_transactions,
        SUM(CASE WHEN f.is_flagged_fraud = 1 AND f.is_fraud = 1 THEN 1 ELSE 0 END) AS true_positives,
        SUM(CASE WHEN f.is_flagged_fraud = 1 AND f.is_fraud = 0 THEN 1 ELSE 0 END) AS false_positives,
        SUM(CASE WHEN f.is_flagged_fraud = 0 AND f.is_fraud = 1 THEN 1 ELSE 0 END) AS false_negatives
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_time dt
        ON f.time_key = dt.time_key
    WHERE dt.rule_period != 'excluded'
    GROUP BY dt.rule_period
) t;
GO

-- =============================================================================
-- Create Report: gold.report_balance_quality
-- =============================================================================
-- Question: How often do the balances fail to add up, by transaction type?
-- For description only. A mismatch is a gap of more than 0.01 between the new
-- balance and what the old balance and the amount say it should be.
-- Every PAYMENT row is a destination mismatch because merchant balances are
-- never recorded, not because the data is broken.
CREATE VIEW gold.report_balance_quality AS
SELECT
    ty.transaction_type                    AS transaction_type,
    COUNT(*)                               AS total_transactions,
    SUM(b.is_merchant_destination)         AS merchant_destination_transactions,
    SUM(b.is_origin_balance_mismatch)      AS origin_mismatch_transactions,
    CAST(SUM(b.is_origin_balance_mismatch) * 100.0 / COUNT(*) AS DECIMAL(5,2))      AS origin_mismatch_pct,
    SUM(b.is_destination_balance_mismatch) AS destination_mismatch_transactions,
    CAST(SUM(b.is_destination_balance_mismatch) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS destination_mismatch_pct
FROM gold.fact_transaction_balances b
LEFT JOIN gold.dim_transaction_type ty
    ON b.transaction_type_key = ty.transaction_type_key
GROUP BY ty.transaction_type;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_by_type_and_hour
-- =============================================================================
-- Question: Within the types where fraud happens, does the time of day separate
-- fraud from normal transactions?
-- TRANSFER and CASH_OUT only, because the other three types have no fraud and
-- would dilute the rates.
-- rule_period is included so the rows can be filtered. Anything used to design
-- the detection rule must be read from the 'build' rows only.
CREATE VIEW gold.report_fraud_by_type_and_hour AS
SELECT
    dt.rule_period                                           AS rule_period,
    ty.transaction_type                                      AS transaction_type,
    dt.hour_slot                                             AS hour_slot,
    COUNT(*)                                                 AS total_transactions,
    SUM(f.is_fraud)                                          AS fraud_transactions,
    CAST(SUM(f.is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM gold.fact_transactions f
LEFT JOIN gold.dim_time dt
    ON f.time_key = dt.time_key
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
WHERE ty.transaction_type IN ('TRANSFER', 'CASH_OUT')
GROUP BY dt.rule_period, ty.transaction_type, dt.hour_slot;
GO

-- =============================================================================
-- Create Report: gold.report_fraud_by_type_and_amount_band
-- =============================================================================
-- Question: Within the types where fraud happens, does the amount separate
-- fraud from normal transactions?
-- TRANSFER and CASH_OUT only. The bands are the same as in
-- gold.report_fraud_by_amount_band.
-- rule_period is included so the rows can be filtered. Anything used to design
-- the detection rule must be read from the 'build' rows only.
CREATE VIEW gold.report_fraud_by_type_and_amount_band AS
SELECT
    rule_period                                            AS rule_period,
    transaction_type                                       AS transaction_type,
    amount_band                                            AS amount_band,
    COUNT(*)                                               AS total_transactions,
    SUM(is_fraud)                                          AS fraud_transactions,
    CAST(SUM(is_fraud) * 100.0 / COUNT(*) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM (
    SELECT
        dt.rule_period,
        ty.transaction_type,
        f.is_fraud,
        CASE
            WHEN f.amount = 0        THEN '0: zero'
            WHEN f.amount < 1000     THEN '1: under 1k'
            WHEN f.amount < 10000    THEN '2: 1k to 10k'
            WHEN f.amount < 100000   THEN '3: 10k to 100k'
            WHEN f.amount < 200000   THEN '4: 100k to 200k'
            WHEN f.amount < 500000   THEN '5: 200k to 500k'
            WHEN f.amount < 1000000  THEN '6: 500k to 1m'
            WHEN f.amount < 10000000 THEN '7: 1m to 10m'
            ELSE                          '8: 10m and over'
        END AS amount_band
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_time dt
        ON f.time_key = dt.time_key
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    WHERE ty.transaction_type IN ('TRANSFER', 'CASH_OUT')
) t
GROUP BY rule_period, transaction_type, amount_band;
GO

-- =============================================================================
-- Create Report: gold.report_missed_fraud
-- =============================================================================
-- Question: What does the fraud that the existing rule misses look like?
-- Fraud rows only, by period, type and amount band, split into the rows the
-- existing flag caught and the rows it missed.
CREATE VIEW gold.report_missed_fraud AS
SELECT
    rule_period                                              AS rule_period,
    transaction_type                                         AS transaction_type,
    amount_band                                              AS amount_band,
    COUNT(*)                                                 AS fraud_transactions,
    SUM(is_flagged_fraud)                                    AS caught_by_existing_rule,
    COUNT(*) - SUM(is_flagged_fraud)                         AS missed_by_existing_rule,
    SUM(CASE WHEN is_flagged_fraud = 0 THEN amount ELSE 0 END) AS missed_fraud_amount
FROM (
    SELECT
        dt.rule_period,
        ty.transaction_type,
        f.is_flagged_fraud,
        f.amount,
        CASE
            WHEN f.amount = 0        THEN '0: zero'
            WHEN f.amount < 1000     THEN '1: under 1k'
            WHEN f.amount < 10000    THEN '2: 1k to 10k'
            WHEN f.amount < 100000   THEN '3: 10k to 100k'
            WHEN f.amount < 200000   THEN '4: 100k to 200k'
            WHEN f.amount < 500000   THEN '5: 200k to 500k'
            WHEN f.amount < 1000000  THEN '6: 500k to 1m'
            WHEN f.amount < 10000000 THEN '7: 1m to 10m'
            ELSE                          '8: 10m and over'
        END AS amount_band
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_time dt
        ON f.time_key = dt.time_key
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    WHERE f.is_fraud = 1
) t
GROUP BY rule_period, transaction_type, amount_band;
GO

-- =============================================================================
-- Create Rule View: gold.rule_flags
-- =============================================================================
-- The new detection rules, as frozen after the build period (days 1 to 15).
-- One row per TRANSFER or CASH_OUT transaction, with a 1 or 0 for each rule.
-- The other three types have no fraud and are never flagged, so they are left
-- out.
--
-- What the rules are allowed to use, and do use:
--     - the transaction's own type, amount and hour slot
--     - whether the destination account had received anything in strictly
--       earlier steps (gold.fact_destination_history)
-- They use no balance column, no fraud label, and nothing from the same step
-- or from later steps.
--
-- 1. Chosen rule (the recommendation). Flag when:
--        a CASH_OUT is 800,000 or more, or is zero, or is in hour slots 0 to 6
--     or a TRANSFER goes to a new destination and is in hour slots 0 to 6,
--        or is 5,000,000 or more
--
-- 2. No-hour rule (the fallback if the hour signal does not carry over to real
--    data, which is likely). Flag when:
--        a CASH_OUT is 800,000 or more, or is zero
--     or a TRANSFER goes to a new destination and is 1,500,000 or more
--
-- 3. Wider rule (a second operating point, NOT the recommendation). It flags
--    about 3% of honest customers in the build period, far outside the 0.5%
--    cap, to show what a looser cap would buy. Flag when:
--        a CASH_OUT is 800,000 or more, or is zero, or is in hour slots 0 to 7
--     or a TRANSFER goes to a new destination
--
-- "New destination" means destination_prior_transactions = 0.
-- These definitions are frozen. They must not be changed after the test period
-- has been looked at.
CREATE VIEW gold.rule_flags AS
SELECT
    f.transaction_id AS transaction_id,
    CASE
        WHEN ty.transaction_type = 'CASH_OUT'
             AND (f.amount >= 800000 OR f.is_zero_amount = 1 OR dt.hour_slot <= 6) THEN 1
        WHEN ty.transaction_type = 'TRANSFER'
             AND h.destination_prior_transactions = 0
             AND (dt.hour_slot <= 6 OR f.amount >= 5000000) THEN 1
        ELSE 0
    END AS is_flagged_chosen_rule,
    CASE
        WHEN ty.transaction_type = 'CASH_OUT'
             AND (f.amount >= 800000 OR f.is_zero_amount = 1) THEN 1
        WHEN ty.transaction_type = 'TRANSFER'
             AND h.destination_prior_transactions = 0
             AND f.amount >= 1500000 THEN 1
        ELSE 0
    END AS is_flagged_no_hour_rule,
    CASE
        WHEN ty.transaction_type = 'CASH_OUT'
             AND (f.amount >= 800000 OR f.is_zero_amount = 1 OR dt.hour_slot <= 7) THEN 1
        WHEN ty.transaction_type = 'TRANSFER'
             AND h.destination_prior_transactions = 0 THEN 1
        ELSE 0
    END AS is_flagged_wider_rule
FROM gold.fact_transactions f
LEFT JOIN gold.fact_destination_history h
    ON f.transaction_id = h.transaction_id
LEFT JOIN gold.dim_time dt
    ON f.time_key = dt.time_key
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
WHERE ty.transaction_type IN ('TRANSFER', 'CASH_OUT');
GO

-- =============================================================================
-- Create Report: gold.report_rule_performance
-- =============================================================================
-- Question: Can a better SQL rule catch more fraud without flagging too many
-- honest customers?
-- One row per rule and period, for the existing flag and the three new rules.
-- Every rule is scored on TRANSFER and CASH_OUT transactions only, so the rows
-- can be compared with each other. Day 31 is excluded from rule evaluation.
--     precision           : of the rows the rule flagged, the share that are fraud
--     recall              : of the fraud rows, the share the rule flagged
--     false positive rate : of the honest rows, the share the rule flagged
-- Recall and false positive rate are the fair comparison between the periods.
-- Read precision next to the period's fraud rate.
-- The fraud label is used here, to score the rules. It is not used by the rules.
--
-- CROSS APPLY (VALUES ...) turns the four flag columns into four rows per
-- transaction, one per rule, so that one pass over the data scores all four.
CREATE VIEW gold.report_rule_performance AS
SELECT
    rule_period                                                                    AS rule_period,
    rule_name                                                                      AS rule_name,
    total_transactions                                                             AS total_transactions,
    fraud_transactions                                                             AS fraud_transactions,
    CAST(fraud_transactions * 100.0 / total_transactions AS DECIMAL(7,4))          AS fraud_rate_pct,
    flagged_transactions                                                           AS flagged_transactions,
    true_positives                                                                 AS true_positives,
    false_positives                                                                AS false_positives,
    false_negatives                                                                AS false_negatives,
    CAST(true_positives * 100.0 / NULLIF(flagged_transactions, 0) AS DECIMAL(7,4)) AS precision_pct,
    CAST(true_positives * 100.0 / NULLIF(fraud_transactions, 0) AS DECIMAL(7,4))   AS recall_pct,
    CAST(false_positives * 100.0
         / NULLIF(total_transactions - fraud_transactions, 0) AS DECIMAL(7,4))     AS false_positive_rate_pct
FROM (
    SELECT
        dt.rule_period,
        v.rule_name,
        COUNT(*)          AS total_transactions,
        SUM(f.is_fraud)   AS fraud_transactions,
        SUM(v.is_flagged) AS flagged_transactions,
        SUM(CASE WHEN v.is_flagged = 1 AND f.is_fraud = 1 THEN 1 ELSE 0 END) AS true_positives,
        SUM(CASE WHEN v.is_flagged = 1 AND f.is_fraud = 0 THEN 1 ELSE 0 END) AS false_positives,
        SUM(CASE WHEN v.is_flagged = 0 AND f.is_fraud = 1 THEN 1 ELSE 0 END) AS false_negatives
    FROM gold.rule_flags r
    INNER JOIN gold.fact_transactions f
        ON f.transaction_id = r.transaction_id
    LEFT JOIN gold.dim_time dt
        ON f.time_key = dt.time_key
    CROSS APPLY (
        VALUES ('1: existing flag', CAST(f.is_flagged_fraud AS INT)),
               ('2: chosen rule',   r.is_flagged_chosen_rule),
               ('3: no-hour rule',  r.is_flagged_no_hour_rule),
               ('4: wider rule (outside the 0.5% cap)', r.is_flagged_wider_rule)
    ) v (rule_name, is_flagged)
    WHERE dt.rule_period != 'excluded'
    GROUP BY dt.rule_period, v.rule_name
) t;
GO
