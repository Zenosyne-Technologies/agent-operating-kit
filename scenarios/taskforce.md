# taskforce — a bounded mini-lifecycle with a mandatory devil's advocate

summary: Run one bounded research→build→validate lifecycle with an always-on devil's-advocate challenge.

This scenario runs under `scenarios/contract.md` — the bounded-execution contract, the
periodic-report schema, the mode model, and the safety rule all come from there and are NOT
restated here. This file only layers this scenario's specific shape on top.

## Bounded-execution declaration

- **GOAL** — one scoped piece of work is carried through a mini-lifecycle: `marvin:researcher`
  investigates and returns a memo, the orchestrator turns that memo into a plan, `marvin:developer`
  builds to it, `marvin:validator-completion` checks it against the plan (and
  `marvin:validator-security` too when the change touches a security surface), AND a dedicated
  **devil's-advocate** pass challenges the solution. The round is done when the solution is built,
  validated, and the devil's advocate has either cleared it or its findings have been resolved.
- **LIMITS** — max sub-agents dispatched: **6** (researcher, developer, completion validator,
  security validator when warranted, the devil's advocate, and at most one remediation developer).
  Max rounds: **4** (research, build, validate-and-challenge, at most one targeted remediation
  round). Per-round fan-out: **3** (the validate-and-challenge round may run completion validator,
  security validator, and the devil's advocate together). Every cap is a hard stop.
- **POSITIVE exit** — the solution is built and validated, AND the devil's advocate either cleared
  it or every blocking finding it raised was resolved within the caps. Close `close-positive`.
- **NEGATIVE exit** — the devil's advocate finds a **blocker that cannot be resolved within these
  LIMITS** (the fix needs redesign, exceeds the round/agent caps, or is out of scope): **close
  gracefully** — record the blocking finding and a recommendation to file it as a properly scoped
  tracked task per `.marvin/agents/ticket-filing.md` (cite, don't restate) — and close
  `close-negative`. Do NOT loop trying to force the solution through; a cap reached before the work
  is validated-and-cleared is likewise a `close-negative`.

## The devil's advocate is never omitted

The devil's-advocate pass is **mandatory on every taskforce run** — it is the point of the
scenario, not an optional extra, and the gate MUST NOT close `close-positive` until it has run.
It is a **fresh adversarial pass** dispatched as `marvin:validator-completion` (or
`marvin:validator-security` where the change is security-sensitive) with an explicit
devil's-advocate brief per `.marvin/agents/briefing.md`: its job is to argue AGAINST the solution —
attack the plan's assumptions, hunt the case that breaks it, and say why it should not ship. It is
never the builder reviewing its own work (contract §5: fresh validators, never the builder). It
operates find-and-report only — it never attacks a live system (contract §4).

## Dispatch (sub-agent mode — the default today)

1. Dispatch one `marvin:researcher` (scoped brief per `.marvin/agents/briefing.md`); it returns a
   memo and the contract's periodic-report block. The orchestrator turns the memo into a plan.
2. Dispatch one `marvin:developer` to build to that plan; it returns the periodic-report block.
3. Dispatch the validate-and-challenge round: `marvin:validator-completion` against the plan,
   `marvin:validator-security` when the change warrants it, and ALWAYS the devil's-advocate pass
   above. Each returns the periodic-report block.
4. **Gate.** If validated and the devil's advocate cleared (or its findings resolved) →
   `close-positive`. If a validator or the devil's advocate raises a fixable finding and a
   remediation round remains, dispatch one `marvin:developer` remediation round, then re-run the
   challenge. If the devil's advocate's blocker is unresolvable within the caps → the negative exit
   above. The gate runs between every round per the contract.

## Agent-teams seam (dormant)

Under agent-teams mode (Milestone E) the researcher, developer, validators, and the devil's
advocate form a **persistent taskforce team** that carries state across rounds instead of the
orchestrator re-dispatching each role fresh each round; the mandatory devil's-advocate challenge,
the GOAL/LIMITS/exits, and the periodic-report schema are unchanged either way. **Today this
defaults to orchestrator-sequenced sub-agents** (the path above), per the contract's mode model.
This scenario names no Milestone E setting or key — only that explicit setting, when it exists,
activates the team path.
