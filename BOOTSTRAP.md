# Bootstrap prompt

Paste everything below the line into a Claude session opened in the target project's repo root, replacing the kit path if you moved it.

---

Install the Agent Operating Kit from `~/Dev/agent-operating-kit` into this project:

1. Read the kit's `README.md` and every file under `templates/` (they are short).
2. Gather project facts yourself (don't ask unless truly undiscoverable): stack + layout from the repo; how shell commands must run (version managers, env prefixes); dev-stack command + ports; where long-form docs live (create `.docs/` notes if none); which trackers are connected and their coordinates (Jira: site URL + project key, Confluence space if any; Linear: team + project).
3. Ask the user which supported PM tool this project uses, presented as a selection they pick from: Linear | Jira | none (none → file-based issue log only). Never pick silently, even if only one tracker is connected. Ask the attribution question from step 5 in the same prompt — one interruption, two answers.
4. Write `CLAUDE.md` at the repo root from `templates/CLAUDE.core.md` with every `{{PLACEHOLDER}}` resolved. If a CLAUDE.md exists, merge — kit rules become the operating-model section, existing project rules are preserved. Start the "conventions that bite" list empty or from the project's existing lessons.
5. Copy `templates/docs/agents/` to `.docs/agents/`, resolving placeholders ({{DOCS_LOCATION}}, tracker coordinates, `label-syntax.md` area values — never alter its version/changelog). Create `.docs/PROJECT-INFO.md` from `templates/docs/PROJECT-INFO.md` with every fact resolved — its YAML frontmatter is the machine contract: resolve every key (`kit_version` from the kit repo's `.claude-plugin/plugin.json`, `label_syntax_version` from the registry's H1). If it already exists, do NOT recreate it — validate its facts against the repo and dispatch a sub-agent to apply line-level fixes for discrepancies (never regenerate the file). Also copy the selected tool's `templates/<tracker>/tracker-config.md` to `.docs/agents/tracker-config.md` (resolve placeholders) — it defines the tool's levels vs the kit's 4-level target, the virtual-milestone rule when only 3 exist (`milestone:<slug>` labels on epics, convertible to releases/milestones later), and the severity→native mapping; planners follow it as installed. Backwards compatibility: if a previous install of this kit put the cascade in `docs/agents/`, `git mv` the kit's files to `.docs/agents/` and rewrite every `docs/agents/` reference in the existing CLAUDE.md; docs that did not come from this kit stay where they are. Copy `templates/settings.json` into `.claude/settings.json` (merge; skip if the owner wants default attribution).
6. Map model tiers to what's currently available (frontier orchestrator / escalation / default worker / micro) and write the names into CLAUDE.md's dispatch table.
7. For the selected tool: fill and dispatch `templates/<tracker>/intake-structure-brief.md` as a sub-agent, then paste the resulting guide URL into `.docs/agents/ticket-filing.md`. If the user chose none, note it in CLAUDE.md as pending and keep the file-based issue log as the sole log.
8. Commit the added files per the attribution policy chosen in step 3 — commit directly, do not ask for approval (autocommit is kit policy; the installed rules apply it to all future work too).
9. Report: what was installed, the selected PM tool + its level configuration, the label-syntax registry version, the PROJECT-INFO.md location, the tier mapping, tracker structure status, and any placeholder you could not resolve.

From then on, operate by CLAUDE.md's dispatch and lifecycle rules.
