---
doc: Tracker configuration — Linear
type: reference
status: active
summary: Linear's hierarchy against the kit's four levels, and how severity and size map onto Linear's native fields.
updated: {{INSTALL_DATE}}
---

# Tracker configuration — Linear

## Levels: 4 of 4 (kit target met natively)

Kit target hierarchy: milestone container → feature grouping → work item → sub-item.

Project → **Milestone** → **Issue** → **Sub-issue**, all native. No virtual constructs: milestones are created directly on the project; epic-scale feature groupings are parent issues with sub-issues.

## Native field usage

Sev labels are canonical; mirror native Priority per this table (on conflict the label wins):

| Kit label | Linear Priority |
|---|---|
| sev1-critical | Urgent |
| sev2-high | High |
| sev3-medium | Medium |
| sev4-low | Low |

Size labels are canonical; mirror the native estimate per this table (on conflict the label wins):

| Kit label | Linear estimate |
|---|---|
| size:xs | 1 |
| size:s | 2 |
| size:m | 3 |
| size:l | 5 |
| size:xl | 8 |

## Release mapping: a native Release where the workspace has one, otherwise the tag alone

A version is NOT a Linear project and NOT a Linear milestone. Project → Milestone is already spent on the kit's milestone axis, and milestone and version are independent axes (`.marvin/agents/git-strategy.md`, which owns the model — this file decides only the mapping): reusing either level would make a milestone and a released version the same object, which they are not.

- Workspace with native **Releases** → the version is a Release named `v<version>`, matching the tag; the issues in the frozen scope attach to it. GitHub's tag-is-the-release case is the shape to copy.
- Workspace without them → the version lives on the annotated tag plus `.docs/release-notes/v<version>.md`, and issues carry nothing. Do NOT invent a `release:*` label to fill the gap: the note already records the frozen scope's issue keys, which is what rollups resolve against, and a hand-synced label would be a second source of truth for a tag that is already canonical.
