#!/usr/bin/env node
'use strict';

/**
 * mssql-mcp-server.js — Stdio MCP server for SQL Server
 * Uses the mssql package already installed in this project.
 * Configured via the same env vars as task-server.js / run-sql.js.
 */

const sql  = require('mssql');
const fs   = require('fs');
const path = require('path');

// ── DB config (mirrors task-server.js) ──────────────────────────────────────
const DB_CONFIG = {
  server:   process.env.MSSQL_SERVER   || 'localhost\\SQLSERVER2022',
  database: process.env.MSSQL_DATABASE || 'TaskManager',
  options: {
    trustedConnection:      !process.env.MSSQL_USER,
    encrypt:                false,
    trustServerCertificate: true,
    enableArithAbort:       true,
  },
  ...(process.env.MSSQL_USER && {
    user:     process.env.MSSQL_USER,
    password: process.env.MSSQL_PASSWORD || '',
  }),
};

let pool = null;

async function getPool() {
  if (!pool) pool = await sql.connect(DB_CONFIG);
  return pool;
}

// ── Shared enum values (mirror DB lookup tables) ────────────────────────────
const SEVERITIES       = ['low', 'medium', 'high', 'critical'];
const CATEGORIES       = ['automation', 'script', 'fix', 'dashboard', 'config', 'feature'];
const STATUSES         = ['open', 'in-progress', 'done', 'planned', 'dismissed', 'ignored', 'archived'];
const AGENTS           = ['unassigned', 'ha-developer', 'ha-reviewer', 'ha-reviver', 'ha-dashboard-designer', 'ha-task-manager'];
const ARCHIVE_REASONS  = ['manual', 'cleanup', 'bulk-replace'];
// model is free-form (no DB constraint) — any current or future LLM model name is valid

// ── String → FK ID maps (mirror dbo._Severity / dbo._Status seed data) ──────
const SEVERITY_ID = { low: 1, medium: 2, high: 3, critical: 4 };
const STATUS_ID   = { open: 1, 'in-progress': 2, planned: 3, done: 4, dismissed: 5, ignored: 6, archived: 7 };

