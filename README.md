# Agent Operating Kit

A reusable methodology for running AI-assisted software projects with an orchestrator + sub-agent system: size-routed model-tier dispatch, a cascading ruleset that keeps context lean, DoD-gated task lifecycles with sequenced adversarial validation (completion, then security), security and secrets discipline, a versioned label registry feeding collect-once reporting — and, with the companion **token-telemetry** plugin, full token/dollar cost visibility down to the individual tracker issue. Battle-tested on a full 7-milestone SaaS build (37 agent-built tasks, every one independently validated), and self-hosting: this kit and its companion are built and operated under their own rules.

## Core ideas

1. **Tier dispatch** — the orchestrator (frontier model — the architect's recommended session model) plans, briefs, and verifies; it never bulk-implements. Execution routes by task size: medium-and-larger work and research to the heavy worker tier, small clearly-defined work to the small worker tier, mechanical micro-tasks to the micro model ("ponytail" profile). After two failed attempts at any tier, escalation goes to the frontier model; milestone close is validated by the orchestrator itself working with small-worker sub-agents.
2. **Cascading ruleset** — one always-loaded core file (`CLAUDE.md`) holds only the rules that apply to *every* turn; per-activity rules live in `.docs/agents/*.md` and are *referenced* in briefs, never inlined. Context stays proportional to the task.
3. **Task lifecycle** — no task enters build without a planner-authored DoD on the tracker issue (`## Scope / ## DoD`, verifiable done-statements); build (worker, TO the DoD) → validate in sequence (completion validator falsifies the DoD per item first — Playwright or direct browser driving for web-facing work — then the security validator, only after completion passes; fresh agents, never the builder) → document (docs agent) → close the tracker issue with commit refs.
4. **Brief discipline** — env preamble, exact scope, ownership boundaries, milestone-branch + autocommit instructions, idempotency, machine-consumed final messages, no mid-run policy changes.
5. **Git discipline** — each milestone works on a `milestone/<slug>` feature branch, merged back only after validation; agents (orchestrator and sub-agents alike) autocommit finished work — atomic, selectively staged, never awaiting approval; commit messages start with their tracker issue key, so every commit traces and syncs back to the PM tool.
6. **Sized planning research** — tasks carry `size:xs..xl` t-shirt labels; `size:xl` plans get adversarial plan-validation + solution research at the escalation tier, `size:l` at the worker tier, smaller sizes skip research. Findings land as issue comments or md docs and are folded into the plan before building.
7. **Tracker intake structure** — a systematic label registry (`label-syntax.md`, self-contained and versioned: type/area/severity/origin dimensions on every item agents create or edit, with backfill-on-touch for unlabeled issues — built for statistics and reporting), a filing template, dedupe rules, and QA-sweep conventions, stored as a document *inside* the tracker so agents and humans share one source of truth. Each supported PM tool ships a `tracker-config.md`: levels available vs the kit's 4-level target (milestone → epic → work item → sub-item), a virtual-milestone rule where only 3 exist, and the severity mapping to the native scheme (the kit's sev labels stay canonical).
8. **Collect-once reporting** — a per-tracker stats brief snapshots every label dimension into versioned JSON under `.docs/reports/`; audience renders (architect digest, milestone close-out at milestone close, internals-free stakeholder page) consume the snapshot, never the tracker.
9. **Security discipline** — secrets are never committed and never pasted into PM-tool surfaces (issue comments, snapshots, PR bodies; a leaked secret is a sev1: rotate first); dependency changes are sized `m`+ with advisory checks and pinned versions; every brief names the task's security surface; security-critical design stays orchestrator-inline.
10. **Token economics (optional suite)** — with the token-telemetry companion plugin, a context sidecar ties every captured token to its issue key, task size, and a one-sentence summary; effective-dated pricing turns usage into dollars at query time; snapshots, digests, milestone close-outs, and the stakeholder page carry cost, and closed issues get a one-line cost comment. `token-economics.md` is the contract; everything degrades silently when telemetry is absent.

