# Reporting & statistics — kit v0.8.0 design

Date: 2026-08-03 · Status: approved for planning · Target plugin version: 0.8.0 · Depends on: v0.7.0 (frontmatter PROJECT-INFO, sizing rubric)

## Context

The label registry (type/area/sev/origin/size/milestone) exists explicitly "for statistics and reporting", but nothing consumes it. v0.8.0 builds the consumer: one tracker query pass feeding four audiences — the architect, milestone close-out review, foreign agents/frameworks, and external stakeholders.

## Goals

1. One collection pass per tracker produces a machine-readable stats snapshot.
2. The same snapshot renders into audience-specific reports; query logic exists exactly once per tracker.
3. Milestone close-out reporting becomes part of the task lifecycle.
4. Everything installed into consumers is self-contained (briefs, not plugin calls); a plugin skill adds convenience.

## Non-goals

- Scheduled/cron delivery (architect digest is on-demand only — decided).
- Historical trend storage beyond the dated snapshot files themselves.
- Dashboards/UI; output is markdown + JSON.

## Design

### 1. Collect once — `templates/<tracker>/stats-collection-brief.md` (per tracker)

A dispatchable sub-agent brief (worker tier; micro if tools are reliable), tracker-specific because the queries are (JQL for Jira, Linear MCP filters for Linear). Scope parameter: whole project or one `milestone:<slug>`/milestone. It queries counts and lists grouped by every registry dimension — type mix, area load, open/closed sev distribution, origin (demand source), size distribution, per-milestone progress (open vs done by size) — plus basics: created/closed in period, oldest open sev1/sev2.

Output: `.docs/reports/<YYYY-MM-DD>-stats[-<scope>].json` — a stable, documented key structure (versioned `stats_schema` field). The JSON snapshot IS the foreign-agent deliverable. FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, failures. Nothing else.

### 2. Render many — `templates/docs/agents/reporting.md` (tracker-neutral, in the cascade)

One lean cascade file defining the three renders, each produced by a worker agent briefed with the snapshot path:

- **Architect digest** (on-demand): `.docs/reports/<date>-digest.md` — what shipped, demand-source mix, quality posture (sev trend vs previous snapshot if present), where effort went, agents' friction points (escalations, failed validations if tracked). Actionable, one page.
- **Milestone close-out** (lifecycle-triggered): `.docs/reports/<date>-closeout-<slug>.md` + a comment on the milestone container (epic/milestone) — delivered vs planned scope, defects by area, research-pass outcomes, sizing accuracy notes.
- **Stakeholder page** (on-demand): polished md (or Confluence/Linear doc where connected) — progress, roadmap position, quality summary; NO agent internals (tiers, escalations, origin labels).

Cascade line added to `CLAUDE.core.md`: "Producing any report → `.docs/agents/reporting.md`". Lifecycle rule extended: milestone merge → dispatch collection + close-out render before archiving the branch.

### 3. Convenience — `report` plugin skill (`skills/report/SKILL.md`)

Thin: reads PROJECT-INFO frontmatter for tracker coordinates, fills the installed collection brief, dispatches it, then dispatches the requested render (digest by default; `closeout <slug>` / `stakeholder` variants). No logic of its own beyond fill-and-dispatch — consumers without the plugin dispatch the same briefs manually.

## File change list

| File | Change |
|---|---|
| `templates/jira/stats-collection-brief.md` | new |
| `templates/linear/stats-collection-brief.md` | new |
| `templates/docs/agents/reporting.md` | new (cascade) |
| `templates/CLAUDE.core.md` | cascade line + milestone-merge lifecycle extension |
| `skills/report/SKILL.md` | new |
| `README.md` | core idea, inventory, skills list |
| `CLAUDE.md` (repo) | extension rule: new tracker folders also ship a stats-collection brief |
| `.claude-plugin/plugin.json` | 0.8.0 |

## Compatibility

Snapshots are additive files; nothing existing changes shape. Projects without `.docs/reports/` get it on first run. Trackers added later must ship a stats brief (extension rule updated).

## Testing

Scratch-project run per tracker: seed a handful of labeled issues, dispatch collection, verify snapshot keys and counts; render digest and close-out; verify the stakeholder render contains no origin/tier internals.

## Validated

Date: 2026-08-04 · Validator: Task 7 scratch validation (spec Testing section, adapted to no live tracker). Caveat, explicit: no live tracker queries were executed against Jira or Linear — this pass fabricates a schema-v1 snapshot and fabricated `PROJECT-INFO.md` frontmatter, then exercises the render and brief-fill logic against that fixture data. It does not validate the actual JQL/MCP query behavior of `stats-collection-brief.md` against a real tracker.

