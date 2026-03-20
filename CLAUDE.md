# HA Agent — BMAD Multi-Agent System for Home Assistant

## Project Overview

This is a BMAD-METHOD project with three specialized AI agents for managing Sharon's Home Assistant system.

- **HA Instance:** http://homeassistant.local:8123/
- **Platform:** Home Assistant OS on Raspberry Pi 4
- **Location:** Hod HaSharon, Israel | Timezone: Asia/Jerusalem
- **Scale:** 121 automations, 104 scripts, 2,600+ entities, 14 areas
- **HA Config Repo:** `crs2007/Home-Assistant_Config` (local: `E:\GitHub\Home-Assistant_Config`)

## BMAD Agents

Three custom HA agents are available alongside the standard BMAD agents:

| Agent | Invoke | Persona | Purpose |
|-------|--------|---------|---------|
| Dashboard Designer | `/ha-dashboard-designer` | Noa | Design & maintain Lovelace dashboards, Mushroom cards, Hebrew RTL layouts |
| Developer | `/ha-developer` | Dev | Build automations, scripts, fix bugs, manage version control |
| Reviver | `/ha-reviver` | Watch | Run Watchman reports, create GitHub Issues, health monitoring |

Standard BMAD agents (`/bmad-help`, `/bmad-dev`, `/bmad-architect`, etc.) are also available.

## MCP Connection

Two MCP servers connect agents to Home Assistant:
- **ha-mcp** (primary): Rich toolset (~96 tools) for entity states, service calls, dashboard CRUD, automation management
- **homeassistant** (fallback): HA native MCP for Assist pipeline tools

The `HASS_TOKEN` environment variable must be set before launching Claude Code.

## Git Workflow — Pi-First Strategy

**The Raspberry Pi is the source of truth.** The GitHub repo is a mirror.

1. **Before any config change:** Compare local repo with live Pi config (via MCP). If they differ, ask Sharon which version to keep.
2. **Sharon may edit directly on the Pi** via HA UI or File Editor add-on. Always check for drift.
3. **After changes:** Commit locally, push to `crs2007/Home-Assistant_Config`
4. **Commit prefixes:** `[automation]`, `[script]`, `[fix]`, `[dashboard]`, `[config]`
5. **Never commit:** `secrets.yaml`, `.storage/`, `home-assistant_v2.db`

## Cross-Agent Handoff

Agents don't call each other directly. Sharon orchestrates. However:
- **Reviver** creates GitHub Issues → **Developer** picks them up
- **Developer** creates/modifies entities → **Dashboard Designer** updates cards
- When one agent identifies work for another, output a handoff note:
  ```
  HANDOFF → [target-agent]: [task description]
  ```

## Key Conventions

- **Notifications:** Use `script.smart_announcement_universal_notifier` (not direct TTS)
- **Tuya devices:** Prefer `tuya_local` entity over `tuya` cloud entity
- **Room automation:** Check room hold boolean before room-specific actions
- **Automations:** Use `continue_on_error: true`, explicit `mode:`, native constructs first
- **Entity references:** Prefer `entity_id` over `device_id` (except Z2M device triggers)
- **Language:** Hebrew primary, English secondary

See `_bmad/bmm/knowledge/` for full coding conventions, dashboard rules, and system overview.
