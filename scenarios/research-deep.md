# research-deep — decompose, fan out, cross-validate, assemble

summary: Split a topic into aspects, fan out marvin:researcher agents, cross-validate, assemble one report.

This scenario runs under `scenarios/contract.md` — the bounded-execution contract, the
periodic-report schema, the mode model, and the safety rule all come from there and are NOT
restated here. This file only layers this scenario's specific shape on top.

## Bounded-execution declaration

- **GOAL** — the orchestrator decomposes the topic into distinct aspects, dispatches one
  `marvin:researcher` per aspect, then runs a cross-validation pass over the returned memos and
  assembles them into ONE report (memos and report follow `.marvin/agents/planning-research.md`
  and `.marvin/agents/document-standard.md`; cite, don't restate).
- **LIMITS** — max aspects / max sub-agents dispatched: **4** (one researcher per aspect, hard
  cap). Max rounds: **3** (aspect fan-out, cross-validation, and at most one targeted
  reconciliation round). Per-round fan-out: **4**.
- **POSITIVE exit** — an assembled, cross-validated report exists: the aspects are covered, their
  memos reconciled, and the combined findings hold together.
- **NEGATIVE exit** — the aspects **conflict irreconcilably** (the cross-validation pass cannot
  reconcile them within the round cap): report the conflict **honestly** — name the conflicting
  findings and why they cannot be reconciled — rather than papering over it, and close
  `close-negative`. A LIMITS cap reached before assembly is likewise a `close-negative`.

## Dispatch (sub-agent mode — the default today)

1. The orchestrator decomposes the topic into up to **4** distinct aspects.
2. It dispatches one `marvin:researcher` per aspect (scoped brief per `.marvin/agents/briefing.md`),
   each returning the contract's periodic-report block and its aspect memo.
3. The orchestrator runs the **cross-validation pass** over the returned memos (checking the
   aspects for agreement, gaps, and contradiction) and assembles ONE report.
4. The gate runs between every round per the contract.

## Agent-teams seam (dormant)

Under agent-teams mode (Milestone E) the researchers self-organise and peer-cross-validate as a
team, carrying state across rounds instead of the orchestrator running the fan-out and doing the
cross-validation itself. **Today this defaults to orchestrator-run fan-out + assembly** (the
sub-agent path above), per the contract's mode model. This scenario names no Milestone E setting
or key — only that explicit setting, when it exists, activates the team path.
