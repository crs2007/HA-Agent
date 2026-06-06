-- =============================================================================
-- 09_normalize_severity_status.sql  —  Normalize severity & status to FK lookups
-- Run against: localhost\SQLSERVER2022 / TaskManager
-- Idempotent: safe to re-run (all steps guarded with IF NOT EXISTS / IF EXISTS).
-- =============================================================================
USE TaskManager;
GO

-- =============================================================================
-- Step 1: Create lookup tables
-- =============================================================================
IF OBJECT_ID('dbo._Severity', 'U') IS NULL
BEGIN
    CREATE TABLE dbo._Severity (
        id         SMALLINT     NOT NULL,
        name       NVARCHAR(20) NOT NULL,
        sort_order TINYINT      NOT NULL,
        CONSTRAINT PK__Severity     PRIMARY KEY (id),
        CONSTRAINT UQ__Severity_name UNIQUE      (name)
    );
    PRINT '_Severity table created.';
END
GO

IF OBJECT_ID('dbo._Status', 'U') IS NULL
BEGIN
    CREATE TABLE dbo._Status (
        id          SMALLINT     NOT NULL,
        name        NVARCHAR(20) NOT NULL,
        is_terminal BIT          NOT NULL DEFAULT 0,
        sort_order  TINYINT      NOT NULL,
        CONSTRAINT PK__Status      PRIMARY KEY (id),
        CONSTRAINT UQ__Status_name UNIQUE      (name)
    );
    PRINT '_Status table created.';
END
GO

-- =============================================================================
-- Step 2: Seed lookup rows (MERGE = idempotent)
-- =============================================================================
MERGE dbo._Severity AS tgt
USING (VALUES
    (1, 'low',      1),
    (2, 'medium',   2),
    (3, 'high',     3),
    (4, 'critical', 4)
) AS src(id, name, sort_order)
ON tgt.id = src.id
WHEN MATCHED     THEN UPDATE SET tgt.name = src.name, tgt.sort_order = src.sort_order
WHEN NOT MATCHED THEN INSERT (id, name, sort_order) VALUES (src.id, src.name, src.sort_order);
PRINT '_Severity seeded.';
GO

MERGE dbo._Status AS tgt
USING (VALUES
    (1, 'open',        0, 1),
    (2, 'in-progress', 0, 2),
    (3, 'planned',     0, 3),
    (4, 'done',        1, 4),
    (5, 'dismissed',   1, 5),
    (6, 'ignored',     1, 6),
    (7, 'archived',    1, 7)
) AS src(id, name, is_terminal, sort_order)
ON tgt.id = src.id
WHEN MATCHED     THEN UPDATE SET tgt.name = src.name, tgt.is_terminal = src.is_terminal, tgt.sort_order = src.sort_order
WHEN NOT MATCHED THEN INSERT (id, name, is_terminal, sort_order) VALUES (src.id, src.name, src.is_terminal, src.sort_order);
PRINT '_Status seeded.';
GO

-- =============================================================================
-- Step 3: Add FK columns (nullable for backfill)
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'severity_id')
BEGIN
    ALTER TABLE dbo.Tasks ADD severity_id SMALLINT NULL;
    PRINT 'Tasks.severity_id column added.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'status_id')
BEGIN
    ALTER TABLE dbo.Tasks ADD status_id SMALLINT NULL;
    PRINT 'Tasks.status_id column added.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'severity_id')
BEGIN
    ALTER TABLE dbo.TasksArchive ADD severity_id SMALLINT NULL;
    PRINT 'TasksArchive.severity_id column added.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'status_id')
BEGIN
    ALTER TABLE dbo.TasksArchive ADD status_id SMALLINT NULL;
    PRINT 'TasksArchive.status_id column added.';
END
GO

-- =============================================================================
-- Step 4: Backfill FK columns from existing string values
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'severity')
BEGIN
    UPDATE t
    SET    t.severity_id = s.id
    FROM   dbo.Tasks t
    JOIN   dbo._Severity s ON s.name = t.severity
    WHERE  t.severity_id IS NULL;
    PRINT 'Tasks.severity_id backfilled.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'status')
BEGIN
    UPDATE t
    SET    t.status_id = s.id
    FROM   dbo.Tasks t
    JOIN   dbo._Status s ON s.name = t.status
    WHERE  t.status_id IS NULL;
    PRINT 'Tasks.status_id backfilled.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'severity')
BEGIN
    UPDATE t
    SET    t.severity_id = s.id
    FROM   dbo.TasksArchive t
    JOIN   dbo._Severity s ON s.name = t.severity
    WHERE  t.severity_id IS NULL;
    PRINT 'TasksArchive.severity_id backfilled.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'status')
BEGIN
    UPDATE t
    SET    t.status_id = s.id
    FROM   dbo.TasksArchive t
    JOIN   dbo._Status s ON s.name = t.status
    WHERE  t.status_id IS NULL;
    PRINT 'TasksArchive.status_id backfilled.';
END
GO

-- =============================================================================
-- Step 5: Make FK columns NOT NULL with defaults
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'severity_id' AND is_nullable = 1)
BEGIN
    UPDATE dbo.Tasks SET severity_id = 2 WHERE severity_id IS NULL;
    ALTER TABLE dbo.Tasks ALTER COLUMN severity_id SMALLINT NOT NULL;
    ALTER TABLE dbo.Tasks ADD CONSTRAINT DF_Tasks_severity_id DEFAULT 2 FOR severity_id;
    PRINT 'Tasks.severity_id set NOT NULL.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'status_id' AND is_nullable = 1)
