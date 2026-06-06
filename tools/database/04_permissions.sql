-- =============================================================================
-- 04_permissions.sql  —  Role setup and permission grants for TaskManager
-- Run AFTER 02_stored_procs.sql
-- =============================================================================
-- PERMISSION MODEL:
--   TaskAppRole members may EXECUTE stored procedures and SELECT from tables.
--   Direct INSERT/UPDATE/DELETE on all three tables is DENIED.
--   DENY always wins over GRANT in SQL Server's permission chain.
--   SPs execute under ownership-chain security (SP owner = dbo = table owner),
--   so the SP itself can perform DML even though the calling principal cannot.
-- =============================================================================
USE TaskManager;
GO

-- Create the application role if it does not exist
IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE name = 'TaskAppRole' AND type = 'R'
)
    CREATE ROLE TaskAppRole;
GO

-- Grant EXECUTE on all stored procedures
GRANT EXECUTE ON dbo.usp_Task_GetNextId     TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_Insert        TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_Update        TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_Delete        TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_Archive       TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_GetAll        TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_GetById       TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_GetStats      TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Task_BulkImport    TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Archive_GetAll     TO TaskAppRole;
GRANT EXECUTE ON dbo.usp_Audit_GetByTaskId  TO TaskAppRole;
GO

-- Grant SELECT for direct read queries (e.g. mssql MCP, SSMS reporting)
GRANT SELECT ON dbo.Tasks        TO TaskAppRole;
GRANT SELECT ON dbo.TasksArchive TO TaskAppRole;
GRANT SELECT ON dbo.TasksAudit   TO TaskAppRole;
GO

-- DENY direct DML on all three tables (DENY always wins over GRANT)
DENY INSERT, UPDATE, DELETE ON dbo.Tasks        TO TaskAppRole;
DENY INSERT, UPDATE, DELETE ON dbo.TasksArchive TO TaskAppRole;
DENY INSERT, UPDATE, DELETE ON dbo.TasksAudit   TO TaskAppRole;
DENY ALTER  ON dbo.Tasks        TO TaskAppRole;
DENY ALTER  ON dbo.TasksArchive TO TaskAppRole;
DENY ALTER  ON dbo.TasksAudit   TO TaskAppRole;
GO

-- =============================================================================
-- Add the current Windows user to TaskAppRole.
-- Runs as the identity executing this script (i.e. your Windows login).
-- If a different service account runs task-server.js, re-run with that account
-- or replace SUSER_SNAME() with the specific login name.
-- =============================================================================
DECLARE @login NVARCHAR(128) = SUSER_SNAME();
DECLARE @sql   NVARCHAR(500);

IF NOT EXISTS (
    SELECT 1 FROM sys.database_principals
    WHERE name = @login AND type IN ('U', 'S')
)
BEGIN
    SET @sql = N'CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login);
    EXEC sp_executesql @sql;
    PRINT 'Created database user: ' + @login;
END

SET @sql = N'ALTER ROLE TaskAppRole ADD MEMBER ' + QUOTENAME(@login);
EXEC sp_executesql @sql;
PRINT 'Added ' + @login + ' to TaskAppRole.';
GO

-- =============================================================================
-- Verification query — run this to confirm the permission setup
-- =============================================================================
SELECT
    dp.name          AS principal,
    o.name           AS [object],
    p.permission_name,
    p.state_desc
FROM sys.database_permissions p
JOIN sys.objects              o  ON o.object_id   = p.major_id
JOIN sys.database_principals  dp ON dp.principal_id = p.grantee_principal_id
WHERE dp.name = 'TaskAppRole'
ORDER BY o.name, p.state_desc, p.permission_name;
GO

PRINT 'Permissions configured successfully.';
GO
