---
name: project-info
description: Create the project's .docs/PROJECT-INFO.md meta page from the kit template, or — if it already exists — validate it against the repo's actual facts and auto-fix discrepancies via a sub-agent, never recreating the file. Use when the user asks to create, generate, check, validate, or fix the project info page / project information overview.
---

# Project info page — create or validate

Template source of truth: `${CLAUDE_PLUGIN_ROOT}/templates/docs/PROJECT-INFO.md`. Target: `.docs/PROJECT-INFO.md` in the current repo.

## If the target does NOT exist → create

1. Gather every fact from the repo itself: name/description (manifest, README), owner, layout, tech stack, dev command + ports; PM tool, coordinates, hierarchy, and guide URL from `.docs/agents/tracker-config.md` + `.docs/agents/ticket-filing.md` if installed; label-syntax version from `.docs/agents/label-syntax.md`. Ask only for facts that are truly undiscoverable.
2. Write `.docs/PROJECT-INFO.md` from the template with every placeholder resolved — every YAML frontmatter key filled (`kit_version` from the plugin's `.claude-plugin/plugin.json` when installed via plugin, else the kit repo's; `label_syntax_version` from `.docs/agents/label-syntax.md`'s H1); body stays facts-only prose, no operating rules.
3. Commit it (autocommit policy, attribution per the project's settings). Report the created path and any unresolved placeholder.

## If the target EXISTS → validate, then fix via sub-agent — never recreate

Do NOT overwrite, regenerate, or restructure the existing file.

1. **Validate**: the YAML frontmatter parses and contains every template key (extra project-specific keys are fine — leave them); each frontmatter fact checked against the repo — `stack`, `dev_command`, `tracker_coordinates`/`project_key`/`hierarchy_levels` (vs `tracker-config.md`), `intake_guide_url`, `label_syntax_version` (vs the registry H1), `docs_location`; body statements must not contradict frontmatter.

   **Legacy page (no frontmatter)**: treat every missing key as a discrepancy — the fix sub-agent adds the frontmatter block from the template (facts lifted from the existing list) and keeps project-specific extras in the body; the file is converted, never regenerated.
2. **Fix automatically**: if there are discrepancies, dispatch ONE sub-agent (micro tier — mechanical zero-discretion work; brief per the installed ponytail profile where available) with the prepared corrections as its payload: exact line-level edits only (`field → new value`), add missing template fields, never touch correct lines or project-specific extras. The sub-agent commits its fix (autocommit policy, attribution per the project's settings).
3. **Report**: `valid`, or the corrections applied (`field → old → new`), plus any fact that stayed unfixable (truly undiscoverable) for the user to fill in.
