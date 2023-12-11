/*********************************************************************************************
SQL Server Performance Tuning Course
Module 04 Execution Plans

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
View Execution Plans
***************************************************************/
USE AdventureWorks
GO

-- Enable statistics IO/Time to measure impact
SET STATISTICS IO ON
SET STATISTICS TIME ON

-- Clear Plan Cache
DBCC FREEPROCCACHE;

-- A simple select against a AW table
-- Show Estimated + Actual Execution plan
-- and some Execution Plan properties
SELECT *
FROM Person.Address;

-- Add a little bit more complexity
SELECT *
FROM Sales.vIndividualCustomer
WHERE BusinessEntityID = 5675;


/***************************************************************
Operator Examples
***************************************************************/

-- Create a test table
CREATE TABLE TestTable
	(
	ID INT IDENTITY(1,1),
	TestData VARCHAR(250)
	)

-- Add a nonclustered index
CREATE NONCLUSTERED INDEX idx_ID
ON TestTable (ID)

-- Insert 500 rows
-- Disable Include Plan
INSERT INTO TestTable
	(TestData)
VALUES
	(CONVERT(VARCHAR(50), NEWID()))
GO 500

-- Example Table Scan
SELECT *
FROM TestTable;

-- Example Index Seek & RID Lookup
SELECT ID, TestData
FROM TestTable
WHERE ID = 5;

-- Example for Join types
SELECT pa.City
FROM Person.Address pa
INNER JOIN Person.Person pp
ON pa.rowguid = pp.rowguid
-- OPTION (LOOP JOIN)
-- OPTION (MERGE JOIN)
-- OPTION (HASH JOIN)

/***************************************************************
Parallelism
***************************************************************/

-- Example of a possible parallel plan
-- Cost of the serial plan is 11,2

-- Let's change the Cost Threshold to be above the cost of the serial plan
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'cost threshold for parallelism', N'15'
GO
RECONFIGURE WITH OVERRIDE

-- Execute our query, should be serial
SELECT 
  p.Name AS ProductName, 
  NonDiscountSales = (OrderQty * UnitPrice),
  Discounts = ((OrderQty * UnitPrice) * UnitPriceDiscount)
FROM Production.Product AS p 
INNER JOIN Sales.SalesOrderDetail AS sod
  ON p.ProductID = sod.ProductID 
ORDER BY ProductName DESC

-- Let's change the Cost Threshold to be below the cost of the serial plan
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'cost threshold for parallelism', N'10'
GO
RECONFIGURE WITH OVERRIDE

-- Execute our query, should be parallel
SELECT 
  p.Name AS ProductName, 
  NonDiscountSales = (OrderQty * UnitPrice),
  Discounts = ((OrderQty * UnitPrice) * UnitPriceDiscount)
FROM Production.Product AS p 
INNER JOIN Sales.SalesOrderDetail AS sod
  ON p.ProductID = sod.ProductID 
ORDER BY ProductName DESC
--OPTION (MAXDOP 1)

/***************************************************************
Parameter Sniffing
***************************************************************/

-- Create example procedure
CREATE PROCEDURE sniff_test (@productid int)
  AS
    SELECT * FROM Sales.SalesOrderDetail
    WHERE ProductID = @productid
GO

-- Execute Stored Procedure first time 
EXEC sniff_test @productid = 897

-- Execute it again, notice the difference in IO
EXEC sniff_test @productid = 870

-- Clear the cache
DBCC FREEPROCCACHE

-- Run it again, notice change in Execution Plan
EXEC sniff_test @productid = 870

-- Change the procedure, recompile
-- Run above examples again
ALTER PROCEDURE sniff_test (@productid int)
  AS
    SELECT * FROM Sales.SalesOrderDetail
    WHERE ProductID = @productid
	OPTION (RECOMPILE)
GO

-- Change the procedure, optimize for unknown
-- Run above examples again
ALTER PROCEDURE sniff_test (@productid int)
  AS
    SELECT * FROM Sales.SalesOrderDetail
    WHERE ProductID = @productid
	OPTION (OPTIMIZE FOR (@productid UNKNOWN))
GO

-- Drop Procedure
DROP PROCEDURE sniff_test

/***************************************************************
Query Hints
***************************************************************/
-- FORCE ORDER option
-- Note the Exeuction Plans
SELECT TOP 1000
  soh.OrderDate,
  soh.ShipDate,
  sod.ModifiedDate,
  cc.CardNumber,
  p.name
FROM Sales.SalesOrderHeader soh
LEFT JOIN Sales.SalesOrderDetail sod
  ON sod.SalesOrderID = sod.SalesOrderID
LEFT JOIN Sales.Customer c
  ON soh.CustomerID = c.CustomerID
LEFT JOIN Sales.CreditCard cc
  ON soh.CreditCardID = cc.CreditCardID
