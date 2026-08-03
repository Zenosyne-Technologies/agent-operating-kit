---
name: install-agent-os
description: Install the Agent Operating Kit (orchestrator + sub-agent methodology) into the current project — writes CLAUDE.md core rules, docs/agents/ cascade, attribution settings, and optionally creates the Jira intake structure. Use when the user asks to install/bootstrap the agent operating kit, agent operating model, or orchestration methodology into a repo.
---

# Install the Agent Operating Kit

Install the kit from this plugin's templates into the current project. Template source of truth: `${CLAUDE_PLUGIN_ROOT}/templates/`.

## Steps

1. **Read the templates** — every file under `${CLAUDE_PLUGIN_ROOT}/templates/` (they are short). Understand the placeholder convention (`{{NAME}}`).
2. **Gather project facts yourself** (don't ask unless truly undiscoverable): stack + layout from the repo; how shell commands must run (version managers, env prefixes); dev-stack command + ports; where long-form docs live (create `docs/` notes if none); which issue tracker is connected and the coordinates to use (for Jira: site URL + project key; Confluence space if any).
3. **Write `CLAUDE.md`** at the repo root from `templates/CLAUDE.core.md` with every placeholder resolved. If a CLAUDE.md exists, MERGE — kit rules become the operating-model section, existing project rules are preserved. Start the "conventions that bite" list empty or from the project's existing lessons.
4. **Copy `templates/docs/agents/`** to `docs/agents/`, resolving placeholders (docs location, tracker coordinates).
5. **Attribution** — ask the user ONE question: keep default AI commit/PR attribution, or disable it? If disable: merge `templates/settings.json` into `.claude/settings.json` (empty-string `attribution.commit`/`attribution.pr` values mean "disabled") and keep the attribution line in CLAUDE.md; if keep: skip the settings file and delete that CLAUDE.md line.
6. **Map model tiers** to currently available models (frontier orchestrator / escalation / default worker / micro) and write the concrete names into CLAUDE.md's dispatch table.
7. **Tracker structure** — if Jira (or another tracker) is connected: fill `${CLAUDE_PLUGIN_ROOT}/templates/jira/intake-structure-brief.md` and dispatch it as a sub-agent; paste the resulting guide URL into `docs/agents/ticket-filing.md`. If no tracker is connected, note it in CLAUDE.md as pending and keep the file-based issue log as the sole log.
8. **Commit** the added files per the attribution policy chosen in step 5.
9. **Report**: what was installed, the tier mapping, tracker structure status, and any placeholder you could not resolve.

From then on, operate by the installed CLAUDE.md's dispatch and lifecycle rules.

## Rules

- Templates are copied and resolved — never reference `${CLAUDE_PLUGIN_ROOT}` paths from the installed files (the consumer project must be self-contained).
- Keep installed files as lean as the templates; do not inline extra explanation.
- Never overwrite existing project rules without merging.
