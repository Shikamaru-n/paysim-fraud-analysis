/*
===============================================================================
Quality Checks
===============================================================================
Script Purpose:
    This script performs quality checks to validate the integrity, consistency,
    and accuracy of the Gold Layer. These checks ensure:
    - Uniqueness of surrogate keys in dimension tables.
    - Referential integrity between fact and dimension tables.
    - The fact views hold every silver row.
    - The balance columns are kept out of gold.fact_transactions.
    - Every report view adds up to the same totals.

Usage Notes:
    - Run these checks after: EXEC gold.load_gold;
    - Investigate and resolve any discrepancies found during the checks.
    - This is synthetic data.
===============================================================================
*/

-- ====================================================================
-- Checking 'gold.dim_time'
-- ====================================================================
-- Check for Uniqueness of Time Key in gold.dim_time
-- Expectation: No results
SELECT
    time_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_time
GROUP BY time_key
HAVING COUNT(*) > 1;

-- Check the row count and that the key equals the step
-- Expectation: 743 rows, and rows_where_key_is_not_step = 0
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN time_key != step THEN 1 ELSE 0 END) AS rows_where_key_is_not_step
FROM gold.dim_time;

-- Check the periods
-- Expectation: build = days 1 to 15 (360 hours), test = days 16 to 30 (360 hours),
--              excluded = day 31 (23 hours)
SELECT
    rule_period,
    MIN(day_number) AS first_day,
    MAX(day_number) AS last_day,
    MIN(step)       AS first_step,
    MAX(step)       AS last_step,
    COUNT(*)        AS hours
FROM gold.dim_time
GROUP BY rule_period
ORDER BY first_day;

-- ====================================================================
-- Checking 'gold.dim_transaction_type'
-- ====================================================================
-- Check for Uniqueness of Transaction Type Key in gold.dim_transaction_type
-- Expectation: No results
SELECT
    transaction_type_key,
    COUNT(*) AS duplicate_count
FROM gold.dim_transaction_type
GROUP BY transaction_type_key
HAVING COUNT(*) > 1;

-- Data Standardization & Consistency
-- Expectation: 5 rows, each with a readable name and none showing 'n/a'
SELECT
    transaction_type_key,
    transaction_type,
    transaction_type_name
FROM gold.dim_transaction_type
ORDER BY transaction_type_key;

-- ====================================================================
-- Checking 'gold.fact_transactions'
-- ====================================================================
-- Check the row counts of both fact views match silver
-- Expectation: all three counts are 6,362,620
SELECT
    (SELECT COUNT(*) FROM silver.paysim_transactions)     AS silver_rows,
    (SELECT COUNT(*) FROM gold.fact_transactions)         AS fact_rows,
    (SELECT COUNT(*) FROM gold.fact_transaction_balances) AS fact_balances_rows;

-- Check the data model connectivity between fact and dimensions
-- Expectation: No results
SELECT *
FROM gold.fact_transactions f
LEFT JOIN gold.dim_time dt
ON dt.time_key = f.time_key
LEFT JOIN gold.dim_transaction_type ty
ON ty.transaction_type_key = f.transaction_type_key
WHERE dt.time_key IS NULL OR ty.transaction_type_key IS NULL;

-- Check gold.fact_transactions exposes no balance column or mismatch flag
-- Detection rules are written against this view, and the balance columns leak
-- the outcome, so none of them may appear here.
-- Expectation: No results
SELECT
    name AS column_that_should_not_be_here
FROM sys.columns
WHERE object_id = OBJECT_ID('gold.fact_transactions')
  AND (name LIKE '%balance%' OR name LIKE '%mismatch%');

-- ====================================================================
-- Checking 'gold.fact_destination_history'
-- ====================================================================
-- Check the row count, the key and the range of the count
-- Expectation: 6,362,620 rows, 6,362,620 distinct ids, no NULLs, lowest value 0
SELECT
    COUNT(*)                            AS total_rows,
    COUNT(DISTINCT transaction_id)      AS distinct_transaction_ids,
    SUM(CASE WHEN destination_prior_transactions IS NULL THEN 1 ELSE 0 END) AS null_counts,
    MIN(destination_prior_transactions) AS lowest_count,
    MAX(destination_prior_transactions) AS highest_count
FROM gold.fact_destination_history;

-- Check the count only uses strictly earlier steps
-- For a sample of transactions (every 5,000th id), the count is worked out again
-- the slow, obvious way: count the transactions to the same destination whose
-- step is lower. Same-step and later transactions are left out.
-- Expectation: No Results
SELECT
    h.transaction_id,
    h.destination_prior_transactions AS stored_count,
    c.recounted                      AS recounted
