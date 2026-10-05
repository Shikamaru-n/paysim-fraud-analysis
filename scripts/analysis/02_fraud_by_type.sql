/*
===============================================================================
Analysis 02: Fraud by Transaction Type
===============================================================================
Business Question:
    Which transaction types does fraud happen in?

Script Purpose:
    Shows, for each transaction type, the number of transactions, the number
    that are fraud, and fraud's share of the transactions and of the money.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Fraud by transaction type, most fraud first
SELECT
    transaction_type,
    transaction_type_name,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct,
    total_amount,
    fraud_amount,
    fraud_amount_pct
FROM gold.report_fraud_by_type
ORDER BY fraud_transactions DESC, total_transactions DESC;