// ── Tool definitions ─────────────────────────────────────────────────────────
const TOOLS = [
  // ── Generic SQL tools (kept for flexibility) ─────────────────────────────
  {
    name: 'execute_query',
    description: 'Execute a SQL SELECT query and return rows as JSON.',
    inputSchema: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'SQL SELECT statement to execute' },
      },
      required: ['query'],
    },
  },
  {
    name: 'execute_statement',
    description: 'Execute a SQL statement (INSERT, UPDATE, DELETE, DDL). Returns rows affected.',
    inputSchema: {
      type: 'object',
      properties: {
        statement: { type: 'string', description: 'SQL statement to execute' },
      },
      required: ['statement'],
    },
  },
  {
    name: 'list_tables',
    description: 'List all tables and views in the current database.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'list_stored_procedures',
    description: 'List all stored procedures in the current database.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'run_sql_file',
    description: 'Execute one of the database setup SQL files (01_tables, 02_stored_procs, 03_trigger, 04_permissions).',
    inputSchema: {
      type: 'object',
      properties: {
        file: {
          type: 'string',
          enum: ['01_tables.sql', '02_stored_procs.sql', '03_trigger.sql', '04_permissions.sql'],
          description: 'SQL file to execute from tools/database/',
        },
      },
      required: ['file'],
    },
  },

  // ── Task-specific tools (wrap stored procedures) ──────────────────────────
  {
    name: 'task_list',
    description: 'List tasks with optional filters. Returns all tasks when no filters are provided.',
    inputSchema: {
      type: 'object',
      properties: {
        status:   { type: 'string', enum: STATUSES,    description: 'Filter by status' },
        agent:    { type: 'string', enum: AGENTS,      description: 'Filter by assigned agent' },
        severity: { type: 'string', enum: SEVERITIES,  description: 'Filter by severity' },
        category: { type: 'string', enum: CATEGORIES,  description: 'Filter by category' },
        q:        { type: 'string', description: 'Full-text search across title, description, and notes' },
      },
    },
  },
  {
    name: 'task_get',
    description: 'Get a single task by ID (e.g. T001).',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Task ID (format: T001–T999)', pattern: '^T[0-9]{3}$' },
      },
      required: ['id'],
    },
  },
  {
    name: 'task_create',
    description: 'Create a new task. Auto-generates the task ID. Returns the created task row.',
    inputSchema: {
      type: 'object',
      properties: {
        title:       { type: 'string', description: 'Task title (required)' },
        description: { type: 'string', description: 'Detailed task description' },
        severity:    { type: 'string', enum: SEVERITIES, description: 'Severity level (default: medium)' },
        category:    { type: 'string', enum: CATEGORIES, description: 'Task category (default: automation)' },
        status:      { type: 'string', enum: STATUSES,   description: 'Initial status (default: open)' },
        agent:       { type: 'string', enum: AGENTS,     description: 'Assigned agent (default: unassigned)' },
        model:       { type: 'string', description: 'Target model (e.g. claude-opus-4-7, claude-sonnet-4-6, gpt-4o; default: unassigned)' },
        source:      { type: 'string', description: 'Origin reference (e.g. "claude-plan", "watchman")' },
        plan:        { type: 'string', description: 'Implementation plan or notes (Markdown)' },
        notes:       { type: 'string', description: 'Escalation notes or additional context' },
      },
      required: ['title'],
    },
  },
  {
    name: 'task_update',
    description: 'Update one or more fields on an existing task. Omitted fields are left unchanged. Returns the updated task row.',
    inputSchema: {
      type: 'object',
      properties: {
        id:          { type: 'string', description: 'Task ID to update', pattern: '^T[0-9]{3}$' },
        title:       { type: 'string', description: 'New title' },
        description: { type: 'string', description: 'New description' },
        severity:    { type: 'string', enum: SEVERITIES, description: 'New severity' },
        category:    { type: 'string', enum: CATEGORIES, description: 'New category' },
        status:      { type: 'string', enum: STATUSES,   description: 'New status' },
        agent:       { type: 'string', enum: AGENTS,     description: 'New assigned agent' },
        model:       { type: 'string', description: 'New target model (e.g. claude-opus-4-7, claude-sonnet-4-6, gpt-4o)' },
        source:      { type: 'string', description: 'New source reference' },
        plan:        { type: 'string', description: 'New or updated implementation plan' },
        notes:       { type: 'string', description: 'New or updated notes' },
      },
      required: ['id'],
    },
  },
  {
    name: 'task_delete',
    description: 'Hard-delete a task by ID. The audit trail entry is preserved.',
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', description: 'Task ID to delete', pattern: '^T[0-9]{3}$' },
      },
      required: ['id'],
    },
  },
  {
    name: 'task_archive',
    description: 'Move a task from the active Tasks table to TasksArchive. Use this instead of delete for completed or dismissed tasks.',
    inputSchema: {
      type: 'object',
      properties: {
        id:              { type: 'string', description: 'Task ID to archive', pattern: '^T[0-9]{3}$' },
        archived_reason: { type: 'string', enum: ARCHIVE_REASONS, description: 'Reason for archiving (default: manual)' },
      },
      required: ['id'],
    },
  },
  {
    name: 'task_stats',
    description: 'Return task queue statistics: total/active/critical_open/unassigned counts plus breakdowns by status, severity, agent, and category.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'task_bulk_import',
    description: 'Atomically replace all active tasks with the provided array. Archives the current task set before replacing. Use for full triage/rebalance operations.',
    inputSchema: {
      type: 'object',
      properties: {
        tasks: {
          type: 'array',
          description: 'Full task array to import. Each item must have id, title, severity, category, status, agent, model.',
          items: { type: 'object' },
        },
      },
      required: ['tasks'],
    },
  },
  {
    name: 'task_archive_list',
    description: 'Return all archived tasks, newest first. Includes archived_at and archived_reason fields.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'task_audit',
    description: 'Return the full column-level audit trail for a task ID. Audit entries survive after task deletion.',
    inputSchema: {
      type: 'object',
      properties: {
        task_id: { type: 'string', description: 'Task ID to fetch audit trail for', pattern: '^T[0-9]{3}$' },
      },
      required: ['task_id'],
    },
  },
];

// ── GO-batch splitter (same as run-sql.js) ───────────────────────────────────
function splitOnGo(text) {
  return text
    .split(/\r?\n/)
    .reduce((batches, line) => {
      if (/^\s*GO\s*$/i.test(line)) batches.push('');
      else batches[batches.length - 1] += line + '\n';
      return batches;
    }, [''])
    .map(b => b.trim())
    .filter(b => b.length > 0);
}

