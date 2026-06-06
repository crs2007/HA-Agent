-- =============================================================================
-- 09_solution.sql  —  Task Solution Storage + Keyword Index
-- Run AFTER 08_plan_review.sql.
-- Idempotent: re-runnable. ALTER TABLE statements are guarded by sys.columns
-- checks; CREATE OR ALTER on procedures replaces in place;
-- TaskKeywords table is guarded by sys.objects check.
-- =============================================================================
-- Adds five solution columns to dbo.Tasks and dbo.TasksArchive:
--   solution           NVARCHAR(MAX)  -- full solution text (markdown)
--   solution_at        DATETIME2(3)   -- UTC timestamp when saved
--   solution_provider  NVARCHAR(40)   -- 'ha-developer' | 'ha-reviewer' | 'human'
--   solution_model     NVARCHAR(80)   -- LLM model ID if AI-generated (nullable)
--   solution_status    NVARCHAR(20)   -- CHECK: 'proposed'|'verified'|'partial'|'failed'
-- Adds new table dbo.TaskKeywords (normalized keyword tags per task, no FK
-- so keywords survive archival and remain searchable post-archive).
-- All SPs in this file supersede their counterparts in 08_plan_review.sql —
-- they include solution_* in SELECTs and carry the columns through archive.
-- =============================================================================
USE TaskManager;
GO

-- =============================================================================
-- Schema additions on dbo.Tasks
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'solution')
    ALTER TABLE dbo.Tasks ADD solution NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'solution_at')
    ALTER TABLE dbo.Tasks ADD solution_at DATETIME2(3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'solution_provider')
    ALTER TABLE dbo.Tasks ADD solution_provider NVARCHAR(40) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'solution_model')
    ALTER TABLE dbo.Tasks ADD solution_model NVARCHAR(80) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Tasks') AND name = 'solution_status')
    ALTER TABLE dbo.Tasks ADD solution_status NVARCHAR(20) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Tasks_solution_status')
    ALTER TABLE dbo.Tasks
        ADD CONSTRAINT CK_Tasks_solution_status
            CHECK (solution_status IN ('proposed','verified','partial','failed') OR solution_status IS NULL);
GO

-- =============================================================================
-- Schema additions on dbo.TasksArchive (mirror — no CHECK constraint)
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'solution')
    ALTER TABLE dbo.TasksArchive ADD solution NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'solution_at')
    ALTER TABLE dbo.TasksArchive ADD solution_at DATETIME2(3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'solution_provider')
    ALTER TABLE dbo.TasksArchive ADD solution_provider NVARCHAR(40) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'solution_model')
    ALTER TABLE dbo.TasksArchive ADD solution_model NVARCHAR(80) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.TasksArchive') AND name = 'solution_status')
    ALTER TABLE dbo.TasksArchive ADD solution_status NVARCHAR(20) NULL;
GO

-- =============================================================================
-- dbo.TaskKeywords — normalized keyword tags
-- No FK on task_id — keywords survive task archival and remain searchable.
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.TaskKeywords') AND type = 'U')
BEGIN
    CREATE TABLE dbo.TaskKeywords (
        id          INT IDENTITY(1,1) NOT NULL
                        CONSTRAINT PK_TaskKeywords PRIMARY KEY CLUSTERED,
        task_id     CHAR(4)          NOT NULL,
        keyword     NVARCHAR(100)    NOT NULL,
        kw_category NVARCHAR(40)     NULL,
        created_at  DATETIME2(3)     NOT NULL
                        CONSTRAINT DF_TaskKeywords_created_at DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_TaskKeywords_task_kw UNIQUE NONCLUSTERED (task_id, keyword)
    );

    -- Keyword search (primary use case: find tasks by keyword)
    CREATE NONCLUSTERED INDEX IX_TKW_keyword
        ON dbo.TaskKeywords (keyword)
        INCLUDE (task_id, kw_category);

    -- Task lookup (what keywords does a given task have?)
    CREATE NONCLUSTERED INDEX IX_TKW_task_id
        ON dbo.TaskKeywords (task_id)
        INCLUDE (keyword, kw_category);

    -- Category-scoped keyword search
    CREATE NONCLUSTERED INDEX IX_TKW_cat_kw
        ON dbo.TaskKeywords (kw_category, keyword)
        INCLUDE (task_id);
END
GO

