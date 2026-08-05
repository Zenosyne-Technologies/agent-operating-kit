---
name: validate-kit
description: Run the kit's full pre-release validation — the static check script plus the three agentic scratch-repo scenarios (fresh install, legacy upgrade, no-op re-run). Use before releasing a new kit version, or when the user asks to validate/test the kit or check the release gate.
---

# Validate the kit

1. **Static gate**: run `bash scripts/validate-kit.sh` from the repo root. Any FAIL stops here — fix before scenarios.
2. **Scenarios** — each in a throwaway git-initialized scratch repo (temp dir; delete afterward). Act as the installing/upgrading agent yourself, following the skills literally with `${CLAUDE_PLUGIN_ROOT}` = this repo root. Tracker steps run DRY: fill the briefs and show them, do not dispatch — unless the user names a sandbox tracker project.
   - (a) **Fresh install**: seed a minimal repo (README + one manifest), run `skills/install-agent-os/SKILL.md` with `pm_tool: none`, attribution default. Verify: `.docs/agents/` complete for the selection, `.docs/agents/stats-collection-brief.md` present, three handbook INDEX.md files present (developer/user/admin), `.docs/marvin/MEMORY.md` present, CLAUDE.md placeholders all resolved, PROJECT-INFO frontmatter parses with every template key and real values (14 frontmatter keys incl. `telemetry`), no `{{` and no `${CLAUDE_PLUGIN_ROOT}` in installed files.
   - (b) **Legacy upgrade**: fabricate a pre-0.7.0 shape (`docs/agents/` with old files, `found-by:*` in ticket-filing, no PROJECT-INFO), run `skills/upgrade-agent-os/SKILL.md`. Verify: files moved to `.docs/agents/`, `.docs/agents/stats-collection-brief.md` present, three handbook INDEX.md files present (developer/user/admin), `.docs/marvin/MEMORY.md` present, references rewritten, frontmatter created and stamped (14 frontmatter keys incl. `telemetry`), relabel sweep OFFERED not executed.
   - (c) **No-op**: re-run the upgrade flow on (a)'s result. Verify: clean `already at <version>` report, `git status --short` empty.
3. **Report**: static-gate result, per-scenario PASS/FAIL with the failed assertion and file diff when failing, and any judgment calls the skills forced (template wording gaps) — those are polish candidates, not blockers.
