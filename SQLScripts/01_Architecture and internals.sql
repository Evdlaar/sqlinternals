/*********************************************************************************************
SQL Server Performance Tuning Course
Module 01 Architecture and Internals

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
Data page architecture demo
***************************************************************/

-- Get page information for the Person.Person table
SELECT
  allocated_page_page_id,
  extent_page_id,
  page_type_desc,
  next_page_page_id,
  previous_page_page_id
FROM sys.dm_db_database_page_allocations(DB_ID('AdventureWorks'),OBJECT_ID('Person.Person'),NULL , NULL , 'DETAILED')
WHERE page_type_desc = 'DATA_PAGE'
ORDER BY allocated_page_page_id ASC

-- Let's look into a data page
-- We need the 3604 TF to return information
DBCC TRACEON (3604)
GO

-- DBCC PAGE can return the contents of a page
-- This is an UNDOCUMENTED function
DBCC PAGE (AdventureWorks, 1, 1249, 3)
