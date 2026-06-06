-- =============================================================================
-- 02_stored_procs.sql  —  All DML/query stored procedures for TaskManager
-- Run AFTER 01_tables.sql
-- severity_id / status_id are numeric FK references — callers convert strings
-- to IDs before calling. SELECTs JOIN lookup tables to return string names.
-- =============================================================================
USE TaskManager;
GO

-- =============================================================================
-- CONTEXT_INFO marker used by every DML SP.
-- The safety-net trigger (03_trigger.sql) allows DML only when this is set.
-- Convention: SPs set 0x5350 ('SP') before DML, clear to 0x00 after commit.
-- =============================================================================

-- =============================================================================
-- SP 1: usp_Task_GetNextId  (internal helper — called by usp_Task_Insert)
-- Scans both Tasks and TasksArchive to find the highest numeric suffix,
-- returns T + (max+1) zero-padded to 3 digits as an OUTPUT parameter.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetNextId
    @next_id CHAR(4) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @max_num INT;

    SELECT @max_num = MAX(CAST(SUBSTRING(id, 2, 3) AS INT))
    FROM (
        SELECT id FROM dbo.Tasks
        UNION ALL
        SELECT id FROM dbo.TasksArchive
    ) combined;

    SET @max_num = ISNULL(@max_num, 0);

    IF @max_num >= 999
        THROW 50001, 'Task ID space T001-T999 exhausted. Extend the schema to support wider IDs.', 1;

    SET @next_id = 'T' + RIGHT('000' + CAST(@max_num + 1 AS VARCHAR(3)), 3);
END
GO

-- =============================================================================
-- SP 2: usp_Task_Insert
-- Creates a new task. Pass @id = NULL to auto-generate via usp_Task_GetNextId.
-- @severity_id / @status_id are FK references to dbo._Severity / dbo._Status.
--   Defaults: 2 = medium, 1 = open. Caller is responsible for ID conversion.
-- @created_at / @updated_at accept explicit timestamps for data migration;
--   NULL defaults to SYSUTCDATETIME().
-- Returns the full inserted row with severity/status as string names.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_Insert
    @id          CHAR(4)       = NULL,
    @title       NVARCHAR(500) = NULL,
    @description NVARCHAR(MAX) = NULL,
    @severity_id SMALLINT      = 2,          -- 2 = medium
    @category    NVARCHAR(50)  = 'automation',
    @status_id   SMALLINT      = 1,          -- 1 = open
    @agent       NVARCHAR(60)  = 'unassigned',
    @model       NVARCHAR(20)  = 'unassigned',
    @source      NVARCHAR(500) = NULL,
    @plan        NVARCHAR(MAX) = NULL,
    @log_count   INT           = 0,
    @notes       NVARCHAR(MAX) = NULL,
    @created_at  DATETIME2(3)  = NULL,
    @updated_at  DATETIME2(3)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        BEGIN TRANSACTION;

        IF @id IS NULL
            EXEC dbo.usp_Task_GetNextId @next_id = @id OUTPUT;

        DECLARE @now DATETIME2(3) = SYSUTCDATETIME();
        SET @created_at = ISNULL(@created_at, @now);
        SET @updated_at = ISNULL(@updated_at, @now);

        INSERT INTO dbo.Tasks
            (id, title, description, severity_id, category, status_id, agent, model,
             [source], [plan], log_count, notes, created_at, updated_at)
        VALUES
            (@id, @title, @description, @severity_id, @category, @status_id, @agent, @model,
             @source, @plan, @log_count, @notes, @created_at, @updated_at);

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        VALUES (@id, 'INSERT', NULL, NULL, NULL);

        COMMIT TRANSACTION;
        SET CONTEXT_INFO 0x00;

        SELECT
            t.id, t.title, t.description,
            sev.name AS severity, t.category, sts.name AS status,
            t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
            CONVERT(NVARCHAR(30), t.created_at, 127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at, 127) AS updated_at
        FROM dbo.Tasks t
        JOIN dbo._Severity sev ON sev.id = t.severity_id
        JOIN dbo._Status   sts ON sts.id = t.status_id
        WHERE t.id = @id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET CONTEXT_INFO 0x00;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- SP 3: usp_Task_Update
