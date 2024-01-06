-- SQL PROJECT: CONVERTING EXCEL SUPERSTORE DATA INTO A SQL DATABASE WITH MULTIPLE SQL TABLES

---- CREATE TEMPORARY TABLES FROM CHOSEN EXCEL FILE
--Order_Temp -> FROM ORDERS SHEET
CREATE TABLE Orders_Temp (
	RowID INT,
	OrderID NVARCHAR(20),
	OrderDate DATE,
	ShipDate DATE,
	ShipMode NVARCHAR(25),
	CustomerID NVARCHAR(20),
	CustomerName NVARCHAR(50),
	Segment NVARCHAR(20),
	Country NVARCHAR(20),
	City NVARCHAR(20),
	[State] NVARCHAR(20),
	PostalCode INT,
	Region NVARCHAR(15),
	ProductID NVARCHAR(50),
	Category NVARCHAR(20),
	Subcategory NVARCHAR(20),
	ProductName NVARCHAR(255),
	Sales MONEY,
	Quantity SMALLINT,
	Discount MONEY,
	Profit MONEY
);

BULK INSERT Orders_Temp
FROM 'D:\Sample - Superstore_ORDER.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2  
);

SELECT *
	FROM Orders_Temp;

--Returns_Temp -> FROM RETURNS SHEET
CREATE TABLE Returns_Temp (
	Returned NVARCHAR(10),
	OrderID NVARCHAR(20)
);

BULK INSERT Returns_Temp
FROM 'D:\Sample - Superstore_RETURNS.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2  
);

SELECT *
	FROM Returns_Temp;

--People_Temp -> FROM PEOPLE SHEET
CREATE TABLE People_Temp (
	RegionalManager NVARCHAR(25),
	Region NVARCHAR(15)
);

BULK INSERT People_Temp
FROM 'D:\Sample - Superstore_PEOPLE.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2  
);

SELECT *
	FROM People_Temp;

-- #Temp_Gender -> CREATED FROM DETERMINING DISTINCT CUSTOMERS' GENDER
--				-> DUE TO NO OTHER INFO OF CUSTOMERS TO DETERMINE GENDER, GENDER OF 
--					CUSTOMER IS DETERMINED BASED ON CUSTOMER NAMES
--				-> GENDER OF NAMES IS BASED ON POPULAR BABY NAMES OF US NATIONAL DATA 
CREATE TABLE #Temp_Gender (
	CustomerID VARCHAR(20),
	FirstName NVARCHAR(25),
	LastName NVARCHAR(25),
	GenderLabel NVARCHAR(25)
);

BULK INSERT #Temp_Gender
FROM 'D:\Book2-CustomerName-Gender.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2  
);

SELECT *
	FROM #Temp_Gender


---- CREATING NEW MULTIPLE SQL TABLES
--dbo.DimProducts
CREATE TABLE DimProducts (
	ProductID VARCHAR(25) PRIMARY KEY,
	Category NVARCHAR(20),
	Subcategory NVARCHAR(20),
	ProductName NVARCHAR(255)
);

SELECT *
	FROM DimProducts

--DETERMINED DISTINCT PRODUCT ID AS THERE EXIST DUPLICATE PRODUCT IDS
CREATE VIEW DistinctProducts AS
	SELECT DISTINCT ProductID,
			Category,
			Subcategory,
			ProductName,
		FROM Orders_Temp