## Install as a Claude Code plugin (recommended)

This repo is itself a Claude Code plugin (and its own marketplace):

```
claude plugin marketplace add zenosyne-technologies/agent-operating-kit
claude plugin install agent-operating-kit@emprove
```

Then, in any project: invoke the **`install-agent-os`** skill (or just ask "install the agent operating kit into this project"). A second skill, **`project-info`**, creates `.docs/PROJECT-INFO.md` standalone — or, when it already exists, validates it against the repo and auto-fixes discrepancies via a sub-agent, without ever recreating the file. It resolves placeholders from the target repo's own facts, merges with existing CLAUDE.md/settings, asks which supported PM tool the project uses (Linear | Jira — a user selection, never inferred), and creates that tool's intake structure via a sub-agent. A third skill, **`upgrade-agent-os`**, migrates an existing install to the current kit version — file moves, new cascade docs, tracker label re-sync, and (gated behind one confirmation) relabel sweeps for superseded labels. A fourth skill, **`report`**, produces an architect digest, milestone close-out, or stakeholder page from tracker statistics via the installed stats-collection brief. A fifth skill, **`validate-kit`**, runs the kit's own release gate — the static check script plus three agentic scratch-repo scenarios.

Repo layout note: `templates/` is the payload that gets installed into consumer projects; everything else (skills/, .claude-plugin/, this README, CLAUDE.md) is kit machinery — see `CLAUDE.md` for the rules agents must follow when extending the kit itself.

**Cost-aware operations suite**: for token/dollar cost visibility on top of the methodology, also install the companion **`token-telemetry`** plugin from this same marketplace (`claude plugin install token-telemetry@emprove`). It is optional — every kit workflow degrades gracefully without it. Together they close the loop: the kit's orchestrator writes a repo-root `.claude/telemetry-context.json` sidecar at tracker-task start (issue key, project, `size:`, one-sentence summary); telemetry's Stop/SubagentStop hooks capture per-turn usage with zero model-token overhead and stamp the sidecar context onto each event; the kit's conventions make the joins free (`milestone/<slug>` branches → cost per milestone, `<KEY>:` commit prefixes → cost per issue, model prefixes → cost per tier); an effective-dated `pricing` table (agent-refreshable weekly from Anthropic's published pricing) turns tokens into dollars at query time; and the kit's reporting reads it all back — schema-v2 snapshots with a `tokens` section, cost in the digest/close-out/stakeholder renders, and a `Cost: ~$X.XX` line on every closed issue. Contract: `templates/docs/agents/token-economics.md` (kit side) ↔ `docs/TELEMETRY-CONTRACT.md` (telemetry side).

## Updating the plugin after repo changes

Installed plugins are **pinned snapshots** — pushing commits to this repo does NOT update installed copies. Two things must happen:

