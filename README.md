# Agent Operating Kit

A reusable methodology for running AI-assisted software projects with an orchestrator + sub-agent system: model-tier dispatch, a cascading ruleset that keeps context lean, adversarial validation personas, post-task documentation agents, and a Jira issue-intake structure. Battle-tested on a full 7-milestone SaaS build (37 agent-built tasks, every one independently validated).

## Core ideas

1. **Tier dispatch** — the orchestrator (frontier model) plans, briefs, and verifies; it never bulk-implements. Default workers are mid-tier; mechanical micro-tasks go to a small model ("ponytail" profile). Escalate only after two failures.
2. **Cascading ruleset** — one always-loaded core file (`CLAUDE.md`) holds only the rules that apply to *every* turn; per-activity rules live in `docs/agents/*.md` and are *referenced* in briefs, never inlined. Context stays proportional to the task.
3. **Task lifecycle** — build (worker) → validate (fresh agents: business-analyst + security-analyst personas, never the builder) → document (docs agent) → close the tracker issue with commit refs.
4. **Brief discipline** — env preamble, exact scope, ownership boundaries, idempotency, machine-consumed final messages, no mid-run policy changes.
5. **Tracker intake structure** — a label taxonomy (type/area/severity/provenance), a filing template, dedupe rules, and QA-sweep conventions, stored as a document *inside* the tracker so agents and humans share one source of truth.

## Install as a Claude Code plugin (recommended)

This repo is itself a Claude Code plugin (and its own marketplace):

```
claude plugin marketplace add zenosyne-technologies/agent-operating-kit
claude plugin install agent-operating-kit@zenosyne
```

Then, in any project: invoke the **`install-agent-os`** skill (or just ask "install the agent operating kit into this project"). It resolves placeholders from the target repo's own facts, merges with existing CLAUDE.md/settings, and optionally creates the Jira intake structure via a sub-agent.

Repo layout note: `templates/` is the payload that gets installed into consumer projects; everything else (skills/, .claude-plugin/, this README, CLAUDE.md) is kit machinery — see `CLAUDE.md` for the rules agents must follow when extending the kit itself.

## Updating the plugin after repo changes

Installed plugins are **pinned snapshots** — pushing commits to this repo does NOT update installed copies. Two things must happen:

1. **Bump `version` in `.claude-plugin/plugin.json`** with every release (already mandated by this repo's CLAUDE.md extension rules). Claude Code resolves updates by that version string — new commits under an unchanged version are invisible to installed copies.
2. **Consumers pull the update** (CLI or Desktop, identical behavior):
   ```
   claude plugin marketplace update zenosyne     # refresh the marketplace clone
   claude plugin update agent-operating-kit@zenosyne
   ```
   Or enable auto-update once: `/plugin` → Marketplaces → zenosyne → Enable auto-update (off by default for third-party marketplaces).

New sessions then load the updated plugin; an already-open CLI session needs `/reload-plugins`.

## Manual install (no plugin, 3 steps)

1. Copy `templates/docs/agents/` → `<repo>/docs/agents/`, `templates/CLAUDE.core.md` → `<repo>/CLAUDE.md`, `templates/settings.json` → `<repo>/.claude/settings.json` (merge if one exists).
2. Fill every `{{PLACEHOLDER}}` in `CLAUDE.md` (project facts, env preamble, tracker coordinates). Delete rules that don't apply; add project-specific "conventions that bite" as you learn them.
3. Create the tracker structure: give an agent `templates/jira/intake-structure-brief.md` with the placeholders filled (works as a small-model task).

Or paste `BOOTSTRAP.md` into a Claude session inside the new project — it performs all three steps interactively.

## Inventory

```
README.md                          this file
BOOTSTRAP.md                       one-shot instantiation prompt
templates/
  CLAUDE.core.md                   always-loaded core (placeholdered)
  settings.json                    disables AI attribution on commits/PRs (optional policy)
  docs/agents/
    briefing.md                    how to write any sub-agent brief
    validation-agent.md            BA + security validator personas, E2E hook
    documentation-agent.md         post-task documentation scope
    ticket-filing.md               tracker filing rules (defers to the in-tracker guide)
    ponytail.md                    small-model micro-task profile
  jira/
    intake-structure-brief.md      agent brief that seeds the label taxonomy + intake guide + hierarchy conventions
```

## Portability notes

- Model names are placeholders — map tiers to whatever is current (`frontier` / `default worker` / `micro`).
- Jira-specific parts are confined to `ticket-filing.md` + `jira/`; swap for Linear/GitHub Issues by rewriting only those two files (taxonomy and template carry over 1:1).
- Hierarchy levels: the current Jira MCP connector cannot create releases, so the kit runs 3 levels (Epic → Story → Task/Sub-task) with epics carrying milestone scope. When the v2 connector adds release creation, milestones move to releases (fixVersions) — restoring the 4-level setup the kit used on Linear (project → milestone → issue → sub-issue).
- The attribution policy (no AI co-author lines) is an owner preference — delete `settings.json` and the CLAUDE.md line to keep default attribution.
