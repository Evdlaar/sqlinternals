/***************************************************************
Index impact
***************************************************************/

-- Create a test table
-- We will fill the table with data from
-- the AdventureWorks database so we have
-- something to work with.
-- I created the Index_Test database to hold our tables.
-- Keep in mind that a SELECT INTO does not copy the indexes
-- from the source table.
USE [AdventureWorks2019]
GO

SELECT *
INTO IndexPerformance
FROM AdventureWorks2019.HumanResources.Employee;

-- Let's add some more data into our table
INSERT INTO IndexPerformance
  SELECT * FROM AdventureWorks2019.HumanResources.Employee;
GO 250

-- Enable statistics for analysis
SET STATISTICS TIME ON
SET STATISTICS IO ON

-- Select a record from the table
-- there is no index here yet.
-- Enable "Include Actual Execution Plan"
-- so the Execution plan will be visible.
SELECT NationalIDNumber
FROM IndexPerformance
WHERE NationalIDNumber = '974026903'

-- Let's add a simple index to the table
CREATE INDEX idx_NationalIDNumber
  ON IndexPerformance (NationalIDNumber);

-- Select a specific record again
-- this time we do have an index in place
SELECT NationalIDNumber
FROM IndexPerformance
WHERE NationalIDNumber = '974026903'

-- Cleanup
DROP INDEX idx_NationalIDNumber
  ON IndexPerformance;

/***************************************************************
Nonclustered vs Clustered performance
***************************************************************/

-- Let's add our index again to our test table
-- By default a Nonclustered Index will be created
CREATE INDEX idx_NationalIDNumber
  ON IndexPerformance (NationalIDNumber);

-- Run a query where we select a number of ID Numbers
-- and some extra data
-- Note the statistics data and Execution plan
SELECT 
  NationalIDNumber, 
  OrganizationLevel,
  HireDate
FROM IndexPerformance
WHERE NationalIDNumber >= '970000000' AND NationalIDNumber <= '990000000'

-- Drop our index
DROP INDEX idx_NationalIDNumber
  ON IndexPerformance;

-- Let's create the same index only this time as a Clustered Index
CREATE CLUSTERED INDEX idx_NationalIDNumber
  ON IndexPerformance (NationalIDNumber);

-- Let's run the query again
-- Take a look at the statistics and Execution plan
SELECT 
  NationalIDNumber, 
  OrganizationLevel,
  HireDate
FROM IndexPerformance
WHERE NationalIDNumber >= '970000000' AND NationalIDNumber <= '990000000';

-- Cleanup
DROP TABLE IndexPerformance

/***************************************************************
Index key size
***************************************************************/
-- Create our test table with a narrow,
-- unique, ever-increasing index key
-- INTEGER is 4 bytes
CREATE TABLE IndexKeySmall
  (
  small_ID INT IDENTITY(1,1) PRIMARY KEY,
  random_data VARCHAR(50)
  );

-- Insert 100.000 rows, takes around 3 minutes
-- Disable Include Execution plan
INSERT INTO IndexKeySmall
	(random_data)
VALUES
	(CONVERT(varchar(50), NEWID()))
GO 100000

-- Query the index structure
SELECT  
  index_id,
  index_type_desc,
  index_depth,
  index_level,
  page_count,
  record_count
FROM sys.dm_db_index_physical_stats
    (DB_ID(N'AdventureWorks2019'), OBJECT_ID(N'IndexKeySmall'), NULL, NULL , 'DETAILED');

-- Let's create another table
-- only this time we will use the
-- UNIQUEIDENTIFIER (16 bytes) as the index key
CREATE TABLE IndexKeyLarge
  (
  large_ID UNIQUEIDENTIFIER PRIMARY KEY,
  random_data VARCHAR(50)
  );

-- Insert 100.000 rows into this table, should take around 3 minute
INSERT INTO IndexKeyLarge
  (large_ID, random_data)
VALUES
  (
  NEWID(),
  CONVERT(varchar(50), NEWID())
  )
GO 100000

-- Query the index structure
SELECT  
  index_id,
  index_type_desc,
  index_depth,
  index_level,
  page_count,
  record_count
FROM sys.dm_db_index_physical_stats
    (DB_ID(N'AdventureWorks2019'), OBJECT_ID(N'IndexKeyLarge'), NULL, NULL , 'DETAILED');

-- Cleanup
DROP TABLE IndexKeySmall;
DROP TABLE IndexKeyLarge;

/***************************************************************
Included Columns
***************************************************************/
-- Included columns will add the additional column data
-- to the index page
USE AdventureWorks2019
GO

-- remove this index for a better demo
DROP INDEX IX_Address_AddressLine1_AddressLine2_City_StateProvinceID_PostalCode
  ON Person.Address;

-- Query multible columns from the Person.Address table
SELECT 
  AddressLine1, 
  AddressLine2, 
  City, 
  StateProvinceID, 
  PostalCode
FROM Person.Address
WHERE PostalCode BETWEEN '98000' and '99999';

-- Let's create a new Nonclustered index
-- and include the columns we needed for
-- our query above
CREATE NONCLUSTERED INDEX IX_Address_PostalCode
  ON Person.Address (PostalCode)
  INCLUDE (AddressLine1, AddressLine2, City, StateProvinceID);

-- Let's run the query again
SELECT 
  AddressLine1, 
  AddressLine2, 
  City, 
  StateProvinceID, 
  PostalCode
FROM Person.Address
WHERE PostalCode BETWEEN '98000' and '99999';

-- Cleanup
DROP INDEX IX_Address_PostalCode
  ON Person.Address;

/***************************************************************
Missing Index Hint
***************************************************************/