1. **Bump `version` in `.claude-plugin/plugin.json`** with every release (already mandated by this repo's CLAUDE.md extension rules). Claude Code resolves updates by that version string — new commits under an unchanged version are invisible to installed copies.
2. **Consumers pull the update** (CLI or Desktop, identical behavior):
   ```
   claude plugin marketplace update emprove     # refresh the marketplace clone
   claude plugin update agent-operating-kit@emprove
   ```
   Or enable auto-update once: `/plugin` → Marketplaces → emprove → Enable auto-update (off by default for third-party marketplaces).

New sessions then load the updated plugin; an already-open CLI session needs `/reload-plugins`.

Contributors: every PR must pass `bash scripts/validate-kit.sh` — CI enforces it.

## Manual install (no plugin, 3 steps)

1. Copy `templates/docs/agents/` → `<repo>/.docs/agents/`, your PM tool's `templates/<tracker>/tracker-config.md` → `<repo>/.docs/agents/tracker-config.md`, its `templates/<tracker>/stats-collection-brief.md` → `<repo>/.docs/agents/stats-collection-brief.md`, `templates/CLAUDE.core.md` → `<repo>/CLAUDE.md`, `templates/settings.json` → `<repo>/.claude/settings.json` (merge if one exists). Upgrading an older install that used `docs/agents/`? `git mv` the kit's files to `.docs/agents/` and fix the CLAUDE.md references.
2. Fill every `{{PLACEHOLDER}}` in `CLAUDE.md` (project facts, env preamble, tracker coordinates). Delete rules that don't apply; add project-specific "conventions that bite" as you learn them.
3. Create the tracker structure: give an agent your PM tool's `templates/<tracker>/intake-structure-brief.md` with the placeholders filled (works as a small-model task).

Or paste `BOOTSTRAP.md` into a Claude session — it is a pointer that walks the session through the install skill directly.

## Inventory

```
README.md                          this file
BOOTSTRAP.md                       pointer prompt at the install skill (plugin-less environments)
scripts/validate-kit.sh              seven-check static release gate (CI runs it on every PR)
templates/
  CLAUDE.core.md                   always-loaded core (placeholdered)
  settings.json                    disables AI attribution on commits/PRs (optional policy)
  docs/
    PROJECT-INFO.md                project meta page — YAML frontmatter machine contract + human body (installed to .docs/PROJECT-INFO.md)
  docs/agents/
    briefing.md                    how to write any sub-agent brief
    label-syntax.md                versioned label registry (dimensions incl. sizing, backfill rule, changelog)
    planning-research.md           size-gated plan-validation + solution research, tier routing
    validation-agent.md            BA + security validator personas, E2E hook
    documentation-agent.md         post-task documentation scope
    ticket-filing.md               tracker filing rules (defers to the in-tracker guide)
    ponytail.md                    small-model micro-task profile
    reporting.md                   collect-once render-many report definitions (digest, close-out, stakeholder)
    security.md                    secrets, dependency vetting, and security-surface discipline
    token-economics.md             telemetry contract — cost queries, pricing rule, context sidecar
    handbooks.md                   three-audience Obsidian handbook system — page format, discovery by sources, INDEX rule
  docs/handbooks/
    INDEX.md                       generic handbook ToC skeleton (installed ×3: developer/user/admin)
  linear/
    intake-structure-brief.md      agent brief that creates labels + intake guide
    tracker-config.md              4/4 levels native; severity → Linear Priority
    stats-collection-brief.md      label-dimension stats snapshot (schema v2, optional tokens section) to .docs/reports/
  jira/
    intake-structure-brief.md      agent brief that seeds the label taxonomy + intake guide
    tracker-config.md              3/4 levels + virtual-milestone rule; severity → Jira Priority / JSM Impact
    convert-milestones-brief.md    dispatchable when the v2 connector adds release creation: milestone labels → releases
    stats-collection-brief.md      label-dimension stats snapshot (schema v2, optional tokens section) to .docs/reports/
```

## Portability notes

- Model names are placeholders — map tiers to whatever is current (`frontier` / `heavy worker` / `small worker` / `micro`).
- Tracker-specific parts are confined to `ticket-filing.md`'s coordinates line + `templates/<tracker>/` (currently `linear/` and `jira/`). Adding a PM tool = one new folder (intake brief + `tracker-config.md` + `stats-collection-brief.md`) plus an entry in the skill's selection list; taxonomy and template carry over 1:1, sev1..sev4 labels stay canonical everywhere.
- Hierarchy levels: the kit targets 4 (milestone → epic/feature grouping → work item → sub-item). Linear meets it natively (Project → Milestone → Issue → Sub-issue). Tools exposing only 3 — Jira until its MCP connector can create releases (v2) — use **virtual milestones**: a `milestone:<slug>` label on every epic in the milestone, encoded only in that label so each converts losslessly into a release/milestone/equivalent once the tool or connector allows. The conversion is a prepared brief (`jira/convert-milestones-brief.md`), not just a rule.
- The attribution policy (no AI co-author lines) is an owner preference — delete `settings.json` and the CLAUDE.md line to keep default attribution.
