# Using the BMAD HA agents in the VS Code Agents window

The [VS Code **Agents window**](https://code.visualstudio.com/docs/agents/agents-window) is an
agent-first surface that runs sessions across workspaces. It supports three agent types —
**Claude Agent**, **Copilot CLI**, and **Copilot Cloud** — and a *Customizations* panel that
surfaces custom agents, instructions, hooks, and MCP servers.

This repo is wired so the BMAD HA personas, MCP tools, and guardrails work under **all** agent
types.

## Opening the window

- Command Palette → `Chat: Open Agents Window`, or
- Terminal: `code --agents`, or
- Browser: `https://insiders.vscode.dev/agents`

Then pick a **workspace** (`E:\GitHub\HA_Agent`, local folder) and an **agent type**. Choose
**folder isolation** to edit the workspace directly, or **worktree isolation** for a throwaway
git worktree — worktree is recommended when an agent will touch git, since the repo's git-guard
hooks assume a clean working tree.

## What each agent type reads

| Capability | Claude Agent | Copilot CLI / Cloud |
|---|---|---|
| Repo instructions | `CLAUDE.md` | `AGENTS.md` |
| Personas | `.claude/skills/ha-*/SKILL.md` (`/ha-developer`, …) | `.github/agents/*.agent.md` (agent dropdown) |
| MCP servers | `.mcp.json` (with secrets, gitignored) | `.vscode/mcp.json` (secret-free, `${input:}`) |
| Hooks/guardrails | `.claude/settings.json` | encoded in `AGENTS.md` + each `.agent.md` |

### Claude Agent
Works out of the box — it runs Claude Code, so `CLAUDE.md`, the `/ha-*` skills, the
`.claude/settings.json` hooks, and `.mcp.json` are all already in effect. Invoke a persona the
usual way (`/ha-developer`, `/ha-dashboard-designer`, `/ha-reviver`, `/ha-reviewer`,
`/ha-task-manager`).

### Copilot CLI / Cloud
The five personas appear in the agent dropdown (sourced from `.github/agents/*.agent.md`):
**Dev**, **Noa**, **Watch**, **Quinn-HA**, **Tix**. Repo-wide rules come from `AGENTS.md`.
MCP tools come from `.vscode/mcp.json`.

> Copilot Cloud only runs on GitHub-backed repositories. This repo has no GitHub remote yet, so
> use **Copilot CLI** (local) or the **Claude Agent** until a remote exists.

## First-run MCP secrets (Copilot only)

`.vscode/mcp.json` contains **no secrets** — credentials are requested via `${input:...}`
prompts the first time each server starts (HA token, GitHub PAT, SSH password, SQL password,
Context7/Tavily/Immich keys). VS Code stores them in its secret storage after that. The Claude
Agent keeps using `.mcp.json` and is unaffected.

Values to have ready (live copies live in the gitignored `.mcp.json`): `ha-mcp-url`,
`ha-token`, `github-pat`, `ssh-password`, `mssql-password`, `context7-key`, `tavily-key`,
`immich-key`.

## Guardrail reminder

Every persona restates the **#1 rule**: the live HA instance is the source of truth — pull live
config before editing any `lovelace.dashboard_*` or HA config file (`tools/pull_dashboard.js`
or MCP), or you will overwrite Sharon's UI edits. See [`AGENTS.md`](../AGENTS.md).

## Maintenance

The source of truth for persona behavior stays in `_bmad/bmm/agents/*.md` and
`_bmad/bmm/config.yaml`. The `.github/agents/*.agent.md` and `.claude/skills/ha-*/SKILL.md`
files are thin wrappers — when a persona changes, update the BMAD agent file and re-sync both
wrappers. The `model:` names in each `.agent.md` are best-effort; adjust them to match the model
names available in your Copilot subscription if the window reports an unknown model.
