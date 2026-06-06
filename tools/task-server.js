#!/usr/bin/env node
'use strict';

/**
 * task-server.js — MS SQL Server backend
 * All persistence is via stored procedures in the TaskManager database.
 * REST API surface is 100% backwards-compatible with the original file-based server.
 *
 * DB: localhost\SQLSERVER2022 / TaskManager (Windows Auth by default)
 * Override with env vars: MSSQL_SERVER, MSSQL_DATABASE, MSSQL_USER, MSSQL_PASSWORD
 */

const express = require('express');
const path    = require('path');

// Pick the DB driver by environment:
//   - TCP (tedious) when MSSQL_SERVER is set — required for the Linux container,
//     which reaches the host SQL Server via host.docker.internal + SQL auth.
//   - Named pipes (msnodesqlv8) otherwise — preserves the original Windows-host
//     `npm run tasks` behavior (Trusted_Connection / Windows Auth).
// require('mssql/msnodesqlv8') is only evaluated on the named-pipe branch, so the
// container image never needs that native module.
const USE_TCP = !!process.env.MSSQL_SERVER;
const sql     = USE_TCP ? require('mssql') : require('mssql/msnodesqlv8');

const PORT     = process.env.PORT || 3001;
const HTML_FILE = path.join(__dirname, '..', '_bmad', 'bmm', 'tasks', 'ha-tasks.html');

// ── String → FK ID maps (mirror dbo._Severity / dbo._Status seed data) ──────
const SEVERITY_ID = { low: 1, medium: 2, high: 3, critical: 4 };
const STATUS_ID   = { open: 1, 'in-progress': 2, planned: 3, done: 4, dismissed: 5, ignored: 6, archived: 7 };

// ── Reviewer model → Tasks.model tier (upgrade-only) ────────────────────────
// On /apply-review, if the reviewer ran on a higher tier than the task's
// current model, we promote Tasks.model to match — so the implementer uses
// the same caliber of model that designed the alternative plan.
// Returns null for unrecognized reviewer ids; callers treat null as
// "leave Tasks.model unchanged" (usp_Task_Update does ISNULL(@model, model)).
const MODEL_TIER_RANK = { unassigned: 0, haiku: 1, sonnet: 2, opus: 3 };
function normalizeReviewerModel(reviewerModel) {
  if (!reviewerModel) return null;
  const m = String(reviewerModel).toLowerCase();
  if (m.includes('opus'))   return 'opus';
  if (m.includes('sonnet')) return 'sonnet';
  if (m.includes('haiku'))  return 'haiku';
  return null;
}
function shouldUpgradeModel(current, reviewer) {
  const c = MODEL_TIER_RANK[current]  ?? 0;
  const r = MODEL_TIER_RANK[reviewer] ?? 0;
  return r > c;
}

// ----------------------------------------------------------------------------
// Database configuration
// Connects via Named Pipes (no SQL Browser / TCP required).
// Override the full ODBC connection string with MSSQL_CONNECTION_STRING.
// ----------------------------------------------------------------------------
const DEFAULT_CONNSTR =
  'Driver={ODBC Driver 18 for SQL Server}' +
  ';Server=np:\\\\.\\pipe\\MSSQL$SQLSERVER2022\\sql\\query' +
  ';Database=TaskManager;Trusted_Connection=yes;TrustServerCertificate=yes;';

const POOL_OPTS = { max: 10, min: 2, idleTimeoutMillis: 30000 };

const DB_CONFIG = USE_TCP
  ? {
      server:   process.env.MSSQL_SERVER,                 // e.g. host.docker.internal
      port:     Number(process.env.MSSQL_PORT) || 1433,
      database: process.env.MSSQL_DATABASE || 'TaskManager',
      user:     process.env.MSSQL_USER,
      password: process.env.MSSQL_PASSWORD,
      options:  { encrypt: false, trustServerCertificate: true, enableArithAbort: true },
      pool:     POOL_OPTS,
    }
  : {
      connectionString: process.env.MSSQL_CONNECTION_STRING || DEFAULT_CONNSTR,
      pool: POOL_OPTS,
    };

