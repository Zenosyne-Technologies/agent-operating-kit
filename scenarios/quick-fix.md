# quick-fix — one small, scoped fix, one agent

summary: Build, validate, and commit one size:s fix via a single agent — stop if it grows.

This scenario runs under `scenarios/contract.md` — the bounded-execution contract, the
periodic-report schema, the mode model, and the safety rule all come from there and are NOT
restated here. This file only layers this scenario's specific shape on top.

## Bounded-execution declaration

- **GOAL** — the scoped fix is built, validated, and committed through the project's normal task
  lifecycle (the same build → completion-validation → security-validation → commit path any
  tracked task follows).
- **LIMITS** — max sub-agents dispatched: **1** at a time (the builder, then the fresh validators
  the lifecycle requires — never the builder validating itself). Max rounds: **2** (build, then at
  most one validator-driven fix round). **Size ceiling: `size:s`** — the work must fit the small
  tier; anything larger is out of scope for this scenario.
- **POSITIVE exit** — the fix is built, both validators pass, and it is committed.
- **NEGATIVE exit (the anti-runaway guard)** — the work turns out **larger than `size:s`** (it
  fans out across files, needs design, or exceeds the small tier): **STOP — do not balloon it into
  a big build.** Close `close-negative`, recommend filing a properly scoped tracked task for it,
  and hand back what was learned (the real shape of the work, what was touched, why it is bigger).

## Dispatch (sub-agent mode)

The build round dispatches **one `marvin:developer-small`** with a scoped brief per
`.marvin/agents/briefing.md` (use `marvin:developer` only if the size clearly demands the heavy
tier — but if it needs that, re-check the size ceiling first). The builder returns the contract's
periodic-report block. The gate closes on an exit, or dispatches the fresh validators the
lifecycle requires before the commit. The moment `budget_used` or the builder's findings show the
task has outgrown `size:s`, the gate takes the negative exit above.

## Agent-teams note

Under agent-teams mode the same single-fix shape applies; a one-agent scoped fix has no team
variation. The contract's mode model governs which mode is active.
