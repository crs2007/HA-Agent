# HA Agent — BMAD Multi-Agent System for Home Assistant

**Version:** 2026.03.23.0
**Release Date:** 2026-03-23

> **Repo:** [crs2007/HA-Agent](https://github.com/crs2007/HA-Agent) · **HA Config:** local only (live HA instance is source of truth, no GitHub mirror yet)

A [BMAD-METHOD](https://github.com/bmadcode/BMAD-METHOD) project with four specialized AI agents for managing a Home Assistant smart home system via Claude Code.

## What This Is

This repo contains the Claude Code configuration, skills, and knowledge base for AI-assisted Home Assistant management. The agents can read live HA state, control devices, manage automations, and keep the config repo in sync — all through MCP-connected tools.

**HA Instance:** Home Assistant OS on Proxmox VM 102 (node `HOME-LAB`) — migrated from RPi4 on 2026-04-16
**Scale:** 121 automations · 104 scripts · 2,600+ entities · 14 areas
**Location:** Hod HaSharon, Israel

## The Four Agents

| Agent | Slash Command | Persona | Responsibilities |
|-------|--------------|---------|-----------------|
| **Dashboard Designer** | `/ha-dashboard-designer` | Noa | Lovelace dashboards, Mushroom cards, Hebrew RTL layouts, glassmorphism UI |
| **Developer** | `/ha-developer` | Dev | Automations, scripts, bug fixes, version control, work watchman PRs |
| **Reviver** | `/ha-reviver` | Watch | Watchman reports, entity health audits, GitHub Issues/PRs for broken references |
| **Reviewer** | `/ha-reviewer` | Quinn-HA | Review watchman PRs, validate config changes, approve/reject |

Standard BMAD agents (`/bmad-architect`, `/bmad-dev`, `/bmad-pm`, etc.) are also available.

## Prerequisites

1. **Claude Code** installed and running
2. **HASS_TOKEN** environment variable set to a long-lived HA access token
3. MCP servers configured (see `.claude/settings.json`)

## MCP Servers

Two MCP servers bridge Claude Code to Home Assistant:

- **ha-mcp** *(primary)* — ~96 tools: entity states, service calls, dashboard CRUD, automation management
- **homeassistant** *(fallback)* — HA native MCP for Assist pipeline tools

## Quick Start

```bash
# Set your HA token before launching
export HASS_TOKEN=your_long_lived_token_here

# Launch Claude Code in this directory
claude
```

Then invoke an agent:
- `/ha-developer` — to build or fix automations
- `/ha-dashboard-designer` — to design or update dashboards
- `/ha-reviver` — to run a health check / Watchman audit

## Git Workflow — Live-Instance-First Strategy

The live HA instance is the source of truth. GitHub is a mirror.

1. Before any config change, compare local repo with the live HA config via MCP
2. Sharon may edit directly in HA (UI / File Editor add-on) — always check for drift
3. After changes: commit locally (no GitHub remote yet — push when repo is created)

**Commit prefixes:** `[automation]` · `[script]` · `[fix]` · `[dashboard]` · `[config]`
**Never commit:** `secrets.yaml` · `.storage/` · `home-assistant_v2.db`

## Cross-Agent Handoff

Agents don't call each other directly — Sharon orchestrates. Standard handoff pattern:

```
HANDOFF → [target-agent]: [task description]
```

Typical flows:
- Reviver finds broken entities → creates draft PRs → Developer implements fixes → Reviewer validates
- Developer adds new entities → Dashboard Designer adds cards

## Project Structure

```
HA_Agent/
├── CLAUDE.md                    # Agent instructions & conventions
├── _bmad/
│   ├── bmm/
│   │   ├── knowledge/           # HA-specific knowledge base
│   │   │   ├── ha-coding-conventions.md
│   │   │   ├── ha-dashboard-rules.md
│   │   │   ├── ha-hebrew-labels.md
│   │   │   └── ha-system-overview.md
│   │   └── workflows/           # BMAD workflow definitions
│   └── _memory/                 # Agent memory/context
└── .claude/
    ├── skills/                  # Skill definitions (agents + workflows)
    └── settings.json            # MCP server config & permissions
```

## Key Conventions

- **Notifications:** Use `script.smart_announcement_universal_notifier` (not direct TTS)
- **Tuya devices:** Prefer `tuya_local` entity over `tuya` cloud entity
- **Room automation:** Check room hold boolean before room-specific actions
- **Automations:** Use `continue_on_error: true`, explicit `mode:`, native constructs first
- **Language:** Hebrew primary, English secondary

Full details in [`_bmad/bmm/knowledge/`](_bmad/bmm/knowledge/).