let pool;
async function getPool() {
  if (!pool) {
    pool = await sql.connect(DB_CONFIG);
    console.log(`Connected to SQL Server (TaskManager via ${USE_TCP ? 'TCP' : 'Named Pipes'})`);
  }
  return pool;
}

// ----------------------------------------------------------------------------
// Shape helpers
// ----------------------------------------------------------------------------

// Convert a DB result row to the JSON shape the API has always returned.
// CHAR(4) columns may right-pad with spaces in some driver configurations.
function rowToTask(row) {
  return {
    id:                   (row.id || '').trim(),
    title:                row.title       ?? '',
    description:          row.description ?? '',
    severity:             row.severity,
    category:             row.category,
    status:               row.status,
    agent:                row.agent,
    model:                row.model,
    source:               row.source      ?? '',
    plan:                 row.plan        ?? '',
    log_count:            row.log_count   ?? 0,
    notes:                row.notes       ?? '',
    plan_review:          row.plan_review          ?? '',
    plan_review_at:       row.plan_review_at       ?? null,
    plan_review_provider: row.plan_review_provider ?? '',
    plan_review_model:    row.plan_review_model    ?? '',
    plan_review_type:     row.plan_review_type     ?? '',
    solution:             row.solution             ?? '',
    solution_at:          row.solution_at          ?? null,
    solution_provider:    row.solution_provider    ?? '',
    solution_model:       row.solution_model       ?? '',
    solution_status:      row.solution_status      ?? '',
    created_at:           row.created_at,
    updated_at:           row.updated_at,
  };
}

// Assemble the 5-result-set output of usp_Task_GetStats into the expected shape.
function buildStats(recordsets) {
  const [scalars, byStatus, bySeverity, byAgent, byCategory] = recordsets;
  const toMap = rows => rows.reduce((acc, r) => { acc[r.key] = r.count; return acc; }, {});
  return {
    total:         scalars[0].total,
    active:        scalars[0].active,
    critical_open: scalars[0].critical_open,
    unassigned:    scalars[0].unassigned,
    by_status:     toMap(byStatus),
    by_severity:   toMap(bySeverity),
    by_agent:      toMap(byAgent),
    by_category:   toMap(byCategory),
  };
}

