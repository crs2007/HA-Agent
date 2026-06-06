# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Cross-tool note:** `AGENTS.md` mirrors the shared subset of this file for non-Claude tools (VS Code Copilot agents, etc.). Keep the two in sync — `CLAUDE.md` is the Claude-specific source of truth. For running these agents in the VS Code Agents window, see `docs/vscode-agents-window.md`.

## Project Overview

This is a BMAD-METHOD project with four specialized AI agents for managing Sharon's Home Assistant system.

- **HA Instance:** http://homeassistant.local:8123/
- **Platform:** Home Assistant OS on Proxmox VM 102 (node `HOME-LAB`, 2 vCPU / 12 GB RAM). Migrated from RPi4 on 2026-04-16.
- **Location:** Hod HaSharon, Israel | Timezone: Asia/Jerusalem
- **Scale:** 121 automations, 104 scripts, 2,600+ entities, 14 areas
- **HA Config Local:** `E:\GitHub\Home-Assistant_Config` (no GitHub mirror yet — the live HA instance is sole source of truth)

## BMAD Agents

Four custom HA agents, plus standard BMAD agents (`/bmad-help`, `/bmad-dev`, `/bmad-architect`, etc.):

| Agent | Invoke | Persona | Model | Purpose |
|-------|--------|---------|-------|---------|
| Dashboard Designer | `/ha-dashboard-designer` | Noa | Sonnet | Design & maintain Lovelace dashboards, Mushroom cards, Hebrew RTL layouts |
| Developer | `/ha-developer` | Dev | Sonnet | Build automations, scripts, fix bugs, manage version control, work watchman PRs |
| Reviver | `/ha-reviver` | Watch | Sonnet | Run Watchman reports, create GitHub Issues/PRs, health monitoring |
| Reviewer | `/ha-reviewer` | Quinn-HA | Opus | Review watchman PRs, validate config changes, approve/reject |

> **Model selection:** Set the session model with `/model sonnet` or `/model opus` before invoking an agent.

## Architecture

### Agent Activation Flow

Every agent follows the same mandatory activation sequence (defined in `_bmad/bmm/agents/{agent}.md`):

1. Load config from `_bmad/bmm/config.yaml` — stores `{user_name}`, `{communication_language}`, `{ha_config_repo}`, `{ha_config_local}` as session variables
2. Load agent-specific knowledge files from `_bmad/bmm/knowledge/`
3. Connect to Home Assistant via MCP
4. Display greeting and numbered menu
5. Wait for user input (never auto-execute)

Variables like `{ha_config_repo}`, `{project-root}`, `{user_name}` are resolved from `config.yaml` at activation time. Agent definitions, checklists, and templates all use these variables.

### Key Directories

| Path | Purpose |
|------|---------|
| `_bmad/bmm/agents/` | Agent persona definitions (XML-in-markdown, menu items, rules) |
| `_bmad/bmm/knowledge/` | Domain knowledge loaded at activation (coding conventions, dashboard rules, system overview) |
| `_bmad/bmm/knowledge/inventory/` | Full HA inventory snapshots (areas, automations, scripts, devices, entities) |
| `_bmad/bmm/checklists/` | Step-by-step workflows (automation-review, reviver-workflow, PR creation/review) |
| `_bmad/bmm/templates/` | YAML/markdown templates for automations, scripts, issues, PRs |
| `.claude/skills/ha-*/SKILL.md` | Thin skill wrappers that load agent definitions from `_bmad/bmm/agents/` |
| `_bmad/bmm/config.yaml` | Central config — agent variables, HA connection details, user preferences |

### Agent ↔ Knowledge Mapping

- **Developer** loads: `ha-coding-conventions.md`, `ha-system-overview.md`
- **Dashboard Designer** loads: `ha-dashboard-rules.md`, `ha-system-overview.md`, `ha-hebrew-labels.md`
- **Reviver** loads: `ha-system-overview.md`, `reviver-workflow.md`
- **Reviewer** loads: `ha-coding-conventions.md`, `ha-system-overview.md`, `automation-review.md`, `pr-review-workflow.md`

## MCP Connection

Two MCP servers connect agents to Home Assistant:
- **ha-mcp** (primary): ~96 tools for entity states, service calls, dashboard CRUD, automation management
- **homeassistant** (fallback): HA native MCP for Assist pipeline tools
- **proxmox** (stdio): Proxmox VE management at 192.168.68.180:8006 — VM/LXC lifecycle, snapshots, storage

The `HASS_TOKEN` environment variable must be set before launching Claude Code.

