# Cost-aware operations — kit v0.12.0 × token-telemetry v0.2.0 design

Date: 2026-08-04 · Status: draft for owner review · Repos: agent-operating-kit (this spec, kit v0.12.0) + agent-token-telemetry (companion release v0.2.0)

## Context

The operating kit measures work in issue counts (labels, snapshots, renders); the token-telemetry plugin measures work in tokens and dollars (per-turn/per-subagent SQLite events with model, agent, branch, commit sha) — each blind to the other's dimension. The join keys already exist on both sides: `events.branch` ↔ the kit's `milestone/<slug>` branches; `events.commit_sha` ↔ the kit's `<KEY>:` issue-key commit convention; `events.agent`/`kind` ↔ the kit's tier dispatch. This design connects them through a versioned data contract — no code merge; two plugins, one suite.

Also folded in: five hardening items surfaced by the live upgrade test on agent-token-telemetry (2026-08-04), which exercised `upgrade-agent-os`, the idempotent Jira intake brief, and the gated relabel sweep against the real AOS project.

Owner decisions baked in: cost surfaces in snapshot + digest + close-out + **stakeholder** (all four); cost-per-issue comments at close: yes; sizing-calibration report: **excluded**; packaging: two releases, one marketplace (emprove), no code merge.

## Goals

1. One versioned data contract lets kit reporting consume telemetry data when present, and degrade silently when absent.
2. Stats snapshots carry token/cost economics (schema v2); all three renders answer "what did it cost".
3. Closed issues get a one-line cost comment via the commit-sha → issue-key join.
4. Install/upgrade offer telemetry opt-in and record it in PROJECT-INFO frontmatter.
5. The five live-test hardening items are fixed.
6. `token-telemetry` joins the emprove marketplace; its query surface learns the kit's dimensions.

## Non-goals

- Sizing-calibration render (owner-excluded; the raw data for it exists — a later release can add the render without schema changes).
- Any change to `capture.py` or the events schema (the join surface is already captured; v0.2.0 is query/docs/packaging only — zero capture risk).
- Storing cost in either system (derived at query time from the pricing map, as today).
- Scheduled/cron delivery; dashboards.

## The data contract (new cascade file: `templates/docs/agents/token-economics.md`)

One lean file, installed to `.docs/agents/token-economics.md`, is the single description of the seam. Contents:

- **Source**: `~/.claude/telemetry/usage.db` (or `$TOKEN_TELEMETRY_DB`), SQLite, telemetry plugin's `events/sessions/projects/models` tables. Availability check: file exists AND the project row matches this repo's root path. Absent → every consumer omits its token output silently; nothing fails.
- **Scoping recipe**: milestone economics = `events.branch = 'milestone/<slug>'`; period economics = `events.ts` window; per-issue economics = `events.commit_sha IN (git log --format=%h --grep='^<KEY>:')` (short-sha match, both `%h` lengths).
- **Tier mapping**: model name prefix → tier (fable→orchestrator, opus→heavy, sonnet→small, haiku→micro) — mirrors the pricing map's prefixes; agent column + `kind` distinguish main vs subagent work.
- **Pricing**: never stored; the pricing map lives in the telemetry plugin's `token-stats` command and is referenced, not duplicated (drift risk lives in exactly one file).
- **Secrets note**: DB paths and cost figures are shareable; transcript paths are not — queries in this contract never expose transcript contents (security.md applies to anything posted to the PM tool).

## Kit v0.12.0 design

### 1. Snapshot schema v2 (`tokens` section)

Both `templates/<tracker>/stats-collection-brief.md` gain a final optional step: if the telemetry DB is available per `token-economics.md`, query it for the same SCOPE/PERIOD and merge a `tokens` object into the snapshot; `stats_schema` becomes 2 with `tokens` nullable (null = telemetry absent — consumers must handle both). Keys: `in`, `out`, `cache_r`, `cache_w`, `cache_hit_pct`, `by_tier` (orchestrator/heavy/small/micro → {out, est_cost}), `by_model`, `main_vs_subagent`, `est_cost_usd` (total, from the referenced pricing map), `events`.

### 2. Renders (reporting.md)

