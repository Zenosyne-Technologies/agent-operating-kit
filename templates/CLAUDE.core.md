# {{PROJECT_NAME}} — orchestrator core rules

{{ONE_PARAGRAPH_PROJECT_FACTS: stack, monorepo layout, env preamble for shell commands, dev-stack command + ports, docs location, tracker site + project key.}}

## Model-tier dispatch (MANDATORY)

Orchestrator ({{FRONTIER_MODEL}} — the architect's recommended session model) plans, decomposes, briefs, sequences, verifies — never bulk-implements. Route execution by the task's `size:` label:

- **Orchestrator inline**: architecture/ADRs, security-critical design, irreversible ops, QA sign-off, brief authoring, conflict resolution.
- **{{ESCALATION_MODEL}} subagent** (heavy worker): `size:m` and larger executions, all planning-research passes, validators (both stages), cross-cutting debugging.
- **{{WORKER_MODEL}} subagent** (small worker): `size:s` and clearly-defined small executions — tests, QA sweeps, imports, docs.
- **{{MICRO_MODEL}} subagent** ("ponytail"): `size:xs` mechanical zero-discretion micro-tasks → `.docs/agents/ponytail.md`.

After two failed attempts at any tier, escalate to {{FRONTIER_MODEL}} (orchestrator inline or a frontier subagent); de-escalate when work turns mechanical.

## Task lifecycle (per tracker task)

build (worker) → **validate-completion** (fresh BA validator) → **validate-security** (fresh security validator, only after completion passes) — both per `.docs/agents/validation-agent.md`, never the builder → **document** (worker → `.docs/agents/documentation-agent.md`) → close the tracker issue with commit refs.

No task enters build without a **DoD** — verifiable done-statements written at planning time on the tracker issue (behavior, tests, docs, env wiring). Builders work TO the DoD; validators falsify AGAINST it.

## Rules cascade

Keep context lean: load a reference ONLY when performing that activity, and cite it in the sub-agent brief instead of inlining its content.

- Writing any agent brief → `.docs/agents/briefing.md`
- Validating done work (BA + security personas, E2E script) → `.docs/agents/validation-agent.md`
- Documenting after a done task → `.docs/agents/documentation-agent.md`
- Creating/updating tracker issues → `.docs/agents/ticket-filing.md` (defers to the in-tracker "Issue Intake & Triage Guide")
- Labeling ANY tracker item you create or edit (and backfilling unlabeled ones) → `.docs/agents/label-syntax.md` (versioned registry)
- Planning milestones/epics or mapping severity to native fields → `.docs/agents/tracker-config.md` (levels, virtual-milestone rule, mappings)
- Planning a `size:l`/`size:xl` task → `.docs/agents/planning-research.md` (plan-validation + solution research, tier-routed by size)
- Producing any report (digest / close-out / stakeholder) → `.docs/agents/reporting.md` (snapshot first, render second)
- Any task touching auth, input boundaries, data exposure, secrets, or dependencies → `.docs/agents/security.md`
- Micro-tasks → `.docs/agents/ponytail.md`

## Standing rules

- **Milestone feature branching**: each milestone gets a `milestone/<slug>` branch off the default branch; all task work commits land there; merge back only after milestone validation ({{FRONTIER_MODEL}} with {{WORKER_MODEL}} sub-agents → `.docs/agents/validation-agent.md`). At milestone close, dispatch stats collection + the close-out render per `.docs/agents/reporting.md` before archiving the branch.
- **Autocommit**: commit finished work immediately — atomic commit per completed task step, selective `git add <paths>`, no approval round-trips. When the work belongs to a tracker issue, the commit message STARTS with its issue key (`<KEY>: <message>`) — keys are how commits trace and sync back to the PM tool. Every sub-agent brief instructs the agent to commit its own scoped work before its final message; work is never left uncommitted.
- **Attribution: none.** Commits, PRs, docs, and code comments carry NO AI attribution of any kind. {{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION}}
- Integration-verify at the real boundary: cold-boot the composed/dev stack for milestone-sized work; API-level checks (curl) are NOT browser E2E — browser-smoke any web-facing change.
- Real bugs → {{DOCS_ISSUE_LOG_PATH}} AND the tracker per `.docs/agents/ticket-filing.md`.
- {{CONVENTIONS_THAT_BITE: grow this list with project-specific hard-won rules — DI quirks, env-wiring gaps, test-serialization needs — each with the incident reference that earned it.}}
