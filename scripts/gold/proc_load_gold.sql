/*
===============================================================================
Stored Procedure: Load Gold Layer (Silver -> Gold)
===============================================================================
Script Purpose:
    This stored procedure loads the tables in the 'gold' schema from the
    'silver' schema.
	Actions Performed:
		- Truncates the gold tables.
		- Inserts one row per step into gold.dim_time.
		- Inserts one row per transaction type into gold.dim_transaction_type.
		- Inserts one row per transaction into gold.fact_destination_history.

    The reference project has no gold procedure, because all of its gold objects
    are views. Here the two dimensions are small tables, so that reports do not
    have to rebuild them from 6.36 million silver rows on every query. The reason
    and the timings are in scripts/gold/ddl_gold.sql. The fact and the reports
    are views and need no loading.

Parameters:
    None.
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC gold.load_gold;
===============================================================================
*/

CREATE OR ALTER PROCEDURE gold.load_gold AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Gold Layer';
        PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading Dimension Tables';
		PRINT '------------------------------------------------';

		-- Loading gold.dim_time
        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: gold.dim_time';
		TRUNCATE TABLE gold.dim_time;
		PRINT '>> Inserting Data Into: gold.dim_time';
		INSERT INTO gold.dim_time (
			time_key,
			step,
			day_number,
			hour_slot,
			rule_period
		)
		SELECT
			ROW_NUMBER() OVER (ORDER BY step) AS time_key, -- Surrogate key. Steps run 1 to 743 with none missing, so it equals the step
			step,
			day_number,
			hour_slot,
			CASE
				WHEN day_number <= 15 THEN 'build'
				WHEN day_number <= 30 THEN 'test'
				ELSE 'excluded'
			END AS rule_period -- The build and test cutoff is defined here and nowhere else
		FROM (
			SELECT DISTINCT
				step,
				day_number,
				hour_slot
			FROM silver.paysim_transactions
		) t;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		-- Loading gold.dim_transaction_type
        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: gold.dim_transaction_type';
		TRUNCATE TABLE gold.dim_transaction_type;
		PRINT '>> Inserting Data Into: gold.dim_transaction_type';
		INSERT INTO gold.dim_transaction_type (
			transaction_type_key,
			transaction_type,
			transaction_type_name
		)
		SELECT
			ROW_NUMBER() OVER (ORDER BY transaction_type) AS transaction_type_key, -- Surrogate key
			transaction_type,
			CASE transaction_type
				WHEN 'CASH_IN'  THEN 'Cash in'
				WHEN 'CASH_OUT' THEN 'Cash out'
				WHEN 'DEBIT'    THEN 'Debit'
				WHEN 'PAYMENT'  THEN 'Payment'
				WHEN 'TRANSFER' THEN 'Transfer'
				ELSE 'n/a'
			END AS transaction_type_name -- Map source codes to readable names
		FROM (
			SELECT DISTINCT
				transaction_type
			FROM silver.paysim_transactions
		) t;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		PRINT '------------------------------------------------';
		PRINT 'Loading Fact Tables';
		PRINT '------------------------------------------------';

		-- Loading gold.fact_destination_history
        SET @start_time = GETDATE();
		PRINT '>> Truncating Table: gold.fact_destination_history';
		TRUNCATE TABLE gold.fact_destination_history;
		PRINT '>> Inserting Data Into: gold.fact_destination_history';
		-- RANK() numbers a destination's transactions in step order, and gives every
		-- transaction in the same step the same number. So RANK() - 1 is the number of
		-- transactions the destination received in strictly earlier steps: nothing from
		-- the same step, and nothing from later steps.
		-- WITH (TABLOCK) keeps the 6.36 million row insert minimally logged, as in silver.
		INSERT INTO gold.fact_destination_history WITH (TABLOCK) (
			transaction_id,
			destination_prior_transactions
		)
		SELECT
			transaction_id,
			RANK() OVER (PARTITION BY destination_account ORDER BY step) - 1 AS destination_prior_transactions
		FROM silver.paysim_transactions;
        SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Gold Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='

	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURRED DURING LOADING GOLD LAYER'
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Number: ' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error State: ' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END
