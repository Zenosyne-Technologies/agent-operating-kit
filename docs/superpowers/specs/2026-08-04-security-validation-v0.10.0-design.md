# Security discipline + two-stage validation — kit v0.10.0 design

Date: 2026-08-04 · Status: approved for planning (owner-directed) · Target plugin version: 0.10.0

## Context

Security in the kit is enforced almost entirely post-build: a strong adversarial security validator exists, security-critical design stays orchestrator-inline, and micro-models are locked out of security-adjacent code — but briefs carry no security awareness, nothing governs secrets handling (increasingly relevant now that comment discipline and reporting write agent output into the PM tool), and dependencies are unvetted. Separately, the owner requires validation to be sequenced: a completion validator directly after execution, gating the security validator — today the BA and security validators run in parallel.

## Goals

1. A security-discipline cascade file governs secrets, dependencies, and security surfaces for every task that touches them.
2. Build briefs name the task's security surface as a mandatory ingredient.
3. Validation is two-stage and ordered: completion validator (BA persona, exists today) runs first after build; the security validator runs only after completion passes. Security review never runs on incomplete work.

## Non-goals

- Automated scanners/SAST in the kit (the discipline names native advisory tooling; wiring project-specific scanners is per-project work).
- Changes to the orchestrator-inline rule for security-critical design (already correct).

## Design

### 1. `templates/docs/agents/security.md` (new, cascade)

Three sections, ≤45 lines, no new placeholders:
- **Secrets**: never commit secrets (keys, tokens, passwords, `.env`, live connection strings) — env wiring + `.env.example` placeholders only; never paste secrets into the PM tool (issue comments, report snapshots, tracker docs, PR bodies are shared surfaces — scrub command output before posting); a leaked secret is a sev1 incident: rotate first, then file.
- **Dependencies**: add/upgrade is never ponytail work — size `m` minimum and named in the brief; check advisories before adopting (npm audit / pip-audit / osv equivalents); pin exact versions; new dependencies listed in the FINAL MESSAGE.
- **Surfaces**: briefs name the task's security surface (per briefing.md); security-critical design stays orchestrator-inline; validation order is two-stage per validation-agent.md.

Cascade line in `CLAUDE.core.md`: any task touching auth, input boundaries, data exposure, secrets, or dependencies → `security.md`.

### 2. Brief ingredient (`briefing.md`)

New item 4 (after DoD; items renumber to 1–10): **Security surface** — the brief names the task's security-sensitive surfaces (auth, input-validation boundaries, data exposure, secrets touched, dependency changes) citing `security.md`; no secrets in code, commits, comments, or reports — ever.

### 3. Two-stage validation (`validation-agent.md` + `CLAUDE.core.md` lifecycle)

- validation-agent.md: the two personas become ordered stages — "run in SEQUENCE" replaces "both may run in parallel". Stage 1 **Completion validator** (business-analyst persona) runs FIRST directly after build; FAIL → back to the builder, stage 2 does not run. Stage 2 **Security validator** runs only after stage 1 passes. Persona content is otherwise unchanged.
- CLAUDE.core.md lifecycle becomes: build → **validate-completion** → **validate-security** (only after completion passes) → document → close.

## File change list

| File | Change |
|---|---|
| `templates/docs/agents/security.md` | new |
| `templates/docs/agents/briefing.md` | security-surface ingredient, renumber to 1–10 |
| `templates/docs/agents/validation-agent.md` | sequenced two-stage restructure |
| `templates/CLAUDE.core.md` | lifecycle two-stage + security cascade line (≤45 lines) |
| `README.md` | core idea 3 sequencing, inventory line for security.md |
| `.claude-plugin/plugin.json` | 0.10.0 |

## Compatibility

- Branches off main at v0.8.0 payload; independent of the v0.9.0 CI branch (whichever merges second resolves a one-line version/README conflict).
- Existing installs pick this up via `upgrade-agent-os` (new cascade file + edited files are its normal diff work).

## Testing

Manual release sweep (JSON, no plugin-root leak, ≤45-line budgets, registry header unchanged at v1.2.0) — the v0.9.0 CI gate re-checks everything once both branches land. Coherence walk: brief ingredient ↔ security.md surfaces section ↔ validation order ↔ lifecycle line all reference each other consistently; secrets rule names the PM-tool surfaces that v0.8.0 introduced (comments, snapshots).
