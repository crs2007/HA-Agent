-- =============================================================================
-- 06_agent_job.sql  —  SQL Server Agent job: auto-archive done tasks after 24h
-- Run against: localhost\SQLSERVER2022 / msdb  (job metadata lives in msdb)
-- =============================================================================
USE msdb;
GO

-- Drop existing job if re-running
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'TaskManager: Archive Done Tasks (24h)')
    EXEC sp_delete_job @job_name = N'TaskManager: Archive Done Tasks (24h)', @delete_unused_schedule = 1;
GO

-- =============================================================================
-- 1. Create the job
-- =============================================================================
EXEC sp_add_job
    @job_name        = N'TaskManager: Archive Done Tasks (24h)',
    @enabled         = 1,
    @description     = N'Moves tasks with status=done and updated_at older than 24 hours into dbo.TasksArchive.',
    @notify_level_eventlog = 2;   -- log on failure
GO

-- =============================================================================
-- 2. Add the job step (runs in TaskManager context)
-- =============================================================================
EXEC sp_add_jobstep
    @job_name      = N'TaskManager: Archive Done Tasks (24h)',
    @step_name     = N'Archive stale done tasks',
    @subsystem     = N'TSQL',
    @database_name = N'TaskManager',
    @command       = N'
DECLARE @id   CHAR(4);
DECLARE @n    INT = 0;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT id
    FROM   dbo.Tasks
    WHERE  status_id  = 4           -- 4 = done (dbo._Status)
      AND  updated_at <= DATEADD(HOUR, -24, SYSUTCDATETIME());

OPEN cur;
FETCH NEXT FROM cur INTO @id;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.usp_Task_Archive
        @id              = @id,
        @archived_reason = N''auto-24h'';
    SET @n += 1;
    FETCH NEXT FROM cur INTO @id;
END

CLOSE cur;
DEALLOCATE cur;

IF @n > 0
    PRINT CAST(@n AS VARCHAR(10)) + '' task(s) archived.''
ELSE
    PRINT ''No done tasks ready to archive.'';
',
    @on_success_action = 1,   -- quit with success
    @on_fail_action    = 2;   -- quit with failure
GO

-- =============================================================================
-- 3. Create schedule: every 1 hour, around the clock
-- Drop first if a leftover exists from a prior run
-- =============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'TaskManager: Every 1 Hour')
    EXEC sp_delete_schedule @schedule_name = N'TaskManager: Every 1 Hour', @force_delete = 1;
GO

EXEC sp_add_schedule
    @schedule_name       = N'TaskManager: Every 1 Hour',
    @freq_type           = 4,    -- daily (repeating intraday)
    @freq_interval       = 1,    -- every day
    @freq_subday_type    = 8,    -- sub-day interval unit = hours
    @freq_subday_interval= 1,    -- every 1 hour
    @active_start_time   = 0;    -- 00:00:00
GO

EXEC sp_attach_schedule
    @job_name      = N'TaskManager: Archive Done Tasks (24h)',
    @schedule_name = N'TaskManager: Every 1 Hour';
GO

-- =============================================================================
-- 4. Register on the local server
-- =============================================================================
EXEC sp_add_jobserver
    @job_name   = N'TaskManager: Archive Done Tasks (24h)',
    @server_name= N'(LOCAL)';
GO

PRINT 'SQL Agent job ''TaskManager: Archive Done Tasks (24h)'' created successfully.';
GO