- **Architect digest**: new paragraph — period cost, tier split, cache hit rate, cost trend vs previous snapshot; called out when heavy-tier spend concentrates on small-sized issues (the raw signal the excluded calibration report would formalize).
- **Milestone close-out**: total milestone cost (branch-scoped snapshot) + cost alongside delivered-vs-planned.
- **Stakeholder page**: total estimated cost for the period/milestone and trend — figures only, still ZERO agent internals (no tiers, models, or token counts; one currency line).

### 3. Cost-per-issue comment (documentation-agent.md)

Documentation agent's closing-comment step gains: if telemetry is available, compute the issue's cost per the contract's per-issue recipe and append one line to the closing comment — `Cost: ~$X.XX (N tokens across M commits)`. Estimates flagged as estimates; skipped silently without telemetry.

### 4. Install/upgrade opt-in

- `install-agent-os`: after PM-tool selection, if the token-telemetry plugin is installed (or the user asks), offer opt-in — create `.claude/telemetry` marker; record `telemetry: enabled|disabled` as a NEW 14th PROJECT-INFO frontmatter key (placeholder `{{TELEMETRY}}` → validate-kit KNOWN list extended in the same PR, per rule 8).
- `upgrade-agent-os`: detects a missing `telemetry` key as part of its normal diff; offers the marker only when the plugin is present.
- `project-info` skill validates the key against the marker's actual presence.

### 5. Upgrade hardening (from the live test)

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
| `templates/CLAUDE.core.md` | cascade line for token-economics.md (≤45 budget check) |
| `skills/install-agent-os/SKILL.md`, `skills/upgrade-agent-os/SKILL.md`, `skills/project-info/SKILL.md`, `skills/validate-kit/SKILL.md` | opt-in flow, hardening 1 + 5 |
| `scripts/validate-kit.sh` | KNOWN list + `{{TELEMETRY}}`; tracker-folder check unchanged |
| `README.md`, `CLAUDE.md` | suite story, inventory, extension-rule touch |
| `.claude-plugin/plugin.json` | 0.12.0 |

## Telemetry v0.2.0 design (companion, in agent-token-telemetry)

1. `commands/token-stats.md`: three additions — by-milestone breakdown (`branch LIKE 'milestone/%'`), by-tier grouping (model-prefix map, matching the contract), and a per-issue query recipe (parameterized by issue key, using the git-log join) with a note that the kit's documentation agent uses the same recipe.
2. `docs/`: a `TELEMETRY-CONTRACT.md` stating the stability promise — `events(branch, commit_sha, agent, kind, model_id …)` is a consumed interface; breaking changes bump SQLite `PRAGMA user_version` and the contract doc together.
3. Marketplace: publish the repo to the Zenosyne-Technologies org; add a `token-telemetry` entry to the kit repo's `.claude-plugin/marketplace.json` (external source) so `emprove` serves the suite; README install instructions in both repos updated.
4. Version 0.2.0. No changes to `capture.py`, hooks, or tests.

## Compatibility

- Snapshot consumers: `stats_schema` 1 → 2 is additive-nullable; the only v1 consumers are the kit's own renders, updated in the same release.
- Projects without telemetry: everything degrades to today's behavior (null tokens, no cost lines).
- Existing installs: `upgrade-agent-os` delivers all of it (new cascade file, edited briefs/renders, frontmatter key) — the live-tested path.

## Testing

- Kit: static gate (CI); scratch coherence walk of the contract's cross-references (briefs ↔ token-economics ↔ renders ↔ documentation-agent ↔ frontmatter).
- Live end-to-end on agent-token-telemetry itself (now a current v0.11.0 install with real AOS Jira): enable telemetry, run a work session, dispatch collection → verify snapshot v2 tokens section from real usage.db rows; render digest + close-out; close one issue and verify the cost comment; stakeholder render carries one cost line and zero internals.

## Open questions (owner)

1. Marketplace source for token-telemetry: publish to GitHub `Zenosyne-Technologies/agent-token-telemetry` (assumed) — confirm org/visibility.
2. Stakeholder cost line: absolute dollars, or a normalized figure (e.g., relative trend) if dollar amounts shouldn't reach external readers?
3. The per-issue cost comment fires at issue close only (documentation agent). Also on milestone close-out for every issue in the milestone, or is close-time enough?
