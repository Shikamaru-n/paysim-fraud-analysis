/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.

    No rows are removed. Rows with problems are marked with flag columns instead,
    so the silver row count always equals the bronze row count.

Parameters:
    None.
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC silver.load_silver;
===============================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading PaySim Table';
		PRINT '------------------------------------------------';

		-- Loading silver.paysim_transactions
        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.paysim_transactions';
		TRUNCATE TABLE silver.paysim_transactions;
		PRINT '>> Inserting Data Into: silver.paysim_transactions';
		-- WITH (TABLOCK) is not in the reference project. It locks the whole table for
		-- the insert, which lets SQL Server log the load minimally instead of writing
		-- all 6.36 million rows to the transaction log in one transaction. Nothing else
		-- reads this table during a load, so the lock costs nothing.
		INSERT INTO silver.paysim_transactions WITH (TABLOCK) (
			transaction_id,
			step,
			day_number,
			hour_slot,
			transaction_type,
			amount,
			origin_account,
			origin_old_balance,
			origin_new_balance,
			destination_account,
			destination_old_balance,
			destination_new_balance,
			is_fraud,
			is_flagged_fraud,
			is_merchant_destination,
			is_zero_amount,
			is_origin_balance_mismatch,
			is_destination_balance_mismatch
		)
		SELECT
			-- Step, origin and destination together are unique in the data, so this
			-- order gives every row the same id on every reload.
			ROW_NUMBER() OVER (ORDER BY step, origin_account, destination_account) AS transaction_id,
			step,
			(step - 1) / 24 + 1 AS day_number, -- Whole-number division: steps 1 to 24 are day 1, step 25 is day 2
			(step - 1) % 24     AS hour_slot,  -- 0 to 23, where 0 is the first hour of each day
			transaction_type,
			amount,
			origin_account,
			origin_old_balance,
			origin_new_balance,
			destination_account,
			destination_old_balance,
			destination_new_balance,
			is_fraud,
			is_flagged_fraud,
			CASE
				WHEN LEFT(destination_account, 1) = 'M' THEN 1
				ELSE 0
			END AS is_merchant_destination, -- Merchant accounts start with 'M', customers with 'C'
			CASE
				WHEN amount = 0 THEN 1
				ELSE 0
			END AS is_zero_amount,
			-- Balance mismatch flags. A row is a mismatch only when the new balance is more
			-- than 0.01 away from what the old balance and the amount say it should be.
			-- A gap of exactly one cent is treated as rounding in the source, not as a
			-- mismatch. Hundreds of thousands of rows are off by a single cent, and
			-- flagging them would bury the rows where the balances really do not add up.
			CASE
				WHEN transaction_type = 'CASH_IN' AND ABS(origin_new_balance - (origin_old_balance + amount)) > 0.01 THEN 1
				WHEN transaction_type != 'CASH_IN' AND ABS(origin_new_balance - (origin_old_balance - amount)) > 0.01 THEN 1
				ELSE 0
			END AS is_origin_balance_mismatch, -- Money leaves the origin, except for CASH_IN where it arrives
			CASE
				WHEN transaction_type = 'CASH_IN' AND ABS(destination_new_balance - (destination_old_balance - amount)) > 0.01 THEN 1
				WHEN transaction_type != 'CASH_IN' AND ABS(destination_new_balance - (destination_old_balance + amount)) > 0.01 THEN 1
				ELSE 0
			END AS is_destination_balance_mismatch -- Money arrives at the destination, except for CASH_IN where it leaves
		FROM (
			-- Rename the columns and cast the money columns first, so the flags above
			-- are worked out on exact DECIMAL values and not on FLOAT.
			SELECT
				step,
				type                                  AS transaction_type,
				CAST(amount         AS DECIMAL(18,2)) AS amount,
				nameOrig                              AS origin_account,
				CAST(oldbalanceOrg  AS DECIMAL(18,2)) AS origin_old_balance,
				CAST(newbalanceOrig AS DECIMAL(18,2)) AS origin_new_balance,
				nameDest                              AS destination_account,
				CAST(oldbalanceDest AS DECIMAL(18,2)) AS destination_old_balance,
				CAST(newbalanceDest AS DECIMAL(18,2)) AS destination_new_balance,
				isFraud                               AS is_fraud,
				isFlaggedFraud                        AS is_flagged_fraud
			FROM bronze.paysim_transactions
		) t;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Silver Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='

	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURRED DURING LOADING SILVER LAYER'
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Number: ' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error State: ' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END
