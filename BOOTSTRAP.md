# Bootstrap prompt

Paste everything below the line into a Claude session opened in the target project's repo root, replacing the kit path if you moved it.

---

Install the Agent Operating Kit from `~/Dev/agent-operating-kit` into this project:

1. Read the kit's `README.md` and every file under `templates/` (they are short).
2. Gather project facts yourself (don't ask unless truly undiscoverable): stack + layout from the repo; how shell commands must run (version managers, env prefixes); dev-stack command + ports; where long-form docs live (create `.docs/` notes if none); which issue tracker is connected and the coordinates to use (for Jira: site URL + project key; Confluence space if any).
3. Write `CLAUDE.md` at the repo root from `templates/CLAUDE.core.md` with every `{{PLACEHOLDER}}` resolved. If a CLAUDE.md exists, merge — kit rules become the operating-model section, existing project rules are preserved. Start the "conventions that bite" list empty or from the project's existing lessons.
4. Copy `templates/docs/agents/` to `.docs/agents/`, resolving placeholders ({{DOCS_LOCATION}}, tracker coordinates). Backwards compatibility: if a previous install of this kit put the cascade in `docs/agents/`, `git mv` the kit's files to `.docs/agents/` and rewrite every `docs/agents/` reference in the existing CLAUDE.md; docs that did not come from this kit stay where they are. Copy `templates/settings.json` into `.claude/settings.json` (merge; skip if the owner wants default attribution — ask this ONE question).
5. Map model tiers to what's currently available (frontier orchestrator / escalation / default worker / micro) and write the names into CLAUDE.md's dispatch table.
6. If Jira (or another tracker) is connected: fill and dispatch `templates/jira/intake-structure-brief.md` as a sub-agent, then paste the resulting guide URL into `.docs/agents/ticket-filing.md`. If no tracker is connected, note it in CLAUDE.md as pending and keep the file-based issue log as the sole log.
7. Commit the added files per the attribution policy chosen in step 4 — commit directly, do not ask for approval (autocommit is kit policy; the installed rules apply it to all future work too).
8. Report: what was installed, the tier mapping, tracker structure status, and any placeholder you could not resolve.

From then on, operate by CLAUDE.md's dispatch and lifecycle rules.
