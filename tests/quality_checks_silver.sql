/*
===============================================================================
Quality Checks
===============================================================================
Script Purpose:
    This script performs various quality checks for data consistency, accuracy,
    and standardization across the 'silver' layer. It includes checks for:
    - Row count and totals matching the 'bronze' layer.
    - Null or duplicate primary keys.
    - Unwanted spaces in string fields.
    - Data standardization and consistency.
    - Derived columns and flag columns holding the values they should.

Usage Notes:
    - Run these checks after data loading Silver Layer.
    - Investigate and resolve any discrepancies found during the checks.
    - This is synthetic data.
===============================================================================
*/

-- ====================================================================
-- Checking 'silver.paysim_transactions'
-- ====================================================================
-- Check the row count matches bronze
-- Expectation: both counts are 6,362,620 and the difference is 0
SELECT
    (SELECT COUNT(*) FROM bronze.paysim_transactions) AS bronze_rows,
    (SELECT COUNT(*) FROM silver.paysim_transactions) AS silver_rows,
    (SELECT COUNT(*) FROM bronze.paysim_transactions)
  - (SELECT COUNT(*) FROM silver.paysim_transactions) AS difference;

-- Check for NULLs or Duplicates in Primary Key
-- Expectation: No Results
SELECT
    transaction_id,
    COUNT(*)
FROM silver.paysim_transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1 OR transaction_id IS NULL;

-- Check the primary key runs from 1 to the row count with no gaps
-- Expectation: min_id = 1, and max_id = total_rows
SELECT
    MIN(transaction_id) AS min_id,
    MAX(transaction_id) AS max_id,
    COUNT(*)            AS total_rows
FROM silver.paysim_transactions;

-- Check the primary key follows the step order
-- Expectation: No Results (no row has a higher step than the row after it)
SELECT
    transaction_id,
    step,
    next_step
FROM (
    SELECT
        transaction_id,
        step,
        LEAD(step) OVER (ORDER BY transaction_id) AS next_step
    FROM silver.paysim_transactions
) t
WHERE step > next_step;

-- Check for NULLs in every column
-- Expectation: all zeros
SELECT
    SUM(CASE WHEN step                            IS NULL THEN 1 ELSE 0 END) AS null_step,
    SUM(CASE WHEN day_number                      IS NULL THEN 1 ELSE 0 END) AS null_day_number,
    SUM(CASE WHEN hour_slot                       IS NULL THEN 1 ELSE 0 END) AS null_hour_slot,
    SUM(CASE WHEN transaction_type                IS NULL THEN 1 ELSE 0 END) AS null_transaction_type,
    SUM(CASE WHEN amount                          IS NULL THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN origin_account                  IS NULL THEN 1 ELSE 0 END) AS null_origin_account,
    SUM(CASE WHEN origin_old_balance              IS NULL THEN 1 ELSE 0 END) AS null_origin_old_balance,
    SUM(CASE WHEN origin_new_balance              IS NULL THEN 1 ELSE 0 END) AS null_origin_new_balance,
    SUM(CASE WHEN destination_account             IS NULL THEN 1 ELSE 0 END) AS null_destination_account,
    SUM(CASE WHEN destination_old_balance         IS NULL THEN 1 ELSE 0 END) AS null_destination_old_balance,
    SUM(CASE WHEN destination_new_balance         IS NULL THEN 1 ELSE 0 END) AS null_destination_new_balance,
    SUM(CASE WHEN is_fraud                        IS NULL THEN 1 ELSE 0 END) AS null_is_fraud,
    SUM(CASE WHEN is_flagged_fraud                IS NULL THEN 1 ELSE 0 END) AS null_is_flagged_fraud,
    SUM(CASE WHEN is_merchant_destination         IS NULL THEN 1 ELSE 0 END) AS null_is_merchant_destination,
    SUM(CASE WHEN is_zero_amount                  IS NULL THEN 1 ELSE 0 END) AS null_is_zero_amount,
    SUM(CASE WHEN is_origin_balance_mismatch      IS NULL THEN 1 ELSE 0 END) AS null_is_origin_balance_mismatch,
    SUM(CASE WHEN is_destination_balance_mismatch IS NULL THEN 1 ELSE 0 END) AS null_is_destination_balance_mismatch
FROM silver.paysim_transactions;

-- Check for Unwanted Spaces
-- Expectation: No Results
SELECT
    transaction_type, origin_account, destination_account
FROM silver.paysim_transactions
WHERE transaction_type    != TRIM(transaction_type)
   OR origin_account      != TRIM(origin_account)
   OR destination_account != TRIM(destination_account);

-- Data Standardization & Consistency
-- Expectation: CASH_IN, CASH_OUT, DEBIT, PAYMENT, TRANSFER
SELECT DISTINCT
    transaction_type
FROM silver.paysim_transactions;

-- Check the money totals match bronze
-- Bronze is FLOAT and silver is DECIMAL. Each bronze value is cast to DECIMAL
-- before it is added up. Adding up 6.36 million FLOAT values first and casting
-- the total afterwards drifts by a few cents, because FLOAT cannot hold a total
-- this large exactly, and that would look like a difference when there is none.
-- Expectation: each silver total equals its bronze total
SELECT
    'bronze' AS layer,
    SUM(CAST(amount         AS DECIMAL(18,2))) AS total_amount,
    SUM(CAST(oldbalanceOrg  AS DECIMAL(18,2))) AS total_origin_old_balance,
    SUM(CAST(newbalanceOrig AS DECIMAL(18,2))) AS total_origin_new_balance,
    SUM(CAST(oldbalanceDest AS DECIMAL(18,2))) AS total_destination_old_balance,
    SUM(CAST(newbalanceDest AS DECIMAL(18,2))) AS total_destination_new_balance
