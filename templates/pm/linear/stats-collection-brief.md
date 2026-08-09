# Agent brief: collect tracker statistics (Linear)

Fill the placeholders, then hand this brief verbatim to an agent (works at the small-worker tier; micro-model if your Linear MCP tools are reliable).

---

Collect issue statistics for {{PROJECT_NAME}} from Linear. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: list_issues, list_issue_labels, list_milestones (Linear MCP).

TARGET: team "{{TEAM_NAME}}" (key {{TEAM_KEY}}), project "{{PROJECT_NAME}}". SCOPE: {{SCOPE: "project" | "milestone:<slug>"}} (milestone scope filters to that native project milestone). PERIOD: last {{PERIOD_DAYS}} days.

1. QUERY (paginate list_issues over the project; respect SCOPE): totals per label value for each dimension — type:*, area:*, origin:*, size:*; per native milestone the open vs done split for `milestones` (slugified milestone name as key); sev1..sev4 split into open (state not in Done/Canceled) and closed; defects per area (issues labeled type:bug, counted per area:* label, open+closed); created and completed counts within PERIOD; oldest open issue labeled sev1-critical or sev2-high (identifier, or "none").
2. WRITE the snapshot to `.docs/reports/<YYYY-MM-DD>-stats[-<scope-slug>].json` (create `.docs/reports/` if absent; overwrite same-day same-scope file — re-runs are idempotent) with EXACTLY these top-level keys: stats_schema (2), generated, scope, pm_tool ("linear"), project_key ({{TEAM_KEY}}), issues_scanned, by_type, by_area, by_origin, by_size, sev_open, sev_closed, defects_by_area, milestones, period ({created, closed, days}), oldest_open_sev1_or_sev2, tokens (per `.marvin/agents/token-economics.md`: null when the telemetry DB is absent). Dimension objects map label value → count; omit zero-count values.
3. TOKENS (optional): if the telemetry DB is available per `.marvin/agents/token-economics.md`, query it for the same SCOPE and PERIOD and set the snapshot's `tokens` object per the contract (tiers, models, cache hit rate, est_cost_usd from the pricing table); otherwise set `tokens: null`.
4. COMMIT the snapshot file (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, then any failures. Nothing else.