-- Updates one or more fields on a single task.
-- NULL parameter = "leave unchanged".
-- @severity_id / @status_id accept FK IDs; NULL means "leave unchanged".
-- Writes one UPDATE audit row per field that actually changed (string names
-- are used in audit old_value / new_value for human readability).
-- Returns the updated row. Raises error 50002 if the task is not found.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_Update
    @id          CHAR(4),
    @title       NVARCHAR(500) = NULL,
    @description NVARCHAR(MAX) = NULL,
    @severity_id SMALLINT      = NULL,
    @category    NVARCHAR(50)  = NULL,
    @status_id   SMALLINT      = NULL,
    @agent       NVARCHAR(60)  = NULL,
    @model       NVARCHAR(20)  = NULL,
    @source      NVARCHAR(500) = NULL,
    @plan        NVARCHAR(MAX) = NULL,
    @log_count   INT           = NULL,
    @notes       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        BEGIN TRANSACTION;

        -- Read current values with an update lock to prevent concurrent updates
        DECLARE
            @old_title        NVARCHAR(500),
            @old_description  NVARCHAR(MAX),
            @old_severity_id  SMALLINT,
            @old_severity_nm  NVARCHAR(20),
            @old_category     NVARCHAR(50),
            @old_status_id    SMALLINT,
            @old_status_nm    NVARCHAR(20),
            @old_agent        NVARCHAR(60),
            @old_model        NVARCHAR(20),
            @old_source       NVARCHAR(500),
            @old_plan         NVARCHAR(MAX),
            @old_log_count    INT,
            @old_notes        NVARCHAR(MAX);

        SELECT
            @old_title        = t.title,
            @old_description  = t.description,
            @old_severity_id  = t.severity_id,
            @old_severity_nm  = sev.name,
            @old_category     = t.category,
            @old_status_id    = t.status_id,
            @old_status_nm    = sts.name,
            @old_agent        = t.agent,
            @old_model        = t.model,
            @old_source       = t.[source],
            @old_plan         = t.[plan],
            @old_log_count    = t.log_count,
            @old_notes        = t.notes
        FROM dbo.Tasks t WITH (UPDLOCK, ROWLOCK)
        JOIN dbo._Severity sev ON sev.id = t.severity_id
        JOIN dbo._Status   sts ON sts.id = t.status_id
        WHERE t.id = @id;

        IF @@ROWCOUNT = 0
            THROW 50002, 'Task not found.', 1;

        UPDATE dbo.Tasks SET
            title       = ISNULL(@title,       title),
            description = ISNULL(@description, description),
            severity_id = ISNULL(@severity_id, severity_id),
            category    = ISNULL(@category,    category),
            status_id   = ISNULL(@status_id,   status_id),
            agent       = ISNULL(@agent,       agent),
            model       = ISNULL(@model,       model),
            [source]    = ISNULL(@source,      [source]),
            [plan]      = ISNULL(@plan,        [plan]),
            log_count   = ISNULL(@log_count,   log_count),
            notes       = ISNULL(@notes,       notes),
            updated_at  = SYSUTCDATETIME()
        WHERE id = @id;

        -- Resolve new IDs to names for audit readability
        DECLARE @new_severity_nm NVARCHAR(20), @new_status_nm NVARCHAR(20);
        SELECT @new_severity_nm = name FROM dbo._Severity WHERE id = ISNULL(@severity_id, @old_severity_id);
        SELECT @new_status_nm   = name FROM dbo._Status   WHERE id = ISNULL(@status_id,   @old_status_id);

        -- Column-level audit: one row per field that actually changed
        CREATE TABLE #audit_rows (
            field_name NVARCHAR(60),
            old_value  NVARCHAR(MAX),
            new_value  NVARCHAR(MAX)
        );

        INSERT INTO #audit_rows (field_name, old_value, new_value)
        SELECT field_name, old_val, new_val
        FROM (VALUES
            ('title',       CAST(@old_title      AS NVARCHAR(MAX)), CAST(ISNULL(@title,      @old_title)      AS NVARCHAR(MAX))),
            ('description', @old_description,                       ISNULL(@description, @old_description)),
            ('severity',    @old_severity_nm,                       @new_severity_nm),
            ('category',    @old_category,                          ISNULL(@category,    @old_category)),
            ('status',      @old_status_nm,                         @new_status_nm),
            ('agent',       @old_agent,                             ISNULL(@agent,       @old_agent)),
            ('model',       @old_model,                             ISNULL(@model,       @old_model)),
            ('[source]',     @old_source,                            ISNULL(@source,      @old_source)),
            ('[plan]',      @old_plan,                              ISNULL(@plan,        @old_plan)),
            ('log_count',   CAST(@old_log_count  AS NVARCHAR(MAX)), CAST(ISNULL(@log_count,  @old_log_count)  AS NVARCHAR(MAX))),
            ('notes',       @old_notes,                             ISNULL(@notes,       @old_notes))
        ) AS x(field_name, old_val, new_val)
        WHERE ISNULL(old_val, N'') <> ISNULL(new_val, N'');

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        SELECT @id, 'UPDATE', field_name, old_value, new_value
        FROM #audit_rows;

        DROP TABLE #audit_rows;
        COMMIT TRANSACTION;
        SET CONTEXT_INFO 0x00;

        SELECT
            t.id, t.title, t.description,
            sev.name AS severity, t.category, sts.name AS status,
            t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
            CONVERT(NVARCHAR(30), t.created_at, 127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at, 127) AS updated_at
        FROM dbo.Tasks t
        JOIN dbo._Severity sev ON sev.id = t.severity_id
        JOIN dbo._Status   sts ON sts.id = t.status_id
        WHERE t.id = @id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        IF OBJECT_ID('tempdb..#audit_rows') IS NOT NULL DROP TABLE #audit_rows;
        SET CONTEXT_INFO 0x00;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- SP 4: usp_Task_Delete
