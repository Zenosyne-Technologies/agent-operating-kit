---
description: Show Marvin (the Agentic Operating System) version and this project's install state and active settings
---

Report Marvin's state for this project, compactly:

1. **Plugin**: read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` — name + version.
2. **Project install**: read `.docs/PROJECT-INFO.md` frontmatter if present — installed `kit_version`, `pm_tool` + `tracker_coordinates` + `project_key`, `hierarchy_levels`, `telemetry`, `label_syntax_version`. Compare installed `kit_version` against the plugin version: if older, say so and point at the `upgrade-agent-os` skill.
3. **Structure health** (one line each): `CLAUDE.md` present; `.docs/agents/` file count; three `.docs/handbooks/*/INDEX.md` present; `.docs/marvin/MEMORY.md` present; `.claude/telemetry` marker (enabled + storage mode from its content, or disabled); companion token-telemetry plugin installed? (`claude plugin list` — when absent, add one advisory line with the install command).
4. **No install found** (no PROJECT-INFO, no `.docs/agents/`): say exactly that and point at the `install-agent-os` skill — do not scaffold anything from this command.

Present as a short table (setting → value) with a one-line verdict at the top (current | upgradable | not installed). Read-only: this command never modifies files.
