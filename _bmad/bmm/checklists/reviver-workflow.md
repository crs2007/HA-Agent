# Reviver Workflow Checklist

Step-by-step process for the Reviver (Watch) agent to audit and maintain HA health.

## 1. Run Watchman Report
- [ ] Call `watchman.report` service via MCP
- [ ] Wait for report to complete
- [ ] Retrieve report data (persistent notification or sensor)

## 2. Parse Report
- [ ] Extract list of missing entities
- [ ] Extract list of broken entity references
- [ ] Note which config files reference each broken entity
- [ ] Identify line numbers where possible

## 3. Categorize by Severity
- [ ] **Critical:** Entities in active automations that are `unavailable`/`unknown`
- [ ] **High:** Script references to non-existent entities, broken triggers
- [ ] **Medium:** Dashboard cards with missing entities, template sensor broken refs
- [ ] **Low:** Orphaned helpers not referenced anywhere, unused entities

## 4. Check Zigbee Health (if applicable)
- [ ] Read `sensor.zigbee_network_health` for overall percentage
- [ ] Check `sensor.zigbee_devices_offline` for offline count
- [ ] Read `binary_sensor.zigbee2mqtt_bridge_connected` for bridge status
- [ ] Cross-reference offline Zigbee devices with Watchman findings

## 5. Check Existing GitHub Issues AND PRs
- [ ] Run `gh issue list --repo {ha_config_repo} --label watchman`
- [ ] Run `gh pr list --repo {ha_config_repo} --label watchman --state open`
- [ ] Compare existing issues and PRs with new findings
- [ ] Skip creating duplicates
- [ ] Note issues/PRs that may have been resolved

## 6a. Create GitHub Issues (low-severity only)
For each NEW **low-severity** finding:
- [ ] Title format: `[watchman] {entity_id} — {brief description}`
- [ ] Body follows template at `_bmad/bmm/templates/ha-watchman-issue.md`
- [ ] Labels applied: `watchman` + `severity:low`
- [ ] Includes: entity ID, source file(s), line number(s), suggested fix

## 6b. Create GitHub PRs (critical/high/medium severity)
For each NEW **critical, high, or medium** finding:
- [ ] Follow the PR creation workflow at `_bmad/bmm/checklists/pr-creation-workflow.md`
- [ ] Group related findings by root cause into batch PRs
- [ ] Create branch, diagnostic file, and draft PR via GitHub API
- [ ] Apply labels: `watchman` + `severity:{level}` + `agent:reviver` + `status:needs-implementation`

## 7. Track Resolution
- [ ] List open watchman issues and PRs
- [ ] For each: verify if the entity is now available/fixed
- [ ] Close resolved issues with verification comment
- [ ] Report summary to Sharon: X new issues, Y new PRs, Z resolved, W remaining

## 8. Generate Summary
- [ ] Present findings in table format
- [ ] Group by severity
- [ ] Include links to created/updated GitHub issues AND PRs
- [ ] Suggest priority order for Developer agent to address
- [ ] Output HANDOFF note if Developer action needed:
  ```
  HANDOFF → ha-developer: {N} watchman PRs ready for implementation (X critical, Y high, Z medium) + {M} low-severity issues
  ```

---

## Automation Error Workflow (for [AE] menu item)

### AE-1. Scan HA Log via SSH
- [ ] SSH to HA host: `grep -E "(ERROR|WARNING).*(automat|script)" /config/home-assistant.log | tail -300`
- [ ] Also run: `grep -E "Error executing script|action at position|Template.*error" /config/home-assistant.log | tail -100`
- [ ] If log is empty or unavailable, try `/homeassistant/home-assistant.log`

### AE-2. Parse Results
- [ ] Extract: automation/script ID, error message, timestamp, occurrence count
- [ ] Group errors by automation ID (deduplicate repeated failures)
- [ ] Note the most recent timestamp per automation

### AE-3. Fetch Trace Detail (for each erroring automation)
- [ ] SSH → REST API: `curl -s -H "Authorization: Bearer <HASS_TOKEN>" http://localhost:8123/api/trace/automation/<automation_id>`
- [ ] Extract failed step: action index, condition that failed, service that errored, exception text
- [ ] Note automation `state` (enabled/disabled) from: `curl -s -H "Authorization: Bearer <HASS_TOKEN>" http://localhost:8123/api/states/automation.<name>`

### AE-4. Categorize by Severity
- [ ] **Critical**: ≥3 failures in last 24h, automation still enabled
- [ ] **High**: 1–2 failures in last 24h, automation still enabled
- [ ] **Medium**: failures >24h but ≤7 days ago, automation still enabled
- [ ] **Low**: automation is disabled, or last failure >7 days ago

### AE-5. Check Existing GitHub Issues AND PRs
- [ ] Run `gh issue list --repo {ha_config_repo} --label automation-error`
- [ ] Run `gh pr list --repo {ha_config_repo} --label automation-error --state open`
- [ ] Skip creating duplicates; note items that may be resolved

### AE-6a. Create GitHub Issues (low/medium severity)
For each NEW low or medium finding:
- [ ] Title format: `[runtime-error] {automation_id} — {brief description}`
- [ ] Body: automation ID, error message, last seen timestamp, failed step/action, suggested fix
- [ ] Labels: `automation-error` + `severity:{level}` + `agent:reviver`

### AE-6b. Create GitHub PRs (critical/high severity)
For each NEW critical or high finding:
- [ ] Follow `_bmad/bmm/checklists/pr-creation-workflow.md`
- [ ] Labels: `automation-error` + `severity:{level}` + `agent:reviver` + `status:needs-implementation`
- [ ] Group related failures (e.g., same root-cause entity) into a single batch PR

### AE-7. Generate Summary & HANDOFF
- [ ] Present findings in table: automation ID | severity | error snippet | last seen | occurrences
- [ ] Output HANDOFF note if Developer action needed:
  ```
  HANDOFF → ha-developer: {N} automation-error PRs ready for implementation (X critical, Y high) + {M} issues (medium/low)
  ```
