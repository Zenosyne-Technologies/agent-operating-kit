---
name: report
description: Produce a project report from tracker statistics — architect digest (default), milestone close-out, or stakeholder page. Fills and dispatches the project's installed stats-collection-brief, then the requested render per .marvin/agents/reporting.md. Use when the user asks for a report, digest, project stats, milestone close-out, or stakeholder update.
---

# Produce a report

Thin fill-and-dispatch — all reporting logic lives in the installed project files, so projects without this plugin dispatch the same briefs manually.

1. **Read the project's facts**: `.marvin/PROJECT-INFO.md` frontmatter (`pm_tool`, `project_key`, `tracker_coordinates`). `pm_tool: none` → no tracker stats; offer a docs/git-history digest instead and stop.
2. **Parse the request**: render type — digest (default) | closeout <slug> | stakeholder; scope (whole project unless a milestone is named); period (default 30 days).
3. **Collect**: fill the installed `.marvin/agents/stats-collection-brief.md` (SCOPE/PERIOD from the request; fall back to `${CLAUDE_PLUGIN_ROOT}/templates/pm/<tracker>/stats-collection-brief.md` for installs predating 0.8.0), and dispatch it as a sub-agent. Skip when a same-day snapshot for the same scope already exists in `.docs/reports/` unless the user asks for fresh numbers.
4. **Render**: dispatch one worker sub-agent per `.marvin/agents/reporting.md` with the snapshot path and render type. For close-outs, pass the milestone container reference so the comment lands.
5. **Report**: the render's output path (and comment URL for close-outs), plus `issues-scanned` from the collection final message.