BEGIN
    UPDATE dbo.Tasks SET status_id = 1 WHERE status_id IS NULL;
    ALTER TABLE dbo.Tasks ALTER COLUMN status_id SMALLINT NOT NULL;
    ALTER TABLE dbo.Tasks ADD CONSTRAINT DF_Tasks_status_id DEFAULT 1 FOR status_id;
    PRINT 'Tasks.status_id set NOT NULL.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'severity_id' AND is_nullable = 1)
BEGIN
    UPDATE dbo.TasksArchive SET severity_id = 2 WHERE severity_id IS NULL;
    ALTER TABLE dbo.TasksArchive ALTER COLUMN severity_id SMALLINT NOT NULL;
    ALTER TABLE dbo.TasksArchive ADD CONSTRAINT DF_Archive_severity_id DEFAULT 2 FOR severity_id;
    PRINT 'TasksArchive.severity_id set NOT NULL.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'status_id' AND is_nullable = 1)
BEGIN
    UPDATE dbo.TasksArchive SET status_id = 1 WHERE status_id IS NULL;
    ALTER TABLE dbo.TasksArchive ALTER COLUMN status_id SMALLINT NOT NULL;
    ALTER TABLE dbo.TasksArchive ADD CONSTRAINT DF_Archive_status_id DEFAULT 1 FOR status_id;
    PRINT 'TasksArchive.status_id set NOT NULL.';
END
GO

-- =============================================================================
-- Step 6: Drop old CHECK constraints on string columns
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Tasks_severity' AND parent_object_id = OBJECT_ID('dbo.Tasks'))
BEGIN
    ALTER TABLE dbo.Tasks DROP CONSTRAINT CK_Tasks_severity;
    PRINT 'CK_Tasks_severity dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Tasks_status' AND parent_object_id = OBJECT_ID('dbo.Tasks'))
BEGIN
    ALTER TABLE dbo.Tasks DROP CONSTRAINT CK_Tasks_status;
    PRINT 'CK_Tasks_status dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Archive_severity' AND parent_object_id = OBJECT_ID('dbo.TasksArchive'))
BEGIN
    ALTER TABLE dbo.TasksArchive DROP CONSTRAINT CK_Archive_severity;
    PRINT 'CK_Archive_severity dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Archive_status' AND parent_object_id = OBJECT_ID('dbo.TasksArchive'))
BEGIN
    ALTER TABLE dbo.TasksArchive DROP CONSTRAINT CK_Archive_status;
    PRINT 'CK_Archive_status dropped.';
END
GO

-- =============================================================================
-- Step 7: Drop old string columns
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'severity')
BEGIN
    ALTER TABLE dbo.Tasks DROP COLUMN severity;
    PRINT 'Tasks.severity column dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'status')
BEGIN
    ALTER TABLE dbo.Tasks DROP COLUMN status;
    PRINT 'Tasks.status column dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'severity')
BEGIN
    ALTER TABLE dbo.TasksArchive DROP COLUMN severity;
    PRINT 'TasksArchive.severity column dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'status')
BEGIN
    ALTER TABLE dbo.TasksArchive DROP COLUMN status;
    PRINT 'TasksArchive.status column dropped.';
END
GO

-- =============================================================================
-- Step 8: Add FK constraints
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Tasks_severity_id')
BEGIN
    ALTER TABLE dbo.Tasks ADD CONSTRAINT FK_Tasks_severity_id
        FOREIGN KEY (severity_id) REFERENCES dbo._Severity(id);
    PRINT 'FK_Tasks_severity_id added.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Tasks_status_id')
BEGIN
    ALTER TABLE dbo.Tasks ADD CONSTRAINT FK_Tasks_status_id
        FOREIGN KEY (status_id) REFERENCES dbo._Status(id);
    PRINT 'FK_Tasks_status_id added.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Archive_severity_id')
BEGIN
    ALTER TABLE dbo.TasksArchive ADD CONSTRAINT FK_Archive_severity_id
        FOREIGN KEY (severity_id) REFERENCES dbo._Severity(id);
    PRINT 'FK_Archive_severity_id added.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Archive_status_id')
BEGIN
    ALTER TABLE dbo.TasksArchive ADD CONSTRAINT FK_Archive_status_id
        FOREIGN KEY (status_id) REFERENCES dbo._Status(id);
    PRINT 'FK_Archive_status_id added.';
END
GO

-- =============================================================================
-- Step 9: Rebuild indexes (drop string-based, create ID-based)
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'IX_Tasks_severity')
BEGIN
    DROP INDEX IX_Tasks_severity ON dbo.Tasks;
    PRINT 'IX_Tasks_severity dropped.';
END
GO

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'IX_Tasks_status')
BEGIN
    DROP INDEX IX_Tasks_status ON dbo.Tasks;
    PRINT 'IX_Tasks_status dropped.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'IX_Tasks_severity_id')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Tasks_severity_id ON dbo.Tasks(severity_id);
    PRINT 'IX_Tasks_severity_id created.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'IX_Tasks_status_id')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Tasks_status_id ON dbo.Tasks(status_id);
    PRINT 'IX_Tasks_status_id created.';
END
GO

-- =============================================================================
-- Step 10: Drop model CHECK constraints — model is now a free-form string
-- to support any current or future LLM model (Claude, GPT-4o, Gemini, etc.)
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Tasks_model' AND parent_object_id = OBJECT_ID('dbo.Tasks'))
BEGIN
    ALTER TABLE dbo.Tasks DROP CONSTRAINT CK_Tasks_model;
    PRINT 'CK_Tasks_model dropped (model is now free-form).';
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Archive_model' AND parent_object_id = OBJECT_ID('dbo.TasksArchive'))
BEGIN
    ALTER TABLE dbo.TasksArchive DROP CONSTRAINT CK_Archive_model;
    PRINT 'CK_Archive_model dropped (model is now free-form).';
END
GO

PRINT '09_normalize_severity_status.sql completed successfully.';
GO
