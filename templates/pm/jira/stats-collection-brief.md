---
doc: Stats collection brief — Jira
type: reference
status: active
summary: The dispatchable brief that snapshots label-dimension statistics from Jira into a report file.
updated: {{INSTALL_DATE}}
---

# Agent brief: collect tracker statistics (Jira)

Fill the placeholders, then hand this brief verbatim to an agent (works at the small-worker tier; micro-model if your Jira MCP tools are reliable).

---

Collect issue statistics for {{PROJECT_NAME}} from Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: searchJiraIssuesUsingJql (Atlassian MCP).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}}. SCOPE: {{SCOPE: "project" | "milestone:<slug>"}} (milestone scope adds `AND labels = "milestone:<slug>"` to every query). PERIOD: last {{PERIOD_DAYS}} days.

1. QUERY (JQL, count-only where possible; respect SCOPE): totals per label value for each dimension — type:*, area:*, origin:*, size:*, and milestone:* labels (each with open vs done split for `milestones`); sev1..sev4 split into open (`statusCategory != Done`) and closed; defects per area (issues labeled type:bug, counted per area:* label, open+closed); `created >= -{{PERIOD_DAYS}}d` and `resolved >= -{{PERIOD_DAYS}}d` counts; oldest unresolved issue labeled sev1-critical or sev2-high (key, or "none").
2. WRITE the snapshot to `.docs/reports/<YYYY-MM-DD>-stats[-<scope-slug>].json` (create `.docs/reports/` if absent; overwrite same-day same-scope file — re-runs are idempotent) with EXACTLY these top-level keys: stats_schema (3), generated, scope, pm_tool ("jira"), project_key, issues_scanned, by_type, by_area, by_origin, by_size, sev_open, sev_closed, defects_by_area, milestones, period ({created, closed, days}), oldest_open_sev1_or_sev2, tokens (per `.marvin/agents/token-economics.md`: `null` ONLY when the telemetry DB is absent, otherwise an object whose `state` is `ok`/`scope-unresolved`/`no-rows`). Dimension objects map label value → count; omit zero-count values.
3. TOKENS (optional): DB absent per `.marvin/agents/token-economics.md` → `tokens: null`, done. Present → resolve SCOPE to its issue-key set by that file's recipe (containers expanded to the items that carry work; a release's keys come from the `scope:` header of `.docs/release-notes/v<version>.md`), run the scoped sums for SCOPE and PERIOD beside the project's control event count, and write `tokens` with `state` + `scope_issue_keys` + `control_events` always, and the figures (tiers, models, cache hit rate, est_cost_usd from the pricing table) ONLY when `state` is `ok`. Never emit zeroed figures for `scope-unresolved` or `no-rows`.
4. COMMIT the snapshot file (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, then any failures. Nothing else.