// ── Tool dispatch ────────────────────────────────────────────────────────────
async function callTool(name, args) {
  const db = await getPool();

  // ── Generic SQL tools ──────────────────────────────────────────────────────

  if (name === 'execute_query') {
    const result = await db.request().query(args.query);
    return jsonText(result.recordset);
  }

  if (name === 'execute_statement') {
    const result = await db.request().query(args.statement);
    return { content: [{ type: 'text', text: `Rows affected: ${result.rowsAffected[0] ?? 0}` }] };
  }

  if (name === 'list_tables') {
    const result = await db.request().query(`
      SELECT TABLE_NAME AS name, TABLE_TYPE AS type
      FROM   INFORMATION_SCHEMA.TABLES
      WHERE  TABLE_CATALOG = DB_NAME()
      ORDER  BY TABLE_TYPE, TABLE_NAME
    `);
    return jsonText(result.recordset);
  }

  if (name === 'list_stored_procedures') {
    const result = await db.request().query(`
      SELECT ROUTINE_NAME AS name, CREATED, LAST_ALTERED
      FROM   INFORMATION_SCHEMA.ROUTINES
      WHERE  ROUTINE_CATALOG = DB_NAME() AND ROUTINE_TYPE = 'PROCEDURE'
      ORDER  BY ROUTINE_NAME
    `);
    return jsonText(result.recordset);
  }

  if (name === 'run_sql_file') {
    const filePath = path.join(__dirname, 'database', args.file);
    if (!fs.existsSync(filePath)) throw new Error(`File not found: ${filePath}`);

    const content = fs.readFileSync(filePath, 'utf8');
    const batches = splitOnGo(content);
    const log = [];

    for (let i = 0; i < batches.length; i++) {
      try {
        await db.request().query(batches[i]);
        log.push(`[OK] batch ${i + 1}`);
      } catch (err) {
        if (err.message.includes('already exists') || err.message.includes('There is already an object')) {
          log.push(`[SKIP] batch ${i + 1}: already exists`);
        } else {
          log.push(`[FAIL] batch ${i + 1}: ${err.message}`);
          return { content: [{ type: 'text', text: log.join('\n') }], isError: true };
        }
      }
    }
    return { content: [{ type: 'text', text: `Executed ${args.file}:\n${log.join('\n')}` }] };
  }

  // ── Task-specific tools ────────────────────────────────────────────────────

  if (name === 'task_list') {
    const req = db.request();
    req.input('status_id',   sql.SmallInt,     args.status   != null ? STATUS_ID[args.status]     : null);
    req.input('agent',       sql.NVarChar(60), args.agent    ?? null);
    req.input('severity_id', sql.SmallInt,     args.severity != null ? SEVERITY_ID[args.severity] : null);
    req.input('category',    sql.NVarChar(50), args.category ?? null);
    req.input('q',           sql.NVarChar(200), args.q       ?? null);
    const result = await req.execute('dbo.usp_Task_GetAll');
    return jsonText(result.recordset);
  }

  if (name === 'task_get') {
    const req = db.request();
    req.input('id', sql.Char(4), args.id);
    const result = await req.execute('dbo.usp_Task_GetById');
    return jsonText(result.recordset[0] ?? null);
  }

  if (name === 'task_create') {
    const req = db.request();
    req.input('id',          sql.Char(4),          null);
    req.input('title',       sql.NVarChar(500),     args.title);
    req.input('description', sql.NVarChar(sql.MAX), args.description ?? null);
    req.input('severity_id', sql.SmallInt,          args.severity != null ? SEVERITY_ID[args.severity] : 2);
    req.input('category',    sql.NVarChar(50),      args.category    ?? null);
    req.input('status_id',   sql.SmallInt,          args.status   != null ? STATUS_ID[args.status]     : 1);
    req.input('agent',       sql.NVarChar(60),      args.agent       ?? null);
    req.input('model',       sql.NVarChar(20),      args.model       ?? null);
    req.input('source',      sql.NVarChar(500),     args.source      ?? null);
    req.input('plan',        sql.NVarChar(sql.MAX), args.plan        ?? null);
    req.input('log_count',   sql.Int,               null);
    req.input('notes',       sql.NVarChar(sql.MAX), args.notes       ?? null);
    req.input('created_at',  sql.DateTime2(3),      null);
    req.input('updated_at',  sql.DateTime2(3),      null);
    const result = await req.execute('dbo.usp_Task_Insert');
    return jsonText(result.recordset[0] ?? null);
  }

  if (name === 'task_update') {
    const req = db.request();
    req.input('id',          sql.Char(4),          args.id);
    req.input('title',       sql.NVarChar(500),     args.title       ?? null);
    req.input('description', sql.NVarChar(sql.MAX), args.description ?? null);
    req.input('severity_id', sql.SmallInt,          args.severity != null ? SEVERITY_ID[args.severity] : null);
    req.input('category',    sql.NVarChar(50),      args.category    ?? null);
    req.input('status_id',   sql.SmallInt,          args.status   != null ? STATUS_ID[args.status]     : null);
    req.input('agent',       sql.NVarChar(60),      args.agent       ?? null);
    req.input('model',       sql.NVarChar(20),      args.model       ?? null);
    req.input('source',      sql.NVarChar(500),     args.source      ?? null);
    req.input('plan',        sql.NVarChar(sql.MAX), args.plan        ?? null);
    req.input('log_count',   sql.Int,               args.log_count   ?? null);
    req.input('notes',       sql.NVarChar(sql.MAX), args.notes       ?? null);
    const result = await req.execute('dbo.usp_Task_Update');
    return jsonText(result.recordset[0] ?? null);
  }

  if (name === 'task_delete') {
    const req = db.request();
    req.input('id', sql.Char(4), args.id);
    await req.execute('dbo.usp_Task_Delete');
    return { content: [{ type: 'text', text: `Task ${args.id} deleted.` }] };
  }

  if (name === 'task_archive') {
    const req = db.request();
    req.input('id',              sql.Char(4),       args.id);
    req.input('archived_reason', sql.NVarChar(100), args.archived_reason ?? 'manual');
    await req.execute('dbo.usp_Task_Archive');
    return { content: [{ type: 'text', text: `Task ${args.id} archived (reason: ${args.archived_reason ?? 'manual'}).` }] };
  }

  if (name === 'task_stats') {
    const result = await db.request().execute('dbo.usp_Task_GetStats');
    return jsonText({
      totals:      result.recordsets[0][0],
      by_status:   result.recordsets[1],
      by_severity: result.recordsets[2],
      by_agent:    result.recordsets[3],
      by_category: result.recordsets[4],
    });
  }

  if (name === 'task_bulk_import') {
    const tasks = args.tasks.map(t => ({
      ...t,
      severity_id: t.severity != null ? SEVERITY_ID[t.severity] : (t.severity_id ?? 2),
      status_id:   t.status   != null ? STATUS_ID[t.status]     : (t.status_id   ?? 1),
      severity:    undefined,
      status:      undefined,
    }));
    const req = db.request();
    req.input('json', sql.NVarChar(sql.MAX), JSON.stringify(tasks));
    const result = await req.execute('dbo.usp_Task_BulkImport');
    return jsonText(result.recordset);
  }

  if (name === 'task_archive_list') {
    const result = await db.request().execute('dbo.usp_Archive_GetAll');
    return jsonText(result.recordset);
  }

  if (name === 'task_audit') {
    const req = db.request();
    req.input('task_id', sql.Char(4), args.task_id);
    const result = await req.execute('dbo.usp_Audit_GetByTaskId');
    return jsonText(result.recordset);
  }

  throw new Error(`Unknown tool: ${name}`);
}