LEFT JOIN Sales.SalesPerson sp
  ON soh.SalesPersonID = sp.BusinessEntityID
LEFT JOIN Production.Product p
  ON sod.ProductID = p.ProductID
--OPTION (FORCE ORDER)

-- MAXDOP
SELECT 
  p.Name AS ProductName, 
  NonDiscountSales = (OrderQty * UnitPrice),
  Discounts = ((OrderQty * UnitPrice) * UnitPriceDiscount)
FROM Production.Product AS p 
INNER JOIN Sales.SalesOrderDetail AS sod
  ON p.ProductID = sod.ProductID 
ORDER BY ProductName DESC
--OPTION (MAXDOP 1)

/***************************************************************
Plan Guides
***************************************************************/

-- Let's start off by adding a query hint to a query using a plan guide
-- This query can generate two different plans based on the ProductID
-- The first one results in an Index Scan
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@params = N'@ProductID int', @ProductID = 870
GO

-- Clear the cache
DBCC FREEPROCCACHE

-- This results in a Index Seek
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@params = N'@ProductID int', @ProductID = 897
GO

-- If we could modify the query we could add an RECOMPILE hint to make sure
-- the most optimal plan is used whenever the query is being executed
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID OPTION (RECOMPILE)',
@params = N'@ProductID int', @ProductID = 870
GO
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID OPTION (RECOMPILE)',
@params = N'@ProductID int', @ProductID = 897
GO

-- Since we can't modify the query since it is generated by an application for example
-- we need to build a plan guide
EXEC sp_create_plan_guide 
@name = N'force_recompile',
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@type = N'SQL',
@module_or_batch = NULL,
@params = N'@ProductID int',
@hints = N'OPTION (RECOMPILE)'
GO

-- If we run both queries now the behaviour should be the same as when we added the RECOMPILE
-- to the query
-- Notice the plan guide in the Properties of the Execution Plan
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@params = N'@ProductID int', @ProductID = 870
GO
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@params = N'@ProductID int', @ProductID = 897
GO

-- Drop the plan guide
EXEC sp_control_plan_guide N'DROP', N'force_recompile';

-- In some cases we need even more control of the query execution
-- and we want to force a specific Execution Plan instead of providing just a hint

-- Clear the plan cache
DBCC FREEPROCCACHE

-- Execute our query with the Execution Plan we want to use
-- In this case we want to use an Index Seek + lookup every time the query executes
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@params = N'@ProductID int', @ProductID = 897
GO

-- Grab the query plan from the plan cache
SELECT
  qt.[text],
  qp.query_plan
FROM 
sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) qt