--FIXING DUPLICATE PRODUCT IDS AND PRODUCT NAMES BY FINDING THE DUPLICATES 
CREATE VIEW UniqueProductIDCount AS
WITH ProductIDCount AS (
SELECT ProductID,
			Category,
			Subcategory,
			ProductName,
	ROW_NUMBER() OVER (PARTITION BY ProductID ORDER BY (SELECT NULL)) AS RowNum,
	TRY_CAST((RIGHT(ProductID,8)) AS INT) AS ProductIDNum,
	ROW_NUMBER() OVER (PARTITION BY ProductName ORDER BY (SELECT NULL)) AS ItemCount
	FROM DistinctProducts
)
SELECT DP.ProductID,
			DP.Category,
			DP.Subcategory,
			DP.ProductName,
	CASE
		WHEN ProductIDCount.RowNum > 1 THEN
			LEFT(DP.ProductID, 7) + TRY_CAST((ProductIDCount.ProductIDNum + 1000000) AS VARCHAR(10))
		ELSE	
			DP.ProductID
	END AS UniqueProductID
	FROM DistinctProducts DP
	LEFT JOIN ProductIDCount ON DP.ProductID = ProductIDCount.ProductID
		AND DP.ProductName = ProductIDCount.ProductName 
	WHERE ProductIDCount.ItemCount = 1

SELECT *
	FROM UniqueProductIDCount;

--INSERTING FINAL DATA IN PRODUCTS TABLE
INSERT INTO DimProducts(ProductID,
			Category,
			Subcategory,
			ProductName
			)
	SELECT UniqueProductID,
			Category,
			Subcategory,
			ProductName
		FROM UniqueProductIDCount

SELECT *
	FROM DimProducts

--ADJUSTING CONSTRAINTS
ALTER TABLE DimProducts
	DROP CONSTRAINT PK__DimProducts__B40CC6EDF470BD6C;
ALTER TABLE DimProducts
	ADD CONSTRAINT PK_Products_ProductID PRIMARY KEY (ProductID)

--dbo.DimCustomers
--PREPARING DIMCUSTOMER TABLE
CREATE TABLE DimCustomers (
	CustomerID VARCHAR(20) PRIMARY KEY,
	FirstName NVARCHAR(25),
	LastName NVARCHAR(25),
	Gender NVARCHAR(25),
	Segment NVARCHAR(20)
);

--PREPARING DATA TO INSERT
CREATE VIEW DistinctCustomers AS
SELECT DISTINCT CustomerID,
		CustomerName,
		Segment
	FROM Orders_Temp;

--INSERTING DATA INTO DIMCUSTOMER TABLE
INSERT INTO DimCustomers (
		CustomerID,
		FirstName,
		LastName,
		Gender,
		Segment
		)
SELECT 
	DC.CustomerID,
	CASE
		WHEN CHARINDEX(' ', DC.CustomerName) > 0
			THEN LEFT(DC.CustomerName, CHARINDEX(' ', DC.CustomerName) - 1)
		ELSE
			DC.CustomerName
	END AS FirstName,
	CASE 
		WHEN CHARINDEX(' ', DC.CustomerName) > 0 
			THEN RIGHT(DC.CustomerName, LEN(DC.CustomerName) - CHARINDEX(' ', DC.CustomerName))
		ELSE	
			NULL
	END As LastName,	
	TG.GenderLabel AS Gender,
	DC.Segment
FROM DistinctCustomers DC
JOIN #Temp_Gender TG ON DC.CustomerID = TG.CustomerID;

SELECT * 
	FROM DimCustomers;

-- DETERMINED THAT THERE ARE DISCREPANCIES IN THE PROVIDED NAMES; PREPARING RESOLUTION
-- CustomerID "SC-20050" HAS "Sample Company A" AS CUSTOMER NAME
-- FOR THIS SAMPLE PROJECT ONLY, DECIDED TO CHANGE NAME OF CustomerID "SC-20050"
UPDATE DimCustomers
SET FirstName = 'Azrael',
    LastName = 'Callisto'
WHERE CustomerID = 'SC-20050';

-- CHECKED FOR ANY NULL VALUES LEFT IN LastName
SELECT * 
	FROM DimCustomers
	WHERE LastName IS NULL;

-- DISCOVERED CustomerID "Co-12640" HAS NULL VALUE IN LastName DUE TO NAME STRUCTURE (Corey-Lock)
-- MAKING SUITABLE CHANGES
UPDATE DimCustomers
SET FirstName = 'Corey',
    LastName = 'Lock'
