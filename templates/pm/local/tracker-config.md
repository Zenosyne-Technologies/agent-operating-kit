# Tracker configuration — Local (file-based)

## Levels: 4 of 4 (kit target met via files)

Kit target hierarchy: milestone container → feature grouping → work item → sub-item.

Root: `.docs/project-management/`.

- **Milestone** → `milestones/{{PROJECT_KEY}}-M<n>.md` (native 4th level).
- **Epic** = an issue with `type: feature` whose `children:` list names issue keys; each child
  carries `parent: <epic key>`. No separate file kind.
- **Work item** → `issues/{{PROJECT_KEY}}-<n>.md`.
- **Sub-item** → a task-list checkbox (`- [ ] …`) inside the issue body.

## Item format

Every milestone and issue file opens with YAML frontmatter:

```yaml
---
key: {{PROJECT_KEY}}-42
title: Short imperative title
type: feature | bug | change-request | investigation | tech-debt
status: todo | in-progress | done
labels: [type:feature, area:core, origin:roadmap, size:m]   # registry dimensions, one per line or inline
milestone: {{PROJECT_KEY}}-M2      # omit when unscoped
parent: {{PROJECT_KEY}}-17         # omit at top level
children: [{{PROJECT_KEY}}-43]     # epics only
created: 2026-01-31
updated: 2026-01-31
---
```

Body follows `ticket-filing.md`: `## Scope / ## DoD` (defects use the repro template), then `## Comments`.

## Native field usage

- The `labels:` list is the canonical dimension carrier (the `type:` frontmatter field mirrors the `type:*` label for fast reads — on conflict the LABEL wins) — values are identical to the tracker labels in
  `label-syntax.md`. There are no native mirrors here (as with GitHub): no priority field, no
  estimate field, do not invent any. `status:` is workflow state, not a label.
- `milestone:<slug>` labels are UNNECESSARY — the `milestone:` field is the real container.

## INDEX.md (at the root)

Two parts: counters (`next_issue: <n>`, `next_milestone: <n>`) and an open-item table
`| key | title | type | status | milestone |` listing every item not yet `done`.

## Operations

- **create** — read `next_issue` from INDEX.md, write `issues/{{PROJECT_KEY}}-<n>.md`, increment the
  counter, add the INDEX row. Same for milestones via `next_milestone`.
- **transition** — edit `status:` and `updated:` in the file; drop the INDEX row when it hits `done`.
- **comment** — append `### <YYYY-MM-DD> — <agent/role>` plus a short summary under `## Comments`.
- **search** — grep the frontmatter (`grep -l 'sev1-critical' issues/*.md`, `grep '^status:' …`).
- **dedupe** — ALWAYS `grep -i '^title:' issues/*.md` for near-matches before filing a new item.

Everything is committed with the code, so history and blame are the audit trail.
