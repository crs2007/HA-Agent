-- =============================================================================
-- 08_plan_review.sql  —  "Review Plan" feature: schema + SPs
-- Run AFTER 01_tables.sql, 02_stored_procs.sql, 03_trigger.sql,
--           04_permissions.sql, 09_normalize_severity_status.sql
-- Idempotent: re-runnable. ALTER TABLE statements are guarded by sys.columns
-- checks; CREATE OR ALTER on procedures replaces in place.
-- =============================================================================
-- Adds five columns to dbo.Tasks and dbo.TasksArchive to persist LLM-generated
-- plan reviews:
--   plan_review          NVARCHAR(MAX)  -- review content (notes or alt plan)
--   plan_review_at       DATETIME2(3)   -- when the review was saved
--   plan_review_provider NVARCHAR(40)   -- 'anthropic' | 'openai' | 'google' | 'copilot' | 'mock'
--   plan_review_model    NVARCHAR(80)   -- model id (e.g. 'claude-opus-4-7')
--   plan_review_type     NVARCHAR(20)   -- 'notes' | 'alternative'
-- All SPs in this file supersede their counterparts in 02_stored_procs.sql —
-- they include plan_review_* in SELECTs and carry the columns through archive
-- operations. severity/status use FK IDs (dbo._Severity / dbo._Status) and are
-- returned as string names via JOIN.
-- =============================================================================
USE TaskManager;
GO

-- =============================================================================
-- Schema additions on dbo.Tasks
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'plan_review')
    ALTER TABLE dbo.Tasks ADD plan_review NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'plan_review_at')
    ALTER TABLE dbo.Tasks ADD plan_review_at DATETIME2(3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'plan_review_provider')
    ALTER TABLE dbo.Tasks ADD plan_review_provider NVARCHAR(40) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'plan_review_model')
    ALTER TABLE dbo.Tasks ADD plan_review_model NVARCHAR(80) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'plan_review_type')
    ALTER TABLE dbo.Tasks ADD plan_review_type NVARCHAR(20) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Tasks_review_type')
    ALTER TABLE dbo.Tasks
        ADD CONSTRAINT CK_Tasks_review_type
            CHECK (plan_review_type IN ('notes','alternative') OR plan_review_type IS NULL);
GO

-- =============================================================================
-- Schema additions on dbo.TasksArchive (mirror — no constraint, archived state)
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'plan_review')
    ALTER TABLE dbo.TasksArchive ADD plan_review NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'plan_review_at')
    ALTER TABLE dbo.TasksArchive ADD plan_review_at DATETIME2(3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'plan_review_provider')
    ALTER TABLE dbo.TasksArchive ADD plan_review_provider NVARCHAR(40) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'plan_review_model')
    ALTER TABLE dbo.TasksArchive ADD plan_review_model NVARCHAR(80) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'plan_review_type')
    ALTER TABLE dbo.TasksArchive ADD plan_review_type NVARCHAR(20) NULL;
GO

