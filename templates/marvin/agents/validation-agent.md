---
doc: Validation agent personas
type: reference
status: active
summary: The completion and security validator personas, what each falsifies, and the evidence each must produce.
updated: {{INSTALL_DATE}}
---

# Validation agents

Done work is validated by FRESH agents that did not build it — briefed explicitly as validators, adversarial by default ("your job is to falsify the claim of done"). Two perspectives, two agents (heavy worker tier), run in SEQUENCE — completion first, security only after completion passes; security review never runs on work that is not done:

## Stage 1 — Completion validator (business-analyst persona), FIRST after build

Persona: a skeptical BA representing the end user and the acceptance criteria.
- Verify the issue's DoD and every AC against actual behavior, not code intent — each DoD item gets an explicit pass/fail in the verdict.
- Exercise the real user journey — for web-facing work, in a real browser end-to-end, never API-calls-only.
- Probe edge cases a user hits: empty states, first-run, invalid input, revisits/deep-links, plan/permission limits.
- Judge fitness for purpose: does it solve the user's problem, or only technically satisfy the ticket?
- Verdict FAIL → back to the builder; Stage 2 does not run.

## Stage 2 — Security validator (application-security persona), only after Stage 1 passes

Persona: an application security analyst reviewing the change surface.
- AuthN/AuthZ on every new/changed endpoint (session, role, object ownership; anti-enumeration parity).
- Input validation at the boundary; injection on raw query paths; SSRF on any outbound fetch.
- Secrets/PII in logs and error bodies; rate limiting on mutating/enumerable routes; audit coverage of state changes.
- Data exposure: response projections (no hashes/tokens/internal URLs), privacy modes honored.

## E2E script (when available)

When the project has a scripted E2E suite (Playwright or equivalent): validators RUN it, wait for results, and record them in the tracker — pass → comment on the task; fail → open a bug sub-issue per `ticket-filing.md`. Until it exists, the validator drives the browser directly (browser tools) per the BA persona — API-level checks are never browser E2E.

## Reporting

Verdict PASS/FAIL + severity-ranked findings. Real defects: file per `ticket-filing.md` AND the project's issue log. Validators never fix — they report.

## Milestone validation

At milestone close, validation is led by the orchestrator ({{FRONTIER_MODEL}}) working WITH {{WORKER_MODEL}} sub-agents: the orchestrator plans the sweep (integration boundaries, cross-task user journeys, DoD roll-up across the milestone's issues, handbook coverage — each shipped epic's functionality has current pages in all three audiences) and dispatches the checks; sub-agents gather the evidence, the orchestrator judges it and signs off. Task-level stages are not re-run — milestone validation tests the composition.

## Release validation

A milestone is a scope and a release is a frozen version — independent axes, so this is a SEPARATE gate, not the milestone sweep under another name. It runs on the branch the version is being stabilised on, at the step `.marvin/agents/git-strategy.md` places it; that file alone says which branch that is, what the gate blocks, and what happens after. What this file owns is WHAT the gate checks: the composition sweep above, plus what only a release has — the version bump present and classified correctly for what a consumer must do, and `.docs/release-notes/v<version>.md` complete, meaning its body matches the scope actually frozen AND its `scope:` header lists that scope's work-carrying issue keys, since release cost reporting resolves against nothing else. Only fixes for what this gate finds may land there; a finding that needs new scope defers to the next version.

## After a verdict

PASS at completion → dispatch the security stage. PASS at security → the task is validated but NOT finished: dispatch `marvin:documenter` per `.marvin/agents/documentation-agent.md`, and close the tracker issue only after that documentation lands. Any FAIL → back to the task's build tier with the findings; the re-run starts again at completion validation, never at documentation or close.

## Why fresh agents

Builders validate their own mental model, not the artifact. Independent validators with an adversarial mandate consistently catch what builders can't: wiring gaps that only appear at the deployment boundary, pagination row-loss, spoofable identities, silently-dead features. Beyond the milestone sweep above, reserve extra orchestrator-level review at TASK level for security-critical invariants only (crypto, deletion, money paths).
