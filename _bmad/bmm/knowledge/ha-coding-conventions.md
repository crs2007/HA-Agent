# Home Assistant Coding Conventions

## YAML Formatting
- 2-space indentation consistently
- Lowercase keys (except where HA requires otherwise)
- snake_case for entity names and IDs
- Quote strings with special characters or spaces
- `|` for multi-line strings, `>` for folded strings
- Lines under 120 characters when possible

## Automation Rules

### Mode Selection (ALWAYS set explicitly)
| Scenario | Mode | Why |
|----------|------|-----|
| Motion-activated light with timeout | `restart` | Re-triggers must reset the off-timer |
| Sequential processing (boiler, locks) | `queued` | Actions must complete in order |
| Independent per-entity actions | `parallel` | Multiple instances simultaneously |
| One-shot events, notifications | `single` | Prevent duplicate execution |

### Required Fields
- `alias` — descriptive name
- `description` — for complex automations
- `mode` — always explicit
- `continue_on_error: true` — on all non-critical action steps

### Native Constructs First
Before writing Jinja2, check if a native construct works:
- `{{ states('x') | float > 25 }}` → use `numeric_state` with `above: 25`
- `{{ is_state('x', 'on') and is_state('y', 'on') }}` → use `condition: and`
- `{{ now().hour >= 9 }}` → use `condition: time` with `after: "09:00:00"`
- `wait_template: "{{ is_state(...) }}"` → use `wait_for_trigger` with state trigger

### Built-in Helpers Over Templates
- Sum/average → `min_max` integration
- Binary any-on/all-on → `group` helper
- Rate of change → `derivative` integration
- Cross-threshold → `threshold` integration (has hysteresis)
- Consumption tracking → `utility_meter` helper

### When Templates ARE Appropriate
Complex multi-threshold logic (ceiling fan power signatures), string manipulation, dynamic entity building, combining multiple unrelated state sources.

### Template Error Handling
Always use `| float(0)`, `| int(0)`, `| default(0)` fallbacks. Handle `unavailable`/`unknown` states. Use `is_state()` over `states()` for boolean checks.

## Room Automation Hold Check
**ALWAYS ask Sharon** whether automation should be skipped when the room's stop toggle is on:
- Office: `input_boolean.toggle_holdoffice`
- Outdoor: `input_boolean.toggle_holdoutdoor`
- Lenny & Miley: `input_boolean.lennyroom_stopautomation`
- Ofri: `input_boolean.ofriroom_stopautomation`
- Parents: `input_boolean.parentsroom_stopautomation`

## Notification Preference
**Prefer `script.smart_announcement_universal_notifier`** over direct `tts.speak` calls. It handles presence, auto-volume, DND, priority, and multi-platform delivery.

## Dual-Integration Strategy (Native + HACS Side-by-Side)

Sharon prefers native HA OS integrations as the baseline. However, when the native integration does not expose all device entities or features, a well-established HACS/community integration is added **alongside** the native one — not as a replacement.

**Rule:** When both a native and a HACS integration exist for the same device:
- Use the **native integration** for any entity it handles well
- Use the **HACS integration** only for the specific features/entities the native one lacks
- Document which entities come from which integration so future refactoring doesn't break things
- When the native integration catches up (adds the missing feature), migrate off the HACS one

**Known dual-integration devices:**

| Device | Native Integration | HACS / Community Integration | Why HACS is needed |
|--------|-------------------|-----------------------------|--------------------|
| Alexa | Alexa (HA native) | Alexa Media Player (HACS) | Native doesn't support volume control yet |
| Govee LED | Matter (native) | Govee to MQTT Bridge (app → MQTT) | Native Matter lacks LED scene/effect control |
| Tuya | Tuya Cloud (`tuya`) | Tuya Local (`tuya_local` / `localtuya`) | Local is faster, no cloud dependency |
| Samsung TV | — | samsungtv_tizen (HACS, patched) | Native Samsung integration is limited |

When referencing these devices in automations, check which integration provides the entity you need. Don't assume all entities come from one source.

## Tuya Device Preference
**Always prefer Tuya Local** (`tuya_local` domain) when available. Fall back to cloud Tuya only when no local entity exists.

## Entity References
**Prefer `entity_id` over `device_id`** for portability. Exception: Z2M autodiscovered device triggers are acceptable.

## Anti-Patterns to Avoid
| Anti-pattern | Correct approach |
|---|---|
| Template condition referencing `trigger` in conditions section | Move to actions section with `if:` |
| `wait_template` for future events | `wait_for_trigger` (event-driven, not polling) |
| `device_id` in triggers/actions | `entity_id` (except Z2M device triggers) |
| `mode: single` for motion lights | `mode: restart` |
| Template sensor for sum/mean | `min_max` helper |
| Colorloop with rgb_color | Only `effect: colorloop` |
| `parallel:` outside `sequence:` | Must be a step within `sequence:` |
| `device_type: turn_on` with `percentage` | Use `action: fan.turn_on` service call |

## Safe Refactoring Workflow
1. Impact analysis: `grep -rn "old_entity_id"` across ALL config files
2. Check groups, conditions, helpers
3. Make the change in all locations
4. Verify: second grep for zero remaining references
5. Test: `ha core check` and test affected automations

## Git Conventions
- The live HA instance is source of truth (currently hosted on Proxmox VM 102)
- Commit prefixes: `[automation]`, `[script]`, `[fix]`, `[dashboard]`, `[config]`
- Never commit: `secrets.yaml`, `.storage/`, `home-assistant_v2.db`

## MCP Tool Reference (ha-mcp v7.x)

Available via the `ha-mcp` MCP server (homeassistant-ai/ha-mcp, ~85 tools).
Requires `ha_mcp_tools` custom component in HA for file system and YAML editing tools.

| Need | Tool | Key Parameters |
|---|---|---|
| Get single automation | `ha_get_automation` | `entity_id` or `alias` |
| Get single script | `ha_get_script` | `entity_id` |
| Search config for entity | `ha_search_config_deep` | `query` |
| Validate HA config | `ha_check_config` | — |
| Read HA error log | `ha_get_logs` | `level`, `search`, `limit` |
| Get automation trace | `ha_get_automation_traces` | `automation_id` |
| Render Jinja2 template | `ha_eval_template` | `template` |
| Pull dashboard config | `ha_config_get_dashboard` | `dashboard_path` |
| Push dashboard config | `ha_config_set_dashboard` | `dashboard_path`, `config` |
| Read config file | `ha_read_file` | `path` (requires ha_mcp_tools) |
| Edit YAML config | `ha_config_set_yaml` | `path`, `content` (requires ha_mcp_tools) |
| Entity registry query | `ha_get_entity_registry` | `domain`, `area_id` |
| Area registry query | `ha_get_area_registry` | — |
| Call Watchman report | `call_service` | `domain: watchman`, `service: report` |
