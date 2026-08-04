# Cost-Telemetry Integration (kit v0.12.0 + telemetry v0.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the operating kit and token-telemetry per `docs/superpowers/specs/2026-08-04-cost-telemetry-integration-v0.12.0-design.md`: token-economics contract, schema-v2 snapshots with cost, cost in all renders + issue-close comments, context sidecar, effective-dated pricing table with weekly refresh, install/upgrade opt-in, five upgrade-hardening fixes, suite packaging.

**Architecture:** Two repos. KIT (this repo, branch `claude/cost-telemetry-v0.12.0`): markdown payload + skills + gate. TELEMETRY (`/Users/spike/Dev/agent-token-telemetry`, branch `claude/v0.2.0` off main): Python capture + SQLite schema + commands. The spec is the requirements source; this plan pins exact mechanics.

**Tech Stack:** Markdown; Python 3 stdlib + sqlite3 + unittest (telemetry).

## Global Constraints

- NO AI attribution in commits, either repo.
- NEW line budgets (this release changes them): `templates/` files ≤ **60** lines, EXCEPT `templates/CLAUDE.core.md` ≤ **50**. Task K1 updates the gate and repo rules FIRST so later tasks build against the new caps.
- No `${CLAUDE_PLUGIN_ROOT}`/model names in templates/; labels only in the registry (untouched, v1.2.0).
- New placeholder this release: `{{TELEMETRY}}` — added to validate-kit.sh KNOWN in the same task that introduces it (K4), per repo rule 8.
- Kit gate `bash scripts/validate-kit.sh` must pass at every kit commit; telemetry tests `python3 -m unittest tests.test_capture -v` must pass at every telemetry commit.
- Read every file before editing. Kit final version 0.12.0 (K5); telemetry 0.2.0 (T2).

---

### Task K1: Line-budget change + token-economics contract + CLAUDE.core line

**Files:** Modify `scripts/validate-kit.sh`, `CLAUDE.md` (repo rule 4), `templates/CLAUDE.core.md`; Create `templates/docs/agents/token-economics.md`.

- [ ] **Step 1**: In `scripts/validate-kit.sh` check 2, replace the fixed 45 with the split: budget 60 for `templates/**/*.md`, 50 for `templates/CLAUDE.core.md` (adjust the loop: `lim=60; [ "$f" = "templates/CLAUDE.core.md" ] && lim=50`; failure message names both caps).
- [ ] **Step 2**: Repo `CLAUDE.md` rule 4: replace `If a template grows past ~40 lines, split it into the cascade instead.` with `Templates stay ≤60 lines (CLAUDE.core.md, always-loaded, ≤50) — past that, split into the cascade instead.`
- [ ] **Step 3**: Create `templates/docs/agents/token-economics.md` (≤60 lines) implementing the spec's contract section verbatim in structure: Source (usage.db path/env override, availability = file exists AND projects.path matches repo root; absent → consumers omit silently); Scoping recipes (milestone = `events.branch='milestone/<slug>'`; period = ts window; per-issue = `events.issue_key = '<KEY>'` preferred, fallback `events.commit_sha IN (git log --format=%h --grep='^<KEY>:')`); Tier mapping table (fable→orchestrator, opus→heavy, sonnet→small, haiku→micro); Pricing (query-time from the telemetry DB `pricing` table, rate in force at events.ts, longest-prefix match; never store cost per event); Context sidecar spec (`.claude/telemetry-context.json`, keys `issue_key/project/size/summary`, write at tracker-task start/switch, delete when leaving tracker work, gitignored; attribution = last-declared task); snapshot `tokens` object keys (`in,out,cache_r,cache_w,cache_hit_pct,by_tier,by_model,main_vs_subagent,est_cost_usd,events`; null when telemetry absent); Secrets line (never expose transcript contents; security.md governs anything posted to the PM tool).
- [ ] **Step 4**: `templates/CLAUDE.core.md` — insert ONE line after the reporting cascade line: `- Token/cost reporting, and starting or switching tracker-issue work with telemetry enabled (write the context sidecar) → \`.docs/agents/token-economics.md\`` (file becomes 45 lines, cap now 50).
- [ ] **Step 5**: Verify — `bash scripts/validate-kit.sh` ALL PASS; `wc -l templates/CLAUDE.core.md templates/docs/agents/token-economics.md` (≤50 / ≤60).
- [ ] **Step 6**: Commit: `feat: token-economics contract + sidecar trigger; line budgets 60/50`

