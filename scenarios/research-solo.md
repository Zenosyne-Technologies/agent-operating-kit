# research-solo — one question, one researcher

summary: Answer a single research question as a memo via one marvin:researcher.

This scenario runs under `scenarios/contract.md` — the bounded-execution contract, the
periodic-report schema, the mode model, and the safety rule all come from there and are NOT
restated here. This file only layers this scenario's specific shape on top.

## Bounded-execution declaration

- **GOAL** — the research question is answered as a single research memo. The memo follows the
  installed `.marvin/agents/planning-research.md` (memo shape) and `.marvin/agents/document-standard.md`
  (header); it cites its sources rather than restating them.
- **LIMITS** — max sub-agents dispatched: **1**. Max rounds: **2** (the initial pass plus at most
  **1** follow-up round for a scoped clarification). Per-round fan-out: **1**.
- **POSITIVE exit** — the memo is delivered: the question is answered with cited support, at the
  depth one researcher can reach within the caps.
- **NEGATIVE exit** — the topic is too broad for one memo → close `close-negative` and recommend
  running `research-deep` instead. Or the question is genuinely unanswerable (no accessible
  sources, or it is not a research question) → say so plainly in the wrap-up and stop. A cap
  reached with the question unanswered is also a `close-negative`.

## Dispatch (sub-agent mode)

One round dispatches a single `marvin:researcher` with a scoped brief per
`.marvin/agents/briefing.md`, carrying the question and the memo's target. The researcher returns
the contract's periodic-report block; the gate either closes on an exit or, if the first pass
surfaced one scoped gap and a follow-up round remains, dispatches one more `marvin:researcher`
round before assembling the delivered memo.

## Agent-teams note

This scenario is **identical under agent-teams mode** — a single-researcher run has no meaningful
team variation. The contract's mode model applies unchanged; there is no team seam here.
