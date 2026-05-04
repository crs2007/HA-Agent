# PR Review Workflow (Reviewer)

Step-by-step process for the Reviewer (Quinn-HA) agent to validate watchman PR changes.

## 1. Select PR to Review

- [ ] List PRs needing review: `gh pr list --repo {ha_config_repo} --label "status:needs-review" --state open`
- [ ] Pick a PR (prioritize by severity: critical → high → medium)
- [ ] Read PR description for full diagnostic context

## 2. Examine Changes

- [ ] View the diff: `gh pr diff {pr_number} --repo {ha_config_repo}`
- [ ] Identify all changed files and the nature of each change
- [ ] Verify `_watchman-fix.md` has been deleted (Developer should have removed it)
- [ ] Flag if `_watchman-fix.md` is still present — request changes

## 3. Run Automation Review Checklist

For each changed YAML file, verify against `automation-review.md`:
- [ ] Required fields: `alias:`, `mode:` explicitly set
- [ ] `continue_on_error: true` on non-critical action steps
- [ ] Room hold booleans considered where applicable
- [ ] Native HA constructs used (no template where built-in condition works)
- [ ] `entity_id` used over `device_id` (except Z2M device triggers)
- [ ] Notifications use `script.smart_announcement_universal_notifier`
- [ ] Template safety: `float(0)`, `int(0)` defaults, unavailable/unknown handled
- [ ] Shabbat/Holiday awareness considered for time-sensitive automations

## 4. Validate Entity References via MCP

- [ ] Extract all `entity_id` values from changed files
- [ ] Query each entity state via MCP to confirm it exists and is available
- [ ] Flag any entity references that return `unavailable`, `unknown`, or not found
- [ ] Cross-check with Zigbee health sensors if Zigbee entities are involved

## 5. Validate HA Config

- [ ] Run HA config check via MCP (homeassistant.check_config or equivalent)
- [ ] Report any configuration errors

## 6. Check for Side Effects

- [ ] Grep affected entity IDs across all config files in the repo
- [ ] Verify the fix doesn't break other automations, scripts, or dashboards that reference the same entities
- [ ] Check if any removed references are still needed elsewhere

## 7. Verify Live-Instance-First Compliance

- [ ] Confirm the Developer compared with the live HA state before making changes
- [ ] Check that no secrets.yaml, .storage/, or other excluded files are in the diff

## 8. Post Review

**If approved:**
- [ ] Approve the PR: `gh pr review {pr_number} --repo {ha_config_repo} --approve --body "{review summary}"`
- [ ] Add label: `gh pr edit {pr_number} --repo {ha_config_repo} --add-label "agent:reviewer"`
- [ ] Notify Sharon the PR is ready to merge

**If changes needed:**
- [ ] Request changes: `gh pr review {pr_number} --repo {ha_config_repo} --request-changes --body "{specific feedback}"`
- [ ] Update labels: remove `status:needs-review`, add `status:changes-requested`
  ```
  gh pr edit {pr_number} --repo {ha_config_repo} \
    --remove-label "status:needs-review" \
    --add-label "status:changes-requested"
  ```
- [ ] List specific issues with file paths and line numbers
- [ ] Output handoff:
  ```
  HANDOFF → ha-developer: PR #{pr_number} needs changes — {summary of issues}
  ```
