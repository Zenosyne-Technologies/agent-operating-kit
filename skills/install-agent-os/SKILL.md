---
name: install-agent-os
description: Install the Agent Operating Kit (orchestrator + sub-agent methodology) into the current project — writes CLAUDE.md core rules, .docs/agents/ cascade, attribution settings, and creates the intake structure in the PM tool the user selects (Linear or Jira). Use when the user asks to install/bootstrap the agent operating kit, agent operating model, or orchestration methodology into a repo.
---

# Install the Agent Operating Kit

Install the kit from this plugin's templates into the current project. Template source of truth: `${CLAUDE_PLUGIN_ROOT}/templates/`.

## Steps

1. **Read the templates** — every file under `${CLAUDE_PLUGIN_ROOT}/templates/` (they are short). Understand the placeholder convention (`{{NAME}}`).
2. **Gather project facts yourself** (don't ask unless truly undiscoverable): stack + layout from the repo; how shell commands must run (version managers, env prefixes); dev-stack command + ports; where long-form docs live (create `.docs/` notes if none); which trackers are connected and their coordinates (Jira: site URL + project key, Confluence space if any; Linear: team + project).
3. **PM tool selection** — ask the user which supported PM tool this project uses, presented as a selection they pick from (AskUserQuestion where available): **Linear | Jira | none** (none → file-based issue log only). Never pick silently, even if only one tracker is connected. Combine this prompt with the attribution question from step 6 — one interruption, two answers.
4. **Write `CLAUDE.md`** at the repo root from `templates/CLAUDE.core.md` with every placeholder resolved. If a CLAUDE.md exists, MERGE — kit rules become the operating-model section, existing project rules are preserved. Start the "conventions that bite" list empty or from the project's existing lessons.
5. **Copy `templates/docs/agents/`** to `.docs/agents/`, resolving placeholders (docs location, tracker coordinates, `label-syntax.md` area values). The label-syntax registry is what makes planners and sub-agents label every item they create or edit — and backfill unlabeled ones — so reporting stays possible; its version lives in the file itself, never resolve or alter it. Also create **`.docs/PROJECT-INFO.md`** from `templates/docs/PROJECT-INFO.md` with every fact resolved — its YAML frontmatter is the machine contract foreign agents and reporting tools parse: resolve EVERY key (`pm_tool`: linear | jira | none; `hierarchy_levels`: `4/4` or `3/4-virtual-milestones`; `kit_version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`'s `version`; `label_syntax_version` from the registry's H1) and keep the body prose human. If it already exists (re-install), do NOT recreate it — validate it and auto-fix discrepancies via a sub-agent per the `project-info` skill. Also copy the selected tool's `templates/<tracker>/tracker-config.md` to `.docs/agents/tracker-config.md` (resolve placeholders) — it defines the tool's available levels vs the kit's 4-level target, the virtual-milestone rule when only 3 exist (`milestone:<slug>` labels on epics, convertible to releases/milestones later), and the severity→native mapping. Planners follow it as installed; don't restate it elsewhere. Copy the same tool's `templates/<tracker>/stats-collection-brief.md` to `.docs/agents/stats-collection-brief.md` with coordinates resolved — SCOPE and PERIOD stay fill-at-dispatch placeholders — so the reporting lifecycle works without the plugin. **Backwards compatibility**: if a previous install of this kit put the cascade in `docs/agents/`, `git mv` the kit's files to `.docs/agents/` and rewrite every `docs/agents/` reference in the existing CLAUDE.md; docs that did not come from this kit stay where they are.
6. **Attribution** — ask the user ONE question (with step 3's prompt): keep default AI commit/PR attribution, or disable it? If disable: merge `templates/settings.json` into `.claude/settings.json` (empty-string `attribution.commit`/`attribution.pr` values mean "disabled") and keep the attribution line in CLAUDE.md; if keep: skip the settings file and delete that CLAUDE.md line.
7. **Map model tiers** to currently available models and write the concrete names into CLAUDE.md's dispatch table. Current recommendation (re-check at install time — usage economics move): frontier orchestrator = Fable (advise the architect to run their own sessions on it), heavy worker = Opus (`size:m`+ executions, research), small worker = Sonnet (small clearly-defined executions, validators), micro = Haiku (ponytail).
8. **Tracker structure** — for the selected tool: fill `${CLAUDE_PLUGIN_ROOT}/templates/<tracker>/intake-structure-brief.md` and dispatch it as a sub-agent; paste the resulting guide URL into `.docs/agents/ticket-filing.md`. If the user chose none, note it in CLAUDE.md as pending and keep the file-based issue log as the sole log.
9. **Commit** the added files per the attribution policy chosen in step 6 — commit directly, do not ask for approval (autocommit is kit policy; the installed rules apply it to all future work too).
10. **Report**: what was installed, the selected PM tool + its level configuration, the label-syntax registry version, the PROJECT-INFO.md location, the tier mapping, tracker structure status, and any placeholder you could not resolve.

From then on, operate by the installed CLAUDE.md's dispatch and lifecycle rules.

## Rules

- Templates are copied and resolved — never reference `${CLAUDE_PLUGIN_ROOT}` paths from the installed files (the consumer project must be self-contained).
- Keep installed files as lean as the templates; do not inline extra explanation.
- Never overwrite existing project rules without merging.
