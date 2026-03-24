# PR Creation Workflow (Reviver)

Step-by-step process for the Reviver (Watch) agent to create draft PRs from Watchman findings.
Used for **critical, high, and medium** severity findings. Low-severity items use GitHub Issues instead.

All operations use `gh` CLI and GitHub API — no local clone needed.

## 1. Triage Findings by Severity

- [ ] Critical/High/Medium → proceed with PR creation (this workflow)
- [ ] Low → create GitHub Issue using `ha-watchman-issue.md` template instead

## 2. Check for Duplicate PRs

- [ ] Run: `gh pr list --repo {ha_config_repo} --label watchman --state open`
- [ ] Compare existing open PRs with new findings
- [ ] Skip findings that already have an open PR
- [ ] Note PRs that may have been resolved but not merged

## 3. Group Related Findings

- [ ] Identify findings with a shared root cause (e.g., same offline Zigbee device, same removed integration)
- [ ] Group related entities into a single batch PR
- [ ] Single-entity findings get their own PR

## 4. Create Branch on GitHub

For each PR (single or batch):
- [ ] Get latest commit SHA from main: `gh api repos/{ha_config_repo}/git/ref/heads/master`
- [ ] Branch naming:
  - Single entity: `watchman/{severity}/{entity-slug}` (e.g., `watchman/critical/light-office-ceiling`)
  - Batch: `watchman/{severity}/batch-{description}-{date}` (e.g., `watchman/high/batch-zigbee-offline-2026-03-24`)
- [ ] Create branch via API: `gh api repos/{ha_config_repo}/git/refs -f ref=refs/heads/{branch} -f sha={commit_sha}`

## 5. Create Diagnostic File on Branch

- [ ] Create `_watchman-fix.md` on the branch via contents API:
  ```
  gh api repos/{ha_config_repo}/contents/_watchman-fix.md \
    -X PUT \
    -f message="[watchman] Add diagnostic context for {entity_id}" \
    -f branch={branch} \
    -f content={base64_encoded_diagnostic_data}
  ```
- [ ] Diagnostic file contains: entity ID, severity, status, where referenced (files + lines), impact, MCP state data, Zigbee status, suggested fixes

## 6. Create Draft PR

- [ ] Create draft PR via `gh pr create`:
  ```
  gh pr create \
    --repo {ha_config_repo} \
    --head {branch} \
    --base master \
    --title "[watchman] {entity_id} — {brief description}" \
    --body "{PR body from ha-watchman-pr.md template}" \
    --draft
  ```
- [ ] For batch PRs, title format: `[watchman] {N} related findings — {root cause description}`

## 7. Apply Labels

- [ ] Add labels to the PR:
  ```
  gh pr edit {pr_number} \
    --repo {ha_config_repo} \
    --add-label "watchman,severity:{level},agent:reviver,status:needs-implementation"
  ```

## 8. Record PR in Summary

- [ ] Log the PR number and URL
- [ ] Include in the Watchman report summary table
- [ ] Output for Developer handoff:
  ```
  HANDOFF → ha-developer: {N} watchman PRs ready for implementation (X critical, Y high, Z medium)
  ```
