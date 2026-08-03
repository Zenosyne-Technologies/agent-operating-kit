# Agent brief: collect tracker statistics (Jira)

Fill the placeholders, then hand this brief verbatim to an agent (works at the default-worker tier; micro-model if your Jira MCP tools are reliable).

---

Collect issue statistics for {{PROJECT_NAME}} from Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: searchJiraIssuesUsingJql (Atlassian MCP).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}}. SCOPE: {{SCOPE: "project" | "milestone:<slug>"}} (milestone scope adds `AND labels = "milestone:<slug>"` to every query). PERIOD: last {{PERIOD_DAYS}} days.

1. QUERY (JQL, count-only where possible; respect SCOPE): totals per label value for each dimension — type:*, area:*, origin:*, size:*, and milestone:* labels (each with open vs done split for `milestones`); sev1..sev4 split into open (`statusCategory != Done`) and closed; `created >= -{{PERIOD_DAYS}}d` and `resolved >= -{{PERIOD_DAYS}}d` counts; oldest unresolved issue labeled sev1-critical or sev2-high (key, or "none").
2. WRITE the snapshot to `.docs/reports/<YYYY-MM-DD>-stats[-<scope-slug>].json` (create `.docs/reports/` if absent; overwrite same-day same-scope file — re-runs are idempotent) with EXACTLY these top-level keys: stats_schema (1), generated, scope, pm_tool ("jira"), project_key, issues_scanned, by_type, by_area, by_origin, by_size, sev_open, sev_closed, milestones, period ({created, closed, days}), oldest_open_sev1_or_sev2. Dimension objects map label value → count; omit zero-count values.
3. COMMIT the snapshot file (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, then any failures. Nothing else.