WHERE CustomerID = 'Co-12640';

-- ADJUSTING CONTRAINTS
ALTER TABLE DimCustomers
	DROP CONSTRAINT PK__DimCusto__A4AE64B8A68D0117;
ALTER TABLE DimCustomers
	ADD CONSTRAINT PK_Customers_CustomerID PRIMARY KEY (CustomerID)


--dbo.DimCustomerDetails
--PREPARING DimCustomerDetails TABLE
CREATE TABLE DimCustomerDetails (
	CustomerDetailsID INT IDENTITY (2000,1) PRIMARY KEY,
	CustomerID VARCHAR(20) FOREIGN KEY
		(CustomerID) REFERENCES DimCustomers(CustomerID),
	Country NVARCHAR(20),
	City NVARCHAR(20),
	[State] NVARCHAR(20),
	PostalCode INT,
	RegionID INT FOREIGN KEY
		(RegionID) REFERENCES DimPeople(RegionID)
);

SELECT *
	FROM DimCustomerDetails

CREATE VIEW DistinctCustomerDetails AS
SELECT DISTINCT CustomerID,
		Country,
		City,
		[State],
		PostalCode,
		Region
	FROM Orders_Temp

SELECT *
FROM DistinctCustomerDetails;

INSERT INTO DimCustomerDetails (CustomerID,
		Country,
		City,
		[State],
		PostalCode,
		RegionID
)
SELECT DCD.CustomerID,
		DCD.Country,
		DCD.City,
		DCD.[State],
		DCD.PostalCode,
		P.RegionID
	FROM DistinctCustomerDetails DCD
	JOIN DimPeople P ON DCD.Region = P.Region

SELECT *
	FROM DimCustomerDetails;

--ADJUSTING CONSTRAINTS
ALTER TABLE DimCustomerDetails
	DROP CONSTRAINT PK__DimOrder__4739199672CCF4F3;
ALTER TABLE DimCustomerDetails
	ADD CONSTRAINT PK_CustomerDetails_CustomerDetailsID PRIMARY KEY (CustomerDetailsID)

ALTER TABLE DimCustomerDetails
	DROP CONSTRAINT FK__DimOrderL__Custo__2B0A656D;
ALTER TABLE DimCustomerDetails
	ADD CONSTRAINT FK_CustomerDetails_Customers FOREIGN KEY (CustomerID) REFERENCES DimCustomers(CustomerID)

ALTER TABLE DimCustomerDetails
	DROP CONSTRAINT FK__DimOrderL__Regio__2BFE89A6;
ALTER TABLE DimCustomerDetails
	ADD CONSTRAINT FK_CustomerDetails_People FOREIGN KEY (RegionID) REFERENCES DimPeople(RegionID)


--BEFORE CONTINUING TO DIMORDERS, I DECIDED TO CONNECT THE OVERALL DATA
CREATE VIEW OverallSuperStoreData AS
SELECT DISTINCT OT.OrderID,
		OT.OrderDate,
		OT.ShipDate,
		OT.ShipMode,
		OT.CustomerID,
		PE.RegionID,
		P.ProductID,
		CD.CustomerDetailsID,
		RT.Returned,
		OT.Sales,
		OT.Quantity,
		OT.Discount,
		OT.Profit
	FROM Orders_Temp OT
	LEFT JOIN DimProducts P ON OT.ProductName = P.ProductName
	LEFT JOIN DimCustomerDetails CD 
		ON OT.CustomerID = CD.CustomerID
		AND OT.PostalCode = CD.PostalCode
	LEFT JOIN Returns_Temp RT ON OT.OrderID = RT.OrderID
	LEFT JOIN DimPeople PE ON OT.Region = PE.Region

SELECT *
	FROM OverallSuperStoreData

---- CONTINUING TO MAKE THE REST OF THE SQL TABLES

