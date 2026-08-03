# Agent Operating Kit — rules for agents working ON this repo

This repo is a **Claude Code plugin** that installs an orchestration methodology into other projects. You are editing the factory, not a consumer project.

## The division (never blur it)

- **`templates/`** — the PAYLOAD. Everything here is copied into consumer projects by the `install-agent-os` skill. It must stay project-agnostic: placeholders (`{{NAME}}`) for anything project-specific, tier names (`frontier/escalation/worker/micro`) instead of model names, no absolute paths, no references to `${CLAUDE_PLUGIN_ROOT}` (installed projects must be self-contained).
- **Everything else** — the FACTORY: plugin machinery (`.claude-plugin/`, `skills/`), kit docs (`README.md`, `BOOTSTRAP.md`), and this file. May reference plugin paths; never gets copied into consumer projects.

A change that helps one specific project belongs in that project's installed files, not in `templates/`. Only lessons that generalize get promoted into templates.

## How the kit works

`skills/install-agent-os/SKILL.md` is the main entry point (`skills/project-info/SKILL.md` is a standalone helper: create-if-missing / validate-only for `.docs/PROJECT-INFO.md`): it reads `templates/`, resolves placeholders from the target repo's own facts, merges (never overwrites) existing CLAUDE.md/settings, asks the user which supported PM tool to use (Linear | Jira — a selection, never inferred), installs that tool's `tracker-config.md`, and dispatches its `templates/<tracker>/intake-structure-brief.md` to build the tracker structure. `BOOTSTRAP.md` is the same flow as a paste-able prompt for environments without the plugin. Keep the two in lockstep — any flow change edits BOTH.

## Extension rules

1. **New activity rule** → add `templates/docs/agents/<activity>.md` (lean, one activity), add its reference line to the cascade in `templates/CLAUDE.core.md`, update the README inventory.
2. **New tracker support** (GitHub Issues/…) → new folder `templates/<tracker>/` mirroring the existing ones: intake brief + `tracker-config.md` (levels vs the kit's 4-level target, virtual-milestone rule if fewer, severity mapping to the native scheme). Taxonomy and template carry over 1:1, sev labels stay canonical; `ticket-filing.md` stays tracker-neutral except its coordinates line; add the tool to the skill's and BOOTSTRAP's selection lists.
3. **Every template change** → bump `version` in `.claude-plugin/plugin.json`.
4. **Keep files lean** — the kit's core value is context proportionality. If a template grows past ~40 lines, split it into the cascade instead.
5. **Validate by installing**: run the `install-agent-os` skill against a scratch repo and check every placeholder resolves and the merge path works.
6. **No AI attribution** in this repo's commits/PRs (also the default policy the kit ships).
7. **Label registry changes** → edit `templates/docs/agents/label-syntax.md` only; bump the registry's OWN version and add its changelog row (on top of the plugin version bump). Never define labels anywhere else — briefs and guides reference the registry.

## Origin

Extracted 2026-07-08 from the Calsye build (7 milestones, 37 agent-built + independently validated tasks). The battle-tested lessons baked into the templates: fresh adversarial validators, machine-consumed final messages, no mid-run policy changes, env-wiring-is-part-of-the-feature, API-level checks are not browser E2E.