-- =============================================================================
-- usp_Task_SaveSolution  —  Persist an identified solution for an existing task.
-- Mirrors usp_Task_SaveReview exactly: CONTEXT_INFO, UPDLOCK, per-field audit.
-- Throws 50002 if the task is not found.
-- Returns the full updated row (all columns including solution_*).
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Task_SaveSolution
    @id                CHAR(4),
    @solution          NVARCHAR(MAX),
    @solution_provider NVARCHAR(40),
    @solution_model    NVARCHAR(80),
    @solution_status   NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        BEGIN TRANSACTION;

        DECLARE
            @old_solution          NVARCHAR(MAX),
            @old_solution_provider NVARCHAR(40),
            @old_solution_model    NVARCHAR(80),
            @old_solution_status   NVARCHAR(20);

        SELECT
            @old_solution          = solution,
            @old_solution_provider = solution_provider,
            @old_solution_model    = solution_model,
            @old_solution_status   = solution_status
        FROM dbo.Tasks WITH (UPDLOCK, ROWLOCK)
        WHERE id = @id;

        IF @@ROWCOUNT = 0
            THROW 50002, 'Task not found.', 1;

        DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

        UPDATE dbo.Tasks SET
            solution          = @solution,
            solution_at       = @now,
            solution_provider = @solution_provider,
            solution_model    = @solution_model,
            solution_status   = @solution_status,
            updated_at        = @now
        WHERE id = @id;

        -- Column-level audit (skip solution_at — always changes by design)
        CREATE TABLE #audit_rows (
            field_name NVARCHAR(60),
            old_value  NVARCHAR(MAX),
            new_value  NVARCHAR(MAX)
        );

        INSERT INTO #audit_rows (field_name, old_value, new_value)
        SELECT field_name, old_val, new_val
        FROM (VALUES
            ('solution',          @old_solution,          @solution),
            ('solution_provider', @old_solution_provider, @solution_provider),
            ('solution_model',    @old_solution_model,    @solution_model),
            ('solution_status',   @old_solution_status,   @solution_status)
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
            t.solution, t.solution_provider, t.solution_model, t.solution_status,
            CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
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
-- usp_TaskKeywords_Replace  —  Idempotent keyword save (full replace per task).
-- Deletes all existing keywords for @task_id and re-inserts from JSON array.
-- Keywords are lowercased. Does not require the task to exist in dbo.Tasks
-- (intentional — keywords may outlive the active row after archival).
-- Returns the new keyword rows for @task_id.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_TaskKeywords_Replace
    @task_id       CHAR(4),
    @keywords_json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @ctx VARBINARY(128) =
            CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));
        SET CONTEXT_INFO @ctx;

        IF ISJSON(@keywords_json) = 0
            THROW 50010, 'Invalid JSON payload for keywords.', 1;

        BEGIN TRANSACTION;

        DELETE FROM dbo.TaskKeywords WHERE task_id = @task_id;

        INSERT INTO dbo.TaskKeywords (task_id, keyword, kw_category)
        SELECT
            @task_id,
            LOWER(LTRIM(RTRIM(j.keyword))),
            j.kw_category
        FROM OPENJSON(@keywords_json) WITH (
            keyword     NVARCHAR(100) '$.keyword',
            kw_category NVARCHAR(40)  '$.kw_category'
        ) AS j
        WHERE NULLIF(LTRIM(RTRIM(j.keyword)), '') IS NOT NULL;

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        VALUES (@task_id, 'UPDATE', 'KEYWORDS-REPLACE', NULL, NULL);

        COMMIT TRANSACTION;
        SET CONTEXT_INFO 0x00;

        SELECT id, task_id, keyword, kw_category,
               CONVERT(NVARCHAR(30), created_at, 127) AS created_at
        FROM dbo.TaskKeywords
        WHERE task_id = @task_id
        ORDER BY kw_category, keyword;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET CONTEXT_INFO 0x00;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- usp_TaskKeywords_GetByTask  —  Return all keywords for a given task ID.
-- Searches TaskKeywords regardless of whether the task is active or archived.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_TaskKeywords_GetByTask
    @task_id CHAR(4)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id, task_id, keyword, kw_category,
           CONVERT(NVARCHAR(30), created_at, 127) AS created_at
    FROM dbo.TaskKeywords
    WHERE task_id = @task_id
    ORDER BY kw_category, keyword;