--dbo.DimOrders
--PREPARING DIMORDER TABLE
CREATE TABLE DimOrders (
	OrderID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
	OrderDate DATE,
	ShipDate DATE,
	ShipMode NVARCHAR(25),
	CustomerID VARCHAR(20) FOREIGN KEY
		(CustomerID) REFERENCES DimCustomers(CustomerID),
	ProductID VARCHAR(25) FOREIGN KEY
		(ProductID) REFERENCES DimProducts(ProductID),
	CustomerDetailsID INT FOREIGN KEY
		(CustomerDetailsID) REFERENCES DimCustomerDetails(CustomerDetailsID)
);

SELECT *
	FROM DimOrders

--INSERTING DATA TO DIMORDER TABLE
INSERT INTO DimOrders (
	OrderDate,
	ShipDate,
	ShipMode,
	CustomerID,
	ProductID,
	CustomerDetailsID
)
SELECT DISTINCT OrderDate,
		ShipDate,
		ShipMode,
		CustomerID,
		ProductID,
		CustomerDetailsID
	FROM OverallSuperStoreData

-- Adding and Updating Orders Table to include Region ID
ALTER TABLE DimOrders
	ADD RegionID INT;

UPDATE DimOrders
SET RegionID = CD.RegionID
FROM DimOrders O
INNER JOIN DimCustomerDetails CD 
ON O.CustomerDetailsID = CD.CustomerDetailsID

-- Checking Updated DimOrders with RegionID
SELECT RegionID,
	COUNT(*) AS Count
FROM DimOrders
GROUP BY RegionID
ORDER BY Count DESC;

--ADJUSTING CONSTRAINTS
ALTER TABLE DimOrders 
	DROP CONSTRAINT DF__DimOrders__Order__671F4F74
ALTER TABLE DimOrders 
	DROP CONSTRAINT PK__DimOrder__C3905BAFFDEC00DA
ALTER TABLE DimOrders 
	ALTER COLUMN OrderID VARCHAR(50) NOT NULL
ALTER TABLE DimOrders
	ADD CONSTRAINT PK_Orders_OrderID PRIMARY KEY (OrderID)

ALTER TABLE DimOrders 
	DROP CONSTRAINT FK__DimOrders__Custo__681373AD;
ALTER TABLE DimOrders 
	DROP CONSTRAINT FK__DimOrders__Custo__69FBBC1F;
ALTER TABLE DimOrders 
	DROP CONSTRAINT FK__DimOrders__Produ__690797E6;
ALTER TABLE DimOrders 
	ADD CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES DimCustomers(CustomerID)
ALTER TABLE DimOrders 
	ADD CONSTRAINT FK_Orders_CustomerDetails FOREIGN KEY (CustomerDetailsID) REFERENCES DimCustomerDetails(CustomerDetailsID)
ALTER TABLE DimOrders 
	ADD CONSTRAINT FK_Orders_Products FOREIGN KEY (ProductID) REFERENCES DimProducts(ProductID)
ALTER TABLE DimOrders 
	ADD CONSTRAINT FK_Orders_People FOREIGN KEY (RegionID) REFERENCES DimPeople(RegionID)


--dbo.People
--PREPARING DIMPEOPLE TABLE
CREATE TABLE DimPeople (
	RegionID INT IDENTITY (101,1) PRIMARY KEY,
	Region NVARCHAR(15),
	RegionalManager NVARCHAR(25)
);

INSERT INTO DimPeople (Region, RegionalManager)
SELECT Region,
		RegionalManager
	FROM People_Temp

SELECT *
	FROM DimPeople;

--ADJUSTING CONSTRAINTS
ALTER TABLE DimPeople
	DROP CONSTRAINT PK__People__ACD8444308521D3B;
ALTER TABLE DimPeople
	ADD CONSTRAINT PK_People_RegionID PRIMARY KEY (RegionID)