// ----------------------------------------------------------------------------
// Express app
// ----------------------------------------------------------------------------
const app = express();
app.use(express.json({ limit: '10mb' }));  // 10 MB covers the largest bulk payloads

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin',  '*');
  res.header('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// Serve the task board HTML UI (unchanged)
app.get('/', (req, res) => res.sendFile(HTML_FILE));

// ============================================================================
// GET /api/tasks/stats
// IMPORTANT: must be registered BEFORE /api/tasks/:id — Express matches in order.
// ============================================================================
app.get('/api/tasks/stats', async (req, res) => {
  try {
    const db     = await getPool();
    const result = await db.request().execute('dbo.usp_Task_GetStats');
    res.json(buildStats(result.recordsets));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// GET /api/tasks  — list with optional filters
// Supports: ?status= ?agent= ?severity= ?category= ?q=
// ============================================================================
app.get('/api/tasks', async (req, res) => {
  try {
    const db     = await getPool();
    const result = await db.request()
      .input('status_id',   sql.SmallInt,     req.query.status   ? STATUS_ID[req.query.status]     : null)
      .input('agent',       sql.NVarChar(60), req.query.agent    || null)
      .input('severity_id', sql.SmallInt,     req.query.severity ? SEVERITY_ID[req.query.severity] : null)
      .input('category',    sql.NVarChar(50), req.query.category || null)
      .input('q',           sql.NVarChar(200), req.query.q       || null)
      .execute('dbo.usp_Task_GetAll');
    res.json(result.recordset.map(rowToTask));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// GET /api/tasks/:id  — get a single task by ID
// IMPORTANT: must be registered AFTER /api/tasks/stats — Express matches in order.
// ============================================================================
app.get('/api/tasks/:id', async (req, res) => {
  try {
    const db     = await getPool();
    const result = await db.request()
      .input('id', sql.Char(4), req.params.id)
      .execute('dbo.usp_Task_GetById');
    if (result.recordset.length === 0)
      return res.status(404).json({ error: 'Not found' });
    res.json(rowToTask(result.recordset[0]));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// POST /api/tasks  — create a new task (auto-assign ID)
// ============================================================================
app.post('/api/tasks', async (req, res) => {
  try {
    const db   = await getPool();
    const body = req.body || {};
    const result = await db.request()
      .input('id',          sql.Char(4),          null)
      .input('title',       sql.NVarChar(500),     body.title       ?? null)
      .input('description', sql.NVarChar(sql.MAX), body.description ?? null)
      .input('severity_id', sql.SmallInt,          SEVERITY_ID[body.severity] ?? 2)
      .input('category',    sql.NVarChar(50),      body.category    ?? 'automation')
      .input('status_id',   sql.SmallInt,          STATUS_ID[body.status]     ?? 1)
      .input('agent',       sql.NVarChar(60),      body.agent       ?? 'unassigned')
      .input('model',       sql.NVarChar(20),      body.model       ?? 'unassigned')
      .input('source',      sql.NVarChar(500),     body.source      ?? null)
      .input('plan',        sql.NVarChar(sql.MAX), body.plan        ?? null)
      .input('log_count',   sql.Int,               body.log_count   ?? 0)
      .input('notes',       sql.NVarChar(sql.MAX), body.notes       ?? null)
      .input('created_at',  sql.DateTime2(3),      null)
      .input('updated_at',  sql.DateTime2(3),      null)
      .execute('dbo.usp_Task_Insert');
    res.status(201).json(rowToTask(result.recordset[0]));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// POST /api/tasks/:id/save-review
// Body: { provider, model, type, content }
//   provider — free-form label of the reviewing LLM (e.g. 'claude-code',
//              'gpt-4o', 'gemini'). Stored verbatim.
//   model    — specific model id used by that LLM.
//   type     — 'notes' (plan is sound, optimization notes) or 'alternative'
//              (full replacement plan). Constrained by CK_Tasks_review_type.
//   content  — markdown body. For 'notes': bullet list. For 'alternative': a
//              full plan that can later be applied via /apply-review.
//
// Called by the in-VS-Code LLM agent after it reviews a task plan. The agent
// reaches this endpoint via fetch (or the mssql MCP server, which exposes
// usp_Task_SaveReview directly). MUST be registered before /api/tasks/:id.
// ============================================================================
app.post('/api/tasks/:id/save-review', async (req, res) => {
  try {
    const { provider, model, type, content } = req.body || {};
    if (!provider || !model || !type || !content)
      return res.status(400).json({
        error: 'provider, model, type, and content are all required',
      });
    if (type !== 'notes' && type !== 'alternative')
      return res.status(400).json({
        error: 'type must be "notes" or "alternative"',
      });

    const db = await getPool();
    const result = await db.request()
      .input('id',                   sql.Char(4),           req.params.id)
      .input('plan_review',          sql.NVarChar(sql.MAX), content)
      .input('plan_review_provider', sql.NVarChar(40),      provider)
      .input('plan_review_model',    sql.NVarChar(80),      model)
      .input('plan_review_type',     sql.NVarChar(20),      type)
      .execute('dbo.usp_Task_SaveReview');

    res.json(rowToTask(result.recordset[0]));
  } catch (e) {
    if (e.number === 50002) return res.status(404).json({ error: 'Not found' });
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// POST /api/tasks/:id/apply-review
// Replaces the task's plan with the proposed alternative review content,
// then clears the five plan_review_* columns. The old plan is preserved
// automatically by the per-field audit trigger on usp_Task_Update.
// Only valid when plan_review_type === 'alternative'.
// MUST be registered before /api/tasks/:id below.
// ============================================================================
app.post('/api/tasks/:id/apply-review', async (req, res) => {
  try {
    const db = await getPool();

    const taskRes = await db.request()
      .input('id', sql.Char(4), req.params.id)
      .execute('dbo.usp_Task_GetById');
    if (taskRes.recordset.length === 0)
      return res.status(404).json({ error: 'Task not found' });
    const task = rowToTask(taskRes.recordset[0]);

    if (task.plan_review_type !== 'alternative')
      return res.status(400).json({
        error: 'No alternative plan available to apply (review type is "' +
               (task.plan_review_type || 'none') + '")',
      });
    if (!task.plan_review || !task.plan_review.trim())
      return res.status(400).json({ error: 'Review content is empty' });

    // Step 1: replace the plan via usp_Task_Update (fires per-field audit).
    // If the reviewer ran on a higher-tier model than the task, also promote
    // Tasks.model — so the implementer uses the same caliber that designed
    // this alternative. null = leave model unchanged.
    const reviewerTier  = normalizeReviewerModel(task.plan_review_model);
    const upgradedModel = reviewerTier && shouldUpgradeModel(task.model, reviewerTier)
      ? reviewerTier
      : null;

    await db.request()
      .input('id',          sql.Char(4),          req.params.id)
      .input('title',       sql.NVarChar(500),     null)
      .input('description', sql.NVarChar(sql.MAX), null)
      .input('severity_id', sql.SmallInt,          null)
      .input('category',    sql.NVarChar(50),      null)
      .input('status_id',   sql.SmallInt,          null)
      .input('agent',       sql.NVarChar(60),      null)
      .input('model',       sql.NVarChar(20),      upgradedModel)
      .input('source',      sql.NVarChar(500),     null)
      .input('plan',        sql.NVarChar(sql.MAX), task.plan_review)
      .input('log_count',   sql.Int,               null)
      .input('notes',       sql.NVarChar(sql.MAX), null)
      .execute('dbo.usp_Task_Update');

    // Step 2: clear the five review columns via usp_Task_SaveReview with NULLs
    const saveRes = await db.request()
      .input('id',                   sql.Char(4),           req.params.id)
      .input('plan_review',          sql.NVarChar(sql.MAX), null)
      .input('plan_review_provider', sql.NVarChar(40),      null)
      .input('plan_review_model',    sql.NVarChar(80),      null)
      .input('plan_review_type',     sql.NVarChar(20),      null)
      .execute('dbo.usp_Task_SaveReview');

    res.json(rowToTask(saveRes.recordset[0]));
  } catch (e) {
    if (e.number === 50002) return res.status(404).json({ error: 'Not found' });
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// POST /api/tasks/:id/solution
// Body: { solution, provider, model, status }
// MUST be registered before /api/tasks/:id.
// ============================================================================
app.post('/api/tasks/:id/solution', async (req, res) => {
  try {
    const { solution, provider, model, status } = req.body || {};
    if (!solution || !provider || !status)
      return res.status(400).json({ error: 'solution, provider, and status are required' });
    if (!['proposed', 'verified', 'partial', 'failed'].includes(status))
      return res.status(400).json({ error: 'status must be proposed|verified|partial|failed' });

    const db = await getPool();
    const result = await db.request()
      .input('id',                sql.Char(4),           req.params.id)
      .input('solution',          sql.NVarChar(sql.MAX), solution)
      .input('solution_provider', sql.NVarChar(40),      provider)
      .input('solution_model',    sql.NVarChar(80),      model ?? null)
      .input('solution_status',   sql.NVarChar(20),      status)
      .execute('dbo.usp_Task_SaveSolution');

    res.json(rowToTask(result.recordset[0]));
  } catch (e) {
    if (e.number === 50002) return res.status(404).json({ error: 'Not found' });
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// PUT /api/tasks/:id/keywords
// Body: [ { keyword, kw_category? }, … ]
// MUST be registered before /api/tasks/:id.
// ============================================================================
app.put('/api/tasks/:id/keywords', async (req, res) => {
  try {
    if (!Array.isArray(req.body))
      return res.status(400).json({ error: 'Expected a JSON array of keyword objects' });

    const db = await getPool();
    const result = await db.request()
      .input('task_id',       sql.Char(4),           req.params.id)
      .input('keywords_json', sql.NVarChar(sql.MAX), JSON.stringify(req.body))
      .execute('dbo.usp_TaskKeywords_Replace');

    res.json(result.recordset);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// GET /api/tasks/:id/keywords
// MUST be registered before /api/tasks/:id.
// ============================================================================
app.get('/api/tasks/:id/keywords', async (req, res) => {
  try {
    const db = await getPool();
    const result = await db.request()
      .input('task_id', sql.Char(4), req.params.id)
      .execute('dbo.usp_TaskKeywords_GetByTask');

    res.json(result.recordset);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// PUT /api/tasks  — bulk replace (MUST be before /:id)
// Body is a JSON array — replaces entire active task set via usp_Task_BulkImport.
// ============================================================================
app.put('/api/tasks', async (req, res) => {
  try {
    if (!Array.isArray(req.body))
      return res.status(400).json({ error: 'Expected a JSON array' });
    const tasks = req.body.map(t => ({
      ...t,
      severity_id: t.severity != null ? SEVERITY_ID[t.severity] : (t.severity_id ?? 2),
      status_id:   t.status   != null ? STATUS_ID[t.status]     : (t.status_id   ?? 1),
      severity:    undefined,
      status:      undefined,
    }));
    const db     = await getPool();
    const result = await db.request()
      .input('json', sql.NVarChar(sql.MAX), JSON.stringify(tasks))
      .execute('dbo.usp_Task_BulkImport');
    res.json(result.recordset.map(rowToTask));
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// PUT /api/tasks/:id  — update a single task (partial update)
// Only fields present in req.body are passed as non-null to the SP;
// absent fields pass null which the SP treats as "leave unchanged".
// ============================================================================
app.put('/api/tasks/:id', async (req, res) => {
  try {
    const body = req.body || {};
    const has  = key => Object.prototype.hasOwnProperty.call(body, key);
    const db   = await getPool();
    const result = await db.request()
      .input('id',          sql.Char(4),          req.params.id)
      .input('title',       sql.NVarChar(500),     has('title')       ? body.title       : null)
      .input('description', sql.NVarChar(sql.MAX), has('description') ? body.description : null)
      .input('severity_id', sql.SmallInt,          has('severity')    ? SEVERITY_ID[body.severity] : null)
      .input('category',    sql.NVarChar(50),      has('category')    ? body.category    : null)
      .input('status_id',   sql.SmallInt,          has('status')      ? STATUS_ID[body.status]     : null)
      .input('agent',       sql.NVarChar(60),      has('agent')       ? body.agent       : null)
      .input('model',       sql.NVarChar(20),      has('model')       ? body.model       : null)
      .input('source',      sql.NVarChar(500),     has('source')      ? body.source      : null)
      .input('plan',        sql.NVarChar(sql.MAX), has('plan')        ? body.plan        : null)
      .input('log_count',   sql.Int,               has('log_count')   ? body.log_count   : null)
      .input('notes',       sql.NVarChar(sql.MAX), has('notes')       ? body.notes       : null)
      .execute('dbo.usp_Task_Update');
    if (result.recordset.length === 0)
      return res.status(404).json({ error: 'Not found' });
    res.json(rowToTask(result.recordset[0]));
  } catch (e) {
    if (e.number === 50002) return res.status(404).json({ error: 'Not found' });
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// DELETE /api/tasks/:id
// ============================================================================
app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const db = await getPool();
    await db.request()
      .input('id', sql.Char(4), req.params.id)
      .execute('dbo.usp_Task_Delete');
    res.sendStatus(204);
  } catch (e) {
    if (e.number === 50002) return res.status(404).json({ error: 'Not found' });
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// GET /api/backups  — repurposed: returns the archive list
// Original response was [{name, size}]. New response is the archive rows with
// a 'name' field (task id + timestamp) for backwards compat with any consumer
// that iterates the array by name.
// ============================================================================
app.get('/api/backups', async (req, res) => {
  try {
    const db     = await getPool();
    const result = await db.request().execute('dbo.usp_Archive_GetAll');
    const rows   = result.recordset.map(row => ({
      name:            `${(row.id || '').trim()}_${row.archived_at}`,
      id:              (row.id || '').trim(),
      title:           row.title ?? '',
      status:          row.status,
      archived_at:     row.archived_at,
      archived_reason: row.archived_reason,
    }));
    res.json(rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// POST /api/backups/:name/restore
// Repurposed: restores a task from TasksArchive back to active Tasks.
// :name must start with the task ID (e.g. "T025_2026-05-...").
// ============================================================================
app.post('/api/backups/:name/restore', async (req, res) => {
  try {
    const db     = await getPool();
    const taskId = req.params.name.substring(0, 4);  // extract "T025" from the name

    // Fetch the archived row
    const archResult = await db.request()
      .input('id', sql.Char(4), taskId)
      .query('SELECT * FROM dbo.TasksArchive WHERE id = @id');

    if (archResult.recordset.length === 0)
      return res.status(404).json({ error: 'Archive record not found' });

    // Reject if already in active Tasks
    const activeResult = await db.request()
      .input('id', sql.Char(4), taskId)
      .query('SELECT 1 FROM dbo.Tasks WHERE id = @id');

    if (activeResult.recordset.length > 0)
      return res.status(409).json({ error: 'Task already exists in active set' });

    const t = archResult.recordset[0];
    await db.request()
      .input('id',          sql.Char(4),          t.id)
      .input('title',       sql.NVarChar(500),     t.title)
      .input('description', sql.NVarChar(sql.MAX), t.description)
      .input('severity_id', sql.SmallInt,          t.severity_id)
      .input('category',    sql.NVarChar(50),      t.category)
      .input('status_id',   sql.SmallInt,          t.status_id)
      .input('agent',       sql.NVarChar(60),      t.agent)
      .input('model',       sql.NVarChar(20),      t.model)
      .input('source',      sql.NVarChar(500),     t.source)
      .input('plan',        sql.NVarChar(sql.MAX), t.plan)
      .input('log_count',   sql.Int,               t.log_count)
      .input('notes',       sql.NVarChar(sql.MAX), t.notes)
      .input('created_at',  sql.DateTime2(3),      new Date(t.created_at))
      .input('updated_at',  sql.DateTime2(3),      new Date(t.updated_at))
      .execute('dbo.usp_Task_Insert');

    res.json({ restored: taskId, tasks: 1 });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// GET /api/solutions/search
// Query params: keywords (CSV, required), category (optional),
//               match ('any'|'all', default 'any'), archived ('0'|'1', default '1')
// ============================================================================
app.get('/api/solutions/search', async (req, res) => {
  try {
    const { keywords, category, match, archived } = req.query;
    if (!keywords || !keywords.trim())
      return res.status(400).json({ error: 'keywords query param is required' });

    const db = await getPool();
    const result = await db.request()
      .input('keywords_csv',     sql.NVarChar(500), keywords)
      .input('kw_category',      sql.NVarChar(40),  category  || null)
      .input('match_mode',       sql.NVarChar(10),  match     || 'any')
      .input('include_archived', sql.Bit,           archived === '0' ? 0 : 1)
      .execute('dbo.usp_Solution_Search');

    res.json(result.recordset);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ============================================================================
// Startup — validate DB connectivity before accepting requests
// ============================================================================
async function start() {
  try {
    await getPool();
    app.listen(PORT, () => {
      console.log(`HA Task Board running at http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('Fatal: cannot connect to SQL Server:', err.message);
    process.exit(1);
  }
}

start();