-- Hard-deletes a task. Writes one DELETE audit row before removing the row.
-- Raises 50002 if the task is not found.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_Delete
    @id CHAR(4)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Tasks WHERE id = @id)
            THROW 50002, 'Task not found.', 1;

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        VALUES (@id, 'DELETE', NULL, NULL, NULL);

        DELETE FROM dbo.Tasks WHERE id = @id;

        COMMIT TRANSACTION;
        SET CONTEXT_INFO 0x00;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET CONTEXT_INFO 0x00;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- SP 5: usp_Task_Archive
-- Moves a task from Tasks to TasksArchive.
-- severity_id / status_id are copied directly (already integer IDs).
-- Writes one ARCHIVE audit row (task_id preserved in audit log).
-- @archived_reason: 'manual' (default) | 'cleanup' | 'bulk-replace'
-- Raises 50002 if the task is not found.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_Archive
    @id              CHAR(4),
    @archived_reason NVARCHAR(100) = 'manual'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM dbo.Tasks WHERE id = @id)
            THROW 50002, 'Task not found.', 1;

        INSERT INTO dbo.TasksArchive
            (id, title, description, severity_id, category, status_id, agent, model,
             [source], [plan], log_count, notes, created_at, updated_at,
             archived_at, archived_reason)
        SELECT
            id, title, description, severity_id, category, status_id, agent, model,
            [source], [plan], log_count, notes, created_at, updated_at,
            SYSUTCDATETIME(), @archived_reason
        FROM dbo.Tasks WHERE id = @id;

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        VALUES (@id, 'ARCHIVE', NULL, NULL, @archived_reason);

        DELETE FROM dbo.Tasks WHERE id = @id;

        COMMIT TRANSACTION;
        SET CONTEXT_INFO 0x00;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET CONTEXT_INFO 0x00;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- SP 6: usp_Task_GetAll
