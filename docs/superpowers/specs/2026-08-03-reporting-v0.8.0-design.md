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