-- Build the plan guide using the XML plan
EXEC sp_create_plan_guide
@name = N'ForcePlan',
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID', 
@type = N'SQL',
@module_or_batch = NULL,
@params = N'@ProductID int',
@hints = N'<ShowPlanXML xmlns="http://schemas.microsoft.com/sqlserver/2004/07/showplan" Version="1.5" Build="13.0.1300.275"><BatchSequence><Batch><Statements><StmtSimple StatementText="(@ProductID int)SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID" StatementId="1" StatementCompId="2" StatementType="SELECT" StatementSqlHandle="0x090007F164DA7A0D746897D879674D5C85F90000000000000000000000000000000000000000000000000000" DatabaseContextSettingsId="1" ParentObjectId="0" StatementParameterizationType="1" RetrievedFromCache="true" StatementSubTreeCost="0.242179" StatementEstRows="75.6667" SecurityPolicyApplied="false" StatementOptmLevel="FULL" QueryHash="0xE539D25E273EFB6A" QueryPlanHash="0x868CD53978198943" StatementOptmEarlyAbortReason="GoodEnoughPlanFound" CardinalityEstimationModelVersion="130"><StatementSetOptions QUOTED_IDENTIFIER="true" ARITHABORT="true" CONCAT_NULL_YIELDS_NULL="true" ANSI_NULLS="true" ANSI_PADDING="true" ANSI_WARNINGS="true" NUMERIC_ROUNDABORT="false" /><QueryPlan CachedPlanSize="40" CompileTime="2" CompileCPU="2" CompileMemory="384"><MemoryGrantInfo SerialRequiredMemory="0" SerialDesiredMemory="0" /><OptimizerHardwareDependentProperties EstimatedAvailableMemoryGrant="104834" EstimatedPagesCached="13104" EstimatedAvailableDegreeOfParallelism="2" /><RelOp NodeId="0" PhysicalOp="Compute Scalar" LogicalOp="Compute Scalar" EstimateRows="75.6667" EstimateIO="0" EstimateCPU="7.56667e-006" AvgRowSize="112" EstimatedTotalSubtreeCost="0.242179" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="CarrierTrackingNumber" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="OrderQty" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ProductID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SpecialOfferID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPrice" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPriceDiscount" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="rowguid" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ModifiedDate" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="LineTotal" ComputedColumn="1" /></OutputList><ComputeScalar><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="LineTotal" ComputedColumn="1" /><ScalarOperator ScalarString="[AdventureWorks].[Sales].[SalesOrderDetail].[LineTotal]"><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="LineTotal" ComputedColumn="1" /></Identifier></ScalarOperator></DefinedValue></DefinedValues><RelOp NodeId="1" PhysicalOp="Nested Loops" LogicalOp="Inner Join" EstimateRows="75.6667" EstimateIO="0" EstimateCPU="0.000316287" AvgRowSize="112" EstimatedTotalSubtreeCost="0.242172" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="CarrierTrackingNumber" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="OrderQty" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ProductID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SpecialOfferID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPrice" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPriceDiscount" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="LineTotal" ComputedColumn="1" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="rowguid" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ModifiedDate" /></OutputList><NestedLoops Optimized="0" WithUnorderedPrefetch="1"><OuterReferences><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /><ColumnReference Column="Expr1002" /></OuterReferences><RelOp NodeId="3" PhysicalOp="Index Seek" LogicalOp="Index Seek" EstimateRows="75.6667" EstimateIO="0.003125" EstimateCPU="0.000240233" AvgRowSize="19" EstimatedTotalSubtreeCost="0.00336523" TableCardinality="121317" Parallel="0" EstimateRebinds="0" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ProductID" /></OutputList><IndexScan Ordered="1" ScanDirection="FORWARD" ForcedIndex="0" ForceSeek="0" ForceScan="0" NoExpandHint="0" Storage="RowStore"><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ProductID" /></DefinedValue></DefinedValues><Object Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Index="[IX_SalesOrderDetail_ProductID]" IndexKind="NonClustered" Storage="RowStore" /><SeekPredicates><SeekPredicateNew><SeekKeys><Prefix ScanType="EQ"><RangeColumns><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ProductID" /></RangeColumns><RangeExpressions><ScalarOperator ScalarString="[@ProductID]"><Identifier><ColumnReference Column="@ProductID" /></Identifier></ScalarOperator></RangeExpressions></Prefix></SeekKeys></SeekPredicateNew></SeekPredicates></IndexScan></RelOp><RelOp NodeId="5" PhysicalOp="Compute Scalar" LogicalOp="Compute Scalar" EstimateRows="1" EstimateIO="0" EstimateCPU="1e-007" AvgRowSize="99" EstimatedTotalSubtreeCost="0.23849" Parallel="0" EstimateRebinds="74.6667" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="LineTotal" ComputedColumn="1" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="CarrierTrackingNumber" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="OrderQty" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SpecialOfferID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPrice" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPriceDiscount" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="rowguid" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ModifiedDate" /></OutputList><ComputeScalar><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="LineTotal" ComputedColumn="1" /><ScalarOperator ScalarString="isnull(CONVERT_IMPLICIT(numeric(19,4),[AdventureWorks].[Sales].[SalesOrderDetail].[UnitPrice],0)*((1.0)-CONVERT_IMPLICIT(numeric(19,4),[AdventureWorks].[Sales].[SalesOrderDetail].[UnitPriceDiscount],0))*CONVERT_IMPLICIT(numeric(5,0),[AdventureWorks].[Sales].[SalesOrderDetail].[OrderQty],0),(0.000000))"><Intrinsic FunctionName="isnull"><ScalarOperator><Arithmetic Operation="MULT"><ScalarOperator><Arithmetic Operation="MULT"><ScalarOperator><Convert DataType="numeric" Precision="19" Scale="4" Style="0" Implicit="1"><ScalarOperator><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPrice" /></Identifier></ScalarOperator></Convert></ScalarOperator><ScalarOperator><Arithmetic Operation="SUB"><ScalarOperator><Const ConstValue="(1.0)" /></ScalarOperator><ScalarOperator><Convert DataType="numeric" Precision="19" Scale="4" Style="0" Implicit="1"><ScalarOperator><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPriceDiscount" /></Identifier></ScalarOperator></Convert></ScalarOperator></Arithmetic></ScalarOperator></Arithmetic></ScalarOperator><ScalarOperator><Convert DataType="numeric" Precision="5" Scale="0" Style="0" Implicit="1"><ScalarOperator><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="OrderQty" /></Identifier></ScalarOperator></Convert></ScalarOperator></Arithmetic></ScalarOperator><ScalarOperator><Const ConstValue="(0.000000)" /></ScalarOperator></Intrinsic></ScalarOperator></DefinedValue></DefinedValues><RelOp NodeId="6" PhysicalOp="Clustered Index Seek" LogicalOp="Clustered Index Seek" EstimateRows="1" EstimateIO="0.003125" EstimateCPU="0.0001581" AvgRowSize="82" EstimatedTotalSubtreeCost="0.238483" TableCardinality="121317" Parallel="0" EstimateRebinds="74.6667" EstimateRewinds="0" EstimatedExecutionMode="Row"><OutputList><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="CarrierTrackingNumber" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="OrderQty" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SpecialOfferID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPrice" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPriceDiscount" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="rowguid" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ModifiedDate" /></OutputList><IndexScan Lookup="1" Ordered="1" ScanDirection="FORWARD" ForcedIndex="0" ForceSeek="0" ForceScan="0" NoExpandHint="0" Storage="RowStore"><DefinedValues><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="CarrierTrackingNumber" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="OrderQty" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SpecialOfferID" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPrice" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="UnitPriceDiscount" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="rowguid" /></DefinedValue><DefinedValue><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="ModifiedDate" /></DefinedValue></DefinedValues><Object Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Index="[PK_SalesOrderDetail_SalesOrderID_SalesOrderDetailID]" TableReferenceId="-1" IndexKind="Clustered" Storage="RowStore" /><SeekPredicates><SeekPredicateNew><SeekKeys><Prefix ScanType="EQ"><RangeColumns><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /></RangeColumns><RangeExpressions><ScalarOperator ScalarString="[AdventureWorks].[Sales].[SalesOrderDetail].[SalesOrderID]"><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderID" /></Identifier></ScalarOperator><ScalarOperator ScalarString="[AdventureWorks].[Sales].[SalesOrderDetail].[SalesOrderDetailID]"><Identifier><ColumnReference Database="[AdventureWorks]" Schema="[Sales]" Table="[SalesOrderDetail]" Column="SalesOrderDetailID" /></Identifier></ScalarOperator></RangeExpressions></Prefix></SeekKeys></SeekPredicateNew></SeekPredicates></IndexScan></RelOp></ComputeScalar></RelOp></NestedLoops></RelOp></ComputeScalar></RelOp><ParameterList><ColumnReference Column="@ProductID" ParameterCompiledValue="(897)" /></ParameterList></QueryPlan></StmtSimple></Statements></Batch></BatchSequence></ShowPlanXML>'

