/*********************************************************************************************
SQL Server Performance Tuning Course
Module 08 Wait Statistics

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
Query scheduler information
***************************************************************/

-- Query available schedulers
SELECT * 
FROM sys.dm_os_schedulers
WHERE status LIKE 'VISIBLE ONLINE%'

/***************************************************************
Wait Stats DMVs
***************************************************************/

-- Query cumulative wait times
SELECT *
FROM sys.dm_os_wait_stats

-- Query what is waiting now
SELECT *
FROM sys.dm_os_waiting_tasks

-- New in SQL Server 2016
-- Session recorded waits!
SELECT *
FROM sys.dm_exec_session_wait_stats

/***************************************************************
CXPACKET
***************************************************************/
-- We will have to cheat a little here to force a parallel plan
sp_configure 'show advanced options', 1;
GO
reconfigure;
GO
sp_configure 'cost threshold for parallelism', 1;
GO
reconfigure;
GO

-- Clear wait stats
-- Enable Actual Execution Plan
DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);

DBCC FREEPROCCACHE

USE AdventureWorks

SELECT * 
FROM Sales.SalesOrderDetail
ORDER BY CarrierTrackingNumber DESC

-- Get wait statistics
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type = 'CXPACKET'

-- CXPACKET demo with MDOP = 1
-- Enable Actual Execution plan

-- Clear wait stats
DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);
DBCC FREEPROCCACHE

USE AdventureWorks

SELECT * 
FROM Sales.SalesOrderDetail
ORDER BY CarrierTrackingNumber DESC
OPTION (MAXDOP 1)

-- Get wait statistics
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type = 'CXPACKET'

/***************************************************************
SOS_SCHEDULER_YIELD
***************************************************************/

-- Clear wait stats
DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);

-- Check SOS_SCHEDULER_YIELD wait times
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type = 'SOS_SCHEDULER_YIELD'


-- We are going to use Ostress to generate some workload
-- "C:\Program Files\Microsoft Corporation\RMLUtils\ostress.exe" -E -dAdventureWorks -i"C:\sos_scheduler.sql" -n20 -r1 -q

-- Check sys.dm_os_waiting_tasks
SELECT *
FROM sys.dm_os_waiting_tasks
WHERE wait_type = 'SOS_SCHEDULER_YIELD'

-- Lets check the top 10 waits inside the sys.dm_os_wait_stats DMV
SELECT TOP 10 * 
FROM sys.dm_os_wait_stats 
ORDER by wait_time_ms DESC


/***************************************************************
LCK_M_XX
***************************************************************/
-- Display all lock types
SELECT * FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'LCK_M_%'

-- LCK information in sys.dm_os_waiting_tasks
-- Copy first part in new query window
USE AdventureWorks
GO

BEGIN TRAN

UPDATE Sales.SalesOrderDetail
SET CarrierTrackingNumber = '4E0A-4F89-AD'
WHERE SalesOrderID = '43661'

-- Rollback
ROLLBACK TRAN

-- Copy in second window
SELECT * FROM AdventureWorks.Sales.SalesOrderDetail

-- Before we check sys.dm_exec_requests let's look at the request
SELECT 
	session_id,
	start_time,
	status,
	command,
	blocking_session_id,
	wait_type,
	wait_time,
	wait_resource,
	total_elapsed_time
FROM sys.dm_exec_requests
WHERE session_id > 50


-- Check sys.dm_os_waiting_tasks
-- We can use the associatedObjectID to trace locks
-- Copy/paste ID
SELECT 
	session_id,
	wait_duration_ms,
	wait_type,
	blocking_session_id,
	resource_description 
FROM sys.dm_os_waiting_tasks
WHERE session_id > 50

-- Check sys.dm_tran_locks for lock information
-- Check resource_associated_entity_id if needed
SELECT * 
FROM sys.dm_tran_locks
WHERE resource_associated_entity_id = '72057594048479232'

/***************************************************************
PAGEIOLATCH_XX
***************************************************************/
-- Display all PAGEIOLATCH types
SELECT * FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'PAGEIOLATCH_%'

-- Clearing the buffer cache
DBCC DROPCLEANBUFFERS

-- Clear wait stats
DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);

-- Get wait statistics
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'PAGEIOLATCH%'

-- SELECT some random data
USE AdventureWorks
GO

SELECT *
FROM Person.Person

-- Get wait statistics
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type LIKE 'PAGEIOLATCH%'

/***************************************************************
OLEDB
***************************************************************/
DBCC SQLPERF ('sys.dm_os_wait_stats', CLEAR);

-- Get wait statistics
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type = 'OLEDB'

DBCC CHECKDB('AdventureWorks')

-- Get wait statistics
SELECT *
FROM sys.dm_os_wait_stats
WHERE wait_type = 'OLEDB'

/***************************************************************
THREADPOOL
***************************************************************/
-- Query Worker Thread information
SELECT max_workers_count 
FROM sys.dm_os_sys_info

-- For this test we will lower them to the minimum of 128
EXEC sp_configure 'show advanced options', 1;
GO
RECONFIGURE
GO
EXEC sp_configure 'max worker threads', 128 ;
GO
RECONFIGURE
GO

-- Let's check the worker threads again
-- Should be 128
SELECT max_workers_count 
FROM sys.dm_os_sys_info

-- We have to create some load to THREADPOOL waits will show up
-- We will be using ostress.exe for this, you can download it (free) from Microsoft
-- ostress command: "C:\Program Files\Microsoft Corporation\RMLUtils\ostress.exe" -E -dAdventureWorks -i"C:\random_select.sql" -n150 -r10 -q

-- While the script is running (around 3 min), check the worker count queue
SELECT 
	scheduler_id,
	current_tasks_count,
	runnable_tasks_count,
	current_workers_count,
	active_workers_count,
	work_queue_count	
FROM sys.dm_os_schedulers
WHERE status = 'VISIBLE ONLINE'

-- Let's look at the waiting tasks
SELECT * FROM sys.dm_os_waiting_tasks
WHERE session_id > 50

-- Nothing to see?
SELECT * FROM sys.dm_os_waiting_tasks

/***************************************************************
PREEMPTIVE_OS_WRITEFILEGATHER
***************************************************************/
DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR) 

USE [master] 
GO 

ALTER DATABASE [AdventureWorks]  
MODIFY FILE  
  (  
  NAME = N'AdventureWorks2014_Data',  
  SIZE = 2048MB 
  );
GO 

SELECT * 
FROM sys.dm_os_wait_stats 
WHERE wait_type = 'PREEMPTIVE_OS_WRITEFILEGATHER';