function jsonText(data) {
  return { content: [{ type: 'text', text: JSON.stringify(data, null, 2) }] };
}

// ── MCP JSON-RPC stdio transport ─────────────────────────────────────────────
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function respond(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function respondError(id, code, message) {
  send({ jsonrpc: '2.0', id, error: { code, message } });
}

async function handle(msg) {
  const { id, method, params } = msg;

  // Notifications have no id — don't respond
  if (method === 'notifications/initialized' || method === 'initialized') return;

  try {
    if (method === 'initialize') {
      respond(id, {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'mssql', version: '1.1.0' },
      });
    } else if (method === 'ping') {
      respond(id, {});
    } else if (method === 'tools/list') {
      respond(id, { tools: TOOLS });
    } else if (method === 'tools/call') {
      const result = await callTool(params.name, params.arguments || {});
      respond(id, result);
    } else {
      respondError(id, -32601, `Method not found: ${method}`);
    }
  } catch (err) {
    respondError(id, -32603, err.message);
  }
}

// ── Stdin loop ───────────────────────────────────────────────────────────────
let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf('\n')) !== -1) {
    const line = buf.slice(0, nl).trim();
    buf = buf.slice(nl + 1);
    if (!line) continue;
    try {
      handle(JSON.parse(line));
    } catch {
      respondError(null, -32700, 'Parse error');
    }
  }
});

process.stdin.on('end', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));
