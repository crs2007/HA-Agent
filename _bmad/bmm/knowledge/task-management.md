# Task Management Knowledge — HA Task Manager (Tix)

This file is loaded by the `ha-task-manager` agent at activation. It defines the rules
Tix uses for triage, routing, status management, and pipeline health reporting.

---

## 1. Severity Definitions and Escalation Rules

| Severity | Meaning | Escalation | Model | Target Resolution |
|----------|---------|-----------|-------|-------------------|
| **critical** | Pipeline-blocking. HA system broken, automation affecting safety/security, or data loss risk. | Surface to `{user_name}` immediately before routing. | opus | Same session |
| **high** | Broken automation, dead entity reference, failing script, regression in active flow. | Assign to primary agent. Flag in pipeline report. | opus | Within 2 sessions |
| **medium** | Watchman finding, dashboard card broken, non-critical config issue, minor regression. | Assign to primary agent. Normal queue. | sonnet | Within the week |
| **low** | Cleanup, orphaned helper, cosmetic dashboard issue, housekeeping. | Assign to primary agent. Low priority. | sonnet | No urgency |

**Escalation rule for critical tasks:**
Before any routing, add to the task `notes` field:
```
ESCALATED: Flagged to {user_name} — {current ISO timestamp}
```
Then surface the task at the top of any triage or report output.

---

## 2. Status Progression

Valid transitions:

```
open
 │
 ├──► in-progress ──► done
 │         │
 │         ├──► dismissed   (decided not to implement)
 │         └──► ignored     (acknowledged, no action, may revisit later)
 │
 ├──► planned              (scheduled for a future session, not yet active)
 │
 └──► dismissed            (closed before starting — won't fix)

done / dismissed / ignored / planned
 └──► archived             (terminal state — set only by CL cleanup)
```

**Rules:**
- Never skip `in-progress` when moving to `done` unless the fix was trivially confirmed in the same breath.
- `dismissed` = decided not to implement. `ignored` = acknowledged but deprioritized indefinitely.
- `archived` is terminal. Only the CL (Cleanup) menu item should set this in bulk.
- Moving backwards (e.g., `done` → `in-progress`) is allowed if a regression is discovered.

---

## 3. Category-to-Agent Routing Table

Used by AT (Auto-Triage) to assign `unassigned` tasks.

| Category | Primary Agent | Escalation Agent | Escalation Condition |
|----------|--------------|-----------------|----------------------|
| automation | ha-developer | ha-reviewer | severity = critical |
| script | ha-developer | ha-reviewer | severity = high or critical |
| fix | ha-developer | ha-reviewer | severity = high or critical |
| dashboard | ha-dashboard-designer | ha-developer | config-level errors only |
| config | ha-developer | ha-reviewer | severity = critical |

**Secondary model override:** When escalating to `ha-reviewer`, also set `model = opus`.

---

## 4. Model Selection

| Severity | Agent has model=unassigned? | Assign model |
|----------|-----------------------------|-------------|
| critical | yes | opus |
| high | yes | opus |
| medium | yes | sonnet |
| low | yes | sonnet |
| any | no (already set) | leave unchanged |

---

## 5. Pipeline Health Thresholds

Calculate pipeline health after every `PR` (Pipeline Report) invocation.

| Metric | Healthy | Warning | Critical Pipeline |
|--------|---------|---------|-------------------|
| `critical_open` | 0 | ≥ 1 | ≥ 3 |
| Active tasks (non-terminal) | < 20 | 20–40 | > 40 |
| `unassigned` active tasks | 0 | 1–5 | > 5 |
| Throughput (done / total × 100) | ≥ 60 % | 40–59 % | < 40 % |

**Throughput formula:**
```
throughput = (count of done tasks / total tasks) × 100
```
Only count tasks that exist — an empty board is reported as N/A, not 100 %.

**Unassigned reminder:** If `unassigned > 5` at activation time, remind `{user_name}` to run
`[AT] Auto-Triage` before proceeding with other work.

---

## 6. Auto-Triage Algorithm (step-by-step)

