---
description: Show Marvin (the Agentic Operating System) version and this project's install state and active settings
---

Report Marvin's state for this project, compactly. **Every read below carries the pre-v0.21.0 fallback**: a file absent from `.marvin/` may still sit at its pre-v0.21.0 location — `.docs/PROJECT-INFO.md`, `.docs/marvin/MEMORY.md`, the cascade in `.docs/agents/` (or `docs/agents/`, pre-v0.15.0) — so read there before concluding it does not exist. Reading only `.marvin/` reports a complete v0.20.0 install as "not installed".

1. **Plugin**: read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` — name + version.
2. **Project install**: read `.marvin/PROJECT-INFO.md` frontmatter, else `.docs/PROJECT-INFO.md`, else `docs/PROJECT-INFO.md` — installed `kit_version`, `pm_tool` + `tracker_coordinates` + `project_key`, `hierarchy_levels`, `telemetry`, `label_syntax_version`; name which location it came from. Compare installed `kit_version` against the plugin version: older → say so and point at the `upgrade-agent-os` skill.
3. **Structure health** (one line each): `CLAUDE.md` present; cascade file count — `.marvin/agents/`, else `.docs/agents/`, else `docs/agents/`, naming the location found; three `.docs/handbooks/*/index.md` present (a pre-v0.21.0 install has `INDEX.md`); `MEMORY.md` — `.marvin/`, else `.docs/marvin/`; `.claude/telemetry` marker (enabled + storage mode from its content, or disabled); companion token-telemetry plugin installed? (`claude plugin list` — when absent, add one advisory line with the install command).
4. **Verdict** — one line at the top, from BOTH the stamp and the layout, and where they disagree **the layout on disk wins** (`upgrade-agent-os` step 1's tie-break: evidence beats a self-report):
   - Anything found at a pre-v0.21.0 location, or `.marvin/agents/` missing/partial against the plugin's cascade → **upgradable**, whatever `kit_version` claims. Point at `upgrade-agent-os` — **never** `install-agent-os`: install is add-missing/create-if-missing, so it leaves v0.21.0 filenames carrying v0.20.0 content and strands the legacy layout in place.
   - Stamp older than the plugin, layout current → **upgradable** (`upgrade-agent-os`).
   - Stamp current and layout current → **current**.
   - **not installed** ONLY when no PROJECT-INFO exists at any of the three locations AND none of `.marvin/agents/`, `.docs/agents/`, `docs/agents/` exists — then point at `install-agent-os`. Never scaffold anything from this command.

Present as a short table (setting → value) under that verdict. Read-only: this command never modifies files.