END
GO

-- =============================================================================
-- usp_Solution_Search  —  Search across active Tasks + TasksArchive by keyword.
-- @keywords_csv   NVARCHAR(500)  — comma-separated keywords, e.g. 'zigbee2mqtt,color_mode'
-- @kw_category    NVARCHAR(40)   — optional category filter ('tech','integration', etc.)
-- @match_mode     NVARCHAR(10)   — 'any' (OR match) | 'all' (AND match, default 'any')
-- @include_archived BIT          — include archived tasks (default 1)
-- Returns tasks with a saved solution that match the keyword criteria, with
-- aggregated keyword list and truncated solution preview.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Solution_Search
    @keywords_csv      NVARCHAR(500),
    @kw_category       NVARCHAR(40)  = NULL,
    @match_mode        NVARCHAR(10)  = 'any',
    @include_archived  BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- Parse comma-separated keyword list into a temp table (lowercase, de-duped)
    CREATE TABLE #kw_list (keyword NVARCHAR(100));

    INSERT INTO #kw_list (keyword)
    SELECT DISTINCT LOWER(LTRIM(RTRIM(value)))
    FROM STRING_SPLIT(@keywords_csv, ',')
    WHERE LTRIM(RTRIM(value)) <> '';

    DECLARE @kw_count INT = (SELECT COUNT(*) FROM #kw_list);

    IF @kw_count = 0
    BEGIN
        DROP TABLE #kw_list;
        RETURN;
    END

    -- Find task_ids that match the keyword criteria
    CREATE TABLE #matched_ids (task_id CHAR(4));

    INSERT INTO #matched_ids (task_id)
    SELECT tkw.task_id
    FROM dbo.TaskKeywords tkw
    JOIN #kw_list k ON tkw.keyword = k.keyword
    WHERE (@kw_category IS NULL OR tkw.kw_category = @kw_category)
    GROUP BY tkw.task_id
    HAVING COUNT(DISTINCT tkw.keyword) >=
           CASE WHEN @match_mode = 'all' THEN @kw_count ELSE 1 END;

    -- Combine active and archived task rows that have a solution saved
    SELECT
        c.task_id,
        c.title,
        c.status,
        c.solution_status,
        c.solution_provider,
        LEFT(c.solution, 500)     AS solution_preview,
        c.solution_at,
        c.[source],
        (
            SELECT STRING_AGG(tkw2.keyword, ', ') WITHIN GROUP (ORDER BY tkw2.keyword)
            FROM dbo.TaskKeywords tkw2
            WHERE tkw2.task_id = c.task_id
        ) AS keywords
    FROM (
        SELECT
            t.id        AS task_id,
            t.title,
            sts.name    AS status,
            t.solution,
            t.solution_status,
            t.solution_provider,
            CONVERT(NVARCHAR(30), t.solution_at, 127) AS solution_at,
            'active'    AS [source]
        FROM dbo.Tasks t
        JOIN dbo._Status sts ON sts.id = t.status_id
        WHERE t.id IN (SELECT task_id FROM #matched_ids)
          AND t.solution IS NOT NULL

        UNION ALL

        SELECT
            t.id        AS task_id,
            t.title,
            sts.name    AS status,
            t.solution,
            t.solution_status,
            t.solution_provider,
            CONVERT(NVARCHAR(30), t.solution_at, 127) AS solution_at,
            'archived'  AS [source]
        FROM dbo.TasksArchive t
        JOIN dbo._Status sts ON sts.id = t.status_id
        WHERE @include_archived = 1
          AND t.id IN (SELECT task_id FROM #matched_ids)
          AND t.solution IS NOT NULL
    ) AS c
    ORDER BY c.solution_at DESC;

    DROP TABLE #kw_list;
    DROP TABLE #matched_ids;
END
GO

-- =============================================================================
-- Re-create existing SPs so their result sets include the new solution_* columns.
-- These supersede their counterparts in 08_plan_review.sql.
-- =============================================================================

-- usp_Task_Insert
CREATE OR ALTER PROCEDURE dbo.usp_Task_Insert
    @id          CHAR(4)       = NULL,
    @title       NVARCHAR(500) = NULL,
    @description NVARCHAR(MAX) = NULL,
    @severity_id SMALLINT      = 2,
    @category    NVARCHAR(50)  = 'automation',
    @status_id   SMALLINT      = 1,
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
            t.solution, t.solution_provider, t.solution_model, t.solution_status,
            CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
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
            ('title',       CAST(@old_title     AS NVARCHAR(MAX)), CAST(ISNULL(@title,     @old_title)     AS NVARCHAR(MAX))),
            ('description', @old_description,                      ISNULL(@description, @old_description)),
            ('severity',    @old_severity_nm,                      @new_severity_nm),
            ('category',    @old_category,                         ISNULL(@category,    @old_category)),
            ('status',      @old_status_nm,                        @new_status_nm),
            ('agent',       @old_agent,                            ISNULL(@agent,       @old_agent)),
            ('model',       @old_model,                            ISNULL(@model,       @old_model)),
            ('[source]',    @old_source,                           ISNULL(@source,      @old_source)),
            ('[plan]',      @old_plan,                             ISNULL(@plan,        @old_plan)),
            ('log_count',   CAST(@old_log_count AS NVARCHAR(MAX)), CAST(ISNULL(@log_count, @old_log_count) AS NVARCHAR(MAX))),
            ('notes',       @old_notes,                            ISNULL(@notes,       @old_notes))
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
            t.solution, t.solution_provider, t.solution_model, t.solution_status,
            CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
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
        t.solution, t.solution_provider, t.solution_model, t.solution_status,
        CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
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
        t.solution, t.solution_provider, t.solution_model, t.solution_status,
        CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
        CONVERT(NVARCHAR(30), t.created_at,     127) AS created_at,
        CONVERT(NVARCHAR(30), t.updated_at,     127) AS updated_at
    FROM dbo.Tasks t
    JOIN dbo._Severity sev ON sev.id = t.severity_id
    JOIN dbo._Status   sts ON sts.id = t.status_id
    WHERE t.id = @id;
END
GO

-- usp_Task_BulkImport  (archive carries solution_* through; JSON supplies severity_id/status_id as integers)
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

        -- Archive current tasks, carrying plan_review_* and solution_* through
        INSERT INTO dbo.TasksArchive
            (id, title, description, severity_id, category, status_id, agent, model,
             [source], [plan], log_count, notes, created_at, updated_at,
             plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
             solution, solution_at, solution_provider, solution_model, solution_status,
             archived_at, archived_reason)
        SELECT
            id, title, description, severity_id, category, status_id, agent, model,
            [source], [plan], log_count, notes, created_at, updated_at,
            plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
            solution, solution_at, solution_provider, solution_model, solution_status,
            SYSUTCDATETIME(), 'bulk-replace'
        FROM dbo.Tasks
        WHERE id NOT IN (SELECT id FROM dbo.TasksArchive);

        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        SELECT id, 'ARCHIVE', NULL, NULL, 'bulk-replace'
        FROM dbo.Tasks;

        DELETE FROM dbo.Tasks;

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
            t.solution, t.solution_provider, t.solution_model, t.solution_status,
            CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
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

-- usp_Task_Archive  (carry plan_review_* and solution_* through to archive table)
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
             solution, solution_at, solution_provider, solution_model, solution_status,
             archived_at, archived_reason)
        SELECT
            id, title, description, severity_id, category, status_id, agent, model,
            [source], [plan], log_count, notes, created_at, updated_at,
            plan_review, plan_review_at, plan_review_provider, plan_review_model, plan_review_type,
            solution, solution_at, solution_provider, solution_model, solution_status,
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

-- usp_Archive_GetAll  (JOIN lookup tables + solution_* + archived columns)
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
        t.solution, t.solution_provider, t.solution_model, t.solution_status,
        CONVERT(NVARCHAR(30), t.solution_at,    127) AS solution_at,
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

-- =============================================================================
-- Permissions — grant EXECUTE on the four new SPs to TaskAppRole
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'TaskAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.usp_Task_SaveSolution       TO TaskAppRole;
    GRANT EXECUTE ON dbo.usp_TaskKeywords_Replace     TO TaskAppRole;
    GRANT EXECUTE ON dbo.usp_TaskKeywords_GetByTask   TO TaskAppRole;
    GRANT EXECUTE ON dbo.usp_Solution_Search          TO TaskAppRole;
END
GO

PRINT '09_solution.sql complete: solution columns added, TaskKeywords table created, 4 new SPs + 7 dependent SPs refreshed.';
GO