--dbo.Returns
--PREPARING DIMRETURNS
CREATE TABLE DimReturns (
	ReturnID INT IDENTITY(30001,1) PRIMARY KEY,
	OrderID VARCHAR(50) FOREIGN KEY
		(OrderID) REFERENCES DimOrders(OrderID),
	Returned NVARCHAR(10)
);

--INSERTING DATA
INSERT INTO DimReturns (
	OrderID,
	Returned
)
SELECT DISTINCT O.OrderID,
		SS.Returned
	FROM DimOrders O
	LEFT JOIN OverallSuperStoreData SS
		ON O.OrderDate = SS.OrderDate
		AND O.ShipDate = SS.ShipDate
		AND O.ShipMode = SS.ShipMode
		AND O.CustomerID = SS.CustomerID
		AND O.ProductID = SS.ProductID
		AND O.CustomerDetailsID = SS.CustomerDetailsID

SELECT *
	FROM DimReturns

UPDATE DimReturns
SET Returned = 'No'
WHERE Returned IS NULL

-- DECIDED TO ABOLISH RETURN TABLE AND INTEGRATE IT TO ORDERS TABLE
ALTER TABLE DimOrders
	ADD IsReturned NVARCHAR(10)

SELECT *
	FROM DimOrders

UPDATE O
SET IsReturned = R.Returned
FROM DimOrders O
JOIN DimReturns R ON O.OrderID = R.OrderID
WHERE O.IsReturned IS NULL

SELECT *,
	CASE
		WHEN O.IsReturned = R.Returned THEN
			'YES'
		ELSE
			'NO'
	END AS CHECKING
	FROM DimOrders O
	JOIN DimReturns R ON O.OrderID = R.OrderID


--dbo.FactOrderSales
DROP TABLE FactOrderSales
CREATE TABLE FactOrderSales (
	OrderSalesID INT IDENTITY(4000001,1) PRIMARY KEY,
	OrderID VARCHAR(50) FOREIGN KEY
		(OrderID) REFERENCES DimOrders(OrderID),
	ProductID VARCHAR(25) FOREIGN KEY
		(ProductID) REFERENCES DimProducts(ProductID),
	Sales MONEY,
	Quantity SMALLINT,
	[Discount Rate %] INT,
	Profit MONEY
)

SELECT *
	FROM FactOrderSales

INSERT INTO FactOrderSales (
	OrderID,
	ProductID,
	Sales,
	Quantity,
	[Discount Rate %],
	Profit
)
SELECT DISTINCT O.OrderID,
		O.ProductID,
		ROUND(SS.Sales,2) AS Sales,
		SS.Quantity,
		TRY_CAST(SS.Discount * 100 AS INT) AS [Discount Rate %],
		ROUND(SS.Profit,2) AS Profit
	FROM DimOrders O
	LEFT JOIN OverallSuperStoreData SS
		ON O.OrderDate = SS.OrderDate
		AND O.ShipDate = SS.ShipDate
		AND O.ShipMode = SS.ShipMode
		AND O.CustomerID = SS.CustomerID
		AND O.ProductID = SS.ProductID
		AND O.CustomerDetailsID = SS.CustomerDetailsID

-- Adding RegionID to FactOrderSales
ALTER TABLE FactOrderSales
	ADD RegionID INT;

UPDATE FactOrderSales
SET RegionID = O.RegionID
FROM FactOrderSales OS
INNER JOIN DimOrders O
ON OS.OrderID = O.OrderID

-- CHECKING UPDATED RegionID IN FactOrderSales
SELECT RegionID,
	COUNT(*) AS Count
FROM FactOrderSales
GROUP BY RegionID
ORDER BY Count DESC;

--ADJUSTING CONSTRAINTS
ALTER TABLE FactOrderSales
	DROP CONSTRAINT PK__FactOrde__6901F98730B75265
ALTER TABLE FactOrderSales
	ADD CONSTRAINT PK_OrderSales_OrderSalesID PRIMARY KEY (OrderSalesID)

ALTER TABLE FactOrderSales
	DROP CONSTRAINT FK__FactOrder__Order__2334397B;
