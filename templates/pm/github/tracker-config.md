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

## Release mapping: native, and the reference case for the other trackers

A git tag and a GitHub Release are the SAME object — publishing the release creates the tag — so nothing is simulated and nothing is mirrored. The branch model, who may tag, and how the version is classified are `.marvin/agents/git-strategy.md`'s; only the mapping is decided here.

- The version lives on that one object: `gh release create v<version> --notes-file .docs/release-notes/v<version>.md` (orchestrator only), so the Release body, the annotated tag message and the release-note document are one text.
- Issues carry NO version marker. Native milestones are already the kit's milestone axis, and milestone and version are independent axes — spending the milestone field on a version would collapse two things that are not one. The frozen scope is enumerated in the release note, which is what milestone- and release-scoped rollups resolve against.
- `release:*` labels are UNNECESSARY here for the same reason `milestone:<slug>` labels are — a hand-synced label would be a second source of truth for what the Release object already holds.
