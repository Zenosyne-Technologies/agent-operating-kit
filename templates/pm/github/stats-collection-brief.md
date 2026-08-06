# Agent brief: collect tracker statistics (GitHub Issues)

Fill the placeholders, then hand this brief verbatim to an agent (works at the small-worker tier; micro-model if your `gh` CLI setup is reliable).

---

Collect issue statistics for {{PROJECT_NAME}} from GitHub Issues. Work synchronously, no sub-agents.

TOOLS: `gh` CLI via Bash — `gh issue list --json`, `gh api` (+ `jq`).

TARGET: repository {{GITHUB_REPO}}. SCOPE: {{SCOPE: "project" | "milestone:<slug>"}} (milestone scope filters by the NATIVE milestone, not a label — `gh issue list --milestone <slug>`). PERIOD: last {{PERIOD_DAYS}} days.

1. QUERY (`gh issue list --label ... --json ...` / `gh api search/issues`, respect SCOPE): totals per label value for each dimension — type:*, area:*, origin:*, size:*; per native milestone the open vs closed split for `milestones`; sev1..sev4 split into open and closed (by issue state); defects per area (issues labeled type:bug, counted per area:* label, open+closed); `createdAt` and `closedAt` counts within PERIOD; oldest open issue labeled sev1-critical or sev2-high (number, or "none").
2. WRITE the snapshot to `.docs/reports/<YYYY-MM-DD>-stats[-<scope-slug>].json` (create `.docs/reports/` if absent; overwrite same-day same-scope file — re-runs are idempotent) with EXACTLY these top-level keys: stats_schema (2), generated, scope, pm_tool ("github"), project_key ({{GITHUB_REPO}}), issues_scanned, by_type, by_area, by_origin, by_size, sev_open, sev_closed, defects_by_area, milestones, period ({created, closed, days}), oldest_open_sev1_or_sev2, tokens (per `.docs/agents/token-economics.md`: null when the telemetry DB is absent). Dimension objects map label value → count; omit zero-count values.
3. TOKENS (optional): if the telemetry DB is available per `.docs/agents/token-economics.md`, query it for the same SCOPE and PERIOD and set the snapshot's `tokens` object per the contract (tiers, models, cache hit rate, est_cost_usd from the pricing table); otherwise set `tokens: null`.
4. COMMIT the snapshot file (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, then any failures. Nothing else.