-- =============================================================================
-- usp_Task_SaveReview  —  Persist an LLM review for an existing task.
-- Sets the SP CONTEXT_INFO marker (required by trg_Tasks_BlockDirectDML).
-- Writes one UPDATE audit row per field that actually changed.
-- Throws 50002 if the task is not found.
-- Returns the full updated row (same columns as usp_Task_GetById + plan_review_*).
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_SaveReview
    @id                   CHAR(4),
    @plan_review          NVARCHAR(MAX),
    @plan_review_provider NVARCHAR(40),
    @plan_review_model    NVARCHAR(80),
    @plan_review_type     NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        BEGIN TRANSACTION;

        DECLARE
            @old_review          NVARCHAR(MAX),
            @old_review_provider NVARCHAR(40),
            @old_review_model    NVARCHAR(80),
            @old_review_type     NVARCHAR(20);

        SELECT
            @old_review          = plan_review,
            @old_review_provider = plan_review_provider,
            @old_review_model    = plan_review_model,
            @old_review_type     = plan_review_type
        FROM dbo.Tasks WITH (UPDLOCK, ROWLOCK)
        WHERE id = @id;

        IF @@ROWCOUNT = 0
            THROW 50002, 'Task not found.', 1;

        DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

        UPDATE dbo.Tasks SET
            plan_review          = @plan_review,
            plan_review_at       = @now,
            plan_review_provider = @plan_review_provider,
            plan_review_model    = @plan_review_model,
            plan_review_type     = @plan_review_type,
            updated_at           = @now
        WHERE id = @id;

        -- Column-level audit (skip plan_review_at — always changes by design)
        CREATE TABLE #audit_rows (
            field_name NVARCHAR(60),
            old_value  NVARCHAR(MAX),
            new_value  NVARCHAR(MAX)
        );

        INSERT INTO #audit_rows (field_name, old_value, new_value)
        SELECT field_name, old_val, new_val
        FROM (VALUES
            ('plan_review',          @old_review,          @plan_review),
            ('plan_review_provider', @old_review_provider, @plan_review_provider),
            ('plan_review_model',    @old_review_model,    @plan_review_model),
            ('plan_review_type',     @old_review_type,     @plan_review_type)
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
            t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
            CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
            CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
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
-- Re-create existing SPs so their result sets include the new plan_review_*
-- columns. Uses severity_id/status_id FK columns; SELECTs JOIN lookup tables.
-- =============================================================================

-- usp_Task_Insert
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
            t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
            CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
            CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
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

-- usp_Task_Update
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
            ('[source]',    @old_source,                            ISNULL(@source,      @old_source)),
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
            t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
            CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
            CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
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

-- usp_Task_GetAll
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
        t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
        CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
        CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
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

-- usp_Task_GetById
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetById
    @id CHAR(4)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        t.id, t.title, t.description,
        sev.name AS severity, t.category, sts.name AS status,
        t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
        t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
        CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
        CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
    FROM dbo.Tasks t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    JOIN dbo._Status   sts ON sts.id = t.status_id
    WHERE t.id = @id;
END
GO

-- usp_Task_BulkImport  (archive carries plan_review_*; JSON supplies severity_id/status_id as integers)
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

        -- Archive current tasks, carrying plan_review_* and FK IDs through
        INSERT INTO dbo.TasksArchive
            (id, title, description, severity_id, category, status_id, agent, model,
             [source], [plan], log_count, notes, created_at, updated_at,
             plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
             archived_at, archived_reason)
        SELECT
            id, title, description, severity_id, category, status_id, agent, model,
            [source], [plan], log_count, notes, created_at, updated_at,
            plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
            SYSUTCDATETIME(), 'bulk-replace'
        FROM dbo.Tasks
        WHERE id NOT IN (SELECT id FROM dbo.TasksArchive);

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        SELECT id, 'ARCHIVE', NULL, NULL, 'bulk-replace'
        FROM dbo.Tasks;

        DELETE FROM dbo.Tasks;

        -- Re-insert from JSON. Caller must supply severity_id/status_id as integers.
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
            t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
            CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
            CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
            CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
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

-- usp_Task_Archive  (carry plan_review_* and FK IDs through to archive table)
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
             plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
             archived_at, archived_reason)
        SELECT
            id, title, description, severity_id, category, status_id, agent, model,
            [source], [plan], log_count, notes, created_at, updated_at,
            plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
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

-- usp_Archive_GetAll  (JOIN lookup tables to return string names + plan_review_*)
CREATE OR ALTER PROCEDURE dbo.usp_Archive_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        t.id, t.title, t.description,
        sev.name AS severity, t.category, sts.name AS status,
        t.agent, t.model, t.[source], t.[plan], t.log_count, t.notes,
        t.plan_review, t.plan_review_provider, t.plan_review_model, t.plan_review_type,
        CONVERT(NVARCHAR(30), t.plan_review_at, 127) AS plan_review_at,
        CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at,
        CONVERT(NVARCHAR(30), t.archived_at,    127) AS archived_at,
        t.archived_reason
    FROM dbo.TasksArchive t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    JOIN dbo._Status   sts ON sts.id = t.status_id
    ORDER BY t.archived_at DESC;
END
GO

-- Grant EXECUTE on the new SP to TaskAppRole (matches 04_permissions.sql pattern).
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TaskAppRole' AND type = 'R')
    GRANT EXECUTE ON dbo.usp_Task_SaveReview TO TaskAppRole;
GO

PRINT '08_plan_review.sql complete: schema migrated, usp_Task_SaveReview created, dependent SPs refreshed.';
GO
