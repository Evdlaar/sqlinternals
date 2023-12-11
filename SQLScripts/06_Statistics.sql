/*********************************************************************************************
SQL Server Performance Tuning Course
Module 06 Statistics

(C) 2016, Enrico van de Laar

Feedback: mailto:enrico@dotnine.net

License: 
	This demo script, that is part of the SQL Server Performance Tuning Course, 
	is free to download and use for personal, educational, and internal 
	corporate purposes, provided that this header is preserved. Redistribution or sale 
	of this script, in whole or in part, is prohibited without the author's express 
	written consent.
*********************************************************************************************/

/***************************************************************
Automatic Statistics Creation
***************************************************************/

-- Create a test table
-- We will fill the table with data from
-- the AdventureWorks database so we have
-- something to work with.
USE [AdventureWorks]
GO

SELECT *
INTO StatsDemo
FROM AdventureWorks.HumanResources.Employee;

-- Let's add some more data into our table
INSERT INTO StatsDemo
  SELECT * FROM AdventureWorks.HumanResources.Employee;
GO 250

-- Check the statistics on the StatsDemo table

-- Select data from a random column
-- If a WHERE clause is included statistics will, by default, automatically be created
SELECT NationalIDNumber
FROM StatsDemo
WHERE NationalIDNumber = 974026903

-- Check the statistics on the StatsDemo table again

-- Let's add an index to the table
CREATE NONCLUSTERED INDEX idx_BusinessEntityID
ON StatsDemo (BusinessEntityID)

-- Check statistics agains

/***************************************************************
Automatic Statistics Update
***************************************************************/

-- Count the number of rows inside our table (72790)
SELECT
  COUNT (*)
FROM StatsDemo

-- To trigger an autoupdate we would need to perform
-- 14.558 + 500 = 15.058 changes

-- Let's grab the statistics date of the statistics on the index we created
SELECT STATS_DATE(OBJECT_ID('StatsDemo'), 3)

-- Let's update 15.057 rows
WITH CTE_Stats AS (SELECT TOP 15057 * FROM StatsDemo)
UPDATE CTE_Stats SET BusinessEntityID = BusinessEntityID

-- We need to run a select to force the auto-update to occur
-- In this case it won't happen since we haven't reached the threshold
SELECT * 
FROM StatsDemo
WHERE BusinessEntityID = 24

-- Check statistics date again
SELECT STATS_DATE(OBJECT_ID('StatsDemo'), 3)

-- Let's insert 1 more row
WITH CTE_Stats AS (SELECT TOP 1 * FROM StatsDemo)
UPDATE CTE_Stats SET BusinessEntityID = BusinessEntityID

-- We need to run a select to force the auto-update to occur
SELECT TOP 1 * 
FROM StatsDemo
WHERE BusinessEntityID = 24

-- Check statistics date again they should have been updated now
SELECT STATS_DATE(OBJECT_ID('StatsDemo'), 3)

-- Cleanup
DROP TABLE StatsDemo

/***************************************************************
Out-of-date Statistics Impact
***************************************************************/

-- Create a simple table
CREATE TABLE Stat_Test
(
  c1 int,
  c2 int,
)

-- Insert a few rows
INSERT INTO Stat_Test
      (c1, c2)
VALUES
      (1,1),(2,2),(3,3),(4,4),(5,5),(6,6),(7,7),(8,8),(9,9),(10,10)
GO

-- Select a record so column statistics are created
SELECT c2 
FROM Stat_Test
WHERE c2 = 5
GO

-- Insert 100 rows
INSERT INTO Stat_Test
      (c1, c2)
SELECT MAX(c1)+1, MAX(c2)+1
FROM Stat_Test
GO 100

-- Select some data from the table
-- Check the Execution Plan
SELECT c2 FROM Stat_Test
WHERE c2 BETWEEN 50 AND 90
OPTION (RECOMPILE)

-- Manually update statistics
-- Copy statistics name in the command below
UPDATE STATISTICS Stat_Test _WA_Sys_00000002_7E42ABEE

-- Run the query again
-- Notice the change in Estimated and Actual rows
SELECT c2 FROM Stat_Test
WHERE c2 BETWEEN 50 AND 90
OPTION (RECOMPILE)

-- Cleanup
DROP TABLE Stat_Test


/***************************************************************
Statistics Internals
***************************************************************/

-- Let's take a look at some index statistics
-- We can use the function DBCC SHOW_STATISTICS to retrieve information about specific statistics
DBCC SHOW_STATISTICS ('Sales.SalesOrderDetailEnlarged', IX_SalesOrderDetailEnlarged_ProductID)

-- Top window is the Stats Header
-- Middle Density Vector information
-- Bottom Histogram

-- Lets take a more detailed look at the Histogram
DBCC SHOW_STATISTICS ('Sales.SalesOrderDetailEnlarged', IX_SalesOrderDetailEnlarged_ProductID) WITH HISTOGRAM

-- RANGE_HI_KEY = Upper Bound Column value of the step
-- RANGE_ROWS = Number of rows inside the Histogram step
-- EQ_ROWS = Number of rows with equal value to the Histogram step
-- DISTINCT_RANGE_ROWS = Number of rows with a distinct value, exclude Histogram step value
-- AVG_RANGE_ROWS = AVG nr of rows equal to a key value

-- Let's check the Execution Plan of a query againt SalesOrderDetailEnlarged
-- where we query the ProductID 708
-- According to the Histogram there are 122420 rows with that ID and no other
-- IDs inside the Histogram step so we should get a good estimate
SELECT ProductID FROM Sales.SalesOrderDetailEnlarged
WHERE ProductID = 708

-- Lets look at an ID that falls into a Histogram step with multiple other IDs
-- In this case check 915, it falls in the 916 step
DBCC SHOW_STATISTICS ('Sales.SalesOrderDetailEnlarged', IX_SalesOrderDetailEnlarged_ProductID) WITH HISTOGRAM

-- The selectivity of the values inside the 916 Histogram step is 1502
-- This means the Optimizer will estimate there are 1502 rows that have an ID of 915
-- Lets check the Execution Plan
SELECT * FROM Sales.SalesOrderDetailEnlarged
WHERE ProductID = 915

-- We can also see how the Density Vector is used
-- Lets start by calculating it manually
-- Keep in mind that the density vector in this case is only calculated for the one-column index
SELECT 1.0 / COUNT(DISTINCT ProductID)
FROM Sales.SalesOrderDetailEnlarged

DBCC SHOW_STATISTICS ('Sales.SalesOrderDetailEnlarged', IX_SalesOrderDetailEnlarged_ProductID) WITH DENSITY_VECTOR

-- The Density Vector is used in various operations like a Stream Aggregate
-- We can force an aggragate by using a GROUP BY clause
-- The calculation the Query Optimizer uses for its estimates is 1 / Density Factor
-- In this case 1 / 0.003759398496 = 266 
SELECT ProductID
FROM Sales.SalesOrderDetailEnlarged
GROUP BY ProductID