### Task K2: Stats briefs schema v2 + brief hardening + ticket-filing status

**Files:** Modify `templates/jira/stats-collection-brief.md`, `templates/linear/stats-collection-brief.md`, `templates/jira/intake-structure-brief.md`, `templates/linear/intake-structure-brief.md`, `templates/docs/agents/ticket-filing.md`.

- [ ] **Step 1**: Both stats briefs — in step 2's key list change `stats_schema (1)` → `stats_schema (2)` and append `, tokens (per \`.docs/agents/token-economics.md\`: null when the telemetry DB is absent)`; add a new numbered step before COMMIT: `TOKENS (optional): if the telemetry DB is available per \`.docs/agents/token-economics.md\`, query it for the same SCOPE and PERIOD and set the snapshot's \`tokens\` object per the contract (tiers, models, cache hit rate, est_cost_usd from the pricing table); otherwise set \`tokens: null\`.`
- [ ] **Step 2**: Both intake briefs — (a) guide-content clause: after the DoD/backfill labeling clause add `; description templates — bugs \`## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs\`, feature/story items \`## Scope / ## DoD\``; (b) every `status Backlog` mention becomes `status Backlog (or the workflow's initial status where Backlog doesn't exist — record which in the guide)`; (c) TARGET lines: replace the project display-name reference with key-first phrasing — Jira: `TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}} (verify by KEY — the tracker's display name may differ from the repo name).` Linear keeps team/project but gains the same parenthetical after the project name.
- [ ] **Step 3**: `ticket-filing.md` — coordinates line: `new issues → Backlog` becomes `new issues → Backlog (or the workflow's initial status — the guide records which)`.
- [ ] **Step 4**: Verify — gate passes; `grep -c "stats_schema (2)"` = 1 per stats brief; `grep -c "tokens" ` ≥ 2 per stats brief; all touched files ≤60.
- [ ] **Step 5**: Commit: `feat: snapshot schema v2 (tokens), brief hardening from the live upgrade test`

### Task K3: Cost in renders + issue-close cost comment

**Files:** Modify `templates/docs/agents/reporting.md`, `templates/docs/agents/documentation-agent.md`.

- [ ] **Step 1**: `reporting.md` — digest bullet: after the milestone-progress clause add `; token economics when the snapshot carries \`tokens\` — period cost, tier split, cache hit rate, trend vs the previous snapshot, and a call-out when heavy-tier spend concentrates on small-sized issues`. Close-out bullet: add `; total milestone cost (from the milestone-scoped snapshot's \`tokens\`)`. Stakeholder bullet: after the quality-summary clause add `; total estimated cost in absolute dollars with trend — one currency line, still no tiers, models, or token counts`. Rules section: add `- \`tokens: null\` in the snapshot → every render omits its cost content silently.`
- [ ] **Step 2**: `documentation-agent.md` — extend scope item 3 (Tracker closing comment): `Append, when telemetry is available per \`.docs/agents/token-economics.md\`: one line \`Cost: ~$X.XX (N tokens across M commits)\` via the contract's per-issue recipe — clearly an estimate; skip silently without telemetry.`
- [ ] **Step 3**: Verify — gate; both files ≤60; `grep -c "tokens" templates/docs/agents/reporting.md` ≥ 3.
- [ ] **Step 4**: Commit: `feat: cost surfaces in all renders and issue-close comments`

### Task K4: PROJECT-INFO telemetry key + skill updates + KNOWN list

**Files:** Modify `templates/docs/PROJECT-INFO.md`, `skills/install-agent-os/SKILL.md`, `skills/upgrade-agent-os/SKILL.md`, `skills/project-info/SKILL.md`, `skills/validate-kit/SKILL.md`, `scripts/validate-kit.sh`.