FROM gold.fact_destination_history h
INNER JOIN (
    SELECT
        s.transaction_id,
        COUNT(e.transaction_id) AS recounted
    FROM silver.paysim_transactions s
    LEFT JOIN silver.paysim_transactions e
        ON e.destination_account = s.destination_account
       AND e.step < s.step
    WHERE s.transaction_id % 5000 = 0
    GROUP BY s.transaction_id
) c
    ON c.transaction_id = h.transaction_id
WHERE h.destination_prior_transactions != c.recounted;

-- ====================================================================
-- Checking 'gold.rule_flags'
-- ====================================================================
-- Check the rule view holds every TRANSFER and CASH_OUT transaction once,
-- and that the flags only hold 0 or 1
-- Expectation: 2,770,409 rows, 2,770,409 distinct ids, 0 bad flag values
SELECT
    COUNT(*)                       AS total_rows,
    COUNT(DISTINCT transaction_id) AS distinct_transaction_ids,
    SUM(CASE WHEN is_flagged_chosen_rule  NOT IN (0, 1)
               OR is_flagged_no_hour_rule NOT IN (0, 1)
               OR is_flagged_wider_rule   NOT IN (0, 1) THEN 1 ELSE 0 END) AS bad_flag_values
FROM gold.rule_flags;

-- ====================================================================
-- Checking the report views
-- ====================================================================
-- Check every report adds up to the same totals
-- Expectation: 6,362,620 transactions and 8,213 fraud on every row, except
--   report_fraud_destinations, which counts fraud rows only (8,213 and 8,213),
--   and report_existing_rule_performance, which leaves out day 31
--   (6,362,348 and 7,941).
SELECT 'report_fraud_overview' AS report_view, total_transactions, fraud_transactions
FROM gold.report_fraud_overview
UNION ALL
SELECT 'report_fraud_by_type', SUM(total_transactions), SUM(fraud_transactions)
FROM gold.report_fraud_by_type
UNION ALL
SELECT 'report_fraud_by_day', SUM(total_transactions), SUM(fraud_transactions)
FROM gold.report_fraud_by_day
UNION ALL
SELECT 'report_fraud_by_hour', SUM(total_transactions), SUM(fraud_transactions)
FROM gold.report_fraud_by_hour
UNION ALL
SELECT 'report_fraud_by_amount_band', SUM(total_transactions), SUM(fraud_transactions)
FROM gold.report_fraud_by_amount_band
UNION ALL
SELECT 'report_balance_quality', SUM(total_transactions), NULL
FROM gold.report_balance_quality
UNION ALL
SELECT 'report_fraud_destinations', SUM(fraud_transactions), SUM(fraud_transactions)
FROM gold.report_fraud_destinations
UNION ALL
SELECT 'report_existing_rule_performance', SUM(total_transactions), SUM(fraud_transactions)
FROM gold.report_existing_rule_performance;

-- Check the TRANSFER and CASH_OUT reports add up
-- These two reports cover only the two types that have fraud.
-- Expectation: 2,770,409 transactions and 8,213 fraud on both rows
SELECT 'report_fraud_by_type_and_hour' AS report_view, SUM(total_transactions) AS total_transactions, SUM(fraud_transactions) AS fraud_transactions
FROM gold.report_fraud_by_type_and_hour
UNION ALL
SELECT 'report_fraud_by_type_and_amount_band', SUM(total_transactions), SUM(fraud_transactions)
FROM gold.report_fraud_by_type_and_amount_band;

-- Check the missed fraud report adds up
-- Expectation: 8,213 fraud = 16 caught + 8,197 missed
SELECT
    SUM(fraud_transactions)      AS fraud_transactions,
    SUM(caught_by_existing_rule) AS caught_by_existing_rule,
    SUM(missed_by_existing_rule) AS missed_by_existing_rule
FROM gold.report_missed_fraud;

-- Check the existing rule's counts are consistent in each period
-- Expectation: both difference columns are 0
--   (flagged = true positives + false positives, fraud = true positives + false negatives)
SELECT
    rule_period,
    flagged_transactions - true_positives - false_positives AS flagged_difference,
    fraud_transactions - true_positives - false_negatives   AS fraud_difference
FROM gold.report_existing_rule_performance;

-- Check the money totals in the overview match silver
-- Expectation: both differences are 0
SELECT
    o.total_amount - s.total_amount AS total_amount_difference,
    o.fraud_amount - s.fraud_amount AS fraud_amount_difference
FROM gold.report_fraud_overview o
CROSS JOIN (
    SELECT
        SUM(amount)                                        AS total_amount,
        SUM(CASE WHEN is_fraud = 1 THEN amount ELSE 0 END) AS fraud_amount
    FROM silver.paysim_transactions
) s;
