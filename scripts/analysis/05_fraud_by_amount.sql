/*
===============================================================================
Analysis 05: Fraud by Amount
===============================================================================
Business Question:
    What amounts does fraud use, compared with normal transactions?

Script Purpose:
    Shows the fraud rate in each amount band, compares fraud and normal amounts
    inside the two types that have fraud, and counts the fraud rows that sit on
    the two unusual amounts (zero, and the largest fraud amount).

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Fraud rate by amount band, all types
SELECT
    amount_band,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct
FROM gold.report_fraud_by_amount_band
ORDER BY amount_band;

-- Fraud against normal amounts, inside TRANSFER and CASH_OUT
-- Comparing inside one type is fairer than comparing fraud with all transactions,
-- because small payments would pull the normal average down.
SELECT
    ty.transaction_type,
    f.is_fraud,
    COUNT(*)                            AS total_transactions,
    MIN(f.amount)                       AS min_amount,
    CAST(AVG(f.amount) AS DECIMAL(18,2)) AS avg_amount,
    MAX(f.amount)                       AS max_amount
FROM gold.fact_transactions f
LEFT JOIN gold.dim_transaction_type ty
    ON f.transaction_type_key = ty.transaction_type_key
WHERE ty.transaction_type IN ('TRANSFER', 'CASH_OUT')
GROUP BY ty.transaction_type, f.is_fraud
ORDER BY ty.transaction_type, f.is_fraud;

-- Fraud rows on the two unusual amounts
-- Zero amounts, and the largest fraud amount (to see whether it is a hard cap).
SELECT
    SUM(CASE WHEN amount = 0 THEN 1 ELSE 0 END)          AS fraud_rows_with_zero_amount,
    MAX(amount)                                          AS largest_fraud_amount,
    SUM(CASE WHEN amount = 10000000 THEN 1 ELSE 0 END)   AS fraud_rows_at_10_million,
    SUM(CASE WHEN amount > 10000000 THEN 1 ELSE 0 END)   AS fraud_rows_above_10_million
FROM gold.fact_transactions
WHERE is_fraud = 1;
