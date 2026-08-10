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

A GitHub Release ATTACHES to a git tag, so a version needs no simulation and no mirror here — but the two are created in that order, never in one step. The branch model, who may tag and how the version is classified are `.marvin/agents/git-strategy.md`'s; only the mapping is decided here.

- Tag FIRST, publish second — `gh release create` against a tag that does not yet exist invents a LIGHTWEIGHT one, which the tag rule forbids: `git tag -a v<version> -m …` on the release branch's merge commit, `git push origin v<version>`, then `gh release create v<version> --verify-tag --notes-file <body>` (orchestrator only, `--verify-tag` refusing to invent anything).
- `<body>` is the release note's BODY — everything below the closing `---` of its YAML header, e.g. `awk 'NR>1 && /^---$/{f=1;next} f' .docs/release-notes/v<version>.md > <body>`. Never hand `gh` the document itself: that publishes the header. Tag message and Release body are then genuinely the same text.
- Issues carry NO version marker. Native milestones are already the kit's milestone axis, and milestone and version are independent axes — spending the milestone field on a version would collapse two things that are not one. So the two scopes resolve from different places: MILESTONE scope from the native milestone (`gh issue list --milestone <slug>`), RELEASE scope from the note's `scope:` header field.
- `release:*` labels are UNNECESSARY here for the same reason `milestone:<slug>` labels are — a hand-synced label would be a second source of truth for what the Release object already holds.
