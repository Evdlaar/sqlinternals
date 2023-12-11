/***************************************************************
Data page architecture demo
***************************************************************/

-- Get page information for the Person.Person table
SELECT
  allocated_page_page_id,
  extent_page_id,
  page_type_desc,
  next_page_page_id,
  previous_page_page_id
FROM sys.dm_db_database_page_allocations(DB_ID('AdventureWorks2019'),OBJECT_ID('Person.Person'),NULL , NULL , 'DETAILED')
WHERE page_type_desc = 'DATA_PAGE'
ORDER BY allocated_page_page_id ASC

-- Let's look into a data page
-- We need the 3604 TF to return information
DBCC TRACEON (3604)
GO

-- DBCC PAGE can return the contents of a page
-- This is an UNDOCUMENTED function
DBCC PAGE (AdventureWorks2019, 1, 1249, 3)

-- Can also show other page type info like an IAM page
DBCC PAGE (AdventureWorks2019, 1, 162, 3)
