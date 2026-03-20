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
- Raspberry Pi is source of truth
- Commit prefixes: `[automation]`, `[script]`, `[fix]`, `[dashboard]`, `[config]`
- Never commit: `secrets.yaml`, `.storage/`, `home-assistant_v2.db`
