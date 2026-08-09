---
doc: Tracker configuration — GitHub Issues
type: reference
status: active
summary: GitHub Issues' hierarchy against the kit's four levels, and why severity and size labels stand alone with no native field to mirror.
updated: {{INSTALL_DATE}}
---

# Tracker configuration — GitHub Issues

## Levels: 4 of 4 (kit target met natively)

Kit target hierarchy: milestone container → feature grouping → work item → sub-item.

**Milestone** (native, created via `gh api repos/{{GITHUB_REPO}}/milestones`) → **Epic** = a parent issue with sub-issues (`gh api` sub-issue endpoints where available; task-list fallback where the plan doesn't have sub-issues) → **Issue** → task-list items. No virtual constructs needed.

## Native field usage

- Sev labels are canonical, with NO native mirror — GitHub has no priority field; do not invent one.
- Size labels are canonical, with NO native estimate field to mirror.
- Native issue TYPE doesn't exist either — the `type:*` label is the only type dimension.
- `milestone:<slug>` labels are UNNECESSARY here (native milestones exist) — do not create them.
