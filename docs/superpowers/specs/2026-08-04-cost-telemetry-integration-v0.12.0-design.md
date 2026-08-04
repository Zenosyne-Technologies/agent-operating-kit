# Cost-aware operations — kit v0.12.0 × token-telemetry v0.2.0 design

Date: 2026-08-04 · Status: draft for owner review · Repos: agent-operating-kit (this spec, kit v0.12.0) + agent-token-telemetry (companion release v0.2.0)

## Context

The operating kit measures work in issue counts (labels, snapshots, renders); the token-telemetry plugin measures work in tokens and dollars (per-turn/per-subagent SQLite events with model, agent, branch, commit sha) — each blind to the other's dimension. The join keys already exist on both sides: `events.branch` ↔ the kit's `milestone/<slug>` branches; `events.commit_sha` ↔ the kit's `<KEY>:` issue-key commit convention; `events.agent`/`kind` ↔ the kit's tier dispatch. This design connects them through a versioned data contract — no code merge; two plugins, one suite.

Also folded in: five hardening items surfaced by the live upgrade test on agent-token-telemetry (2026-08-04), which exercised `upgrade-agent-os`, the idempotent Jira intake brief, and the gated relabel sweep against the real AOS project.

Owner decisions baked in: cost surfaces in snapshot + digest + close-out + **stakeholder in absolute dollars** (all four); cost-per-issue comments at issue close only; sizing-calibration report: **excluded**; packaging: two releases, one marketplace (emprove — telemetry publishes to GitHub `Zenosyne-Technologies/agent-token-telemetry`), no code merge. Additional owner requirements (2026-08-04): pricing becomes configurable, versioned DATA (provider × model × model-version, effective-dated) with a weekly background refresh from Anthropic's published pricing; and when kit + telemetry are both enabled, telemetry events carry work context (issue key, project name, task size, one-sentence summary).

## Goals

1. One versioned data contract lets kit reporting consume telemetry data when present, and degrade silently when absent.
2. Stats snapshots carry token/cost economics (schema v2); all three renders answer "what did it cost".
3. Closed issues get a one-line cost comment via the commit-sha → issue-key join.
4. Install/upgrade offer telemetry opt-in and record it in PROJECT-INFO frontmatter.
5. The five live-test hardening items are fixed.
6. `token-telemetry` joins the emprove marketplace; its query surface learns the kit's dimensions.

## Non-goals

- Sizing-calibration render (owner-excluded; the raw data for it exists — a later release can add the render without schema changes).
- Storing cost per event (cost stays derived at query time — now from the effective-dated pricing table, which preserves historical accuracy: events price at the rate in force at `events.ts`).
- Dashboards. (Scheduled delivery of REPORTS remains out; the scheduled pricing refresh is in — see Telemetry §4.)

## The data contract (new cascade file: `templates/docs/agents/token-economics.md`)

One lean file, installed to `.docs/agents/token-economics.md`, is the single description of the seam. Contents:

- **Source**: `~/.claude/telemetry/usage.db` (or `$TOKEN_TELEMETRY_DB`), SQLite, telemetry plugin's `events/sessions/projects/models` tables. Availability check: file exists AND the project row matches this repo's root path. Absent → every consumer omits its token output silently; nothing fails.
- **Scoping recipe**: milestone economics = `events.branch = 'milestone/<slug>'`; period economics = `events.ts` window; per-issue economics = `events.commit_sha IN (git log --format=%h --grep='^<KEY>:')` (short-sha match, both `%h` lengths).
- **Tier mapping**: model name prefix → tier (fable→orchestrator, opus→heavy, sonnet→small, haiku→micro) — mirrors the pricing table's prefixes; agent column + `kind` distinguish main vs subagent work.
- **Pricing**: never stored per event; cost derives at query time from the telemetry DB's `pricing` table (provider × model × model-version, effective-dated) — join `events.ts` against the price in force at that time.
- **Context sidecar** (kit → telemetry): when telemetry is enabled, the orchestrator writes `.claude/telemetry-context.json` at tracker-task start — `{"issue_key", "project", "size", "summary"}` (summary = one sentence from the brief) — and rewrites it on task switch; capture stamps these onto events. Attribution is last-declared-task; that approximation is documented, not hidden.
- **Secrets note**: DB paths and cost figures are shareable; transcript paths are not — queries in this contract never expose transcript contents (security.md applies to anything posted to the PM tool).

## Kit v0.12.0 design

### 1. Snapshot schema v2 (`tokens` section)

