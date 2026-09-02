# bug-hunt — fan out adversarial hunters, then filter the findings

summary: Fan out adversarial sub-agents to FIND bugs from distinct angles, then validate and file the real ones.

This scenario runs under `scenarios/contract.md` — the bounded-execution contract, the
periodic-report schema, the mode model, and the safety rule all come from there and are NOT
restated here. This file only layers this scenario's specific shape on top.

## Find, never attack — mandatory, not optional

**The hunters LOCATE and REPORT weaknesses; they do NOT attack, exploit, run destructive
proof-of-concepts, or touch a live system, and never make a state-changing call to prove a
finding.** This is the hard line of the scenario, stated here for emphasis; the rule is owned (not re-defined) by
`scenarios/contract.md` (§4, find-never-attack), `.marvin/agents/security.md` (security surfaces,
find-not-exploit), and `.marvin/agents/guardrails.md` (the DO NOT dispositions and the escalation
chain). Any angle that could only be confirmed by crossing that line is reported as a suspected
weakness to verify safely — never proven by exploiting it.

## Bounded-execution declaration

- **GOAL** — the orchestrator dispatches several adversarial hunters, each on a **distinct angle**
  (e.g. input-boundary, state/concurrency, auth/exposure — the boundary classes
  `.marvin/agents/security.md` names; cite, don't restate), to FIND bugs and exploitable
  weaknesses and REPORT them; then a single validation pass checks and filters the findings,
  killing false positives, so that only confirmed findings are filed. The round is done when the
  filtered findings are filed (or the hunt came back clean within the caps).
- **LIMITS** — max hunters dispatched: **4** (one per distinct angle, hard cap; per-round fan-out
  **4**). Exactly **ONE** validation pass. Max rounds: **2** (the hunt fan-out, then the single
  filtering pass). Every cap is a hard stop.
- **POSITIVE exit** — the validation pass has filtered the hunters' findings and the survivors are
  filed: recorded in the issue log and opened in the tracker per `.marvin/agents/ticket-filing.md`
  (cite, don't restate). Close `close-positive`.
- **NEGATIVE exit** — no findings survive validation within the caps: report **"clean within these
  stated limits"** — naming the angles hunted and the caps — and **NEVER imply exhaustiveness or a
  guarantee of no bugs** (the caps bound the search, they do not certify the code). A LIMITS cap
  reached mid-hunt is likewise a `close-negative`, reported at the state actually reached.

## Dispatch (sub-agent mode — the default today)

1. The orchestrator picks up to **4** distinct angles and dispatches one `marvin:validator-security`
   hunter per angle (scoped brief per `.marvin/agents/briefing.md`, each angle a different brief).
   Each hunter LOCATES and REPORTS only — never attacks — and returns its findings plus the
   contract's periodic-report block.
2. The single validation pass — one fresh `marvin:validator-*` (a `marvin:validator-security`
   review), never one of the hunters re-checking itself (contract §5) — checks every reported
   finding, kills false positives, and confirms the survivors.
3. **Gate.** Confirmed findings → filed per `.marvin/agents/ticket-filing.md` and `close-positive`;
   nothing survives → the "clean within these stated limits" negative exit above. The gate runs
   between every round per the contract; there is no third round.

## Agent-teams seam (dormant)

Under agent-teams mode (Milestone E) the hunters and the filtering validator form a **standing team
of adversaries plus a validator** that carries state across rounds instead of the orchestrator
re-dispatching each hunter fresh; find-never-attack, the GOAL/LIMITS/exits, and the periodic-report
schema are unchanged either way. **Today this defaults to orchestrator-dispatched sub-agents** (the
path above), per the contract's mode model. This scenario names no Milestone E setting or key —
only that explicit setting, when it exists, activates the team path.
