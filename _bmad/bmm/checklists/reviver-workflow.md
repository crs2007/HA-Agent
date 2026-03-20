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

## 5. Check Existing GitHub Issues
- [ ] Run `gh issue list --repo crs2007/Home-Assistant_Config --label watchman`
- [ ] Compare existing issues with new findings
- [ ] Skip creating duplicates
- [ ] Note issues that may have been resolved

## 6. Create GitHub Issues
For each NEW finding:
- [ ] Title format: `[watchman] {entity_id} — {brief description}`
- [ ] Body follows template at `_bmad/bmm/templates/ha-watchman-issue.md`
- [ ] Labels applied: `watchman` + `severity:{level}`
- [ ] Includes: entity ID, source file(s), line number(s), suggested fix

## 7. Track Resolution
- [ ] List open watchman issues
- [ ] For each: verify if the entity is now available/fixed
- [ ] Close resolved issues with verification comment
- [ ] Report summary to Sharon: X new issues, Y resolved, Z remaining

## 8. Generate Summary
- [ ] Present findings in table format
- [ ] Group by severity
- [ ] Include links to created/updated GitHub issues
- [ ] Suggest priority order for Developer agent to address
- [ ] Output HANDOFF note if Developer action needed:
  ```
  HANDOFF → ha-developer: Fix {N} watchman issues (X critical, Y high)
  ```
