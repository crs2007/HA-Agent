# AGENTS.md

Cross-tool agent instructions for the **BMAD HA system**. This is the tool-neutral
companion to [`CLAUDE.md`](CLAUDE.md): Claude Code reads `CLAUDE.md`, while VS Code
Copilot agents (CLI/Cloud) and other AGENTS.md-aware tools read this file. The two are
kept in sync — `CLAUDE.md` is the full Claude-specific source of truth, `AGENTS.md` is the
shared subset every agent must honor.

## Project Overview

A BMAD-METHOD project with specialized AI agents that manage Sharon's Home Assistant system.

- **HA Instance:** http://homeassistant.local:8123/
- **Platform:** Home Assistant OS on Proxmox VM 102 (node `HOME-LAB`, 2 vCPU / 12 GB RAM). Migrated from RPi4 on 2026-04-16.
- **Location:** Hod HaSharon, Israel | Timezone: Asia/Jerusalem
- **Scale:** 121 automations, 104 scripts, 2,600+ entities, 14 areas
- **HA Config Local:** `E:\GitHub\Home-Assistant_Config` (no GitHub mirror yet — the live HA instance is sole source of truth)
- **Language:** Hebrew primary, English secondary

## ⛔ CRITICAL — Live-Instance-First Workflow (the #1 rule)

**The live HA instance is the source of truth. No GitHub mirror exists yet.**

The files in `_bmad/bmm/knowledge/inventory/raw/` (especially `lovelace.dashboard_*`) are
**point-in-time snapshots**. They are NOT live. Sharon edits HA directly via the UI — the
local snapshot can be weeks behind.

**BEFORE editing any `lovelace.dashboard_*` file you MUST:**
1. Pull the current version from the live HA instance via `tools/pull_dashboard.js` (or read live config via MCP)
2. Overwrite the local snapshot with the live version
3. THEN apply your changes
4. THEN push back with `tools/push_dashboard.js`

**Skipping step 1 will silently overwrite Sharon's recent changes. This has happened — do not repeat it.**

For any config change: compare the local repo with the live HA config (via MCP) first. If
they differ, show the diff and ask Sharon which version to keep. Always show YAML before
applying and get explicit confirmation.

## The Agents

Personas are defined in `_bmad/bmm/agents/` and surfaced to each tool through thin wrappers:
Claude Code uses `.claude/skills/ha-*/SKILL.md`; VS Code Copilot uses `.github/agents/*.agent.md`.

| Persona | Name | Purpose | Model |
|---------|------|---------|-------|
| Dashboard Designer | Noa | Lovelace dashboards, Mushroom cards, Hebrew RTL, glassmorphism | sonnet |
| Developer | Dev | Automations, scripts, bug fixes, version control, watchman PRs | sonnet |
| Reviver | Watch | Watchman reports, entity health, GitHub Issues/PRs | sonnet |
| Reviewer | Quinn-HA | Review watchman PRs, validate config, approve/reject | opus |
| Task Manager | Tix | BMAD pipeline task queue (triage, routing, reporting) | sonnet |

Each agent must, on activation: load `_bmad/bmm/config.yaml` (session variables like
`{user_name}`, `{communication_language}`, `{ha_config_repo}`), load its mapped knowledge
files from `_bmad/bmm/knowledge/`, connect to HA via MCP, then present a numbered menu and
**wait for input — never auto-execute**.

## MCP Connection

- **ha-mcp** (primary): entity states, service calls, dashboard CRUD, automation management
- **homeassistant** (fallback): HA native MCP / Assist pipeline tools
- **proxmox** (stdio): Proxmox VE management — VM/LXC lifecycle, snapshots, storage
- **mssql**: TaskManager DB — Tix's task pipeline (primary data path)
- Plus `github`, `context7`, `tavily`, `ssh`, `playwright`, `immich`

Claude Code reads MCP servers from `.mcp.json`. VS Code Copilot agents read them from
`.vscode/mcp.json`, which is **secret-free** — credentials are prompted via `${input:...}`
on first launch, never committed.

## Git Workflow

1. **Before any config change:** compare local repo with live HA config via MCP; ask Sharon if they differ.
2. **Sharon may edit directly in HA** via UI / File Editor — always check for drift.
3. **After changes:** commit locally (push when a GitHub remote is created).
4. **Commit prefixes:** `[automation]`, `[script]`, `[fix]`, `[dashboard]`, `[config]`, `[agents]`, `[docs]`
5. **Never commit:** `secrets.yaml`, `.storage/`, `home-assistant_v2.db`, `.env`, raw inventory snapshots, `.mcp.json`, `.vscode/mcp.json` — and never paste tokens/passwords into tracked files.

## Cross-Agent Handoff — PR-Driven Pipeline

Agents don't call each other directly; Sharon orchestrates. Primary flow uses GitHub PRs:

1. **Reviver** runs Watchman → creates draft PRs (critical/high/medium) or Issues (low)
2. **Developer** picks up a draft PR → implements the fix → marks ready for review
3. **Reviewer** validates via MCP + checklist → approves or requests changes
4. **Sharon** merges approved PRs

Handoff note format: `HANDOFF → [target-agent]: [task description]`

## Key Conventions

- **Notifications:** use `script.smart_announcement_universal_notifier` (not direct TTS)
- **Tuya devices:** prefer `tuya_local` entity over `tuya` cloud entity
- **Room automation:** check the room hold boolean before room-specific actions
- **Automations:** `continue_on_error: true`, explicit `mode:`, native constructs before Jinja2 templates
- **Entity references:** prefer `entity_id` over `device_id` (except Z2M device triggers)

## Versioning

CalVer `YYYY.MM.DD.Minor` (e.g., `2026.06.06.0`). Minor starts at `0` and increments for
multiple same-day releases. Update **Version** and **Release Date** in `README.md` on release.

See `_bmad/bmm/knowledge/` for full coding conventions, dashboard rules, and system overview.
