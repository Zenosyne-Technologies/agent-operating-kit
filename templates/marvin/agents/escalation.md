---
doc: Escalation ladder
type: reference
status: active
summary: What happens when a task fails twice — the orchestrator climbs an EFFORT ladder on its own model, asks the user at the max gate whether to swap to the frontier tier instead, and stops at the user when the last rung fails.
updated: {{INSTALL_DATE}}
---

# Escalation ladder — effort before model

The orchestrator's model ({{ESCALATION_MODEL}}) is the CEILING: no sub-agent runs above it by default, and a hard, repeating or very complex task does NOT default to the frontier tier. Why: the orchestrator's model class at `medium` effort now outperforms the frontier tier at `max`, and costs less — so escalation raises EFFORT on the ceiling model, one level per rung above the base (`medium` → `high` → `xhigh` → `max`). The base rung is `medium`: the {{ESCALATION_MODEL}} personas (`marvin:developer`, `marvin:researcher`, the three validators) pin `effort: medium`, matching the orchestrator's session, and {{FRONTIER_MODEL}} is opt-in, reachable only through the max gate below.

## What counts as a failed attempt

One attempt = one dispatch of one persona on the task. It FAILED when the task is not done at the end of it, or when a validator FAIL it was dispatched to correct is still standing (re-validation fails again). A CLARIFY/REQUEST_APPROVAL stop is NOT a failed attempt — resolve it per `guardrails.md` and re-dispatch the same rung.

## The ladder

Any task not done or corrected within 2 attempts at its assigned persona (any tier, `marvin:developer` included) climbs. Each rung gets 2 attempts:

1. `marvin:escalation-high` — the ceiling model at `high` effort.
2. `marvin:escalation-xhigh` — the ceiling model at `xhigh` effort.
3. **MAX GATE** — before going to `max`, the orchestrator asks the user ONE question: swap this task to the frontier tier ({{FRONTIER_MODEL}}, `marvin:escalation-frontier`), or go to `max` effort on the ceiling model (`marvin:escalation-max`)? If the session is unattended or the question goes unanswered, dispatch `marvin:escalation-max`. The answer applies to THIS task only — it is never a standing preference.
4. The chosen final rung fails twice → **STOP**. The ladder terminates; never loop back to a lower rung. Escalate to the user per `guardrails.md`'s escalation chain with the full attempt history.

The ladder is the orchestrator's to climb. Escalation personas never self-escalate or dispatch agents — they report back in their FINAL MESSAGE and the orchestrator decides the next rung.

## The escalation brief

Written per `briefing.md`, around the ORIGINAL brief and DoD (unchanged — escalation raises effort, never scope), plus:

- every failed attempt's findings: the final messages, the validator FAIL reports, the exact reproduction steps;
- what was tried and ruled out, so the rung does not repeat it;
- the rung and attempt number (`escalation-xhigh, attempt 1 of 2`).

## Why one persona per rung

The persona name is stamped onto every telemetry event (`token-economics.md`), so a distinct persona per rung makes escalation cost reportable PER RUNG — what the ladder spends, and at which effort level tasks actually get unstuck. One generic persona with a varying effort would hide exactly that.

## De-escalate

Once the blocker is resolved and the remaining work is mechanical, route it back down by its `size:` label per the core dispatch rules — the ladder is for the blocker, not for the rest of the task.
