/*
===============================================================================
Analysis 07: Existing Rule Performance
===============================================================================
Business Question:
    How badly does the existing rule perform?

Script Purpose:
    Scores the existing fraud flag (is_flagged_fraud) for the build period and
    the test period, then looks at what the flag actually marked.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - Day 31 is excluded from rule evaluation, because it has no normal
      transactions.
    - Recall and false positive rate are the fair comparison between periods.
      Read precision next to the period's fraud rate.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- The existing rule, scored per period
SELECT
    rule_period,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct,
    flagged_transactions,
    true_positives,
    false_positives,
    false_negatives,
    precision_pct,
    recall_pct,
    false_positive_rate_pct
FROM gold.report_existing_rule_performance
ORDER BY rule_period;

-- What did the existing rule flag?
-- All periods, including day 31, to account for every flagged row.
SELECT
    dt.rule_period,
    ty.transaction_type,
    COUNT(*)        AS flagged_transactions,
    SUM(f.is_fraud) AS flagged_that_are_fraud,
    MIN(f.amount)   AS smallest_flagged_amount,
    MAX(f.amount)   AS largest_flagged_amount
FROM gold.fact_transactions f
LEFT JOIN gold.dim_time dt
    ON f.time_key = dt.time_key
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
WHERE f.is_flagged_fraud = 1
GROUP BY dt.rule_period, ty.transaction_type
ORDER BY dt.rule_period;

-- Does the flag behave like its description?
-- The dataset description says the flag marks transfers of more than 200,000.
-- This counts the transfers over 200,000 and how many of them were flagged.
SELECT
    COUNT(*)                AS transfers_over_200k,
    SUM(f.is_fraud)         AS fraud_transactions,
    SUM(f.is_flagged_fraud) AS flagged_transactions
FROM gold.fact_transactions f
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
WHERE ty.transaction_type = 'TRANSFER'
  AND f.amount > 200000;