Tix follows this deterministic sequence for AT:

1. **Fetch ALL tasks** using MCP `task_list()` (no filter). Store as `all_tasks`.
2. **Identify candidates:** filter `all_tasks` where `status = open` AND `agent = unassigned`.
   Call this `candidates`.
3. **Surface criticals first:** For each `candidate` where `severity = critical`:
   - Inform `{user_name}` immediately.
   - Append escalation note to `candidate.notes`.
4. **Apply routing table:** For each `candidate`:
   - Look up `candidate.category` in the routing table.
   - Determine `primary_agent` and whether escalation applies.
   - Set `candidate.agent` to `primary_agent` (or escalation agent if condition met).
   - If model is still `unassigned`, set it per the model selection table.
5. **Show diff table** — display proposed assignments before writing:
   ```
   | ID    | Title           | Severity | Category | → Agent          | → Model |
   |-------|-----------------|----------|----------|-----------------|---------|
   | T012  | Fix motion lamp | high     | fix      | ha-reviewer     | opus    |
   | T015  | Dashboard card  | medium   | dashboard| ha-dashboard-.. | sonnet  |
   ```
6. **Confirm:** Ask `{user_name}` for explicit `y/n` confirmation.
7. **Write atomically:** Merge `candidates` back into `all_tasks` (replace by ID). Then
   call MCP `task_bulk_import({ tasks: all_tasks })`.
   **Never import only the candidate subset** — that would wipe other tasks.
8. **Confirm result:** Call MCP `task_stats()` and display updated counts.

---

## 7. Cleanup Algorithm (CL)

1. Fetch all tasks via MCP `task_list()`.
2. Identify candidates: `status` is `done` OR `dismissed`, AND
   `updated_at` is more than 7 days before now (compare ISO timestamps).
3. Display count and table of candidates to `{user_name}`.
4. Ask for explicit `y/n` confirmation.
5. On yes: call MCP `task_archive({ id, archived_reason: "cleanup" })` for each candidate.
   For 3+ candidates, prefer MCP `task_bulk_import({ tasks: full_remaining_array })` after
   removing the archived candidates from the full array (more atomic).

---

## 8. Task Operations Quick Reference

### Primary: mssql MCP tools (use these — no server process required)

| MCP Tool | Purpose | Required params | Optional params |
|----------|---------|-----------------|-----------------|
| `task_list` | List/filter tasks | — | status, agent, severity, category, q |
| `task_get` | Fetch one task | id | — |
| `task_create` | Create task, auto-assigns ID | title | description, severity, category, status, agent, model, source, plan, notes |
| `task_update` | Partial update (omitted = unchanged) | id | any other field |
| `task_archive` | Move to archive | id | archived_reason (manual\|cleanup\|bulk-replace) |
| `task_delete` | Hard-delete | id | — — **avoid, prefer task_archive** |
| `task_stats` | Pipeline health counts + breakdowns | — | — |
| `task_bulk_import` | Atomic replace all tasks | tasks (array) | — |
| `task_archive_list` | List archived tasks | — | — |
| `task_audit` | Column-level audit trail | task_id | — |

### Fallback: REST API (use when MCP unavailable; also powers the web UI)

**Default URL:** `http://localhost:3001` — served by the always-on `ha-task-server` Docker
container (auto-starts with Docker Desktop; no manual start needed). If it's down, bring it back
with `docker start ha-task-server`.

| Verb | Path | Purpose |
|------|------|---------|
| GET | `/api/tasks` | All tasks. Supports `?status=`, `?agent=`, `?severity=`, `?category=`, `?q=` |
| GET | `/api/tasks/stats` | Summary: total, active, critical_open, unassigned, by_status/severity/agent/category |
| POST | `/api/tasks` | Create. `title` required. Enum validation enforced. |
| PUT | `/api/tasks/:id` | Update single task. Enum validation enforced. |
| DELETE | `/api/tasks/:id` | Hard-delete (prefer archive via CL instead). |
| PUT | `/api/tasks` | Bulk replace entire array. Used by AT and CL. |
