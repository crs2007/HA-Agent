-- =============================================================================
-- 01_tables.sql  —  TaskManager database schema
-- Run against: localhost\SQLSERVER2022 / TaskManager
-- =============================================================================
USE TaskManager;
GO

-- =============================================================================
-- Lookup: _Severity  (1=low, 2=medium, 3=high, 4=critical)
-- =============================================================================
CREATE TABLE dbo._Severity (
    id         SMALLINT     NOT NULL,
    name       NVARCHAR(20) NOT NULL,
    sort_order TINYINT      NOT NULL,
    CONSTRAINT PK__Severity      PRIMARY KEY (id),
    CONSTRAINT UQ__Severity_name UNIQUE      (name)
);
GO

INSERT INTO dbo._Severity (id, name, sort_order) VALUES
    (1, 'low',      1),
    (2, 'medium',   2),
    (3, 'high',     3),
    (4, 'critical', 4);
GO

-- =============================================================================
-- Lookup: _Status  (is_terminal=1 means closed/final state)
-- 1=open, 2=in-progress, 3=planned, 4=done, 5=dismissed, 6=ignored, 7=archived
-- =============================================================================
CREATE TABLE dbo._Status (
    id          SMALLINT     NOT NULL,
    name        NVARCHAR(20) NOT NULL,
    is_terminal BIT          NOT NULL DEFAULT 0,
    sort_order  TINYINT      NOT NULL,
    CONSTRAINT PK__Status      PRIMARY KEY (id),
    CONSTRAINT UQ__Status_name UNIQUE      (name)
);
GO

INSERT INTO dbo._Status (id, name, is_terminal, sort_order) VALUES
    (1, 'open',        0, 1),
    (2, 'in-progress', 0, 2),
    (3, 'planned',     0, 3),
    (4, 'done',        1, 4),
    (5, 'dismissed',   1, 5),
    (6, 'ignored',     1, 6),
    (7, 'archived',    1, 7);
GO

-- =============================================================================
-- Tasks: active task queue
-- Note: [plan] and [source] are bracketed — reserved/future-reserved in T-SQL
-- =============================================================================
CREATE TABLE dbo.Tasks (
    id           CHAR(4)       NOT NULL,
    title        NVARCHAR(500) NULL,
    description  NVARCHAR(MAX) NULL,
    severity_id  SMALLINT      NOT NULL DEFAULT 2,    -- FK → _Severity (2 = medium)
    category     NVARCHAR(50)  NOT NULL DEFAULT 'automation',
    status_id    SMALLINT      NOT NULL DEFAULT 1,    -- FK → _Status   (1 = open)
    agent        NVARCHAR(60)  NOT NULL DEFAULT 'unassigned',
    model        NVARCHAR(20)  NOT NULL DEFAULT 'unassigned',
    [source]     NVARCHAR(500) NULL,
    [plan]       NVARCHAR(MAX) NULL,
    log_count    INT           NOT NULL DEFAULT 0,
    notes        NVARCHAR(MAX) NULL,
    created_at   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at   DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Tasks          PRIMARY KEY (id),
    CONSTRAINT CK_Tasks_id_fmt   CHECK (id LIKE 'T[0-9][0-9][0-9]'),
    CONSTRAINT CK_Tasks_category CHECK (category IN ('automation','script','fix','dashboard','config','feature')),
    CONSTRAINT CK_Tasks_agent    CHECK (agent    IN ('unassigned','ha-developer','ha-reviewer','ha-reviver','ha-dashboard-designer','ha-task-manager')),
    CONSTRAINT FK_Tasks_severity_id FOREIGN KEY (severity_id) REFERENCES dbo._Severity(id),
    CONSTRAINT FK_Tasks_status_id   FOREIGN KEY (status_id)   REFERENCES dbo._Status(id)
);
GO