ALTER TABLE FactOrderSales
	DROP CONSTRAINT FK__FactOrder__Produ__24285DB4;
ALTER TABLE FactOrderSales
	ADD CONSTRAINT FK_OrderSales_Orders FOREIGN KEY (OrderID) REFERENCES DimOrders(OrderID)
ALTER TABLE FactOrderSales
	ADD CONSTRAINT FK_OrderSales_Products FOREIGN KEY (ProductID) REFERENCES DimProducts(ProductID)
ALTER TABLE FactOrderSales
	ADD CONSTRAINT FK_OrderSales_People FOREIGN KEY (RegionID) REFERENCES DimPeople(RegionID)


-- FINISHING TOUCHES ON THE DATA
-- REMOVING TEMPORARY TABLES AND VIEWS
DROP TABLE DimReturns
DROP TABLE Orders_Temp
DROP TABLE People_Temp
DROP TABLE Returns_Temp

DROP VIEW DistinctCustomerDetails
DROP VIEW DistinctCustomers
DROP VIEW DistinctProducts
DROP VIEW OverallSuperStoreData
DROP VIEW UniqueProductIDCount


--------- ADDING USERS AND SECURITY (DCL)
---- CREATING TEAM ROLES 
USE SuperStoreDec2017
CREATE ROLE SalesTeam;
CREATE ROLE CustomerSupportTeam;
CREATE ROLE ManagementTeam;
CREATE ROLE InventoryTeam;
CREATE ROLE FinancialTeam;

---- GRANTING ACCESS TO EACH TEAM ROLES
GRANT SELECT ON dbo.DimCustomerDetails TO SalesTeam
GRANT SELECT ON dbo.DimCustomers TO SalesTeam
GRANT SELECT ON dbo.DimOrders TO SalesTeam
GRANT SELECT ON dbo.DimProducts TO SalesTeam
GRANT SELECT ON dbo.FactOrderSales TO SalesTeam

GRANT SELECT ON dbo.DimCustomerDetails TO CustomerSupportTeam
GRANT SELECT ON dbo.DimCustomers TO CustomerSupportTeam
GRANT SELECT ON dbo.DimOrders TO CustomerSupportTeam

GRANT SELECT ON SCHEMA::dbo TO ManagementTeam

GRANT SELECT ON dbo.DimProducts TO InventoryTeam
GRANT SELECT ON dbo.DimPeople TO InventoryTeam
GRANT SELECT ON dbo.FactOrderSales TO InventoryTeam

GRANT SELECT ON dbo.DimCustomers TO FinancialTeam
GRANT SELECT ON dbo.DimOrders TO FinancialTeam
GRANT SELECT ON dbo.DimProducts TO FinancialTeam
GRANT SELECT ON dbo.FactOrderSales TO FinancialTeam

---- CREATING USER ACCESS LOGINS FROM EACH TEAM ROLE
-- CREATING LOGINS
USE master
CREATE LOGIN Sahara WITH PASSWORD = 'SaharaSalesRep'
CREATE LOGIN Alex WITH PASSWORD = 'AlexAccManager'
CREATE LOGIN Chris WITH PASSWORD = 'ChrisSalesAsso'
CREATE LOGIN Marie WITH PASSWORD = 'MarieSalesCoord'

CREATE LOGIN Emilia WITH PASSWORD = 'EmiliaCustomerSupport'
CREATE LOGIN Kevin WITH PASSWORD = 'KevinTechSupport'
CREATE LOGIN Lizzie WITH PASSWORD = 'LizzieCustomerService'
CREATE LOGIN Mikey WITH PASSWORD = 'MikeySupportSpecial'

CREATE LOGIN Mark WITH PASSWORD = 'MarkCOO'
CREATE LOGIN Laura WITH PASSWORD = 'LauraSalesDirect'
CREATE LOGIN Brian WITH PASSWORD = 'BrianFinanceManage'
CREATE LOGIN Rachelle WITH PASSWORD = 'RachelleHRDirect'

