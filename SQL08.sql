CREATE TABLE PatientAudit (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT,
    PatientName NVARCHAR(100),
    WardId INT,
    DateOfBirth DATE,
    AuditDate DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- Q30 and Q34: Consultant Salary Audit
CREATE TABLE ConsultantSalaryAudit (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    ConsultantID INT,
    OldSalary DECIMAL(18,2),
    NewSalary DECIMAL(18,2),
    AuditDate DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- Q31: Patient Ward Audit
CREATE TABLE PatientWardAudit (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT,
    OldWardId INT,
    NewWardId INT,
    AuditDate DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- Q32, Q42 and Q45: Deleted Patient Archive
CREATE TABLE DeletedPatients (
    ArchiveID INT IDENTITY(1,1) PRIMARY KEY,
    PatientID INT,
    PatientName NVARCHAR(100),
    WardId INT,
    DateOfBirth DATE,
    DeletedDate DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- Q33: Deleted Consultant Audit
CREATE TABLE DeletedConsultants (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    ConsultantID INT,
    ConsultantName NVARCHAR(100),
    Salary DECIMAL(18,2),
    DeletedDate DATETIME2 DEFAULT SYSDATETIME()
);
GO
CREATE TRIGGER trg_Patient_AfterInsert
ON Patients
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO PatientAudit
        (PatientID, PatientName, WardId, DateOfBirth)
    SELECT
        PatientID, PatientName, WardId, DateOfBirth
    FROM inserted;
END;
GO
CREATE TRIGGER trg_Consultant_SalaryUpdate
ON Consultants
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO ConsultantSalaryAudit
        (ConsultantID, OldSalary, NewSalary)
    SELECT
        i.ConsultantID,
        d.Salary,
        i.Salary
    FROM inserted i
    INNER JOIN deleted d
        ON i.ConsultantID = d.ConsultantID
    WHERE
        i.Salary <> d.Salary
        OR (i.Salary IS NULL AND d.Salary IS NOT NULL)
        OR (i.Salary IS NOT NULL AND d.Salary IS NULL);

    SELECT
        i.ConsultantID,
        d.Salary AS OldSalary,
        i.Salary AS NewSalary
    FROM inserted i
    INNER JOIN deleted d
        ON i.ConsultantID = d.ConsultantID
    WHERE
        i.Salary <> d.Salary
        OR (i.Salary IS NULL AND d.Salary IS NOT NULL)
        OR (i.Salary IS NOT NULL AND d.Salary IS NULL);
END;
GO
CREATE TRIGGER trg_Patient_WardUpdate
ON Patients
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO PatientWardAudit
        (PatientID, OldWardId, NewWardId)
    SELECT
        i.PatientID,
        d.WardId,
        i.WardId
    FROM inserted i
    INNER JOIN deleted d
        ON i.PatientID = d.PatientID
    WHERE
        i.WardId <> d.WardId
        OR (i.WardId IS NULL AND d.WardId IS NOT NULL)
        OR (i.WardId IS NOT NULL AND d.WardId IS NULL);

    SELECT
        i.PatientID,
        d.WardId AS OldWardId,
        i.WardId AS NewWardId
    FROM inserted i
    INNER JOIN deleted d
        ON i.PatientID = d.PatientID
    WHERE
        i.WardId <> d.WardId
        OR (i.WardId IS NULL AND d.WardId IS NOT NULL)
        OR (i.WardId IS NOT NULL AND d.WardId IS NULL);
END;
GO
CREATE TRIGGER trg_Consultant_AfterDelete
ON Consultants
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO DeletedConsultants
        (ConsultantID, ConsultantName, Salary)
    SELECT
        ConsultantID, ConsultantName, Salary
    FROM deleted;
END;
GO
CREATE TRIGGER trg_Patient_ValidateInsert
ON Patients
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted
        WHERE WardId IS NULL
    )
    BEGIN
        THROW 50001, 'Patient must have a ward.', 1;
    END;

    IF EXISTS (
        SELECT 1
        FROM inserted
        WHERE DateOfBirth > CAST(GETDATE() AS DATE)
    )
    BEGIN
        THROW 50002, 'Date of birth cannot be in the future.', 1;
    END;

    INSERT INTO Patients
        (PatientName, WardId, DateOfBirth)
    SELECT
        PatientName, WardId, DateOfBirth
    FROM inserted;
END;
GO
CREATE TRIGGER trg_PreventSalaryReduction
ON Consultants
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN deleted d
            ON i.ConsultantID = d.ConsultantID
        WHERE i.Salary < d.Salary
    )
    BEGIN
        THROW 50003, 'Consultant salary cannot be reduced.', 1;
    END;

    UPDATE c
    SET
        c.ConsultantName = i.ConsultantName,
        c.Salary = i.Salary
    FROM Consultants c
    INNER JOIN inserted i
        ON c.ConsultantID = i.ConsultantID;
END;
GO
CREATE TRIGGER trg_Patient_ControlUpdate
ON Patients
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET
        p.PatientName = i.PatientName,
        p.WardId = i.WardId,
        p.DateOfBirth = i.DateOfBirth
    FROM Patients p
    INNER JOIN deleted d
        ON p.PatientID = d.PatientID
    INNER JOIN inserted i
        ON i.PatientID = d.PatientID;
END;
GO
CREATE TRIGGER trg_Patient_ControlDelete
ON Patients
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRY_CAST(SESSION_CONTEXT(N'AllowPatientDelete') AS INT) <> 1
    BEGIN
        THROW 50004,
              'Direct patient deletion is not allowed. Use the stored procedure.',
              1;
    END;

    INSERT INTO DeletedPatients
        (PatientID, PatientName, WardId, DateOfBirth)
    SELECT
        PatientID, PatientName, WardId, DateOfBirth
    FROM deleted;

    DELETE p
    FROM Patients p
    INNER JOIN deleted d
        ON p.PatientID = d.PatientID;
END;
GO
CREATE PROCEDURE AddPatient
    @PatientName NVARCHAR(100),
    @WardId INT,
    @DateOfBirth DATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Patients
        (PatientName, WardId, DateOfBirth)
    VALUES
        (@PatientName, @WardId, @DateOfBirth);
END;
GO

CREATE PROCEDURE UpdateConsultantSalary
    @ConsultantID INT,
    @NewSalary DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Consultants
    SET Salary = @NewSalary
    WHERE ConsultantID = @ConsultantID;

    IF @@ROWCOUNT = 0
        THROW 50005, 'Consultant not found.', 1;
END;
GO

CREATE PROCEDURE DeletePatientAndArchive
    @PatientID INT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        EXEC sys.sp_set_session_context
            @key = N'AllowPatientDelete',
            @value = 1;

        DELETE FROM Patients
        WHERE PatientID = @PatientID;

        IF @@ROWCOUNT = 0
            THROW 50006, 'Patient not found.', 1;

        EXEC sys.sp_set_session_context
            @key = N'AllowPatientDelete',
            @value = NULL;
    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context
            @key = N'AllowPatientDelete',
            @value = NULL;

        THROW;
    END CATCH;
END;
GO


-- Q43
EXEC AddPatient
    @PatientName = N'Ahmed',
    @WardId = 1,
    @DateOfBirth = '2000-05-10';
GO


SELECT * FROM PatientAudit;
GO

-- Q44
EXEC UpdateConsultantSalary
    @ConsultantID = 1,
    @NewSalary = 15000;
GO


SELECT * FROM ConsultantSalaryAudit;
GO

-- Q45
EXEC DeletePatientAndArchive