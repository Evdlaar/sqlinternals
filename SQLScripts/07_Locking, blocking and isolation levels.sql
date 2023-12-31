/***************************************************************
Lock demonstration
***************************************************************/

-- Lets run a simple update query
BEGIN TRAN

  UPDATE Person.Address
  SET City = 'New York'
  WHERE StateProvinceID = 79

--ROLLBACK

-- Copy the query below in a new window and execute it
SELECT *
FROM Person.Address

-- We now have a blocking situation
-- Lets look for some lock info inside the DMVs
SELECT *
FROM sys.dm_tran_locks
WHERE resource_database_id = 5

-- Let use sp_whoisactive since it can return a lock overview
-- that is far easier to analyse
exec sp_whoisactive @get_locks = 1

/***************************************************************
Read Uncommitted 
***************************************************************/

BEGIN TRAN
  
  UPDATE Person.Address
  SET City = 'New York'
  WHERE StateProvinceID = 79
  
  WAITFOR DELAY '00:00:15'

ROLLBACK

-- Copy in new window and execute
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

  SELECT City
  FROM Person.Address
  WHERE StateProvinceID =  79

/***************************************************************
Read Committed 
***************************************************************/

BEGIN TRAN
  
  UPDATE Person.Address
  SET City = 'New York'
  WHERE StateProvinceID = 79

  WAITFOR DELAY '00:00:15'

ROLLBACK

-- Copy in new window and execute
SET TRANSACTION ISOLATION LEVEL READ COMMITTED

  SELECT City
  From Person.Address
  WHERE StateProvinceID =  79

/***************************************************************
Blocking
***************************************************************/

BEGIN TRAN

  UPDATE Person.Address
  SET City = 'New York'
  WHERE StateProvinceID = 79

--ROLLBACK

-- Copy the query below in a new window and execute it
SELECT *
FROM Person.Address

-- Check Activity Monitor

-- Run sp_who2
EXEC sp_who

-- Check some DMVs
-- sys.dm_exec_requests
SELECT *
FROM sys.dm_exec_requests
WHERE session_id > 50

-- sys.dm_os_waiting_tasks
SELECT *
FROM sys.dm_os_waiting_tasks
WHERE session_id > 50

-- sp_whoisactive
EXEC sp_whoisactive