- [ ] **Step 1**: PROJECT-INFO frontmatter — insert `telemetry: {{TELEMETRY}}` after `docs_location` (14 keys); add `TELEMETRY` to validate-kit.sh KNOWN (same commit, rule 8).
- [ ] **Step 2**: install skill — step 3 selection prompt gains: if the token-telemetry plugin is present (or the user asks), include a telemetry opt-in choice in the SAME prompt; on enable: create `.claude/telemetry` marker, add `.claude/telemetry-context.json` to the consumer `.gitignore`, resolve `telemetry: enabled` (else `disabled`). Step 5 mentions resolving the new key.
- [ ] **Step 3**: upgrade skill — step 2 diff list gains the `telemetry` frontmatter key; step 3's installables sentence becomes explicit per hardening 1: `add missing cascade files INCLUDING the selected tracker's \`tracker-config.md\` and \`stats-collection-brief.md\` (installed to \`.docs/agents/\`) with placeholders resolved`; step 5 unchanged; the report mentions telemetry opt-in offered when the plugin is present but the marker absent.
- [ ] **Step 4**: project-info skill — validate branch checks `telemetry` key against the marker's actual presence.
- [ ] **Step 5**: validate-kit skill — scenarios (a) and (b) verification lists gain `.docs/agents/stats-collection-brief.md present` and `PROJECT-INFO has 14 frontmatter keys incl. telemetry`.
- [ ] **Step 6**: Verify — gate (placeholders check must pass WITH the new key used); PROJECT-INFO parses 14 keys in order.
- [ ] **Step 7**: Commit: `feat: telemetry opt-in through install/upgrade; validate-kit covers installed stats brief`

### Task K5: Suite packaging + docs + 0.12.0 + gate

**Files:** Modify `README.md`, `CLAUDE.md`, `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`.

- [ ] **Step 1**: marketplace.json — add second plugin entry: `{"name": "token-telemetry", "source": "zenosyne-technologies/agent-token-telemetry", "description": "Zero-token-overhead usage telemetry with kit-aware cost reporting — companion to agent-operating-kit."}` (valid JSON).
- [ ] **Step 2**: README — suite paragraph in the install section (install both plugins for cost-aware operations; telemetry optional, everything degrades without it); inventory line for `token-economics.md` under docs/agents/; core idea 8 extended with `; with the token-telemetry companion plugin, snapshots and renders carry token/dollar economics and closed issues get a cost comment`.
- [ ] **Step 3**: repo CLAUDE.md — "How the kit works" sentence mentioning the companion plugin contract lives in `token-economics.md`.
- [ ] **Step 4**: plugin.json → `0.12.0`. Run gate — ALL PASS (hard gate).
- [ ] **Step 5**: Commit: `feat: v0.12.0 — cost-aware operations suite (marketplace, docs, version)`

---

### Task T1: Telemetry schema v2 + pricing table + sidecar capture (TDD)

**Files (in /Users/spike/Dev/agent-token-telemetry, branch `claude/v0.2.0` off main):** Modify `scripts/capture.py`, `tests/test_capture.py`.

- [ ] **Step 1**: Write failing tests first (extend tests/test_capture.py): (a) fresh DB has `PRAGMA user_version`=2, `pricing` table seeded with ≥4 rows (fable/opus/sonnet/haiku prefixes, effective_from>0, source='seed-v0.2.0'); (b) migrating a pre-existing v0.1.0 DB (create with the OLD schema in the test) adds `issue_key/task_size/note` columns and the pricing table without touching existing rows; (c) sidecar present → event rows carry its `issue_key/size/summary` values in `issue_key/task_size/note`; (d) sidecar absent → issue_key falls back to the last commit subject's `<KEY>:` prefix when one exists (fixture git repo), else NULL; (e) malformed sidecar JSON → ignored silently, capture still succeeds. Run: must FAIL.
- [ ] **Step 2**: Implement in capture.py: `MIGRATIONS` applied in `connect()` — if `user_version` < 2: `ALTER TABLE events ADD COLUMN issue_key TEXT` / `task_size TEXT` / `note TEXT` (each wrapped in try/except OperationalError for idempotency), `CREATE TABLE IF NOT EXISTS pricing(provider TEXT NOT NULL, model_prefix TEXT NOT NULL, model_version TEXT NOT NULL DEFAULT '', in_usd REAL, out_usd REAL, cache_r_usd REAL, cache_w_usd REAL, effective_from INTEGER NOT NULL, source TEXT, UNIQUE(provider, model_prefix, model_version, effective_from))`, seed rows (anthropic: claude-fable-5 10/50/1/12.50, claude-opus 5/25/0.50/6.25, claude-sonnet 3/15/0.30/3.75, claude-haiku 1/5/0.10/1.25; effective_from = migration time, source 'seed-v0.2.0'), `PRAGMA user_version=2`. New `read_sidecar(root)` → dict or None (json errors → None). Fallback `issue_key_from_git(cwd)`: reuse the hardened git runner, `log -1 --format=%s`, regex `^([A-Z][A-Z0-9]+-\d+):`. In `main()`: after opt-in, `ctx = read_sidecar(root) or {}`; pass `issue_key = ctx.get('issue_key') or issue_key_from_git(cwd)`, `task_size = ctx.get('size')`, `note = ctx.get('summary')` through `record()` into the INSERT (3 new columns). Never let sidecar/fallback failures break capture (existing outer try/except covers; keep git call before the write lock like git_meta).
- [ ] **Step 3**: Run `python3 -m unittest tests.test_capture -v` — ALL PASS (old tests must still pass; update any that assert column counts).
- [ ] **Step 4**: Commit: `Add schema v2: pricing table, context-sidecar enrichment, issue-key fallback`