FROM bronze.paysim_transactions
UNION ALL
SELECT
    'silver',
    SUM(amount),
    SUM(origin_old_balance),
    SUM(origin_new_balance),
    SUM(destination_old_balance),
    SUM(destination_new_balance)
FROM silver.paysim_transactions;

-- Check for Negative Amounts or Balances
-- Expectation: No Results
SELECT
    transaction_id
FROM silver.paysim_transactions
WHERE amount < 0
   OR origin_old_balance < 0
   OR origin_new_balance < 0
   OR destination_old_balance < 0
   OR destination_new_balance < 0;

-- Check the fraud labels match bronze
-- Expectation: 8,213 fraud rows and 16 flagged rows in both layers
SELECT
    'bronze' AS layer,
    SUM(isFraud)        AS fraud_rows,
    SUM(isFlaggedFraud) AS flagged_rows
FROM bronze.paysim_transactions
UNION ALL
SELECT
    'silver',
    SUM(is_fraud),
    SUM(is_flagged_fraud)
FROM silver.paysim_transactions;

-- Check the derived time columns
-- Expectation: days 1 to 31, hour slots 0 to 23
SELECT
    MIN(day_number) AS min_day,
    MAX(day_number) AS max_day,
    MIN(hour_slot)  AS min_hour_slot,
    MAX(hour_slot)  AS max_hour_slot
FROM silver.paysim_transactions;

-- Check day and hour slot rebuild the step they came from
-- Expectation: No Results
SELECT
    step,
    day_number,
    hour_slot
FROM silver.paysim_transactions
WHERE (day_number - 1) * 24 + hour_slot + 1 != step;

-- Check the flag columns only hold 0 or 1
-- Expectation: No Results
SELECT
    transaction_id
FROM silver.paysim_transactions
WHERE is_fraud                        NOT IN (0, 1)
   OR is_flagged_fraud                NOT IN (0, 1)
   OR is_merchant_destination         NOT IN (0, 1)
   OR is_zero_amount                  NOT IN (0, 1)
   OR is_origin_balance_mismatch      NOT IN (0, 1)
   OR is_destination_balance_mismatch NOT IN (0, 1);

-- Check the merchant flag against the transaction type
-- Expectation: PAYMENT rows are all merchant destinations, and no other type has any
SELECT
    transaction_type,
    COUNT(*)                     AS total_rows,
    SUM(is_merchant_destination) AS merchant_rows
FROM silver.paysim_transactions
GROUP BY transaction_type
ORDER BY transaction_type;

-- Check the zero amount flag
-- Expectation: 16 rows, all fraud
SELECT
    SUM(is_zero_amount)            AS zero_amount_rows,
    SUM(is_zero_amount * is_fraud) AS zero_amount_fraud_rows
FROM silver.paysim_transactions;

-- Check the balance mismatch flags against the profiling counts
-- The bronze side repeats the rule from scripts/bronze/profile_bronze.sql: cast
-- to DECIMAL(18,2), then count rows where the new balance is more than 0.01 away
-- from what the old balance and the amount say it should be.
-- Expectation: both difference columns are 0 for every type
SELECT
    s.transaction_type,
    b.orig_mismatch_rows                        AS bronze_orig_mismatch_rows,
    s.orig_mismatch_rows                        AS silver_orig_mismatch_rows,
    b.orig_mismatch_rows - s.orig_mismatch_rows AS orig_difference,
    b.dest_mismatch_rows                        AS bronze_dest_mismatch_rows,
    s.dest_mismatch_rows                        AS silver_dest_mismatch_rows,
    b.dest_mismatch_rows - s.dest_mismatch_rows AS dest_difference
FROM (
    SELECT
        transaction_type,
        SUM(is_origin_balance_mismatch)      AS orig_mismatch_rows,
        SUM(is_destination_balance_mismatch) AS dest_mismatch_rows
    FROM silver.paysim_transactions
    GROUP BY transaction_type
) s
LEFT JOIN (
    SELECT
        type,
        SUM(CASE WHEN ABS(expected_newbalanceOrig - newbalanceOrig) > 0.01 THEN 1 ELSE 0 END) AS orig_mismatch_rows,
        SUM(CASE WHEN ABS(expected_newbalanceDest - newbalanceDest) > 0.01 THEN 1 ELSE 0 END) AS dest_mismatch_rows
    FROM (
        SELECT
            type,
            CAST(newbalanceOrig AS DECIMAL(18,2)) AS newbalanceOrig,
            CAST(newbalanceDest AS DECIMAL(18,2)) AS newbalanceDest,
            CASE WHEN type = 'CASH_IN' THEN CAST(oldbalanceOrg AS DECIMAL(18,2)) + CAST(amount AS DECIMAL(18,2))
                 ELSE CAST(oldbalanceOrg AS DECIMAL(18,2)) - CAST(amount AS DECIMAL(18,2))
            END AS expected_newbalanceOrig,
            CASE WHEN type = 'CASH_IN' THEN CAST(oldbalanceDest AS DECIMAL(18,2)) - CAST(amount AS DECIMAL(18,2))
                 ELSE CAST(oldbalanceDest AS DECIMAL(18,2)) + CAST(amount AS DECIMAL(18,2))
            END AS expected_newbalanceDest
        FROM bronze.paysim_transactions
    ) t
    GROUP BY type
) b
    ON b.type = s.transaction_type
ORDER BY s.transaction_type;
