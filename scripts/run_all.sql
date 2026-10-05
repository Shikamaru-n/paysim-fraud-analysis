/*
===============================================================================
Run All: Rebuild the Whole Project from Scratch
===============================================================================
Script Purpose:
    This script runs every script in the project, in order:
        1. Create the database and schemas
        2. Bronze layer : create the table, load the CSV
        3. Silver layer : create the table, load from bronze
        4. Gold layer   : create the tables and views, load from silver
        5. Tests        : quality checks, rule checks, reconciliation checks
        6. Profiling and analysis scripts

    It exists to prove the project is reproducible: starting from nothing but
    the CSV file, it rebuilds everything and reruns every check.

WARNING:
    The first step drops the entire 'PaysimFraudAnalysis' database if it exists.
    Everything is rebuilt from the CSV file, but proceed with caution.

Usage Notes:
    - This script only works with sqlcmd, or in SSMS with SQLCMD Mode turned on,
      because it uses the sqlcmd include command to pull in the other scripts.
    - Run it from the project's root folder, so the relative paths resolve:
        sqlcmd -S localhost\SQLEXPRESS -E -C -d master -i scripts\run_all.sql
    - Before running, set the CSV path in scripts\bronze\proc_load_bronze.sql
      and tests\reconciliation_checks.sql to where the file is on your machine.
    - It takes roughly 10 to 20 minutes on an 8 GB laptop, depending on how
      much memory is free. Close other applications first: the silver load
      needs free memory for a large sort.
    - The load procedures catch their own errors and print them. So after each
      load this script checks the table is not empty, and stops if it is.
===============================================================================
*/

:on error exit

PRINT '################################################';
PRINT 'Step 1: Create the database and schemas';
PRINT '################################################';
:r .\scripts\init_database.sql
GO

PRINT '################################################';
PRINT 'Step 2: Bronze layer';
PRINT '################################################';
:r .\scripts\bronze\ddl_bronze.sql
GO
:r .\scripts\bronze\proc_load_bronze.sql
GO
EXEC bronze.load_bronze;
GO
IF (SELECT COUNT(*) FROM bronze.paysim_transactions) = 0
    RAISERROR('The bronze load produced no rows. Stopping.', 16, 1);
GO

PRINT '################################################';
PRINT 'Step 3: Silver layer';
PRINT '################################################';
:r .\scripts\silver\ddl_silver.sql
GO
:r .\scripts\silver\proc_load_silver.sql
GO
EXEC silver.load_silver;
GO
IF (SELECT COUNT(*) FROM silver.paysim_transactions) = 0
    RAISERROR('The silver load produced no rows. Stopping.', 16, 1);
GO

PRINT '################################################';
PRINT 'Step 4: Gold layer';
PRINT '################################################';
:r .\scripts\gold\ddl_gold.sql
GO
:r .\scripts\gold\proc_load_gold.sql
GO
EXEC gold.load_gold;
GO
IF (SELECT COUNT(*) FROM gold.fact_destination_history) = 0
    RAISERROR('The gold load produced no rows. Stopping.', 16, 1);
GO

PRINT '################################################';
PRINT 'Step 5: Tests';
PRINT '################################################';
PRINT '>> tests\quality_checks_silver.sql';
:r .\tests\quality_checks_silver.sql
GO
PRINT '>> tests\quality_checks_gold.sql';
:r .\tests\quality_checks_gold.sql
GO
PRINT '>> tests\rule_checks.sql';
:r .\tests\rule_checks.sql
GO
PRINT '>> tests\reconciliation_checks.sql';
:r .\tests\reconciliation_checks.sql
GO

PRINT '################################################';
PRINT 'Step 6: Profiling and analysis';
PRINT '################################################';
PRINT '>> scripts\bronze\profile_bronze.sql';
:r .\scripts\bronze\profile_bronze.sql
GO
PRINT '>> scripts\analysis\01_fraud_overview.sql';
:r .\scripts\analysis\01_fraud_overview.sql
GO
PRINT '>> scripts\analysis\02_fraud_by_type.sql';
:r .\scripts\analysis\02_fraud_by_type.sql
GO
PRINT '>> scripts\analysis\03_fraud_by_day.sql';
:r .\scripts\analysis\03_fraud_by_day.sql
GO
PRINT '>> scripts\analysis\04_fraud_by_hour.sql';
:r .\scripts\analysis\04_fraud_by_hour.sql
GO
PRINT '>> scripts\analysis\05_fraud_by_amount.sql';
:r .\scripts\analysis\05_fraud_by_amount.sql
GO
PRINT '>> scripts\analysis\06_fraud_destinations.sql';
:r .\scripts\analysis\06_fraud_destinations.sql
GO
PRINT '>> scripts\analysis\07_existing_rule_performance.sql';
:r .\scripts\analysis\07_existing_rule_performance.sql
GO
PRINT '>> scripts\analysis\08_missed_fraud.sql';
:r .\scripts\analysis\08_missed_fraud.sql
GO
PRINT '>> scripts\analysis\09_fraud_signals_build_period.sql';
:r .\scripts\analysis\09_fraud_signals_build_period.sql
GO
PRINT '>> scripts\analysis\10_better_rule.sql';
:r .\scripts\analysis\10_better_rule.sql
GO

PRINT '################################################';
PRINT 'Run All is Completed';
PRINT '################################################';
GO