### Task T2: Commands + contract doc + version

**Files (telemetry):** Modify `commands/token-stats.md`, `README.md`, `.claude-plugin/plugin.json`; Create `commands/pricing-update.md`, `commands/schedule-pricing.md`, `docs/TELEMETRY-CONTRACT.md`.

- [ ] **Step 1**: token-stats.md — replace the hardcoded pricing table with: read rates from the `pricing` table (rate in force at each event's ts: max effective_from ≤ ts per longest matching model_prefix; show the effective_from date next to estimates); add three sections: by-milestone (`WHERE branch LIKE 'milestone/%' GROUP BY branch`), by-tier (CASE on model prefix → orchestrator/heavy/small/micro), by-issue (`WHERE issue_key IS NOT NULL GROUP BY issue_key`, note the kit's documentation agent uses the same per-issue recipe with git-log fallback for pre-v0.2.0 rows).
- [ ] **Step 2**: pricing-update.md (new command) — instructions for an agent: fetch Anthropic's current published per-MTok pricing for the model families present in the `models` table (use web fetch of the official pricing/docs pages; no official API exists — read carefully, do not guess); compare against the current effective rates; on change INSERT new rows with today's effective_from and source URL (never UPDATE/DELETE history); report a table of changes; unknown models reported as unpriced. schedule-pricing.md (new) — registers pricing-update as a weekly background scheduled agent where the host supports routines, else prints the manual cadence advice.
- [ ] **Step 3**: docs/TELEMETRY-CONTRACT.md — stability promise per spec §Telemetry 5 (consumed columns list incl. the three new ones, pricing table shape, user_version discipline, sidecar file spec mirroring the kit's token-economics.md).
- [ ] **Step 4**: README — v0.2.0 story (kit-aware columns, pricing table, new commands, suite install via emprove marketplace). plugin.json → `0.2.0`.
- [ ] **Step 5**: Tests still green; commit: `v0.2.0: pricing-as-data commands, kit contract doc, suite README`

### Task T3: Publish + suite wiring

- [ ] **Step 1**: In the telemetry repo: merge `claude/v0.2.0` → main (after review). Create the GitHub repo `Zenosyne-Technologies/agent-token-telemetry` (private), push main.
- [ ] **Step 2**: Kit branch already carries the marketplace entry (K5) — nothing further kit-side.
- [ ] **Step 3**: Verify `gh repo view Zenosyne-Technologies/agent-token-telemetry` resolves.

### Task V: Live end-to-end validation + record

- [ ] **Step 1**: On the telemetry repo (v0.11.0 install, real AOS): enable telemetry (`.claude/telemetry` marker + gitignore line + frontmatter `telemetry: enabled`), write a sample sidecar, run capture against a fixture hook-input/transcript pair (test-style, real DB copy in scratch — NOT the live DB), verify enriched rows and pricing joins.
- [ ] **Step 2**: Dispatch the installed stats brief (scope project, 30d) against real AOS with the scratch DB as TOKEN_TELEMETRY_DB — verify snapshot v2 with a real tokens object; render digest + stakeholder; check the stakeholder render has exactly one cost line and zero internals.
- [ ] **Step 3**: Append `## Validated` to the v0.12.0 spec (kit repo) with outcomes + caveats; commit.
