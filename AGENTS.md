# Agent Operating Kit — rules for agents working ON this repo

This repo is a **Codex plugin** (plugin name `marvin` — "Marvin — The Agentic Operating System") that installs an orchestration methodology into other projects. You are editing the factory, not a consumer project.

## The division (never blur it)

- **`templates/`** — the PAYLOAD. Everything here is copied into consumer projects by the `install-agent-os` skill. It must stay project-agnostic: placeholders (`{{NAME}}`) for anything project-specific, tier names (`frontier/escalation/worker/micro`) instead of model names, no absolute paths, no references to `${CLAUDE_PLUGIN_ROOT}` (installed projects must be self-contained). One deliberate exception: `templates/pm/INSTALL.md` is a factory-side reference the install/upgrade skills read — never copied into a consumer — but it lives here so PM-tool support stays in one folder and is held to the same template gates.
- **Everything else** — the FACTORY: plugin machinery (`.Codex-plugin/`, `skills/`), kit docs (`README.md`, `BOOTSTRAP.md`), and this file. May reference plugin paths; never gets copied into consumer projects.

A change that helps one specific project belongs in that project's installed files, not in `templates/`. Only lessons that generalize get promoted into templates.

## How the kit works

`skills/install-agent-os/SKILL.md` is the main entry point (`skills/project-info/SKILL.md`: create-if-missing / validate-and-auto-fix for `.docs/PROJECT-INFO.md`; `skills/upgrade-agent-os/SKILL.md`: migrate an existing install to the current kit version): it reads `templates/`, resolves placeholders from the target repo's own facts, merges (never overwrites) existing AGENTS.md/settings, runs the PM subsystem flow defined in `templates/pm/INSTALL.md` (selection Linear | Jira | GitHub | Local — never inferred — reachability sensecheck, project-key resolution), installs that tool's `tracker-config.md`, and dispatches its `templates/pm/<tracker>/intake-structure-brief.md` to build the tracker structure. `BOOTSTRAP.md` is a pointer prompt at the install skill for plugin-less environments — flow changes edit the skill (or `templates/pm/INSTALL.md` for PM-selection flow) ONLY. The optional companion `token-telemetry` plugin's contract with this kit — what it reads, what it writes, and how reporting degrades without it — lives in `templates/docs/agents/token-economics.md`, not here.

## Extension rules

1. **New activity rule** → add `templates/docs/agents/<activity>.md` (lean, one activity), add its reference line to the cascade in `templates/Codex.core.md`, update the README inventory.
2. **New tracker support** (GitHub Issues/…) → new folder `templates/pm/<tracker>/` mirroring the existing ones: intake brief + `tracker-config.md` + `stats-collection-brief.md` (same snapshot schema) (levels vs the kit's 4-level target, virtual-milestone rule if fewer, severity mapping to the native scheme). Taxonomy and template carry over 1:1, sev labels stay canonical; `ticket-filing.md` stays tracker-neutral except its coordinates line; add the tool to `templates/pm/INSTALL.md`'s selection, sensecheck, and project-key tables (the skills read it — do not restate the flow in a skill). Intake briefs MUST be idempotent/re-runnable — the upgrade skill re-dispatches them as the label-sync mechanism.
3. **Every template change** → bump `version` in `.Codex-plugin/plugin.json`.
4. **Keep files lean** — the kit's core value is context proportionality. Templates stay ≤60 lines (Codex.core.md, always-loaded, ≤55) — past that, split into the cascade instead.
5. **Validate by installing**: run the `install-agent-os` skill against a scratch repo and check every placeholder resolves and the merge path works.
6. **No AI attribution** in this repo's commits/PRs (also the default policy the kit ships).
7. **Label registry changes** → edit `templates/docs/agents/label-syntax.md` only; bump the registry's OWN version and add its changelog row (on top of the plugin version bump). Never define labels anywhere else — briefs and guides reference the registry.
8. **Every PR must pass `scripts/validate-kit.sh`** (CI runs it; run it locally before pushing). Extend the script's known-placeholder list when a template legitimately introduces a new placeholder — in the same PR.
9. **Every release adds `upgrades/v<version>.md`** — ≤15 lines, ONLY the consumer-visible deltas from the previous version as mechanical steps; factory-only releases state "No consumer-visible changes". The upgrade skill walks these files in order; CI enforces the current version's file exists.

## Origin

Extracted 2026-07-08 from the Calsye build (7 milestones, 37 agent-built + independently validated tasks). The battle-tested lessons baked into the templates: fresh adversarial validators, machine-consumed final messages, no mid-run policy changes, env-wiring-is-part-of-the-feature, API-level checks are not browser E2E.
