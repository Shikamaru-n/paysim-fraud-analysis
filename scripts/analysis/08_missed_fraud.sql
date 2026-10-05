/*
===============================================================================
Analysis 08: Fraud the Existing Rule Misses
===============================================================================
Business Question:
    What does the fraud that the existing rule misses look like?

Script Purpose:
    Shows the fraud rows the existing flag caught and missed, by transaction
    type and by amount band, and how much money the missed fraud adds up to.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - All periods together. This is a description, not rule design.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Caught and missed fraud, in total
SELECT
    SUM(fraud_transactions)      AS fraud_transactions,
    SUM(caught_by_existing_rule) AS caught_by_existing_rule,
    SUM(missed_by_existing_rule) AS missed_by_existing_rule,
    CAST(SUM(missed_by_existing_rule) * 100.0 / SUM(fraud_transactions) AS DECIMAL(7,4)) AS missed_pct,
    SUM(missed_fraud_amount)     AS missed_fraud_amount
FROM gold.report_missed_fraud;

-- Caught and missed fraud by transaction type
SELECT
    transaction_type,
    SUM(fraud_transactions)      AS fraud_transactions,
    SUM(caught_by_existing_rule) AS caught_by_existing_rule,
    SUM(missed_by_existing_rule) AS missed_by_existing_rule,
    SUM(missed_fraud_amount)     AS missed_fraud_amount
FROM gold.report_missed_fraud
GROUP BY transaction_type
ORDER BY transaction_type;

-- Caught and missed fraud by amount band
SELECT
    amount_band,
    SUM(fraud_transactions)      AS fraud_transactions,
    SUM(caught_by_existing_rule) AS caught_by_existing_rule,
    SUM(missed_by_existing_rule) AS missed_by_existing_rule,
    SUM(missed_fraud_amount)     AS missed_fraud_amount
FROM gold.report_missed_fraud
GROUP BY amount_band
ORDER BY amount_band;
