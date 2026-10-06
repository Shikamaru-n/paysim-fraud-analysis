/*
===============================================================================
Stored Procedure: Load Bronze Layer (Source -> Bronze)
===============================================================================
Script Purpose:
    This stored procedure loads data into the 'bronze' schema from the PaySim CSV file.
    It performs the following actions:
    - Truncates the bronze table before loading data.
    - Uses the `BULK INSERT` command to load data from the csv File to the bronze table.

Parameters:
    None.
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC bronze.load_bronze;
===============================================================================
*/
CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN
	DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME;
	BEGIN TRY
		SET @batch_start_time = GETDATE();
		PRINT '================================================';
		PRINT 'Loading Bronze Layer';
		PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading PaySim Table';
		PRINT '------------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: bronze.paysim_transactions';
		TRUNCATE TABLE bronze.paysim_transactions;
		PRINT '>> Inserting Data Into: bronze.paysim_transactions';
		-- Two options below are not in the reference project, and both matter here.
		--
		-- ROWTERMINATOR = '0x0a': the CSV uses LF line endings, but BULK INSERT defaults
		-- to CRLF. Writing '\n' does not help, because BULK INSERT silently converts it
		-- back to '\r\n'. The hex form is passed through literally, so it is the only
		-- way to ask for a bare line feed. Without it the load fails with
		-- "the column is too long in the data file for row 1, column 11", which sounds
		-- like a column sizing problem and is not. See docs/row_terminator_note.md.
		--
		-- MAXERRORS = 0: the default is 10, which means BULK INSERT skips rows it cannot
		-- convert and still reports success. A partial load that looks clean is worse
		-- than a failed one, especially since the reconciliation checks compare row
		-- counts across the layers. Setting it to 0 makes any conversion failure stop the load.
		-- See docs/maxerrors_note.md.
		--
		-- BATCHSIZE = 100000: without it the whole 6.36 million rows is one transaction,
		-- and every page it touches has to stay in the buffer pool until the end. On a
		-- machine short of memory that stalls completely. Committing in batches lets the
		-- engine flush and reuse pages as it goes.
		BULK INSERT bronze.paysim_transactions
		FROM 'C:\Users\malac\Desktop\Data\Projects\PaysimFraudAnalysis\datasets\PS_20174392719_1491204439457_log.csv'
		WITH (
			FIRSTROW = 2,
			FIELDTERMINATOR = ',',
			ROWTERMINATOR   = '0x0a',
			MAXERRORS       = 0,
			BATCHSIZE       = 100000,
			TABLOCK
		);
		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Bronze Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='
	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURRED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Number: ' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error State: ' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END
