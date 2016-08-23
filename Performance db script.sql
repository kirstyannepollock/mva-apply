---------------------------------------------------------------------
-- Code to create and populate Performance sample database
-- � Itzik Ben-Gan
---------------------------------------------------------------------

-- Creation Script for Sample Database and Tables
SET NOCOUNT ON;
USE master;
IF DB_ID('Performance') IS NULL CREATE DATABASE Performance;
GO
USE Performance;
GO

-- drop objects if exist
IF OBJECT_ID('dbo.GetNums', 'IF') IS NOT NULL DROP FUNCTION dbo.GetNums;

IF OBJECT_ID('dbo.VEmpOrders') IS NOT NULL DROP VIEW dbo.VEmpOrders;

IF OBJECT_ID('dbo.Orders') IS NOT NULL DROP TABLE dbo.Orders;
IF OBJECT_ID('dbo.Customers') IS NOT NULL DROP TABLE dbo.Customers;
IF OBJECT_ID('dbo.Employees') IS NOT NULL DROP TABLE dbo.Employees;
IF OBJECT_ID('dbo.Shippers') IS NOT NULL DROP TABLE dbo.Shippers;

IF OBJECT_ID('dbo.Fact', 'U') IS NOT NULL DROP TABLE dbo.Fact;
IF OBJECT_ID('dbo.Dim1', 'U') IS NOT NULL DROP TABLE dbo.Dim1;
IF OBJECT_ID('dbo.Dim2', 'U') IS NOT NULL DROP TABLE dbo.Dim2;
IF OBJECT_ID('dbo.Dim3', 'U') IS NOT NULL DROP TABLE dbo.Dim3;
GO

-- definition of GetNums function
CREATE FUNCTION dbo.GetNums(@low AS BIGINT, @high AS BIGINT) RETURNS TABLE
AS
RETURN
  WITH
    L0   AS (SELECT c FROM (VALUES(1),(1)) AS D(c)),
    L1   AS (SELECT 1 AS c FROM L0 AS A CROSS JOIN L0 AS B),
    L2   AS (SELECT 1 AS c FROM L1 AS A CROSS JOIN L1 AS B),
    L3   AS (SELECT 1 AS c FROM L2 AS A CROSS JOIN L2 AS B),
    L4   AS (SELECT 1 AS c FROM L3 AS A CROSS JOIN L3 AS B),
    L5   AS (SELECT 1 AS c FROM L4 AS A CROSS JOIN L4 AS B),
    Nums AS (SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS rownum
            FROM L5)
  SELECT TOP(@high - @low + 1) @low + rownum - 1 AS n
  FROM Nums
  ORDER BY rownum;
GO

-- data distribution settings for orders
DECLARE
  @numorders   AS INT      =   1000000,
  @numcusts    AS INT      =     20000,
  @numemps     AS INT      =       500,
  @numshippers AS INT      =         5,
  @numyears    AS INT      =         4,
  @startdate   AS DATETIME = '20050101';

-- Creating and Populating the Customers Table
CREATE TABLE dbo.Customers
(
  custid   CHAR(11)     NOT NULL,
  custname NVARCHAR(50) NOT NULL
);

INSERT INTO dbo.Customers(custid, custname)
  SELECT
    'C' + RIGHT('000000000' + CAST(n AS VARCHAR(10)), 10) AS custid,
    N'Cust_' + CAST(n AS VARCHAR(10)) AS custname
  FROM dbo.GetNums(1, @numcusts);

ALTER TABLE dbo.Customers ADD
  CONSTRAINT PK_Customers PRIMARY KEY(custid);

-- Creating and Populating the Employees Table
CREATE TABLE dbo.Employees
(
  empid     INT          NOT NULL,
  firstname NVARCHAR(25) NOT NULL,
  lastname  NVARCHAR(25) NOT NULL
);

INSERT INTO dbo.Employees(empid, firstname, lastname)
  SELECT n AS empid,
    N'Fname_' + CAST(n AS NVARCHAR(10)) AS firstname,
    N'Lname_' + CAST(n AS NVARCHAR(10)) AS lastname
  FROM dbo.GetNums(1, @numemps);

ALTER TABLE dbo.Employees ADD
  CONSTRAINT PK_Employees PRIMARY KEY(empid);

-- Creating and Populating the Shippers Table
CREATE TABLE dbo.Shippers
(
  shipperid   VARCHAR(5)   NOT NULL,
  shippername NVARCHAR(50) NOT NULL
);

INSERT INTO dbo.Shippers(shipperid, shippername)
  SELECT shipperid, N'Shipper_' + shipperid AS shippername
  FROM (SELECT CHAR(ASCII('A') - 2 + 2 * n) AS shipperid
        FROM dbo.GetNums(1, @numshippers)) AS D;

ALTER TABLE dbo.Shippers ADD
  CONSTRAINT PK_Shippers PRIMARY KEY(shipperid);