CREATE LOGIN Daniel WITH PASSWORD = 'DanielInventDirect'
CREATE LOGIN Jessica WITH PASSWORD = 'JessicaPurchaseAgent'
CREATE LOGIN Thomas WITH PASSWORD = 'ThomasWarehouseSup'
CREATE LOGIN Olivia WITH PASSWORD = 'OliviaStoreClerk'

CREATE LOGIN Eric WITH PASSWORD = 'EricCFO'
CREATE LOGIN Nerissa WITH PASSWORD = 'NerissaFAnalyst'
CREATE LOGIN Roberu WITH PASSWORD = 'RoberuAccountant'
CREATE LOGIN Shiori WITH PASSWORD = 'ShioriTreasury'

-- CREATUNG USERS FOR LOGIN
USE SuperStoreDec2017
CREATE USER Sahara_SalesRep FOR LOGIN Sahara
CREATE USER Alex_AccountManager FOR LOGIN Alex
CREATE USER Chris_SalesAssociate FOR LOGIN Chris
CREATE USER Marie_SalesCoordinator FOR LOGIN Marie

CREATE USER Emilia_CustomerSupportRep FOR LOGIN Emilia
CREATE USER Kevin_TechnicalSupportRep FOR LOGIN Kevin
CREATE USER Lizzie_CustomerServiceRep FOR LOGIN Lizzie
CREATE USER Mikey_SupportSpecialist FOR LOGIN Mikey

CREATE USER Mark_ChiefOperatingOfficer FOR LOGIN Mark
CREATE USER Laura_SalesDirector FOR LOGIN Laura
CREATE USER Brian_FinanceManager FOR LOGIN Brian
CREATE USER Rachelle_HRDirector FOR LOGIN Rachelle

CREATE USER Daniel_InventoryManager FOR LOGIN Daniel
CREATE USER Jessica_PurchasingAgent FOR LOGIN Jessica
CREATE USER Thomas_WarehouseSupervisor FOR LOGIN Thomas
CREATE USER Olivia_StoreClerk FOR LOGIN Olivia

CREATE USER Eric_ChiefFinancialOfficer FOR LOGIN Eric
CREATE USER Nerissa_FinancialAnalyst FOR LOGIN Nerissa
CREATE USER Roberu_Accountant FOR LOGIN Roberu
CREATE USER Shiori_TreasurySpecialist FOR LOGIN Shiori

-- ADDING USERS TO THEIR RESPECTIVE TEAMS
EXEC sp_addrolemember 'SalesTeam', 'Sahara_SalesRep'
EXEC sp_addrolemember 'SalesTeam', 'Alex_AccountManager'
EXEC sp_addrolemember 'SalesTeam', 'Chris_SalesAssociate'
EXEC sp_addrolemember 'SalesTeam', 'Marie_SalesCoordinator'
EXEC sp_addrolemember 'CustomerSupportTeam', 'Emilia_CustomerSupportRep'
EXEC sp_addrolemember 'CustomerSupportTeam', 'Kevin_TechnicalSupportRep'
EXEC sp_addrolemember 'CustomerSupportTeam', 'Lizzie_CustomerServiceRep'
EXEC sp_addrolemember 'CustomerSupportTeam', 'Mikey_SupportSpecialist'
EXEC sp_addrolemember 'ManagementTeam', 'Mark_ChiefOperatingOfficer'
EXEC sp_addrolemember 'ManagementTeam', 'Laura_SalesDirector'
EXEC sp_addrolemember 'ManagementTeam', 'Brian_FinanceManager'
EXEC sp_addrolemember 'ManagementTeam', 'Rachelle_HRDirector'
EXEC sp_addrolemember 'InventoryTeam', 'Daniel_InventoryManager'
EXEC sp_addrolemember 'InventoryTeam', 'Jessica_PurchasingAgent'
EXEC sp_addrolemember 'InventoryTeam', 'Thomas_WarehouseSupervisor'
EXEC sp_addrolemember 'InventoryTeam', 'Olivia_StoreClerk'
EXEC sp_addrolemember 'FinancialTeam', 'Eric_ChiefFinancialOfficer'
EXEC sp_addrolemember 'FinancialTeam', 'Nerissa_FinancialAnalyst'
EXEC sp_addrolemember 'FinancialTeam', 'Roberu_Accountant'
EXEC sp_addrolemember 'FinancialTeam', 'Shiori_TreasurySpecialist'

