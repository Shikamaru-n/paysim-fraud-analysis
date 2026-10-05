/*
===============================================================================
Analysis 01: Fraud Overview
===============================================================================
Business Question:
    How big is the fraud problem, in transactions and in money?

Script Purpose:
    Shows the total number of transactions, how many are fraud, and fraud's
    share of the transactions and of the money. All periods together.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Fraud's share of the transactions (fraud_rate_pct) against its share of the
-- money (fraud_amount_pct)
SELECT
    total_transactions,
    fraud_transactions,
    fraud_rate_pct,
    total_amount,
    fraud_amount,
    fraud_amount_pct
FROM gold.report_fraud_overview;
