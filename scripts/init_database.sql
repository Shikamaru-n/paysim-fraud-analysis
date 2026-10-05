/*
=============================================================
Create Database and Schemas
=============================================================
Script Purpose:
    This script creates a new database named 'PaysimFraudAnalysis' after checking if it already
    exists. If the database exists, it is dropped and recreated. Additionally, the script sets up
    three schemas within the database: 'bronze', 'silver', and 'gold'.

WARNING:
    Running this script will drop the entire 'PaysimFraudAnalysis' database if it exists.
    All data in the database will be permanently deleted. Proceed with caution
    and ensure you have proper backups before running this script.
*/

USE master;
GO

-- Drop and recreate the 'PaysimFraudAnalysis' database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'PaysimFraudAnalysis')
BEGIN
    ALTER DATABASE PaysimFraudAnalysis SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PaysimFraudAnalysis;
END;
GO

-- Create the 'PaysimFraudAnalysis' database
CREATE DATABASE PaysimFraudAnalysis;
GO

-- Use the simple recovery model. The source file holds about 6.4 million rows, and under the
-- full recovery model that single bulk load would write every row to the transaction log and
-- grow it to several gigabytes. Simple recovery lets the bulk load be minimally logged. This is
-- a local analysis database rebuilt from the CSV, so point-in-time recovery is not needed.
ALTER DATABASE PaysimFraudAnalysis SET RECOVERY SIMPLE;
GO

USE PaysimFraudAnalysis;
GO

-- Create Schemas
CREATE SCHEMA bronze;
GO

CREATE SCHEMA silver;
GO

CREATE SCHEMA gold;
GO
