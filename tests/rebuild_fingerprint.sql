/*
===============================================================================
Rebuild Fingerprint
===============================================================================
Script Purpose:
    This script prints a fingerprint of the whole database: row counts, money
    totals, fingerprints of the ids, the destination history and the rule
    flags, and the rule scores.

    It is used to prove the project is reproducible. Save its output to a
    file, rebuild the database from scratch with scripts/run_all.sql, save the
    output again, and compare the two files. They must be identical.

Usage Notes:
    - Run with sqlcmd and save the output, for example:
        sqlcmd -S localhost\SQLEXPRESS -E -C -W -d PaysimFraudAnalysis
               -i tests\rebuild_fingerprint.sql -o fingerprint.txt
    - Nothing here depends on when the data was loaded, so two runs on the
      same data give exactly the same text.
    - CHECKSUM_AGG gives one number for a whole set of rows. If any row
      changes, the number almost certainly changes too.
    - This is synthetic data.
===============================================================================
*/

SET NOCOUNT ON;

-- Row counts in every table and fact view
SELECT 'bronze.paysim_transactions' AS object_name, COUNT(*) AS total_rows FROM bronze.paysim_transactions
UNION ALL
SELECT 'silver.paysim_transactions', COUNT(*) FROM silver.paysim_transactions
UNION ALL
SELECT 'gold.dim_time', COUNT(*) FROM gold.dim_time
UNION ALL
SELECT 'gold.dim_transaction_type', COUNT(*) FROM gold.dim_transaction_type
UNION ALL
SELECT 'gold.fact_destination_history', COUNT(*) FROM gold.fact_destination_history
UNION ALL
SELECT 'gold.fact_transactions', COUNT(*) FROM gold.fact_transactions
UNION ALL
SELECT 'gold.rule_flags', COUNT(*) FROM gold.rule_flags;

-- Money totals, fraud counts and flag counts in silver
SELECT
    SUM(amount)                          AS total_amount,
    SUM(origin_old_balance)              AS total_origin_old_balance,
    SUM(origin_new_balance)              AS total_origin_new_balance,
    SUM(destination_old_balance)         AS total_destination_old_balance,
    SUM(destination_new_balance)         AS total_destination_new_balance,
    SUM(is_fraud)                        AS fraud_rows,
    SUM(is_flagged_fraud)                AS flagged_rows,
    SUM(is_merchant_destination)         AS merchant_destination_rows,
    SUM(is_zero_amount)                  AS zero_amount_rows,
    SUM(is_origin_balance_mismatch)      AS origin_mismatch_rows,
    SUM(is_destination_balance_mismatch) AS destination_mismatch_rows
FROM silver.paysim_transactions;

-- Id fingerprint: which row got which transaction_id
SELECT
    MIN(transaction_id)                                                              AS min_id,
    MAX(transaction_id)                                                              AS max_id,
    SUM(CAST(transaction_id AS BIGINT) * step)                                       AS sum_of_id_times_step,
    CHECKSUM_AGG(CHECKSUM(transaction_id, step, origin_account, destination_account)) AS id_fingerprint
FROM silver.paysim_transactions;

-- Destination history fingerprint
SELECT
    SUM(CAST(destination_prior_transactions AS BIGINT))                 AS sum_of_prior_transactions,
    MAX(destination_prior_transactions)                                 AS highest_prior_transactions,
    CHECKSUM_AGG(CHECKSUM(transaction_id, destination_prior_transactions)) AS history_fingerprint
FROM gold.fact_destination_history;

-- Rule flag fingerprint
SELECT
    SUM(is_flagged_chosen_rule)  AS chosen_rule_flagged,
    SUM(is_flagged_no_hour_rule) AS no_hour_rule_flagged,
    SUM(is_flagged_wider_rule)   AS wider_rule_flagged,
    CHECKSUM_AGG(CHECKSUM(transaction_id, is_flagged_chosen_rule, is_flagged_no_hour_rule, is_flagged_wider_rule)) AS rule_flag_fingerprint
FROM gold.rule_flags;

-- Rule scores, build and test
SELECT
    rule_name,
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
FROM gold.report_rule_performance
ORDER BY rule_name, rule_period;
