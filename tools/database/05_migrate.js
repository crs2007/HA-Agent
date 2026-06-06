#!/usr/bin/env node
'use strict';

/**
 * 05_migrate.js — Migrate tasks.json → SQL Server TaskManager DB
 *
 * Reads _bmad/bmm/tasks/tasks.json and inserts each task via usp_Task_Insert,
 * preserving original id, created_at, and updated_at.
 *
 * Usage:
 *   node tools/database/05_migrate.js               # live migration
 *   node tools/database/05_migrate.js --dry-run     # validate only, no DB write
 *   node tools/database/05_migrate.js --file /path/to/tasks.json
 *
 * Prerequisites:
 *   npm install            (adds mssql to node_modules)
 *   Run SQL scripts 01-04 first
 */

const sql  = require('mssql/msnodesqlv8');
const fs   = require('fs');
const path = require('path');

// ----------------------------------------------------------------------------
// DB config — Named Pipes (no SQL Browser / TCP required).
// Override with MSSQL_CONNECTION_STRING env var if needed.
// ----------------------------------------------------------------------------
const DEFAULT_CONNSTR =
  'Driver={ODBC Driver 18 for SQL Server}' +
  ';Server=np:\\\\.\\pipe\\MSSQL$SQLSERVER2022\\sql\\query' +
  ';Database=TaskManager;Trusted_Connection=yes;TrustServerCertificate=yes;';

const DB_CONFIG = {
  connectionString: process.env.MSSQL_CONNECTION_STRING || DEFAULT_CONNSTR,
};

const DEFAULT_TASKS_FILE = path.join(
  __dirname, '..', '..', '_bmad', 'bmm', 'tasks', 'tasks.json'
);

// ----------------------------------------------------------------------------
// Defaults applied to sparse task objects (e.g. T025 has only id+status+notes)
// ----------------------------------------------------------------------------
const DEFAULTS = {
  title:       null,
  description: null,
  severity:    'medium',
  category:    'automation',
  status:      'open',
  agent:       'unassigned',
  model:       'unassigned',
  source:      null,
  plan:        null,
  log_count:   0,
  notes:       null,
};

const VALID = {
  severity: new Set(['low', 'medium', 'high', 'critical']),
  category: new Set(['automation', 'script', 'fix', 'dashboard', 'config', 'feature']),
  status:   new Set(['open', 'in-progress', 'done', 'planned', 'dismissed', 'ignored', 'archived']),
  agent:    new Set(['unassigned', 'ha-developer', 'ha-reviewer', 'ha-reviver', 'ha-dashboard-designer', 'ha-task-manager']),
  // model is free-form — any LLM model name is accepted
};

// ── String → FK ID maps (mirror dbo._Severity / dbo._Status seed data) ──────
const SEVERITY_ID = { low: 1, medium: 2, high: 3, critical: 4 };
const STATUS_ID   = { open: 1, 'in-progress': 2, planned: 3, done: 4, dismissed: 5, ignored: 6, archived: 7 };

function validateTask(task, index) {
  const errors = [];
  if (!task.id || !/^T\d{3}$/.test(task.id))
    errors.push(`id must match T[0-9]{3}, got: ${JSON.stringify(task.id)}`);
  if (task.severity  && !VALID.severity.has(task.severity))
    errors.push(`Invalid severity: ${task.severity}`);
  if (task.category  && !VALID.category.has(task.category))
    errors.push(`Invalid category: ${task.category}`);
  if (task.status    && !VALID.status.has(task.status))
    errors.push(`Invalid status: ${task.status}`);
  if (task.agent     && !VALID.agent.has(task.agent))
    errors.push(`Invalid agent: ${task.agent}`);
  if (errors.length)
    throw new Error(`Task[${index}] ${task.id || '(no id)'}: ${errors.join('; ')}`);
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------
async function migrate() {
  const args    = process.argv.slice(2);
  const dryRun  = args.includes('--dry-run');
  const fileIdx = args.indexOf('--file');
  const taskFile = fileIdx !== -1 ? args[fileIdx + 1] : DEFAULT_TASKS_FILE;

  console.log(`\nHA Task Migration — ${dryRun ? 'DRY RUN' : 'LIVE'}`);
  console.log(`Source: ${taskFile}`);

  if (!fs.existsSync(taskFile)) {
    console.error(`ERROR: File not found: ${taskFile}`);
    process.exit(1);
  }

  const raw   = fs.readFileSync(taskFile, 'utf8');
  const tasks = JSON.parse(raw);

  if (!Array.isArray(tasks)) throw new Error('tasks.json must be a JSON array');

  console.log(`\nFound ${tasks.length} task(s). Validating...`);
  tasks.forEach((t, i) => validateTask(t, i));
  console.log('Validation passed.\n');

  if (dryRun) {
    tasks.forEach(t => console.log(`  WOULD INSERT ${t.id}  ${t.title || '(no title)'}`));
    console.log('\n--dry-run: no database changes made.');
    return;
  }

  const pool = await sql.connect(DB_CONFIG);
  console.log('Connected to SQL Server (TaskManager via Named Pipes)\n');

  let inserted = 0;
  let skipped  = 0;

  for (const raw of tasks) {
    const t = { ...DEFAULTS, ...raw };

    // Idempotent: skip if already in Tasks table
    const existing = await pool.request()
      .input('id', sql.Char(4), t.id)
      .query('SELECT 1 FROM dbo.Tasks WHERE id = @id');

    if (existing.recordset.length > 0) {
      console.log(`  SKIP ${t.id} — already exists`);
      skipped++;
      continue;
    }

    try {
      await pool.request()
        .input('id',          sql.Char(4),          t.id)
        .input('title',       sql.NVarChar(500),     t.title       ?? null)
        .input('description', sql.NVarChar(sql.MAX), t.description ?? null)
        .input('severity_id', sql.SmallInt,            SEVERITY_ID[t.severity])
        .input('category',    sql.NVarChar(50),      t.category)
        .input('status_id',   sql.SmallInt,            STATUS_ID[t.status])
        .input('agent',       sql.NVarChar(60),      t.agent)
        .input('model',       sql.NVarChar(20),      t.model)
        .input('source',      sql.NVarChar(500),     t.source      ?? null)
        .input('plan',        sql.NVarChar(sql.MAX), t.plan        ?? null)
        .input('log_count',   sql.Int,               t.log_count   ?? 0)
        .input('notes',       sql.NVarChar(sql.MAX), t.notes       ?? null)
        .input('created_at',  sql.DateTime2(3),      t.created_at ? new Date(t.created_at) : null)
        .input('updated_at',  sql.DateTime2(3),      t.updated_at ? new Date(t.updated_at) : null)
        .execute('dbo.usp_Task_Insert');

      console.log(`  OK   ${t.id}  ${t.title || '(no title)'}`);
      inserted++;
    } catch (err) {
      console.error(`  FAIL ${t.id}: ${err.message}`);
      await pool.close();
      process.exit(1);   // abort on first error — DB is consistent (each SP is transactional)
    }
  }

  await pool.close();
  console.log(`\nMigration complete. Inserted: ${inserted}, Skipped: ${skipped}`);
}

migrate().catch(err => {
  console.error('\nFatal error:', err.message);
  process.exit(1);
});