## Task Board Service

The Tix task pipeline is backed by the **TaskManager** SQL Server DB (`SQLSERVER2022`). Two interfaces:

- **`mssql` MCP server** (primary): stdio, spawned per session by Claude Code from `.mcp.json`. Connects over TCP with the `HA_Task_DBAccess` SQL login. This is Tix's main data path.
- **`ha-task-server` Docker container** (web UI + REST fallback): the always-on board at `http://localhost:3001`, replacing the old manual `npm run tasks`. Runs on the Windows PC via Docker Desktop, reaching host SQL Server through `host.docker.internal,1433`.
  - Source: `services/ha-task-server/` (Dockerfile + docker-compose.yml). Password lives in the gitignored `services/ha-task-server/.env`.
  - Start/rebuild: `docker compose -f services/ha-task-server/docker-compose.yml up -d --build`. With `restart: unless-stopped` it auto-starts whenever Docker Desktop launches.
  - `tools/task-server.js` selects its DB driver by env: TCP `mssql` when `MSSQL_SERVER` is set (container), else named-pipe `msnodesqlv8` (Windows host, original behavior).

## Git Workflow — Live-Instance-First Strategy

**The live HA instance is the source of truth.** No GitHub mirror exists yet.

> ### ⛔ CRITICAL — READ BEFORE ANY DASHBOARD OR CONFIG CHANGE
>
> The files in `_bmad/bmm/knowledge/inventory/raw/` (especially `lovelace.dashboard_*`) are **point-in-time snapshots**. They are NOT live. Sharon edits HA directly via the UI — the local snapshot can be weeks behind.
>
> **BEFORE editing any `lovelace.dashboard_*` file you MUST:**
> 1. Pull the current version from the live HA instance via the `tools/pull_dashboard.js` tool (or read live config via MCP)
> 2. Overwrite the local snapshot with the live version
> 3. THEN apply your changes
> 4. THEN push back with `tools/push_dashboard.js`
>
> **Skipping step 1 will silently overwrite Sharon's recent changes.** This has happened — do not repeat it.

1. **Before any config change:** Compare local repo with the live HA config (via MCP). If they differ, ask Sharon which version to keep.
2. **Sharon may edit directly in HA** via the UI or File Editor add-on. Always check for drift.
3. **After changes:** Commit locally (push when a GitHub remote is created)
4. **Commit prefixes:** `[automation]`, `[script]`, `[fix]`, `[dashboard]`, `[config]`, `[agents]`, `[docs]`
5. **Never commit:** `secrets.yaml`, `.storage/`, `home-assistant_v2.db`

## Cross-Agent Handoff — PR-Driven Pipeline

Agents don't call each other directly. Sharon orchestrates. The primary workflow uses GitHub PRs (once `ha_config_repo` is configured in `config.yaml`):

### Watchman PR Pipeline
1. **Reviver** runs Watchman report → creates **draft PRs** (critical/high/medium) or **Issues** (low)
2. **Developer** picks up a draft PR (`[WP]` menu) → implements the fix → marks ready for review
3. **Reviewer** reviews the PR (`[RP]` menu) → validates via MCP + automation checklist → approves or requests changes
4. **Sharon** merges approved PRs

### PR State Machine
- `draft + status:needs-implementation` → Reviver created, awaiting Developer
- `open + status:needs-review` → Developer implemented, awaiting Reviewer
- `status:changes-requested` → Reviewer sent back to Developer
- `approved + agent:reviewer` → Ready for Sharon to merge

### Other Handoffs
- **Developer** creates/modifies entities → **Dashboard Designer** updates cards
- Handoff note format: `HANDOFF → [target-agent]: [task description]`

## Key Conventions

- **Notifications:** Use `script.smart_announcement_universal_notifier` (not direct TTS)
- **Tuya devices:** Prefer `tuya_local` entity over `tuya` cloud entity
- **Room automation:** Check room hold boolean before room-specific actions
- **Automations:** Use `continue_on_error: true`, explicit `mode:`, native constructs first
- **Entity references:** Prefer `entity_id` over `device_id` (except Z2M device triggers)
- **Language:** Hebrew primary, English secondary

See `_bmad/bmm/knowledge/` for full coding conventions, dashboard rules, and system overview.

## Versioning

- **Format:** CalVer `YYYY.MM.DD.Minor` (e.g., `2026.03.23.0`)
- Minor starts at `0` and increments for multiple releases on the same day
- Version and release date are tracked at the top of `README.md`
- When releasing a new version, update both the **Version** and **Release Date** fields in `README.md`
