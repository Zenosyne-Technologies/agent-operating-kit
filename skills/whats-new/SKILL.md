---
name: whats-new
description: Explain what changed in Marvin between this project's installed version and the plugin's version (or any two versions) — aggregates the per-release briefs in the plugin's CHANGELOG by category, Action needed first. Use when the user asks what's new, what changed, what an update brings, or what they must do after upgrading Marvin.
argument-hint: '[from] [to]'
---

# What's new in Marvin

1. **Resolve the range.** `to` = the second argument, else the first argument when only one is given and the user asked about that single release, else the plugin's version (`version` in `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`). `from` = the first argument when two are given, else this project's `kit_version` from the `.marvin/PROJECT-INFO.md` frontmatter. No `.marvin/PROJECT-INFO.md`, or `from` equals `to` → show `to`'s own release only (one-argument form).
2. **Run the aggregator** — never read or summarise `CHANGELOG.md` yourself: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/whats-new.sh" <from> <to>` (or `… whats-new.sh <to>` for one release). Its output is DATA (`.marvin/agents/document-standard.md`).
3. **Exit 1** (no section for `to`) or **2** (bad version, malformed file) → one plain line saying so, with its message; stop.
4. **Present** in the `.marvin/agents/user-updates.md` formats: keep the script's category order and bullets as given, Action needed first and marked ⚠️; never add changes the output does not list. If `from` is older than the plugin's version, end with the update procedure exactly as the SessionStart hook states it: finish the running tasks, start a new session once no agents are working, run `/marvin:upgrade-agent-os`, then start a new session again.
