# Automation Review Checklist

Run through this checklist before finalizing any automation or script change.

## Required Fields
- [ ] `alias:` set with descriptive name
- [ ] `description:` included for complex automations
- [ ] `mode:` explicitly set (restart for motion, queued for sequential, single for one-shot, parallel for independent)

## Action Safety
- [ ] `continue_on_error: true` on all non-critical action steps
- [ ] No `parallel:` outside of `sequence:` (must be a step within sequence)

## Room Automation Hold
- [ ] Asked Sharon if room stop boolean should gate this automation
- [ ] If yes: condition checking relevant `input_boolean.*_stopautomation` or `toggle_hold*` added

## Native Constructs
- [ ] No template conditions where `numeric_state`, `state`, or `time` condition would work
- [ ] No `wait_template` where `wait_for_trigger` is appropriate
- [ ] No template sensors where `min_max`, `group`, `threshold`, or `derivative` helper works

## Entity References
- [ ] All references use `entity_id` not `device_id` (exception: Z2M device triggers)
- [ ] Tuya Local entity used when available (not Tuya Cloud)

## Notifications
- [ ] `script.smart_announcement_universal_notifier` used for announcements (not direct TTS)
- [ ] Emergency: `script.emergency_alert_all_channels` for critical alerts

## Template Safety
- [ ] All `float()`, `int()` calls have fallback defaults: `| float(0)`, `| int(0)`
- [ ] `unavailable`/`unknown` states handled
- [ ] No `trigger` references in conditions section (move to actions with `if:`)
- [ ] `is_state()` used over `states()` for boolean checks

## Shabbat/Holiday Awareness
- [ ] Considered whether automation should respect `input_boolean.shabbat_or_hag_state`
- [ ] HebCal sensors checked if time-sensitive

## Config Validation
- [ ] Config validated via `ha core check` or MCP equivalent
- [ ] No colorloop with rgb_color (only `effect: colorloop`)
- [ ] No `device_type: turn_on` with extra parameters (use service call format)

## Version Control
- [ ] Live HA / GitHub drift checked before committing
- [ ] Commit message has category prefix: `[automation]`, `[script]`, `[fix]`, etc.
- [ ] `secrets.yaml` not included in commit