-- Clear the plan cache
DBCC FREEPROCCACHE

-- Execute the query again with the ID that should result in an Index Scan
-- Again, notice the PlanGuideName in the Properties of the Plan
EXEC sp_executesql 
@stmt = N'SELECT * FROM Sales.SalesOrderDetail WHERE ProductID = @ProductID',
@params = N'@ProductID int', @ProductID = 870
GO

-- Drop all plan guides
EXEC sp_control_plan_guide N'DROP ALL';

/***************************************************************
Plan Warnings
***************************************************************/
-- Implicit conversion
SELECT  
  e.BusinessEntityID,
  e.NationalIDNumber
FROM HumanResources.Employee AS e
WHERE e.NationalIDNumber = 112457891

-- Sort spill
SELECT *
FROM Sales.SalesOrderHeader
WHERE DueDate > ShipDate
ORDER BY OrderDate;

-- No Join predicate + implicit conversion
SELECT top 100 *
FROM Sales.SalesOrderHeader AS soh
,Sales.SalesOrderDetail AS sod
,Production.Product AS p
WHERE soh.SalesOrderID = 43659

/***************************************************************
Analyzing Execution Plans
***************************************************************/
-- Select all Execution Plans for DBID 5
SELECT
  q.text,
  p.query_plan,
  refcounts,
  usecounts,
  size_in_bytes
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) p
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) as q
WHERE cp.cacheobjtype = 'Compiled Plan'
AND p.dbid = 5

-- We can do more fun stuff though
-- like searching for parallel plans
WITH XMLNAMESPACES
  (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
    SELECT
      COALESCE(DB_NAME(p.dbid), p.query_plan.value('(//RelOp/OutputList/ColumnReference/@Database)[1]','nvarchar(128)')) AS DatabaseName --Works in a number of cases, but not perfect.
      ,DB_NAME(p.dbid) + '.' + OBJECT_SCHEMA_NAME(p.objectid, p.dbid) + '.' + OBJECT_NAME(p.objectid, p.dbid) AS ObjectName
      ,cp.objtype
      ,p.query_plan
      ,cp.UseCounts
      ,cp.plan_handle
      ,CAST('<?query --' + CHAR(13) + q.text + CHAR(13) + '--?>' AS xml) AS SQLText
    FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) p
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) as q
    WHERE cp.cacheobjtype = 'Compiled Plan'
      AND p.query_plan.exist('//RelOp[@Parallel = "1"]') = 1
    ORDER BY COALESCE(DB_NAME(p.dbid), p.query_plan.value('(//RelOp/OutputList/ColumnReference/@Database)[1]','nvarchar(128)')), UseCounts DESC