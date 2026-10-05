/*
===============================================================================
Reconciliation Checks
===============================================================================
Script Purpose:
    This script reconciles the data across all layers, from the source file
    to gold. It checks that:
    - The bronze table holds every data line of the source file.
    - Bronze, silver and gold agree on rows, fraud counts and money totals.
    - The three layers agree for every transaction type and every day, not
      only in total.
    - The transaction ids in silver follow the documented order, so a reload
      gives every row the same id.

Usage Notes:
    - Run these checks after all three layers are loaded.
    - The first check reads the source CSV file again. Its path is the same
      one used in scripts/bronze/proc_load_bronze.sql.
    - Investigate and resolve any discrepancies found during the checks.
    - This is synthetic data.
===============================================================================
*/

-- ====================================================================
-- Source file to bronze
-- ====================================================================
-- Check bronze holds every data line of the source file
-- The file is loaded again as plain lines, one row per line, and counted.
-- The first line is the header, so data lines = lines - 1.
-- Expectation: source_data_lines = bronze_rows, and difference = 0
IF OBJECT_ID('tempdb..#source_lines') IS NOT NULL
    DROP TABLE #source_lines;

CREATE TABLE #source_lines (
    line NVARCHAR(500)
);

-- NOCOUNT is switched on for the load, so it does not print a row count for
-- every batch of 100,000 lines.
SET NOCOUNT ON;

BULK INSERT #source_lines
FROM 'C:\Users\malac\Desktop\Data\Projects\PaysimFraudAnalysis\datasets\PS_20174392719_1491204439457_log.csv'
WITH (
    ROWTERMINATOR = '0x0a',
    MAXERRORS     = 0,
    BATCHSIZE     = 100000,
    TABLOCK
);

SET NOCOUNT OFF;

SELECT
    (SELECT COUNT(*) FROM #source_lines)               AS source_lines,
    (SELECT COUNT(*) FROM #source_lines) - 1           AS source_data_lines,
    (SELECT COUNT(*) FROM bronze.paysim_transactions)  AS bronze_rows,
    (SELECT COUNT(*) FROM #source_lines) - 1
  - (SELECT COUNT(*) FROM bronze.paysim_transactions)  AS difference;

DROP TABLE #source_lines;

-- ====================================================================
-- Bronze, silver and gold side by side
-- ====================================================================
-- Check the three layers agree in total
-- Bronze amounts are FLOAT, so each one is cast to DECIMAL before it is added up.
-- Expectation: the three rows are identical apart from the layer name
SELECT
    'bronze' AS layer,
    COUNT(*)                                  AS total_rows,
    SUM(isFraud)                              AS fraud_rows,
    SUM(isFlaggedFraud)                       AS flagged_rows,
    SUM(CAST(amount AS DECIMAL(18,2)))        AS total_amount
FROM bronze.paysim_transactions
UNION ALL
SELECT
    'silver',
    COUNT(*),
    SUM(is_fraud),
    SUM(is_flagged_fraud),
    SUM(amount)
FROM silver.paysim_transactions
UNION ALL
SELECT
    'gold',
    COUNT(*),
    SUM(is_fraud),
    SUM(is_flagged_fraud),
    SUM(amount)
FROM gold.fact_transactions;

-- Check the three layers agree for every transaction type
-- Expectation: both difference columns are 0 on every row
SELECT
    b.type                      AS transaction_type,
    b.total_rows                AS bronze_rows,
    s.total_rows                AS silver_rows,
    g.total_rows                AS gold_rows,
    b.total_rows - s.total_rows AS bronze_silver_difference,
    s.total_rows - g.total_rows AS silver_gold_difference
FROM (
    SELECT type, COUNT(*) AS total_rows
    FROM bronze.paysim_transactions
    GROUP BY type
) b
FULL JOIN (
    SELECT transaction_type, COUNT(*) AS total_rows
    FROM silver.paysim_transactions
    GROUP BY transaction_type
) s
    ON s.transaction_type = b.type
FULL JOIN (
    SELECT ty.transaction_type, COUNT(*) AS total_rows
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_transaction_type ty
        ON f.transaction_type_key = ty.transaction_type_key
    GROUP BY ty.transaction_type
) g
    ON g.transaction_type = s.transaction_type
ORDER BY transaction_type;

-- Check the three layers agree for every day, on rows and on fraud
-- Bronze has no day column, so the day is worked out from the step.
-- Expectation: No Results (a row appears only for a day where the layers differ)
SELECT
    b.day_number,
    b.total_rows AS bronze_rows,
    s.total_rows AS silver_rows,
    g.total_rows AS gold_rows,
    b.fraud_rows AS bronze_fraud,
    s.fraud_rows AS silver_fraud,
    g.fraud_rows AS gold_fraud
FROM (
    SELECT (step - 1) / 24 + 1 AS day_number, COUNT(*) AS total_rows, SUM(isFraud) AS fraud_rows
    FROM bronze.paysim_transactions
    GROUP BY (step - 1) / 24 + 1
) b
FULL JOIN (
    SELECT day_number, COUNT(*) AS total_rows, SUM(is_fraud) AS fraud_rows
    FROM silver.paysim_transactions
    GROUP BY day_number
) s
    ON s.day_number = b.day_number
FULL JOIN (
    SELECT dt.day_number, COUNT(*) AS total_rows, SUM(f.is_fraud) AS fraud_rows
    FROM gold.fact_transactions f
    LEFT JOIN gold.dim_time dt
        ON f.time_key = dt.time_key
    GROUP BY dt.day_number
) g
    ON g.day_number = s.day_number
WHERE b.day_number IS NULL
   OR s.day_number IS NULL
   OR g.day_number IS NULL
   OR b.total_rows != s.total_rows
   OR s.total_rows != g.total_rows
   OR b.fraud_rows != s.fraud_rows
   OR s.fraud_rows != g.fraud_rows;

-- ====================================================================
-- Transaction id stability
-- ====================================================================
-- Check the ids follow the documented order: step, origin account, destination
-- account. That combination is unique in the data, so there is only one way to
-- put the rows in this order. If every row sorts after the row before it, the
-- ids are fixed by the data, and any reload gives each row the same id.
-- Expectation: No Results
SELECT
    transaction_id,
    step,
    origin_account,
    destination_account
FROM (
    SELECT
        transaction_id,
        step,
        origin_account,
        destination_account,
        LAG(step)                OVER (ORDER BY transaction_id) AS previous_step,
        LAG(origin_account)      OVER (ORDER BY transaction_id) AS previous_origin_account,
        LAG(destination_account) OVER (ORDER BY transaction_id) AS previous_destination_account
    FROM silver.paysim_transactions
) t
WHERE step < previous_step
   OR (step = previous_step AND origin_account < previous_origin_account)
   OR (step = previous_step AND origin_account = previous_origin_account
       AND destination_account <= previous_destination_account);
