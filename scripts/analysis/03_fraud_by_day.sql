/*
===============================================================================
Analysis 03: Fraud by Day
===============================================================================
Business Question:
    On which days does fraud happen, and how does it compare with normal volume?

Script Purpose:
    Shows fraud and normal transactions for each of the 31 days, then sums up
    how steady fraud is from day to day compared with normal volume.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - Day 31 has 23 hours, because the steps stop at 743.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Fraud and normal transactions per day
SELECT
    day_number,
    rule_period,
    hours_in_day,
    total_transactions,
    normal_transactions,
    fraud_transactions,
    fraud_rate_pct
FROM gold.report_fraud_by_day
ORDER BY day_number;

-- How much do the daily counts vary?
-- A small gap between the lowest and highest day means the count is steady.
SELECT
    MIN(fraud_transactions)  AS lowest_fraud_day,
    MAX(fraud_transactions)  AS highest_fraud_day,
    AVG(fraud_transactions)  AS average_fraud_per_day,
    MIN(normal_transactions) AS lowest_normal_day,
    MAX(normal_transactions) AS highest_normal_day,
    AVG(normal_transactions) AS average_normal_per_day
FROM gold.report_fraud_by_day;

-- Busy days against thin days
-- A day is called thin here if it has fewer than 100,000 normal transactions.
SELECT
    CASE
        WHEN normal_transactions < 100000 THEN 'thin day'
        ELSE 'busy day'
    END                      AS day_kind,
    COUNT(*)                 AS days,
    SUM(total_transactions)  AS total_transactions,
    SUM(normal_transactions) AS normal_transactions,
    SUM(fraud_transactions)  AS fraud_transactions,
    CAST(SUM(fraud_transactions) * 100.0 / SUM(total_transactions) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM gold.report_fraud_by_day
GROUP BY
    CASE
        WHEN normal_transactions < 100000 THEN 'thin day'
        ELSE 'busy day'
    END
ORDER BY day_kind;