---- Adjusting permissions per each users of the team
GRANT INSERT, UPDATE, DELETE ON dbo.DimCustomerDetails TO Sahara_SalesRep
GRANT INSERT, UPDATE, DELETE ON dbo.DimCustomers TO Sahara_SalesRep
GRANT INSERT, UPDATE, DELETE ON dbo.DimOrders TO Sahara_SalesRep
GRANT INSERT, UPDATE, DELETE ON dbo.DimProducts TO Sahara_SalesRep
GRANT INSERT, UPDATE, DELETE ON dbo.FactOrderSales TO Sahara_SalesRep
GRANT UPDATE ON dbo.DimCustomerDetails TO Alex_AccountManager
GRANT UPDATE ON dbo.DimCustomers TO Alex_AccountManager
GRANT UPDATE ON dbo.DimOrders TO Alex_AccountManager
GRANT UPDATE ON dbo.DimProducts TO Alex_AccountManager
GRANT UPDATE ON dbo.FactOrderSales TO Alex_AccountManager
GRANT INSERT, UPDATE ON dbo.DimCustomerDetails TO Emilia_CustomerSupportRep
GRANT INSERT, UPDATE ON dbo.DimCustomers TO Emilia_CustomerSupportRep
GRANT INSERT, UPDATE ON dbo.DimOrders TO Emilia_CustomerSupportRep
GRANT INSERT ON dbo.DimCustomerDetails TO Kevin_TechnicalSupportRep, Lizzie_CustomerServiceRep, Mikey_SupportSpecialist
GRANT INSERT ON dbo.DimCustomers TO Kevin_TechnicalSupportRep, Lizzie_CustomerServiceRep, Mikey_SupportSpecialist
GRANT INSERT ON dbo.DimOrders TO Kevin_TechnicalSupportRep, Lizzie_CustomerServiceRep, Mikey_SupportSpecialist
GRANT UPDATE ON SCHEMA::dbo TO Mark_ChiefOperatingOfficer, Brian_FinanceManager
GRANT INSERT, UPDATE ON dbo.DimProducts TO Daniel_InventoryManager
GRANT INSERT, UPDATE ON dbo.DimPeople TO Daniel_InventoryManager
GRANT INSERT, UPDATE ON dbo.FactOrderSales TO Daniel_InventoryManager
GRANT INSERT ON dbo.DimProducts TO Jessica_PurchasingAgent
GRANT INSERT ON dbo.DimPeople TO Jessica_PurchasingAgent
GRANT INSERT ON dbo.FactOrderSales TO Jessica_PurchasingAgent
GRANT INSERT, UPDATE ON dbo.DimCustomers TO Eric_ChiefFinancialOfficer
GRANT INSERT, UPDATE ON dbo.DimOrders TO Eric_ChiefFinancialOfficer
GRANT INSERT, UPDATE ON dbo.DimProducts TO Eric_ChiefFinancialOfficer
GRANT INSERT, UPDATE ON dbo.FactOrderSales TO Eric_ChiefFinancialOfficer


---- Checking if user is successful: Shiori_TreasurySpecialist ACC

SELECT *
	FROM DimProducts

EXECUTE AS USER = 'Shiori_TreasurySpecialist'

UPDATE DimProducts
SET ProductName = 'Bush Birmingham Collection Bookcase_ Dark Cherry'
WHERE ProductID = 'FUR-BO-10000112';

REVERT;

