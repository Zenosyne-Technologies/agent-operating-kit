# visual-sweep — enumerate every surface, fan out, aggregate one design report

summary: Enumerate all UI surfaces, fan out marvin:validator-visual agents, aggregate one whole-project design report.

This scenario runs under `scenarios/contract.md` — the bounded-execution contract, the
periodic-report schema, the mode model, and the find-never-attack safety rule all come from there
and are NOT restated here. This file only layers this scenario's specific shape on top. The review
procedure each agent follows — capture, degradation ladder, checklist, severity, reporting — is
`.marvin/agents/visual-validation.md`; cite it, don't restate.

## Bounded-execution declaration

- **GOAL** — assess the WHOLE project's UI: enumerate every declared surface, dispatch
  `marvin:validator-visual` agents across slices to capture + review them, then reconcile the
  per-surface findings into ONE whole-project design report (a design-consistency view, not just a
  pile of per-page notes) written to `.docs/reports/` per `.marvin/agents/document-standard.md`.
- **LIMITS** — max sub-agents dispatched per round: **4** (hard cap, one slice each). Max rounds:
  **3** (fan-out, at most one reconciliation round for surfaces that came back UNREACHABLE or
  under-covered, and the aggregation pass). A surface count beyond one round's capacity is sliced
  across rounds, still 4/round.
- **POSITIVE exit** — every enumerated surface was captured + assessed (or honestly marked
  UNREACHABLE/NO-RUNTIME per the guide's degradation ladder), and the single aggregated design
  report exists with its cross-surface findings.
- **NEGATIVE exit** — the visual tooling is absent, or no runnable app exists (`dev_command` empty
  / boot fails for every surface): capture nothing to assess. Report that **honestly** per the
  degradation ladder (SKIP(TOOLING-ABSENT) / NO-RUNTIME), write no fabricated findings, and close
  `close-negative`. A LIMITS cap reached before aggregation is likewise a `close-negative`.

## Dispatch (sub-agent mode — the default today)

1. **Enumerate** all surfaces from the project's screen-catalog developer docs (the index-based
   catalog under `.docs/`, per `.marvin/agents/visual-validation.md`), plus any router config or
   Storybook the catalog points at. No catalog yet → enumerate what the catalog's index does list,
   and report the gap.
2. **Slice & fan out** (up to **4** `marvin:validator-visual` per round, scoped brief per
   `.marvin/agents/briefing.md`): each agent takes a slice of surfaces, boots the app, screenshots
   at the declared breakpoints (desktop + mobile; dark where themed), applies the checklist, and
   returns the guide's machine-consumed FINAL MESSAGE plus the contract's periodic-report block.
3. **Aggregate**: the orchestrator reconciles the per-surface findings into ONE report — the
   cross-surface view a per-page pass cannot see: shared-component drift, type/colour-scale
   coherence, spacing-rhythm consistency, and any sev1/sev2 that recurs across surfaces.
4. The gate runs between every round per the contract.

Also exposed inside `marvin:report` posture (a whole-project design digest), and auto-registered in
`/marvin:play`'s menu (the command lists every `scenarios/*.md` except `contract.md`).

## Agent-teams seam (dormant)

Under agent-teams mode (Milestone E) the visual validators self-organise across slices and share
the cross-surface reconciliation as a team, carrying state across rounds instead of the orchestrator
running the fan-out and aggregation itself. **Today this defaults to orchestrator-run fan-out +
aggregation** (the sub-agent path above), per the contract's mode model. This scenario names no
Milestone E setting or key — only that explicit setting, when it exists, activates the team path.
