-- =============================================================================
-- 03_trigger.sql  —  Safety-net trigger: blocks direct DML on dbo.Tasks
-- Run AFTER 02_stored_procs.sql
-- =============================================================================
-- HOW IT WORKS:
--   All DML stored procedures set CONTEXT_INFO = 0x5350... ('SP' + 126 zero bytes)
--   before executing any INSERT/UPDATE/DELETE, and clear it after COMMIT.
--   This trigger fires AFTER any DML on Tasks. If CONTEXT_INFO does not carry
--   the SP marker, the DML is considered a direct bypass attempt: it is logged
--   to TasksAudit and the transaction is rolled back.
--
--   Primary enforcement is the DENY grant in 04_permissions.sql.
--   This trigger is defense-in-depth for privileged accounts.
-- =============================================================================
USE TaskManager;
GO

CREATE OR ALTER TRIGGER dbo.trg_Tasks_BlockDirectDML
ON dbo.Tasks
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sp_marker VARBINARY(128) =
        CAST('SP' AS VARBINARY(2)) + CAST(REPLICATE(CHAR(0), 126) AS VARBINARY(126));

    IF CONTEXT_INFO() <> @sp_marker
    BEGIN
        -- Determine action type from inserted/deleted pseudo-tables
        DECLARE @action NVARCHAR(20) =
            CASE
                WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
                WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT'
                ELSE 'DELETE'
            END;

        -- Log the bypass attempt before rolling back
        INSERT INTO dbo.TasksAudit (task_id, action, field_name, old_value, new_value)
        SELECT
            ISNULL(i.id, d.id),
            'DIRECT_DML_BLOCKED',
            @action,
            SYSTEM_USER,
            HOST_NAME()
        FROM (
            SELECT id FROM inserted
            UNION
            SELECT id FROM deleted
        ) AS x(id)
        LEFT JOIN inserted i ON i.id = x.id
        LEFT JOIN deleted  d ON d.id = x.id;

        ROLLBACK TRANSACTION;
        THROW 50099, 'Direct DML on dbo.Tasks is not permitted. Use stored procedures.', 1;
    END
END
GO

PRINT 'Safety-net trigger created successfully.';
GO
