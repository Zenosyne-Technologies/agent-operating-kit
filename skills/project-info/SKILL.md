---
name: project-info
description: Create the project's .docs/PROJECT-INFO.md meta page from the kit template, or — if it already exists — validate it against the repo's actual facts without recreating it. Use when the user asks to create, generate, check, or validate the project info page / project information overview.
---

# Project info page — create or validate

Template source of truth: `${CLAUDE_PLUGIN_ROOT}/templates/docs/PROJECT-INFO.md`. Target: `.docs/PROJECT-INFO.md` in the current repo.

## If the target does NOT exist → create

1. Gather every fact from the repo itself: name/description (manifest, README), owner, layout, tech stack, dev command + ports; PM tool, coordinates, hierarchy, and guide URL from `.docs/agents/tracker-config.md` + `.docs/agents/ticket-filing.md` if installed; label-syntax version from `.docs/agents/label-syntax.md`. Ask only for facts that are truly undiscoverable.
2. Write `.docs/PROJECT-INFO.md` from the template with every placeholder resolved; facts only, no operating rules.
3. Commit it (autocommit policy, attribution per the project's settings). Report the created path and any unresolved placeholder.

## If the target EXISTS → validate only, never recreate

Do NOT overwrite, regenerate, or restructure the existing file.

1. **Structure**: every template field is present (extra project-specific fields are fine — leave them).
2. **Facts**: check each stated fact against the repo — stack, dev command/ports, tracker coordinates and hierarchy (vs `tracker-config.md`), intake guide URL, label-syntax version (vs the registry header), docs paths.
3. **Report** a validation verdict: `valid`, or a list of discrepancies (field → stated vs actual) and missing fields. Do not modify the file; fixing is a separate, explicitly requested task (normally the documentation agent's job per its scope).
