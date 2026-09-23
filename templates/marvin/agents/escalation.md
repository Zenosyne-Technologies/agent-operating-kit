---
doc: Escalation ladder
type: reference
status: active
summary: What happens when a build task fails twice — the orchestrator climbs an EFFORT ladder on its own model, asks the user at the max gate whether to swap to the frontier tier instead, and stops at the user when the last rung fails.
updated: {{INSTALL_DATE}}
---

# Escalation ladder — effort before model

The orchestrator's model ({{ESCALATION_MODEL}}) is the CEILING: no sub-agent runs above it by default, and a hard, repeating or very complex task does NOT default to the frontier tier. Why: the orchestrator's model class at `medium` effort now outperforms the frontier tier at `max`, and costs less — so escalation raises EFFORT on the ceiling model, one level per rung above the base (`medium` → `high` → `xhigh` → `max`). The base rung is `medium`: the {{ESCALATION_MODEL}} personas (`marvin:developer`, `marvin:researcher`, the three validators) pin `effort: medium`, matching the orchestrator's session, and {{FRONTIER_MODEL}} is opt-in, reachable only through the max gate below.

## What counts as a failed attempt

One attempt = one dispatch of a build or correction persona (`marvin:developer`, `marvin:developer-small`, `marvin:ponytail`, or a ladder rung) on the task. It FAILS when the task is not done at the end of that dispatch, OR when the validator that checks it FAILs. So: build (claims done) → validator FAIL = attempt 1 failed; correction dispatch → validator FAIL = attempt 2 failed → climb. "Two attempts" means two dispatches per rung — never two validator runs of one dispatch.

A completion or security FAIL returns the task to the persona that built the failing attempt — on the ladder, its CURRENT rung, never back down to the original build tier — with the findings, and counts as one of that rung's 2 attempts; if it was that rung's 2nd failed attempt, the task climbs instead.

A CLARIFY/REQUEST_APPROVAL/SKIP stop is NOT a failed attempt, but the orchestrator RESOLVES it before re-dispatching — answers it, or carries it to the user per `guardrails.md`. NEVER re-dispatch the same rung with an unchanged brief.

**Off the ladder.** Only the build personas above climb. EVERY other persona — `marvin:researcher`, `marvin:documenter`, the validators, and any persona added later — is off the ladder by definition: a non-build pass that fails twice (not done, or its output rejected) is taken inline by the orchestrator (the ceiling) or carried to the user — except a validator, which always goes to the user (validation stays fresh; the orchestrator never grades its own sign-off) — never a third dispatch, never a rung, since rungs run under developer rows that would let it change product code. A validator that errors without a verdict is re-run fresh; a second error → the user. Inside a `/marvin:play` scenario the ladder does not run: that scenario's gate and LIMITS govern (`scenarios/contract.md`).

## Entering the ladder

A task entering the ladder KEEPS its `size:` label — a small-sized issue that needed the ladder IS the mis-sizing evidence (`reporting.md`'s call-out), so relabelling would erase it. Escalation personas run under the heavy `marvin:developer`'s guardrail rows plus the failed task's scope — NEVER `developer-small`'s or `ponytail`'s discretion-STOP rows, whatever the task's size.

## The ladder

Any BUILD task that fails 2 attempts at its assigned build persona (any tier, `marvin:developer` included) climbs. Each rung gets 2 attempts:

1. `marvin:escalation-high` — the ceiling model at `high` effort.
2. `marvin:escalation-xhigh` — the ceiling model at `xhigh` effort.
3. **MAX GATE** — before going to `max`, the orchestrator asks the user ONE question: swap this task to the frontier tier ({{FRONTIER_MODEL}}, `marvin:escalation-frontier` — a model change at the session's effort, not an effort climb), or go to `max` effort on the ceiling model (`marvin:escalation-max`)? The answer applies to THIS task only — never a standing preference.
   - **Interactive session** → ask with the host's question tool. Only an explicit frontier choice dispatches `marvin:escalation-frontier`; a reply giving a different instruction ("stop, I'll take it") is followed instead; ANY other outcome — max chosen, the question dismissed or skipped, or a reply that picks neither — dispatches `marvin:escalation-max`. No answer means max.
   - **Unattended** — a scheduled, headless or background session, the user having said to proceed without them, or no interactive question tool → do not ask; dispatch `marvin:escalation-max` immediately.
   - Either way, RECORD in the task's report and tracker comment which way the gate went and why (frontier chosen / max chosen / no answer or neither / other instruction / unattended). Never silently.
4. The chosen final rung fails twice → **STOP**. The ladder terminates; never loop back to a lower rung. Escalate to the user per `guardrails.md`'s escalation chain with the full attempt history.

`marvin:escalation-frontier` is deliberately UNPINNED on effort: it inherits the session's effort, because the swap is a model change, not an effort climb. The max-gate question tells the user so.

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
