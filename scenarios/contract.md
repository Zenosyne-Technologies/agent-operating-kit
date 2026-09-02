# Marvin play scenarios — the shared contract

Every `/marvin:play <scenario>` run obeys this file. It is plugin-side machinery (never
copied into a consumer). The dispatcher (`commands/play.md`) reads it first and follows it for
the whole run; each scenario file under `scenarios/` layers its own specific shape on top. A
scenario that contradicts this contract is wrong — the contract wins.

## 1. Bounded execution — the core invariant

**A play scenario can NEVER run an unbounded loop.** Before dispatching ANY agent, the scenario
declares all four of these, out loud, and the orchestrator refuses to start a round if any is
missing:

- **GOAL** — one clear, checkable objective ("the round is done when …").
- **LIMITS** — concrete caps, as numbers: max sub-agents dispatched, max rounds/iterations, and
  any per-round fan-out cap. No cap may be "as many as needed".
- **POSITIVE exit** — the condition that means the goal is MET; hitting it closes the scenario
  as a success.
- **NEGATIVE exit** — any condition that means stop without success: cannot proceed, diminishing
  returns across rounds, a LIMITS cap reached, or the work turns out to be out of scope.

All four are set at declaration time and are not renegotiated mid-run (no mid-run policy change —
same discipline as a sub-agent brief). A cap is a hard stop, not a suggestion.

## 2. The periodic-report schema — the between-rounds checkpoint

Every dispatched sub-agent returns this exact status block as the tail of its final message, and
the orchestrator reads ONLY this block between rounds (never the transcript — context blowout).
It is what lets the orchestrator SEE a scenario looping or overrunning and instruct it to close
and summarise gracefully AT ITS CURRENT STATE.

```
goal_progress: <one line — what is now true toward the GOAL vs. at round start>
artifacts_or_findings_so_far: <concrete outputs this round — file paths, findings, PR/issue refs>
budget_used: <agents X/MAX, rounds Y/MAX — consumed vs. the declared LIMITS caps>
recommended_next_action: continue | close-positive | close-negative
```

Field rules:
- `recommended_next_action` is exactly one of the three literals. `close-positive` ⇒ POSITIVE
  exit reached; `close-negative` ⇒ a NEGATIVE exit reached; `continue` ⇒ neither, and budget
  remains.
- The orchestrator OVERRIDES a `continue` to `close-negative` whenever a LIMITS cap is now hit,
  regardless of what the sub-agent recommended — the cap is the orchestrator's to enforce.
- On any close, the orchestrator writes a graceful wrap-up from the accumulated
  `artifacts_or_findings_so_far`, at the state actually reached. There is no "one more round to
  finish up" past a cap.

## 3. Mode model — sub-agent by default, agent-teams a dormant seam

Execution mode is **sub-agent by DEFAULT**. Each round dispatches fresh `marvin:*` sub-agents
(section 5); this is the mode that runs today.

Agent-teams mode is a **dormant seam**, not yet wired: when agent-teams mode is active
(Milestone E) the scenario's roles form a persistent team that carries state across rounds
instead of being re-dispatched fresh each round; a scenario reads the same GOAL/LIMITS/exits and
the same periodic-report schema either way — only who runs the rounds changes.

Mode is selected by **the project's execution-mode setting (Milestone E)** — this contract does
NOT define that setting's key or schema; Milestone E owns it, this contract owns the scenarios.
When no such setting exists (the case today), default to sub-agent mode. Never infer agent-teams
mode; only an explicit setting activates it.

## 4. Find, never attack — safety

Adversarial scenarios (e.g. a bug-hunt) **FIND and REPORT** weaknesses. They NEVER attack,
exploit, run destructive proof-of-concepts, touch a live system, or make a
state-changing call to prove a finding. The rules are owned, not restated here: follow the
installed `.marvin/agents/security.md` (security surfaces, find-not-exploit) and
`.marvin/agents/guardrails.md` (the DO NOT dispositions and the escalation chain). A scenario
that would cross that line closes `close-negative` and reports instead.

## 5. Dispatch and round-gating in sub-agent mode

A scenario runs as a sequence of gated rounds:

1. Declare the four bounded-execution elements (section 1) for the run.
2. Dispatch one or more named Marvin personas for the round, each with a scoped brief per
   `.marvin/agents/briefing.md`. The personas a scenario may use are exactly the installed set:
   `marvin:researcher`, `marvin:developer`, `marvin:developer-small`,
   `marvin:validator-completion`, `marvin:validator-security`, `marvin:ponytail`. Pick the tier
   the task warrants; a scenario file names which persona(s) it uses.
3. Each dispatched sub-agent returns the section-2 periodic-report block.
4. **Gate before the next round:** the orchestrator evaluates every report against the POSITIVE
   and NEGATIVE exits and the LIMITS caps. Only if the gate says `continue` — goal not yet met,
   no cap hit — does it dispatch another round. Otherwise it closes (section 2) and summarises.

The gate runs between EVERY round. There is no path from one round to the next that skips it.

## 6. Scenario file shape (for scenario authors — F2/F3)

Each `scenarios/<name>.md` (everything under `scenarios/` except this `contract.md`) is a plain
plugin-side file, not a command. It MUST carry:

- A one-line **`summary:`** field near the top — the dispatcher lists it, verbatim, as that
  scenario's menu line.
- Its own GOAL / LIMITS / POSITIVE exit / NEGATIVE exit defaults (section 1), which the run
  declares.
- Which persona(s) it dispatches and the per-round shape (section 5).

It inherits everything else from this contract and never re-defines the periodic-report schema,
the mode model, or the safety rule.