-- SELECT with optional WHERE filters. NULL parameter = no filter.
-- @severity_id / @status_id are FK IDs — caller converts strings before calling.
-- @q applies LIKE '%...%' against title + description + notes.
-- Returns severity / status as string names via JOIN.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetAll
    @status_id   SMALLINT      = NULL,
    @agent       NVARCHAR(60)  = NULL,
    @severity_id SMALLINT      = NULL,
    @category    NVARCHAR(50)  = NULL,
    @q           NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        t.id, t.title, t.description,
        sev.name AS severity, t.category, sts.name AS status,
        t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
        CONVERT(NVARCHAR(30), t.created_at, 127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at, 127) AS updated_at
    FROM dbo.Tasks t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    JOIN dbo._Status   sts ON sts.id = t.status_id
    WHERE
        (@status_id   IS NULL OR t.status_id   = @status_id)
        AND (@agent      IS NULL OR t.agent      = @agent)
        AND (@severity_id IS NULL OR t.severity_id = @severity_id)
        AND (@category   IS NULL OR t.category   = @category)
        AND (@q          IS NULL OR (
            t.title       LIKE '%' + @q + '%'
            OR t.description LIKE '%' + @q + '%'
            OR t.notes       LIKE '%' + @q + '%'
        ))
    ORDER BY t.updated_at DESC;
END
GO

-- =============================================================================
-- SP 7: usp_Task_GetById
-- Returns one row by PK. Zero rows → 404 in the API layer.
-- Returns severity / status as string names via JOIN.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetById
    @id CHAR(4)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        t.id, t.title, t.description,
        sev.name AS severity, t.category, sts.name AS status,
        t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
        CONVERT(NVARCHAR(30), t.created_at, 127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at, 127) AS updated_at
    FROM dbo.Tasks t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    JOIN dbo._Status   sts ON sts.id = t.status_id
    WHERE t.id = @id;
END
GO

-- =============================================================================
-- SP 8: usp_Task_GetStats
-- Returns 5 result sets assembled by the Node.js layer into the stats object:
--   RS1: total, active, critical_open, unassigned  (scalar)
--   RS2: by_status   [{key, count}]
--   RS3: by_severity [{key, count}]
--   RS4: by_agent    [{key, count}]
--   RS5: by_category [{key, count}]
-- "active"       = _Status.is_terminal = 0
-- "critical_open" = status_id=1 (open) AND severity_id=4 (critical)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetStats
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        COUNT(*)                                                                       AS total,
        SUM(CASE WHEN sts.is_terminal = 0                          THEN 1 ELSE 0 END) AS active,
        SUM(CASE WHEN t.status_id = 1 AND t.severity_id = 4        THEN 1 ELSE 0 END) AS critical_open,
        SUM(CASE WHEN t.agent = 'unassigned' AND sts.is_terminal = 0 THEN 1 ELSE 0 END) AS unassigned
    FROM dbo.Tasks t
    JOIN dbo._Status sts ON sts.id = t.status_id;

    SELECT sts.name AS [key], COUNT(*) AS [count]
    FROM dbo.Tasks t
    JOIN dbo._Status sts ON sts.id = t.status_id
    GROUP BY sts.name;

    SELECT sev.name AS [key], COUNT(*) AS [count]
    FROM dbo.Tasks t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    GROUP BY sev.name;

    SELECT agent AS [key], COUNT(*) AS [count] FROM dbo.Tasks GROUP BY agent;
    SELECT category AS [key], COUNT(*) AS [count] FROM dbo.Tasks GROUP BY category;
END
GO

