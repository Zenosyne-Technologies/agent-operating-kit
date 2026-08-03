# {{PROJECT_NAME}} — orchestrator core rules

{{ONE_PARAGRAPH_PROJECT_FACTS: stack, monorepo layout, env preamble for shell commands, dev-stack command + ports, docs location, tracker site + project key.}}

## Model-tier dispatch (MANDATORY)

Orchestrator ({{FRONTIER_MODEL}}) plans, decomposes, briefs, sequences, verifies — never bulk-implements. Route to the cheapest capable tier:

- **Orchestrator inline**: architecture/ADRs, security-critical design, irreversible ops, QA sign-off, brief authoring, conflict resolution.
- **{{ESCALATION_MODEL}} subagent**: only after two {{WORKER_MODEL}} failures, or cross-cutting debugging with no clear repro (state why in the brief).
- **{{WORKER_MODEL}} subagent** (default): features, fixes, validators, tests, QA sweeps, imports, docs.
- **{{MICRO_MODEL}} subagent** ("ponytail"): mechanical zero-discretion micro-tasks → `.docs/agents/ponytail.md`.

Escalate after two failures; de-escalate when work turns mechanical.

## Task lifecycle (per tracker task)

build (worker) → **validate** (fresh agents, never the builder → `.docs/agents/validation-agent.md`) → **document** (worker → `.docs/agents/documentation-agent.md`) → close the tracker issue with commit refs.

## Rules cascade

Keep context lean: load a reference ONLY when performing that activity, and cite it in the sub-agent brief instead of inlining its content.

- Writing any agent brief → `.docs/agents/briefing.md`
- Validating done work (BA + security personas, E2E script) → `.docs/agents/validation-agent.md`
- Documenting after a done task → `.docs/agents/documentation-agent.md`
- Creating/updating tracker issues → `.docs/agents/ticket-filing.md` (defers to the in-tracker "Issue Intake & Triage Guide")
- Labeling ANY tracker item you create or edit (and backfilling unlabeled ones) → `.docs/agents/label-syntax.md` (versioned registry)
- Planning milestones/epics or mapping severity to native fields → `.docs/agents/tracker-config.md` (levels, virtual-milestone rule, mappings)
- Micro-tasks → `.docs/agents/ponytail.md`

## Standing rules

- **Milestone feature branching**: each milestone gets a `milestone/<slug>` branch off the default branch; all task work commits land there; merge back only at milestone close, after validation.
- **Autocommit**: commit finished work immediately — atomic commit per completed task step, selective `git add <paths>`, no approval round-trips. Every sub-agent brief instructs the agent to commit its own scoped work before its final message; work is never left uncommitted.
- **Attribution: none.** Commits, PRs, docs, and code comments carry NO AI attribution of any kind. {{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION}}
- Integration-verify at the real boundary: cold-boot the composed/dev stack for milestone-sized work; API-level checks (curl) are NOT browser E2E — browser-smoke any web-facing change.
- Real bugs → {{DOCS_ISSUE_LOG_PATH}} AND the tracker per `.docs/agents/ticket-filing.md`.
- {{CONVENTIONS_THAT_BITE: grow this list with project-specific hard-won rules — DI quirks, env-wiring gaps, test-serialization needs — each with the incident reference that earned it.}}
