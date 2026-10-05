/*
===============================================================================
Analysis 04: Fraud by Hour of the Day
===============================================================================
Business Question:
    At what time of day is fraud most concentrated?

Script Purpose:
    Shows fraud and total transactions for each of the 24 hour slots, then
    compares the quiet hours with the busy hours.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - hour_slot 0 is the first hour of each day. The data does not say which
      clock hour that is.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Fraud and total transactions per hour slot
SELECT
    hour_slot,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct
FROM gold.report_fraud_by_hour
ORDER BY hour_slot;

-- Quiet hours against busy hours
-- An hour slot is called quiet here if it has fewer than 100,000 transactions
-- across the whole month.
-- The quiet slots are 0 to 7 and 23, so they are not one unbroken range.
-- first_slot and last_slot only show the lowest and highest slot in each group.
SELECT
    CASE
        WHEN total_transactions < 100000 THEN 'quiet hours'
        ELSE 'busy hours'
    END                     AS hour_kind,
    COUNT(*)                AS hour_slots,
    MIN(hour_slot)          AS first_slot,
    MAX(hour_slot)          AS last_slot,
    SUM(total_transactions) AS total_transactions,
    SUM(fraud_transactions) AS fraud_transactions,
    CAST(SUM(fraud_transactions) * 100.0 / SUM(total_transactions) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM gold.report_fraud_by_hour
GROUP BY
    CASE
        WHEN total_transactions < 100000 THEN 'quiet hours'
        ELSE 'busy hours'
    END
ORDER BY hour_kind;
