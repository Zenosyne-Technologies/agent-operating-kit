---
doc: Token economics contract
type: reference
status: active
summary: The telemetry contract — cost queries, the pricing rule, the per-issue context sidecar, and how reporting degrades without telemetry.
updated: {{INSTALL_DATE}}
---

# Token & cost telemetry contract

The single description of the seam between the kit and the token-telemetry plugin. Every consumer (stats collection, reporting, documentation agent) reads this file instead of re-deriving these rules.

## Source

SQLite DB at `~/.claude/telemetry/usage.db` (override: `$TOKEN_TELEMETRY_DB`), tables `events`/`sessions`/`projects`/`models`/`pricing`. Available when the file exists AND a `projects` row's path matches this repo's root. Projects on project-folder storage also keep a local mirror DB, but the central DB stays complete and authoritative — consumers read central. **Absent → every consumer omits its token output silently; nothing fails, nothing warns.** `events` stores, per row: `ts`, `session_id`, `kind`, `agent`, `model_id`, the token counters, `dur_ms`, `branch`, `commit_sha`, `issue_key`, `task_size`, `note` — those last three from the sidecar below. There is no milestone column and no release column; both are derived, per the recipes.

## Scoping recipes

A branch name carries ONE work item's key, never a milestone's or a version's (`.marvin/agents/git-strategy.md`) — so no rollup keys off a branch-name prefix. Every multi-issue scope resolves to an ISSUE-KEY SET first, then sums the per-issue recipe over it.

- **Per-issue**: `events.issue_key = '<KEY>'` when rows are tagged directly (preferred); fallback `events.commit_sha IN (git log --format=%h --grep='^<KEY>:')` (match both `%h` lengths) when `issue_key` is null. `events.branch = 'feature/<KEY>-<slug>'` corroborates; it never substitutes.
- **Milestone, release, or any multi-issue scope**: resolve the scope to its issue keys — a milestone's from its container's children in the tracker, a version's from the frozen scope recorded in `.docs/release-notes/v<version>.md` — then apply BOTH branches of the per-issue recipe across that set and sum. A release belonging to no milestone needs nothing extra: same recipe, different key set.
- **Period**: `events.ts` window (the report's date range).
- **A zero is never $0.** Run every scoped sum beside a control count of THIS project's events (`events` → `sessions.project_id` → the `projects` row matching the repo root, as in Source), and report which case it is: empty key set → scope resolution failed, name the scope and stop; control 0 → telemetry absent, omit silently per Source above; control > 0 with the scoped sum at 0 → "0 of N scoped issues have telemetry rows", which is a broken scope until proven otherwise. Never render a cost figure from an unexplained zero — a query that stopped matching and a project that spent nothing are the same number.

## Tier mapping

Model name prefix → kit tier, mirrors the pricing table's own prefixes:

| Model prefix | Tier |
|---|---|
| `claude-fable-*` | orchestrator |
| `claude-opus-*` | heavy |
| `claude-sonnet-*` | small |
| `claude-haiku-*` | micro |

`events.agent` + `events.kind` distinguish main-session vs subagent work within a tier.

## Pricing

Never stored per event. Cost derives at query time from the telemetry DB's `pricing` table (provider × model × model-version, effective-dated): join against the rate in force at `events.ts` (latest `effective_from` ≤ ts), longest-prefix model match. A reported cost figure always carries its `effective_from` date. Seed rows carry `effective_from = 0` — render them as "seed rates (undated)", never as a 1970 date.

## Context sidecar

When telemetry is enabled, write the repo-root `.claude/telemetry-context.json` at tracker-task start and rewrite it on every task switch:

```json
{"issue_key": "<KEY>", "project": "<name>", "size": "<size>", "summary": "<one sentence>"}
```

Capture reads `PROJECT-INFO.md`'s frontmatter (`.marvin/`, else `.docs/`) to stamp `project` with the repo's human name. Delete the sidecar when leaving tracker work (no active task). Capture stamps these fields onto events as they are written. Gitignored — install/upgrade add the ignore line. Attribution is last-declared-task: events land under whichever task was declared most recently, even across a race with a switch. That approximation is documented, not hidden.

## Snapshot `tokens` object

Stats snapshots (schema v2) carry a `tokens` key, null when telemetry is absent — every consumer must handle both. Keys: `in`, `out`, `cache_r`, `cache_w`, `cache_hit_pct`, `by_tier` (orchestrator/heavy/small/micro → `{out, est_cost_usd}`), `by_model`, `main_vs_subagent`, `est_cost_usd`, `events`.

## Secrets

DB paths and cost figures are shareable. Transcript contents are not — no query or render built from this contract ever exposes transcript text. Anything posted to the PM tool (comments, attachments) stays governed by `.marvin/agents/security.md`.
