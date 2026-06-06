-- =============================================================================
-- 07_audit_purge.sql  —  Audit-log retention: SP + SQL Agent job
-- Run against: localhost\SQLSERVER2022
-- Part 1 (TaskManager): create Job schema and usp_TasksAudit_Purge
-- Part 2 (msdb):        create the SQL Agent job that calls it daily
-- =============================================================================

-- =============================================================================
-- PART 1 — TaskManager database
-- =============================================================================
USE TaskManager;
GO

-- Create the Job schema if it doesn't already exist
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Job')
BEGIN
    EXEC('CREATE SCHEMA Job AUTHORIZATION dbo');
    PRINT 'Schema Job created.';
END
GO

-- =============================================================================
-- Job.usp_TasksAudit_Purge
-- Deletes dbo.TasksAudit rows older than @retention_days (default 31).
-- Runs in 5 000-row batches to keep the transaction log lean.
-- No CONTEXT_INFO needed — the safety-net trigger guards dbo.Tasks only.
-- Returns the total number of rows deleted via PRINT and RETURN value.
-- =============================================================================
CREATE OR ALTER PROCEDURE Job.usp_TasksAudit_Purge
    @retention_days INT = 31
AS
BEGIN
    SET NOCOUNT ON;

    IF @retention_days < 1
        THROW 50020, 'retention_days must be >= 1.', 1;

    DECLARE @cutoff  DATETIME2(3) = DATEADD(DAY, -@retention_days, SYSUTCDATETIME());
    DECLARE @batch   INT          = 5000;
    DECLARE @deleted INT          = 0;
    DECLARE @total   INT          = 0;

    WHILE 1 = 1
    BEGIN
        DELETE TOP (@batch) FROM dbo.TasksAudit
        WHERE changed_at < @cutoff;

        SET @deleted  = @@ROWCOUNT;
        SET @total   += @deleted;

        IF @deleted < @batch BREAK;
    END

    PRINT CAST(@total AS VARCHAR(10)) + ' audit row(s) purged '
        + '(cutoff: ' + CONVERT(NVARCHAR(30), @cutoff, 127) + ').';

    RETURN @total;
END
GO

-- Grant EXECUTE to the application role so privileged app paths can also call it
GRANT EXECUTE ON Job.usp_TasksAudit_Purge TO TaskAppRole;
GO

PRINT 'Job.usp_TasksAudit_Purge created and permission granted.';
GO


-- =============================================================================
-- PART 2 — msdb database (SQL Server Agent metadata)
-- =============================================================================
USE msdb;
GO

-- Drop existing job if re-running
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'TaskManager: Purge Audit Log (31d)')
    EXEC sp_delete_job
        @job_name             = N'TaskManager: Purge Audit Log (31d)',
        @delete_unused_schedule = 1;
GO

-- =============================================================================
-- 1. Create the job
-- =============================================================================
EXEC sp_add_job
    @job_name              = N'TaskManager: Purge Audit Log (31d)',
    @enabled               = 1,
    @description           = N'Deletes dbo.TasksAudit rows older than 31 days via Job.usp_TasksAudit_Purge. Runs in 5 000-row batches.',
    @notify_level_eventlog = 2;   -- log on failure
GO

-- =============================================================================
-- 2. Add the job step
-- =============================================================================
EXEC sp_add_jobstep
    @job_name          = N'TaskManager: Purge Audit Log (31d)',
    @step_name         = N'Purge audit rows > 31 days',
    @subsystem         = N'TSQL',
    @database_name     = N'TaskManager',
    @command           = N'EXEC Job.usp_TasksAudit_Purge @retention_days = 31;',
    @on_success_action = 1,   -- quit with success
    @on_fail_action    = 2;   -- quit with failure
GO

-- =============================================================================
-- 3. Create schedule: once daily at 03:00
-- =============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'TaskManager: Daily 03:00')
    EXEC sp_delete_schedule
        @schedule_name = N'TaskManager: Daily 03:00',
        @force_delete  = 1;
GO

EXEC sp_add_schedule
    @schedule_name        = N'TaskManager: Daily 03:00',
    @freq_type            = 4,      -- daily
    @freq_interval        = 1,      -- every 1 day
    @freq_subday_type     = 1,      -- once per day (not repeating intraday)
    @freq_subday_interval = 0,
    @active_start_time    = 30000;  -- 03:00:00
GO

EXEC sp_attach_schedule
    @job_name      = N'TaskManager: Purge Audit Log (31d)',
    @schedule_name = N'TaskManager: Daily 03:00';
GO

-- =============================================================================
-- 4. Register on the local server
-- =============================================================================
EXEC sp_add_jobserver
    @job_name    = N'TaskManager: Purge Audit Log (31d)',
    @server_name = N'(LOCAL)';
GO

PRINT 'SQL Agent job ''TaskManager: Purge Audit Log (31d)'' created successfully.';
GO
