/*
===============================================================================
Analysis 06: Where the Fraud Money Goes
===============================================================================
Business Question:
    Where does the fraud money go: repeated destination accounts, merchants?

Script Purpose:
    Shows how many destination accounts received fraud more than once, whether
    any fraud goes to merchants, and whether fraud transfers and fraud cash-outs
    come in pairs.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - These queries describe how the fraud works. They use is_fraud and look
      across the whole month, so none of them can be used as a detection rule.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- Do fraud transactions go to the same destination accounts repeatedly?
-- Each row: this many accounts received this many fraud transactions each.
SELECT
    fraud_transactions_received,
    destination_accounts,
    fraud_transactions
FROM gold.report_fraud_destinations
ORDER BY fraud_transactions_received;

-- Does any fraud go to merchants?
SELECT
    CASE
        WHEN is_merchant_destination = 1 THEN 'merchant'
        ELSE 'customer'
    END           AS destination_kind,
    COUNT(*)      AS total_transactions,
    SUM(is_fraud) AS fraud_transactions
FROM gold.fact_transactions
GROUP BY is_merchant_destination
ORDER BY destination_kind;

-- Do fraud transfers and fraud cash-outs come in pairs?
-- Fraud rows are grouped by step and amount. Each row of the result says: this
-- many groups hold this many fraud transfers and this many fraud cash-outs.
-- A group with 1 transfer and 1 cash-out is a pair: the same amount moved out
-- by transfer and cashed out in the same hour.
SELECT
    fraud_transfers_in_group,
    fraud_cash_outs_in_group,
    COUNT(*)                                                  AS groups,
    SUM(fraud_transfers_in_group + fraud_cash_outs_in_group)  AS fraud_transactions
FROM (
    SELECT
        f.time_key,
        f.amount,
        SUM(CASE WHEN ty.transaction_type = 'TRANSFER' THEN 1 ELSE 0 END) AS fraud_transfers_in_group,
        SUM(CASE WHEN ty.transaction_type = 'CASH_OUT' THEN 1 ELSE 0 END) AS fraud_cash_outs_in_group
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    WHERE f.is_fraud = 1
    GROUP BY f.time_key, f.amount
) t
GROUP BY fraud_transfers_in_group, fraud_cash_outs_in_group
ORDER BY groups DESC;

-- Is the cash-out made from the account the transfer went to?
-- Counts fraud transfers whose destination account is the origin account of a
-- fraud cash-out.
SELECT
    COUNT(*) AS fraud_transfers,
    SUM(CASE WHEN co.origin_account IS NOT NULL THEN 1 ELSE 0 END) AS transfers_whose_destination_then_cashes_out
FROM (
    SELECT
        f.destination_account
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    WHERE f.is_fraud = 1
      AND ty.transaction_type = 'TRANSFER'
) tr
LEFT JOIN (
    SELECT DISTINCT
        f.origin_account
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    WHERE f.is_fraud = 1
      AND ty.transaction_type = 'CASH_OUT'
) co
    ON tr.destination_account = co.origin_account;
