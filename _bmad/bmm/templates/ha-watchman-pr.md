## Watchman Finding

**Entity:** `{entity_id}`
**Severity:** {CRITICAL|HIGH|MEDIUM|LOW}
**Status:** {unavailable|missing|orphaned}
**Detected:** {date}

## Where Referenced

| File | Line | Context |
|------|------|---------|
| `automations.yaml` | 123 | Trigger in "Automation Name" |
| `scripts.yaml` | 456 | Action in "Script Name" |

## Impact

Describe what breaks or degrades when this entity is missing/unavailable.

## Diagnostic Data

- **Current entity state:** {from MCP query or "not found in HA"}
- **Zigbee device status:** {online/offline/N/A — check Z2M if Zigbee entity}
- **Related entities:** {list any grouped or dependent entities}
- **Last known working state:** {if available from HA history}

## Suggested Fix

- [ ] Option A: Re-add the entity (if accidentally removed)
- [ ] Option B: Update references to use correct entity ID
- [ ] Option C: Remove references (entity no longer needed)

## Developer Checklist

- [ ] Fetch branch to local clone and pull latest from the live HA instance
- [ ] Compare live HA config with branch via MCP
- [ ] Implement fix following HA coding conventions
- [ ] Run config validation via MCP
- [ ] Delete `_watchman-fix.md` from branch
- [ ] Push changes and mark PR as ready for review

## Additional Context

- Related automations/scripts affected: {list}
- Zigbee coordinator: {indoor SLZB-06M / outdoor SLZB-06 / N/A}
- Part of batch: {yes/no — if grouped with related findings}

---
*Created by HA Reviver Agent (Watch) via Watchman report*
