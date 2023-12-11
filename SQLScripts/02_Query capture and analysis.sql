/***************************************************************
DMV Walktrough
***************************************************************/

-- sys.dm_exec_requests
-- Very powerfull DMV that returns information on what is running right now
SELECT *
FROM sys.dm_exec_requests

-- The sys.dm_exec_requests also gives us access to interesting information
-- like the query text and the Execution Plan through handles.
-- We can pass these handles to DMFs or other DMVs
SELECT *
FROM sys.dm_exec_requests
CROSS APPLY sys.dm_exec_sql_text(sql_handle)
CROSS APPLY sys.dm_exec_query_plan(plan_handle)

-- We can also add additional DMVs to get a better overview of activity
-- like sys.dm_exec_sessions
SELECT
  ses.login_name,
  ses.[host_name],
  ses.login_time,
  ses.nt_user_name,
  req.command,
  st.[text],
  sp.query_plan,
  req.cpu_time,
  req.reads,
  req.writes,
  req.wait_type,
  req.wait_time
FROM sys.dm_exec_requests req
INNER JOIN sys.dm_exec_sessions ses
ON req.session_id = ses.session_id
CROSS APPLY sys.dm_exec_sql_text(sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(plan_handle) sp

-- Let's look at some DMVs that return query performance information.
-- These are based on the performance of an Execution Plan inside the
-- Plan Cache of SQL Server

-- sys.dm_exec_cached_plans
-- Returns all the Execution Plans that are inside the Plan Cache
SELECT * FROM sys.dm_exec_cached_plans

-- sys.dm_exec_query_stats
-- Returns aggregated runtime information for each Execution Plan
SELECT * FROM sys.dm_exec_query_stats

-- Let's join both DMVs and grab some performance information
SELECT
  st.[text],
  sp.query_plan,
  cp.cacheobjtype,
  cp.objtype,
  cp.size_in_bytes,
  cp.usecounts,
  qs.creation_time,
  qs.last_execution_time,
  qs.last_rows,
  qs.min_rows,
  qs.max_rows,
  qs.max_used_grant_kb
FROM sys.dm_exec_query_stats qs
INNER JOIN sys.dm_exec_cached_plans cp
ON qs.plan_handle = cp.plan_handle
CROSS APPLY sys.dm_exec_sql_text(sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) sp
WHERE st.[text] LIKE 'SELECT * FROM sys.dm_exec_query_stats%'

-- It is important to know that the information inside these DMVs is tied
-- to the Plan Cache.
-- If SQL Server restarts or we clear the plan cache all the information 
-- inside the DMVs will be reset as well!
DBCC FREEPROCCACHE

-- Rerun the queries above

/***************************************************************
Extended Events
***************************************************************/

-- Create an Extended Events session through T-SQL
CREATE EVENT SESSION [XE_Demo] ON SERVER 
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(sqlserver.sql_text,sqlserver.username)
    WHERE ([sqlserver].[database_name]=N'AdventureWorks2019'))
ADD TARGET package0.event_file(SET filename=N'C:\Temp\XE_Demo.xel')
WITH (STARTUP_STATE=OFF)
GO

-- Start the Extended Events session
ALTER EVENT SESSION "XE_Demo" ON SERVER STATE = START

-- Query against the AdventureWorks database
USE [AdventureWorks2019]

SELECT TOP 1000 *
FROM Sales.SalesOrderDetail

-- Stop the Extended Events session
ALTER EVENT SESSION "XE_Demo" ON SERVER STATE = STOP

-- Read the contents of the .xel file into a temp table
-- Check if temp table is present 
-- Drop if exist 
IF OBJECT_ID('tempdb..#XE_Data') IS NOT NULL DROP TABLE #XE_Data 
-- Create temp table to hold raw XE data 
CREATE TABLE #XE_Data
  (  
  XE_Data XML  
  ); 
GO 

-- Write contents of the XE file into our table
-- Copy the correct file into the command 
INSERT INTO #XE_Data  
  (  
  XE_Data  
  ) 
SELECT  
  CAST (event_data AS XML) 
FROM sys.fn_xe_file_target_read_file  
  (  
  'C:\Temp\XE_Demo_0_133464267754790000.xel',  
  null,  null,  null  
  ); 
GO 

-- Query the data inside the temp table
SELECT * FROM #XE_Data

-- Format the data for readability
SELECT
  XE_Data.value ('(/event/@timestamp)[1]', 'DATETIME') AS 'Date/Time',
  XE_Data.value ('(/event/action[@name=''username'']/value)[1]', 'VARCHAR(100)') AS 'Username',
  XE_Data.value ('(/event/data[@name=''duration'']/value)[1]', 'BIGINT') AS 'Duration',
  XE_Data.value ('(/event/action[@name=''sql_text'']/value)[1]', 'VARCHAR(100)') AS 'Query' 
FROM #XE_Data 
ORDER BY 'Date/Time' ASC 

-- Cleanup
DROP EVENT SESSION "XE_Demo" ON SERVER