Both `templates/<tracker>/stats-collection-brief.md` gain a final optional step: if the telemetry DB is available per `token-economics.md`, query it for the same SCOPE/PERIOD and merge a `tokens` object into the snapshot; `stats_schema` becomes 2 with `tokens` nullable (null = telemetry absent — consumers must handle both). Keys: `in`, `out`, `cache_r`, `cache_w`, `cache_hit_pct`, `by_tier` (orchestrator/heavy/small/micro → {out, est_cost}), `by_model`, `main_vs_subagent`, `est_cost_usd` (total, from the referenced pricing map), `events`.

### 2. Renders (reporting.md)

- **Architect digest**: new paragraph — period cost, tier split, cache hit rate, cost trend vs previous snapshot; called out when heavy-tier spend concentrates on small-sized issues (the raw signal the excluded calibration report would formalize).
- **Milestone close-out**: total milestone cost (branch-scoped snapshot) + cost alongside delivered-vs-planned.
- **Stakeholder page**: total estimated cost for the period/milestone in absolute dollars, plus trend — still ZERO agent internals (no tiers, models, or token counts; one currency line).

### 3. Cost-per-issue comment (documentation-agent.md)

Documentation agent's closing-comment step gains: if telemetry is available, compute the issue's cost per the contract's per-issue recipe and append one line to the closing comment — `Cost: ~$X.XX (N tokens across M commits)`. Estimates flagged as estimates; skipped silently without telemetry.

### 4. Context sidecar rule (kit side)

One standing-rule line in `CLAUDE.core.md`: when telemetry is enabled and work on a tracker issue starts (or switches), write `.claude/telemetry-context.json` per `token-economics.md`; remove it when leaving tracker work. The sidecar is gitignored (install/upgrade add the ignore line). This is the entire kit-side cost of enrichment — one file write per task switch, zero model-token overhead.

### 5. Install/upgrade opt-in

- `install-agent-os`: after PM-tool selection, if the token-telemetry plugin is installed (or the user asks), offer opt-in — create `.claude/telemetry` marker; record `telemetry: enabled|disabled` as a NEW 14th PROJECT-INFO frontmatter key (placeholder `{{TELEMETRY}}` → validate-kit KNOWN list extended in the same PR, per rule 8).
- `upgrade-agent-os`: detects a missing `telemetry` key as part of its normal diff; offers the marker only when the plugin is present.
- `project-info` skill validates the key against the marker's actual presence.

### 6. Upgrade hardening (from the live test)

1. `upgrade-agent-os` step 3: explicitly name the tracker files among installables — "missing cascade files INCLUDING the selected tracker's `tracker-config.md` and `stats-collection-brief.md` (installed to `.docs/agents/`)". (Live test: the stats brief was skipped because it lives under `templates/<tracker>/`.)
2. Intake briefs' guide content: add the `## Scope / ## DoD` feature/story template line (guide currently lags `ticket-filing.md`).
3. Status assumption: intake briefs + `ticket-filing.md` say "Backlog (or the workflow's initial status where Backlog doesn't exist — record which)". (Live test: AOS has no Backlog.)
4. Intake brief TARGET line: verify by KEY; note the tracker display name may differ from the repo name (live test: "agent-token-telemetry" vs "AgentOS").
5. `validate-kit` scenarios (a)/(b): add `.docs/agents/stats-collection-brief.md` presence to the verification lists.

### File change list (kit)

| File | Change |
|---|---|
| `templates/docs/agents/token-economics.md` | new (the contract) |
| `templates/jira/stats-collection-brief.md`, `templates/linear/stats-collection-brief.md` | tokens step, schema v2, hardening items 2–4 as applicable |
| `templates/docs/agents/reporting.md` | cost paragraphs in all three renders |
| `templates/docs/agents/documentation-agent.md` | cost line in closing comment |
| `templates/docs/agents/ticket-filing.md` | status wording (hardening 3) |
| `templates/jira/intake-structure-brief.md`, `templates/linear/intake-structure-brief.md` | guide DoD line, status wording, TARGET-by-key (hardening 2–4) |
| `templates/docs/PROJECT-INFO.md` | `telemetry` frontmatter key |
| `templates/CLAUDE.core.md` | ONE combined line (budget: file is 44/45): cascade entry that is also the sidecar trigger — "Token/cost reporting, and starting/switching tracker-issue work with telemetry enabled (write the context sidecar) → `.docs/agents/token-economics.md`" |
| `.gitignore` guidance (install/upgrade skills) | ignore `.claude/telemetry-context.json` in consumers |
| `skills/install-agent-os/SKILL.md`, `skills/upgrade-agent-os/SKILL.md`, `skills/project-info/SKILL.md`, `skills/validate-kit/SKILL.md` | opt-in flow, hardening 1 + 5 |
| `scripts/validate-kit.sh` | KNOWN list + `{{TELEMETRY}}`; tracker-folder check unchanged |
| `README.md`, `CLAUDE.md` | suite story, inventory, extension-rule touch |
| `.claude-plugin/plugin.json` | 0.12.0 |

