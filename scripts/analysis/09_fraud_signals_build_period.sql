/*
===============================================================================
Analysis 09: Fraud Signals in the Build Period
===============================================================================
Business Question:
    Within the types where fraud happens, which signals separate fraud from
    normal?

Script Purpose:
    Looks at TRANSFER and CASH_OUT transactions and shows how the fraud rate
    changes with the hour of the day and with the amount. These are the
    signals a detection rule is allowed to use.

Usage Notes:
    - Run after the Gold Layer is created and loaded.
    - BUILD PERIOD ONLY (days 1 to 15). This script feeds the design of the
      detection rule, so every query filters on rule_period = 'build'. The test
      period must stay unseen until the finished rule is scored.
    - No balance columns are used.
    - This is synthetic data. The results describe a simulation.
===============================================================================
*/

-- The starting point: fraud rate for each type in the build period
SELECT
    transaction_type,
    SUM(total_transactions) AS total_transactions,
    SUM(fraud_transactions) AS fraud_transactions,
    CAST(SUM(fraud_transactions) * 100.0 / SUM(total_transactions) AS DECIMAL(7,4)) AS fraud_rate_pct
FROM gold.report_fraud_by_type_and_hour
WHERE rule_period = 'build'
GROUP BY transaction_type
ORDER BY transaction_type;

-- Signal 1: hour of the day, by type
SELECT
    transaction_type,
    hour_slot,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct
FROM gold.report_fraud_by_type_and_hour
WHERE rule_period = 'build'
ORDER BY transaction_type, hour_slot;

-- Signal 2: amount band, by type
SELECT
    transaction_type,
    amount_band,
    total_transactions,
    fraud_transactions,
    fraud_rate_pct
FROM gold.report_fraud_by_type_and_amount_band
WHERE rule_period = 'build'
ORDER BY transaction_type, amount_band;