-- Run the query below, it has a missing index
SELECT 
  AddressLine1, 
  AddressLine2, 
  City, 
  StateProvinceID, 
  PostalCode
FROM Person.Address
WHERE PostalCode BETWEEN '98000' and '99999';



/***************************************************************
Index Usage
***************************************************************/
SELECT
  OBJECT_NAME(a.[object_id]) as 'Table Name',
  b.name AS 'Index Name',
  a.index_type_desc AS 'Index Type',
  s.user_seeks AS 'Index Seeks',
  s.user_scans AS 'Index Scans',
  s.user_lookups AS 'Index Lookups',
  (s.user_seeks + s.user_scans + s.user_lookups) AS 'Index Read Operations',
  s.user_updates AS 'Index Update Operations'
FROM
  sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') a
INNER JOIN sys.indexes b
  ON a.[object_id] = b.[object_id]
  AND a.index_id = b.index_id
INNER JOIN SYS.dm_db_index_usage_stats AS s
  ON b.[object_id] = s.[object_id]
  AND b.index_id = s.index_id
WHERE b.name IS NOT NULL
ORDER BY b.name ASC

/***************************************************************
Duplicate and overlapping indexes
***************************************************************/
-- Script by Edward Pollack
-- SQLServer Central
-- http://www.sqlservercentral.com/articles/Indexing/110106/

;WITH CTE_INDEX_DATA AS (
       SELECT
              SCHEMA_DATA.name AS schema_name,
              TABLE_DATA.name AS table_name,
              INDEX_DATA.name AS index_name,
              STUFF((SELECT  ', ' + COLUMN_DATA_KEY_COLS.name + ' ' + CASE WHEN INDEX_COLUMN_DATA_KEY_COLS.is_descending_key = 1 THEN 'DESC' ELSE 'ASC' END -- Include column order (ASC / DESC)

                                  FROM    sys.tables AS T
                                                INNER JOIN sys.indexes INDEX_DATA_KEY_COLS
                                                ON T.object_id = INDEX_DATA_KEY_COLS.object_id
                                                INNER JOIN sys.index_columns INDEX_COLUMN_DATA_KEY_COLS
                                                ON INDEX_DATA_KEY_COLS.object_id = INDEX_COLUMN_DATA_KEY_COLS.object_id
                                                AND INDEX_DATA_KEY_COLS.index_id = INDEX_COLUMN_DATA_KEY_COLS.index_id
                                                INNER JOIN sys.columns COLUMN_DATA_KEY_COLS
                                                ON T.object_id = COLUMN_DATA_KEY_COLS.object_id
                                                AND INDEX_COLUMN_DATA_KEY_COLS.column_id = COLUMN_DATA_KEY_COLS.column_id
                                  WHERE   INDEX_DATA.object_id = INDEX_DATA_KEY_COLS.object_id
                                                AND INDEX_DATA.index_id = INDEX_DATA_KEY_COLS.index_id
                                                AND INDEX_COLUMN_DATA_KEY_COLS.is_included_column = 0
                                  ORDER BY INDEX_COLUMN_DATA_KEY_COLS.key_ordinal
                                  FOR XML PATH('')), 1, 2, '') AS key_column_list ,
          STUFF(( SELECT  ', ' + COLUMN_DATA_INC_COLS.name
                                  FROM    sys.tables AS T
                                                INNER JOIN sys.indexes INDEX_DATA_INC_COLS
                                                ON T.object_id = INDEX_DATA_INC_COLS.object_id
                                                INNER JOIN sys.index_columns INDEX_COLUMN_DATA_INC_COLS
                                                ON INDEX_DATA_INC_COLS.object_id = INDEX_COLUMN_DATA_INC_COLS.object_id
                                                AND INDEX_DATA_INC_COLS.index_id = INDEX_COLUMN_DATA_INC_COLS.index_id
                                                INNER JOIN sys.columns COLUMN_DATA_INC_COLS
                                                ON T.object_id = COLUMN_DATA_INC_COLS.object_id
                                                AND INDEX_COLUMN_DATA_INC_COLS.column_id = COLUMN_DATA_INC_COLS.column_id
                                  WHERE   INDEX_DATA.object_id = INDEX_DATA_INC_COLS.object_id
                                                AND INDEX_DATA.index_id = INDEX_DATA_INC_COLS.index_id
                                                AND INDEX_COLUMN_DATA_INC_COLS.is_included_column = 1
                                  ORDER BY INDEX_COLUMN_DATA_INC_COLS.key_ordinal
                                  FOR XML PATH('')), 1, 2, '') AS include_column_list,
       INDEX_DATA.is_disabled -- Check if index is disabled before determining which dupe to drop (if applicable)
       FROM sys.indexes INDEX_DATA
       INNER JOIN sys.tables TABLE_DATA
       ON TABLE_DATA.object_id = INDEX_DATA.object_id
       INNER JOIN sys.schemas SCHEMA_DATA
       ON SCHEMA_DATA.schema_id = TABLE_DATA.schema_id
       WHERE TABLE_DATA.is_ms_shipped = 0
       AND INDEX_DATA.type_desc IN ('NONCLUSTERED', 'CLUSTERED')
)
SELECT
       *
FROM CTE_INDEX_DATA DUPE1
WHERE EXISTS
(SELECT * FROM CTE_INDEX_DATA DUPE2
 WHERE DUPE1.schema_name = DUPE2.schema_name
 AND DUPE1.table_name = DUPE2.table_name
 AND (DUPE1.key_column_list LIKE LEFT(DUPE2.key_column_list, LEN(DUPE1.key_column_list)) OR DUPE2.key_column_list LIKE LEFT(DUPE1.key_column_list, LEN(DUPE2.key_column_list)))
 AND DUPE1.index_name <> DUPE2.index_name)