## Telemetry v0.2.0 design (companion, in agent-token-telemetry)

1. **Schema (additive migration, `PRAGMA user_version` 0→2)**:
   - `events` gains nullable columns `issue_key TEXT`, `task_size TEXT`, `note TEXT` (the sidecar summary) — `ALTER TABLE ADD COLUMN`, safe on live DBs, applied idempotently in `connect()`.
   - New `pricing` table: `provider TEXT, model_prefix TEXT, model_version TEXT, in_usd REAL, out_usd REAL, cache_r_usd REAL, cache_w_usd REAL, effective_from INTEGER, source TEXT` (unique on provider+prefix+version+effective_from). Seeded from today's map on first migration. Cost at query time = rates in force at `events.ts` (latest `effective_from` ≤ ts), longest-prefix model match.
2. **`capture.py` sidecar read**: after opt-in passes, read `<project-root>/.claude/telemetry-context.json` if present (malformed → ignore silently); stamp `issue_key`/`task_size`/`note` onto the rows written this invocation. Fallback when absent: `issue_key` from the last commit subject's `<KEY>:` prefix (reuses the hardened git runner), size/note null. Tests extend accordingly (sidecar present / absent / malformed / stale).
3. **`commands/token-stats.md`**: queries move to the pricing table (no hardcoded map); additions — by-milestone (`branch LIKE 'milestone/%'`), by-tier (prefix map matching the contract), by-issue (`GROUP BY issue_key`), and a per-issue recipe parameterized by key (sidecar column first, git-log join fallback) noted as the same recipe the kit's documentation agent uses.
4. **Pricing refresh**: new `commands/pricing-update.md` — an agent fetches Anthropic's published pricing page(s), compares against the table's current rates, and inserts new effective-dated rows on change (never mutates history; unknown models reported, not guessed). New `commands/schedule-pricing.md` registers it as a weekly scheduled background agent where the host supports scheduled tasks (Claude Code routines); documented caveat: there is no official pricing API — the page-reading agent is best-effort, the manual command is the reliable path, and stale pricing degrades gracefully (cost estimates carry their `effective_from` date).
5. **`docs/TELEMETRY-CONTRACT.md`**: stability promise — `events(branch, commit_sha, agent, kind, model_id, issue_key, task_size, note …)` and `pricing` are consumed interfaces; breaking changes bump `PRAGMA user_version` and this doc together.
6. **Marketplace**: publish the repo to GitHub `Zenosyne-Technologies/agent-token-telemetry`; add a `token-telemetry` entry (external source) to the kit repo's `.claude-plugin/marketplace.json` so `emprove` serves the suite; README install instructions in both repos updated.
7. Version 0.2.0. Hooks manifest unchanged; capture changes are covered by the extended unittest suite.

## Compatibility

- Snapshot consumers: `stats_schema` 1 → 2 is additive-nullable; the only v1 consumers are the kit's own renders, updated in the same release.
- Projects without telemetry: everything degrades to today's behavior (null tokens, no cost lines).
- Existing installs: `upgrade-agent-os` delivers all of it (new cascade file, edited briefs/renders, frontmatter key) — the live-tested path.

## Testing

- Kit: static gate (CI); scratch coherence walk of the contract's cross-references (briefs ↔ token-economics ↔ renders ↔ documentation-agent ↔ frontmatter).
- Live end-to-end on agent-token-telemetry itself (now a current v0.11.0 install with real AOS Jira): enable telemetry, run a work session, dispatch collection → verify snapshot v2 tokens section from real usage.db rows; render digest + close-out; close one issue and verify the cost comment; stakeholder render carries one cost line and zero internals.

## Resolved owner questions (2026-08-04)

1. Marketplace: publish to GitHub `Zenosyne-Technologies/agent-token-telemetry` — confirmed.
2. Stakeholder cost: absolute dollars — confirmed; pricing became effective-dated data with weekly agent-driven refresh (§Telemetry 1, 4).
3. Per-issue cost comments: at issue close only — confirmed; enrichment via the context sidecar (§Kit 4, §Telemetry 1–2) ties events to issue key, project, size, and a one-sentence summary when both systems are enabled.