### Step 1 — Snapshot + render simulation

Fabricated a valid schema-v1 snapshot (`2026-08-04-stats.json`, project `NIM`, milestone slug `v1-launch`) with all 15 top-level keys from `templates/jira/stats-collection-brief.md` step 2, internally consistent counts (`by_type`/`by_area`/`by_origin`/`by_size` each sum to `issues_scanned` = 75; `sev_open` + `sev_closed` = 18 = `by_type.bug`). Produced all three renders per `templates/docs/agents/reporting.md`:

- **Digest**: ends with exactly 3 numbered observations; all cited figures trace to snapshot fields verbatim (no invented percentages or cross-sums). PASS.
- **Close-out**: covers delivered-vs-planned from `milestones.v1-launch` (34 done / 6 open) as the render brief requires. PASS, with a caveat below.
- **Stakeholder**: `grep -n -i 'origin:\|size:\|worker\|escalation\|ponytail'` against the rendered file returned zero hits (grep exit 1). PASS.

**Defect found (real, not fixed — recorded per instructions)**: `templates/docs/agents/reporting.md` specifies render content that schema-v1 cannot supply. The digest asks for "where effort went (`by_area × by_size`)" and the close-out asks for "defects by area" and "sizing distribution of shipped work" — all three are cross-tabulations (area × type=bug, area × size, milestone-done × size). `templates/jira/stats-collection-brief.md` step 1 and `templates/linear/stats-collection-brief.md` step 1 both collect only independent per-dimension totals (one count per label value per dimension, plus milestone open/done) — there is no query or output field that joins two dimensions. A render agent following `reporting.md` literally cannot produce "defects by area" or an area×size effort breakdown from a schema-v1 snapshot without recomputing/estimating, which `reporting.md`'s own rule forbids ("Numbers come from the snapshot verbatim — an agent that recomputes or estimates figures is doing it wrong"). During this validation the close-out and digest renders were written to state the limitation explicitly and fall back to the independent totals rather than inventing a join. Fix options for a future task: either drop the cross-tabulated asks from `reporting.md`, or extend the schema/queries to collect the specific joins actually needed (e.g. `by_area_defects`, milestone-scoped `by_size`).

Resolved post-validation in this release: the snapshot schema gains `defects_by_area` (16 top-level keys, still stats_schema 1 — pre-release change) and the digest/close-out wording now names only collected fields; a second fix made explicit that close-outs render from a milestone-scoped snapshot.

### Step 2 — Brief fill check

Filled both stats briefs against fabricated `PROJECT-INFO.md` frontmatter (jira variant: project `Nimbus`/`NIM`; linear variant: team/project `Aurora`/`AUR`). `grep '{{'` against both filled briefs returned zero hits (exit 1) in each case. Every label value the filled briefs' query instructions reference (`type:*`, `area:*`, `origin:*`, `size:*`, `milestone:*` in the jira variant; `type:*`, `area:*`, `origin:*`, `size:*` in the linear variant — correctly omitting `milestone:*` since Linear milestones are native, not label-based per `tracker-config.md`; plus bare `sev1-critical`/`sev2-high` in both) exists in `templates/docs/agents/label-syntax.md` v1.2.0. PASS.

**Minor observation (not blocking)**: the Linear brief needs `TEAM_NAME` and `TEAM_KEY` distinct from `PROJECT_NAME`, but `templates/docs/PROJECT-INFO.md`'s frontmatter has no dedicated team-name/team-key fields — only `project`/`project_key` plus freeform `tracker_coordinates`. Resolution required reading the team identity out of `tracker_coordinates` prose rather than a structured field. This fabrication succeeded, but the mapping is implicit rather than documented.

### Outcome

DONE_WITH_CONCERNS — one confirmed defect (cross-tabulated render asks vs. flat schema-v1 data) recorded above per instructions; not fixed in this pass.

## Addendum (2026-08-04) — traceability rules

Owner-requested, added pre-release: (1) commit messages start with the tracker issue key (`CLAUDE.core.md` autocommit rule + `briefing.md` brief ingredient) so commits trace and sync to the PM tool; (2) comment discipline — agents leave short summarized comments on issues for anything solved, fixed, or caught (`ticket-filing.md`); (3) planning-research passes mine both code and tracker history — issue keys found via `git log`/`git blame` lead to prior issue comments (`planning-research.md`).
