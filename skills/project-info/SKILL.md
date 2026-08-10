---
name: project-info
description: Create the project's .marvin/PROJECT-INFO.md meta page from the kit template, or — if it already exists (including at its pre-v0.21.0 .docs/ location) — validate it against the repo's actual facts and auto-fix discrepancies via a sub-agent, never recreating the file. Use when the user asks to create, generate, check, validate, or fix the project info page / project information overview.
---

# Project info page — create or validate

Template source of truth: `${CLAUDE_PLUGIN_ROOT}/templates/marvin/PROJECT-INFO.md`. Target: `.marvin/PROJECT-INFO.md`.

**Locate before you conclude — the pre-v0.21.0 fallback.** Absent from `.marvin/`? Read `.docs/PROJECT-INFO.md`, then `docs/PROJECT-INFO.md` (pre-v0.21.0 locations) before concluding none exists. Whichever of the three you find FIRST is *the* file — there is exactly one PROJECT-INFO in a repo, because its frontmatter is the machine contract foreign agents and reporting tools parse. Creating a second one at `.marvin/` while the real one sits at `.docs/` is the failure this fallback exists to prevent: the v0.21.0 migration then refuses the move as a destination collision (exit 3), and `upgrade-agent-os` step 1 reads the NEW stamp, finds no upgrade file past it, and does nothing — leaving the cascade stale in `.docs/agents/`, `.marvin/agents/` empty, and every `marvin:*` persona pointing at a path that does not exist.

**Found at a legacy location → validate it THERE, in place, and do not move it.** Relocating is `upgrade-agent-os`'s job, not this skill's: the migration script stages the rename atomically with the reference edits that must land in the same commit. Validate and fix as below, then report — in words — that this install is on the pre-v0.21.0 layout and needs the `upgrade-agent-os` skill, naming the path you validated. The same fallback applies to every fact source this skill reads: `.marvin/agents/*`, else `.docs/agents/*`, else `docs/agents/*`.

## If NO file exists at any of the three locations → create

1. Gather every fact from the repo itself: name/description (manifest, README), owner, layout, tech stack, dev command + ports; PM tool, coordinates, hierarchy, and guide URL from the installed `tracker-config.md` + `ticket-filing.md` if present; label-syntax version from the installed `label-syntax.md`. Ask only for facts that are truly undiscoverable.
2. Write `.marvin/PROJECT-INFO.md` from the template with every placeholder resolved — every YAML frontmatter key filled (`kit_version` from the plugin's `.claude-plugin/plugin.json` when installed via plugin, else the kit repo's; `label_syntax_version` from the installed `label-syntax.md`'s H1); body stays facts-only prose, no operating rules.
3. Commit it (autocommit policy, attribution per the project's settings). Report the created path and any unresolved placeholder.

## If the file EXISTS (at any of the three) → validate, then fix via sub-agent — never recreate

Do NOT overwrite, regenerate, restructure or relocate the existing file.

1. **Validate**: the YAML frontmatter parses and contains every template key (extra project-specific keys are fine — leave them); each frontmatter fact checked against the repo — `stack`, `dev_command`, `tracker_coordinates`/`project_key`/`hierarchy_levels` (vs the installed `tracker-config.md`), `intake_guide_url`, `label_syntax_version` (vs the registry H1), `docs_location`, `telemetry` (`enabled` iff `.claude/telemetry` exists, else `disabled`); body statements must not contradict frontmatter. **`kit_version` is NOT auto-corrected here**: a stamp that disagrees with the layout on disk is a finding for `upgrade-agent-os`'s tie-break (the layout wins), and restamping it from this skill would hide the pending upgrade.

   **Legacy page (no frontmatter)**: treat every missing key as a discrepancy — the fix sub-agent adds the frontmatter block from the template (facts lifted from the existing list) and keeps project-specific extras in the body; the file is converted, never regenerated.
2. **Fix automatically**: if there are discrepancies, dispatch ONE sub-agent (micro tier — mechanical zero-discretion work; brief per the installed ponytail profile where available) with the prepared corrections as its payload: exact line-level edits only (`field → new value`), add missing template fields, never touch correct lines or project-specific extras. The sub-agent commits its fix (autocommit policy, attribution per the project's settings).
3. **Report**: the path validated (and that it is the legacy location, where it is), `valid` or the corrections applied (`field → old → new`), any fact that stayed unfixable (truly undiscoverable) for the user to fill in, and any stamp-vs-layout disagreement you saw.
