USE master;
GO

SET NOCOUNT ON;
GO

-- Cleanup and reset identity columns

DELETE FROM WorkItem;
DELETE FROM Works;
DELETE FROM Analiz;
DELETE FROM Employee;
DELETE FROM WorkStatus;
GO

DBCC CHECKIDENT('WorkItem', RESEED, 0);
DBCC CHECKIDENT('Works', RESEED, 0);
DBCC CHECKIDENT('Analiz', RESEED, 0);
DBCC CHECKIDENT('Employee', RESEED, 0);
DBCC CHECKIDENT('WorkStatus', RESEED, 0);
GO


-- Insert reference data


-- Insert Employees
INSERT INTO Employee (Login_Name, Name, Patronymic, Surname, Email, Post, CreateDate, Archived, IS_Role)
SELECT
  'user' + CAST(v.number AS VARCHAR(5)),
  'FirstName' + CAST(v.number AS VARCHAR(5)),
  'Patronymic' + CAST(v.number AS VARCHAR(5)),
  'LastName' + CAST(v.number AS VARCHAR(5)),
  'user' + CAST(v.number AS VARCHAR(5)) + '@example.com',
  'doctor',
  GETDATE(),
  0,
  0
FROM master.dbo.spt_values v
WHERE v.type = 'P' AND v.number BETWEEN 1 AND 100;
GO

-- Insert Analyses
INSERT INTO Analiz (IS_GROUP, MATERIAL_TYPE, CODE_NAME, FULL_NAME, Text_Norm, Price)
SELECT
  0,
  1,
  'AN' + CAST(v.number AS VARCHAR(5)),
  'Test Analysis ' + CAST(v.number AS VARCHAR(5)),
  'normal',
  ROUND(RAND(CHECKSUM(NEWID())) * 1000, 2)
FROM master.dbo.spt_values v
WHERE v.type = 'P' AND v.number BETWEEN 1 AND 200;
GO

-- Insert Work Statuses
INSERT INTO WorkStatus (StatusName)
VALUES
  ('Created'),
  ('In Progress'),
  ('Completed'),
  ('Cancelled')
GO

-- Generate 50,000 Orders with random items

DECLARE
  @i INT = 1,
  @maxOrders INT = 50000,
  @workId INT,
  @isComplit BIT,
  @daysOffset INT,
  @createDate DATETIME,
  @closeDate DATETIME,
  @itemCount INT,
  @j INT,
  @empId INT,
  @statusId INT,
  @analizId INT,
  @itemEmpId INT,
  @clientFIO NVARCHAR(200);

WHILE @i <= @maxOrders
BEGIN
  -- Generate order-level attributes
  SET @isComplit = CAST(ABS(CHECKSUM(NEWID())) % 2 AS BIT);
  SET @daysOffset = ABS(CHECKSUM(NEWID())) % 365;
  SET @createDate = DATEADD(DAY, -@daysOffset, GETDATE());
  SET @closeDate = CASE
                     WHEN @isComplit = 1 THEN DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 30 + 1, @createDate)
                     ELSE NULL
                   END;

  -- Random employee and status
  SELECT TOP 1 @empId = Id_Employee FROM Employee ORDER BY NEWID();
  SELECT TOP 1 @statusId = StatusID FROM WorkStatus ORDER BY NEWID();

  -- Random patient name
  SET @clientFIO = 'Patient ' + CAST(ABS(CHECKSUM(NEWID())) % 100000 + 1 AS NVARCHAR(10));

  -- Insert order
  INSERT INTO Works (IS_Complit, CREATE_Date, CLOSE_DATE, Id_Employee, FIO, StatusId)
  VALUES (@isComplit, @createDate, @closeDate, @empId, @clientFIO, @statusId);

  SET @workId = SCOPE_IDENTITY();

  -- Generate 1 to 5 work items per order (avg ~ 3)
  SET @itemCount = ABS(CHECKSUM(NEWID())) % 5 + 1;
  SET @j = 1;

  WHILE @j <= @itemCount
  BEGIN
    SELECT TOP 1 @analizId = ID_ANALIZ FROM Analiz ORDER BY NEWID();
    SELECT TOP 1 @itemEmpId = Id_Employee FROM Employee ORDER BY NEWID();

    INSERT INTO WorkItem (Id_Work, ID_ANALIZ, Id_Employee, Is_Complit, Is_Print)
    VALUES (@workId, @analizId, @itemEmpId, CAST(ABS(CHECKSUM(NEWID())) % 2 AS BIT), 1);

    SET @j += 1;
  END

  -- Print progress every 1000 rows
  IF @i % 1000 = 0
    PRINT CAST(@i AS VARCHAR(10)) + ' orders inserted...';

  SET @i += 1;
END

PRINT 'Test data generation completed successfully.';
GO