-- =============================================================================
-- TasksArchive: tasks moved out of the active set (done / dismissed / cleanup)
-- No FK back to Tasks — tasks are deleted from Tasks when archived.
-- PK on id prevents the same task ID from being archived twice.
-- =============================================================================
CREATE TABLE dbo.TasksArchive (
    id              CHAR(4)       NOT NULL,
    title           NVARCHAR(500) NULL,
    description     NVARCHAR(MAX) NULL,
    severity_id     SMALLINT      NOT NULL,
    category        NVARCHAR(50)  NOT NULL,
    status_id       SMALLINT      NOT NULL,
    agent           NVARCHAR(60)  NOT NULL,
    model           NVARCHAR(20)  NOT NULL,
    [source]        NVARCHAR(500) NULL,
    [plan]          NVARCHAR(MAX) NULL,
    log_count       INT           NOT NULL DEFAULT 0,
    notes           NVARCHAR(MAX) NULL,
    created_at      DATETIME2(3)  NOT NULL,
    updated_at      DATETIME2(3)  NOT NULL,
    archived_at     DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    archived_reason NVARCHAR(100) NULL,

    CONSTRAINT PK_TasksArchive          PRIMARY KEY (id),
    CONSTRAINT CK_Archive_category      CHECK (category IN ('automation','script','fix','dashboard','config','feature')),
    CONSTRAINT CK_Archive_agent         CHECK (agent    IN ('unassigned','ha-developer','ha-reviewer','ha-reviver','ha-dashboard-designer','ha-task-manager')),
    CONSTRAINT FK_Archive_severity_id   FOREIGN KEY (severity_id) REFERENCES dbo._Severity(id),
    CONSTRAINT FK_Archive_status_id     FOREIGN KEY (status_id)   REFERENCES dbo._Status(id)
);
GO

-- =============================================================================
-- TasksAudit: column-level audit of every change to dbo.Tasks
-- No FK to Tasks — audit rows must survive after a task is deleted.
-- Uses BIGINT IDENTITY to support millions of rows without overflow.
-- =============================================================================
CREATE TABLE dbo.TasksAudit (
    audit_id   BIGINT        NOT NULL IDENTITY(1,1),
    task_id    CHAR(4)       NOT NULL,
    action     NVARCHAR(20)  NOT NULL,   -- INSERT | UPDATE | DELETE | ARCHIVE | DIRECT_DML_BLOCKED
    field_name NVARCHAR(60)  NULL,       -- NULL for whole-row events (INSERT/DELETE/ARCHIVE)
    old_value  NVARCHAR(MAX) NULL,
    new_value  NVARCHAR(MAX) NULL,
    changed_by NVARCHAR(128) NOT NULL DEFAULT SYSTEM_USER,
    changed_at DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_TasksAudit   PRIMARY KEY (audit_id),
    CONSTRAINT CK_Audit_action CHECK (action IN ('INSERT','UPDATE','DELETE','ARCHIVE','DIRECT_DML_BLOCKED'))
);
GO

-- =============================================================================
-- Indexes
-- =============================================================================
CREATE NONCLUSTERED INDEX IX_Tasks_status_id   ON dbo.Tasks(status_id);
CREATE NONCLUSTERED INDEX IX_Tasks_agent       ON dbo.Tasks(agent);
CREATE NONCLUSTERED INDEX IX_Tasks_severity_id ON dbo.Tasks(severity_id);
CREATE NONCLUSTERED INDEX IX_Tasks_category    ON dbo.Tasks(category);

CREATE NONCLUSTERED INDEX IX_Archive_archived_at ON dbo.TasksArchive(archived_at DESC);

CREATE NONCLUSTERED INDEX IX_Audit_task_id  ON dbo.TasksAudit(task_id);
CREATE NONCLUSTERED INDEX IX_Audit_changed  ON dbo.TasksAudit(changed_at);
GO

PRINT 'Tables, constraints, and indexes created successfully.';
GO