-- =============================================================================
-- SP 9: usp_Task_BulkImport
-- Accepts the full task array as a JSON string.
-- JSON must use severity_id / status_id integer fields (caller pre-processes).
-- Strategy:
--   1. Archive all current Tasks (reason = 'bulk-replace') to preserve history
--   2. DELETE all current Tasks
--   3. INSERT from JSON using OPENJSON
-- Entire operation is one transaction — atomic, no partial writes.
-- Returns the new active task set with string names.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_BulkImport
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        IF ISJSON(@json) = 0
            THROW 50010, 'Invalid JSON payload for bulk import.', 1;

        BEGIN TRANSACTION;

        -- Archive current active tasks that are not already in TasksArchive
        INSERT INTO dbo.TasksArchive
            (id, title, description, severity_id, category, status_id, agent, model,
             [source], [plan], log_count, notes, created_at, updated_at,
             archived_at, archived_reason)
        SELECT
            id, title, description, severity_id, category, status_id, agent, model,
            [source], [plan], log_count, notes, created_at, updated_at,
            SYSUTCDATETIME(), 'bulk-replace'
        FROM dbo.Tasks
        WHERE id NOT IN (SELECT id FROM dbo.TasksArchive);

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        SELECT id, 'ARCHIVE', NULL, NULL, 'bulk-replace'
        FROM dbo.Tasks;

        DELETE FROM dbo.Tasks;

        -- Re-insert from JSON; OPENJSON parses each element of the array.
        -- Caller must supply severity_id / status_id as integers.
        -- Defaults: severity_id=2 (medium), status_id=1 (open).
        INSERT INTO dbo.Tasks
            (id, title, description, severity_id, category, status_id, agent, model,
             [source], [plan], log_count, notes, created_at, updated_at)
        SELECT
            j.id,
            j.title,
            j.description,
            ISNULL(TRY_CAST(j.severity_id AS SMALLINT), 2),
            ISNULL(j.category,   'automation'),
            ISNULL(TRY_CAST(j.status_id AS SMALLINT), 1),
            ISNULL(j.agent,      'unassigned'),
            ISNULL(j.model,      'unassigned'),
            j.[source],
            j.[plan],
            ISNULL(TRY_CAST(j.log_count AS INT), 0),
            j.notes,
            ISNULL(TRY_CAST(j.created_at AS DATETIME2(3)), SYSUTCDATETIME()),
            ISNULL(TRY_CAST(j.updated_at AS DATETIME2(3)), SYSUTCDATETIME())
        FROM OPENJSON(@json) WITH (
            id          NVARCHAR(10)  '$.id',
            title       NVARCHAR(500) '$.title',
            description NVARCHAR(MAX) '$.description',
            severity_id NVARCHAR(5)   '$.severity_id',
            category    NVARCHAR(50)  '$.category',
            status_id   NVARCHAR(5)   '$.status_id',
            agent       NVARCHAR(60)  '$.agent',
            model       NVARCHAR(20)  '$.model',
            [source]    NVARCHAR(500) '$.source',
            [plan]      NVARCHAR(MAX) '$.plan',
            log_count   NVARCHAR(10)  '$.log_count',
            notes       NVARCHAR(MAX) '$.notes',
            created_at  NVARCHAR(40)  '$.created_at',
            updated_at  NVARCHAR(40)  '$.updated_at'
        ) AS j;

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        SELECT id, 'INSERT', NULL, NULL, 'bulk-import'
        FROM dbo.Tasks;

        COMMIT TRANSACTION;
        SET CONTEXT_INFO 0x00;

        SELECT
            t.id, t.title, t.description,
            sev.name AS severity, t.category, sts.name AS status,
            t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
            CONVERT(NVARCHAR(30), t.created_at, 127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at, 127) AS updated_at
        FROM dbo.Tasks t
        JOIN dbo._Severity sev ON sev.id = t.severity_id
        JOIN dbo._Status   sts ON sts.id = t.status_id
        ORDER BY t.id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET CONTEXT_INFO 0x00;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- SP 10: usp_Archive_GetAll
-- Returns all rows from TasksArchive newest-first.
-- Returns severity / status as string names via JOIN.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Archive_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        t.id, t.title, t.description,
        sev.name AS severity, t.category, sts.name AS status,
        t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
        CONVERT(NVARCHAR(30), t.created_at,  127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at,  127) AS updated_at,
        CONVERT(NVARCHAR(30), t.archived_at, 127) AS archived_at,
        t.archived_reason
    FROM dbo.TasksArchive t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    JOIN dbo._Status   sts ON sts.id = t.status_id
    ORDER BY t.archived_at DESC;
END
GO

-- =============================================================================
-- SP 11: usp_Audit_GetByTaskId
-- Returns the full audit trail for a task (including after deletion).
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Audit_GetByTaskId
    @task_id CHAR(4)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        audit_id, task_id, action, field_name, old_value, new_value,
        changed_by,
        CONVERT(NVARCHAR(30), changed_at, 127) AS changed_at
    FROM dbo.TasksAudit
    WHERE task_id = @task_id
    ORDER BY audit_id;
END
GO

PRINT 'All 11 stored procedures created successfully.';
GO