-- Creating and Populating the Orders Table
CREATE TABLE dbo.Orders
(
  orderid   INT        NOT NULL,
  custid    CHAR(11)   NOT NULL,
  empid     INT        NOT NULL,
  shipperid VARCHAR(5) NOT NULL,
  orderdate DATETIME   NOT NULL,
  filler    CHAR(155)  NOT NULL DEFAULT('a')
);

INSERT INTO dbo.Orders(orderid, custid, empid, shipperid, orderdate)
  SELECT n AS orderid,
    'C' + RIGHT('000000000'
            + CAST(
                1 + ABS(CHECKSUM(NEWID())) % @numcusts
                AS VARCHAR(10)), 10) AS custid,
    1 + ABS(CHECKSUM(NEWID())) % @numemps AS empid,
    CHAR(ASCII('A') - 2
           + 2 * (1 + ABS(CHECKSUM(NEWID())) % @numshippers)) AS shipperid,
      DATEADD(day, n / (@numorders / (@numyears * 365.25)), @startdate)
        -- late arrival with earlier date
        - CASE WHEN n % 10 = 0
            THEN 1 + ABS(CHECKSUM(NEWID())) % 30
            ELSE 0 
          END AS orderdate
  FROM dbo.GetNums(1, @numorders)
  ORDER BY CHECKSUM(NEWID());

CREATE CLUSTERED INDEX idx_cl_od ON dbo.Orders(orderdate);

CREATE NONCLUSTERED INDEX idx_nc_sid_od_cid
  ON dbo.Orders(shipperid, orderdate, custid);

CREATE UNIQUE INDEX idx_unc_od_oid_i_cid_eid
  ON dbo.Orders(orderdate, orderid)
  INCLUDE(custid, empid);

ALTER TABLE dbo.Orders ADD
  CONSTRAINT PK_Orders PRIMARY KEY NONCLUSTERED(orderid),
  CONSTRAINT FK_Orders_Customers
    FOREIGN KEY(custid)    REFERENCES dbo.Customers(custid),
  CONSTRAINT FK_Orders_Employees
    FOREIGN KEY(empid)     REFERENCES dbo.Employees(empid),
  CONSTRAINT FK_Orders_Shippers
    FOREIGN KEY(shipperid) REFERENCES dbo.Shippers(shipperid);
GO

-- data distribution settings for dw
DECLARE
  @dim1rows AS INT = 100,
  @dim2rows AS INT = 50,
  @dim3rows AS INT = 200;

CREATE TABLE dbo.Dim1
(
  key1  INT NOT NULL CONSTRAINT PK_Dim1 PRIMARY KEY,
  attr1 INT NOT NULL,
  filler BINARY(100) NOT NULL DEFAULT (0x)
);

CREATE TABLE dbo.Dim2
(
  key2  INT NOT NULL CONSTRAINT PK_Dim2 PRIMARY KEY,
  attr1 INT NOT NULL,
  filler BINARY(100) NOT NULL DEFAULT (0x)
);

CREATE TABLE dbo.Dim3
(
  key3  INT NOT NULL CONSTRAINT PK_Dim3 PRIMARY KEY,
  attr1 INT NOT NULL,
  filler BINARY(100) NOT NULL DEFAULT (0x)
);

CREATE TABLE dbo.Fact
(
  key1 INT NOT NULL CONSTRAINT FK_Fact_Dim1 FOREIGN KEY REFERENCES dbo.Dim1,
  key2 INT NOT NULL CONSTRAINT FK_Fact_Dim2 FOREIGN KEY REFERENCES dbo.Dim2,
  key3 INT NOT NULL CONSTRAINT FK_Fact_Dim3 FOREIGN KEY REFERENCES dbo.Dim3,
  measure1 INT NOT NULL,
  measure2 INT NOT NULL,
  measure3 INT NOT NULL,
  filler  BINARY(100) NOT NULL DEFAULT (0x),
  CONSTRAINT PK_Fact PRIMARY KEY(key1, key2, key3)
);

INSERT INTO dbo.Dim1(key1, attr1)
  SELECT n, ABS(CHECKSUM(NEWID())) % 20 + 1
  FROM dbo.GetNums(1, @dim1rows);

INSERT INTO dbo.Dim2(key2, attr1)
  SELECT n, ABS(CHECKSUM(NEWID())) % 10 + 1
  FROM dbo.GetNums(1, @dim2rows);

INSERT INTO dbo.Dim3(key3, attr1)
  SELECT n, ABS(CHECKSUM(NEWID())) % 40 + 1
  FROM dbo.GetNums(1, @dim3rows);

INSERT INTO dbo.Fact WITH (TABLOCK) 
    (key1, key2, key3, measure1, measure2, measure3)
  SELECT N1.n, N2.n, N3.n,
    ABS(CHECKSUM(NEWID())) % 1000000 + 1,
    ABS(CHECKSUM(NEWID())) % 1000000 + 1,
    ABS(CHECKSUM(NEWID())) % 1000000 + 1
  FROM dbo.GetNums(1, @dim1rows) AS N1
    CROSS JOIN dbo.GetNums(1, @dim2rows) AS N2
    CROSS JOIN dbo.GetNums(1, @dim3rows) AS N3;
GO