# Label syntax registry — v1.0.0

Self-contained and versioned: ANY change to this registry bumps the version above and adds a changelog row. This file is the single source of truth for labels; the in-tracker guide summarizes it and loses on label conflicts.

## Rules

- EVERY tracker item an agent creates or edits carries one label per required dimension — epics, stories, tasks, and sub-items alike, not only bugs. This is what makes statistics and reporting possible; an unlabeled item is invisible to reporting.
- Syntax: `dimension:value`, kebab-case values. Exceptions for continuity: severity is bare (`sev1-critical`..`sev4-low`); virtual milestones are `milestone:<slug>` (only where `tracker-config.md` prescribes them).
- Use only values from this registry. Need a new value or dimension? Bump this file first (version + changelog), then use it.
- **Backfill on touch**: an agent editing an issue that lacks required labels adds them, inferred from the title/description (and code refs if present). Uncertain inference → best guess plus a comment stating it was inferred.

## Dimensions

| Dimension | Required on | Values |
|---|---|---|
| `type:` | every item | feature · bug · change-request · investigation · tech-debt |
| `area:` | every item | {{AREA_1}} · {{AREA_2}} · {{AREA_3}} · infra · docs (project components, e.g. ui, core) |
| `sev1..sev4` | defects only | sev1-critical · sev2-high · sev3-medium · sev4-low (definitions in `ticket-filing.md`) |
| `origin:` | every item | user-request (end users) · architect-request (the human managing the agent sessions) · agent-qa (QA sweeps, validators) · agent-dev (found by an agent while building) · roadmap (planned milestone work) |
| `milestone:<slug>` | epics on 3-level trackers | virtual milestone container per `tracker-config.md` |

## Reporting intent

type = work mix · area = component load · sev = quality posture · origin = demand source (users vs architect vs agents) · milestone = scope progress.

## Changelog

| Version | Change |
|---|---|
| 1.0.0 | Initial registry. Adds `type:feature` and `origin:*` (supersedes `found-by:*`: agent-qa → origin:agent-qa, owner → origin:architect-request). Labeling extended from intake-only to every created/edited item; backfill-on-touch rule introduced. |
