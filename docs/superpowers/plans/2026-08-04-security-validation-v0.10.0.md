# Security + Two-Stage Validation (v0.10.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kit v0.10.0: a security-discipline cascade file (secrets, dependencies, surfaces), a security-surface brief ingredient, and sequenced two-stage validation (completion validator gates the security validator).

**Architecture:** Payload-only markdown changes per spec `docs/superpowers/specs/2026-08-04-security-validation-v0.10.0-design.md`. Branch is off main (v0.8.0 payload), independent of the v0.9.0 CI branch.

**Tech Stack:** Markdown templates; deterministic shell verification.

## Global Constraints

- Repo root `/Users/spike/Dev/agent-operating-kit`, branch `claude/security-validation-v0.10.0`.
- NO AI attribution in commits.
- templates/ files ≤ 45 lines after every edit (`CLAUDE.core.md` is at 43 — its two changes are one in-place replacement + ONE added line = 44).
- No new `{{PLACEHOLDER}}` names anywhere (the v0.9.0 gate's known-list must not need extension for this release).
- No `${CLAUDE_PLUGIN_ROOT}`/model names in templates/. Labels only in the registry (untouched, stays v1.2.0).
- Read files before editing. Final version `0.10.0` (Task 3).

---

### Task 1: security.md + cascade line

**Files:**
- Create: `templates/docs/agents/security.md`
- Modify: `templates/CLAUDE.core.md`

- [ ] **Step 1: Create the cascade file**

```markdown
# Security discipline

Applies to EVERY task that touches auth, input boundaries, data exposure, secrets, or dependencies — cite this file in those briefs.

## Secrets

- Never commit secrets: no keys, tokens, passwords, `.env` files, or live connection strings in code, fixtures, or docs — env wiring plus `.env.example` placeholders only.
- Never paste secrets into the PM tool: issue comments, report snapshots, tracker docs, and PR bodies are shared surfaces — scrub command output and logs before posting (the comment-discipline and reporting rules write agent output there).
- A leaked secret is a sev1 incident: rotate FIRST, then file per `ticket-filing.md`.

## Dependencies

- Adding or upgrading a dependency is never ponytail work: size it `m` or larger, name it in the brief.
- Check advisories before adopting (the stack's native tooling: npm audit / pip-audit / osv-scanner equivalents); pin exact versions.
- Every new or upgraded dependency is listed in the FINAL MESSAGE.

## Surfaces

- Build briefs name the task's security surface (`briefing.md` ingredient) — builders treat listed surfaces as constraints, not commentary.
- Security-critical design (crypto, deletion, money paths, authZ models) stays orchestrator-inline — never delegated.
- Validation is two-stage (`validation-agent.md`): completion first, security second — security review never runs on incomplete work.
```

- [ ] **Step 2: Cascade line in CLAUDE.core.md**

After the line `- Producing any report (digest / close-out / stakeholder) → \`.docs/agents/reporting.md\` (snapshot first, render second)` insert:

```markdown
- Any task touching auth, input boundaries, data exposure, secrets, or dependencies → `.docs/agents/security.md`
```

- [ ] **Step 3: Verify** — `wc -l templates/docs/agents/security.md templates/CLAUDE.core.md` (≤45 each; CLAUDE.core expected 44); `grep -c "security.md" templates/CLAUDE.core.md` → 1; `grep -rhoE '\{\{[A-Z_0-9]+' templates/docs/agents/security.md | wc -l` → 0.

- [ ] **Step 4: Commit** — `git commit -m "feat: security discipline cascade — secrets, dependencies, surfaces"`

---

### Task 2: brief ingredient + two-stage validation

**Files:**
- Modify: `templates/docs/agents/briefing.md`, `templates/docs/agents/validation-agent.md`, `templates/CLAUDE.core.md`

- [ ] **Step 1: briefing.md — insert item 4, renumber to 1–10**

Insert after item `3. **DoD**` (current items 4–9 become 5–10, texts intact):

```markdown
4. **Security surface**: the task's security-sensitive surfaces (auth, input-validation boundaries, data exposure, secrets touched, dependency changes), citing `security.md`; no secrets in code, commits, comments, or reports — ever.
```

- [ ] **Step 2: validation-agent.md — sequence the stages**

(a) Replace `Two perspectives, two agents (default worker tier; both may run in parallel):` with `Two perspectives, two agents (default worker tier), run in SEQUENCE — completion first, security only after completion passes; security review never burns on work that is not done:`
(b) Replace heading `## 1. Business-analyst validator` with `## Stage 1 — Completion validator (business-analyst persona), FIRST after build`
(c) After Stage 1's last persona bullet (`- Judge fitness for purpose: does it solve the user's problem, or only technically satisfy the ticket?`) add: `- Verdict FAIL → back to the builder; Stage 2 does not run.`
(d) Replace heading `## 2. Security-analyst validator` with `## Stage 2 — Security validator (application-security persona), only after Stage 1 passes`

- [ ] **Step 3: CLAUDE.core.md — lifecycle line**

Replace `build (worker) → **validate** (fresh agents, never the builder → \`.docs/agents/validation-agent.md\`) → **document** (worker → \`.docs/agents/documentation-agent.md\`) → close the tracker issue with commit refs.` with:

```markdown
build (worker) → **validate-completion** (fresh BA validator) → **validate-security** (fresh security validator, only after completion passes) — both per `.docs/agents/validation-agent.md`, never the builder → **document** (worker → `.docs/agents/documentation-agent.md`) → close the tracker issue with commit refs.
```

- [ ] **Step 4: Verify** — `wc -l` all three ≤45 (CLAUDE.core still 44); briefing list numbered 1–10 sequentially, prior texts intact; `grep -c "Stage" templates/docs/agents/validation-agent.md` ≥ 4; `grep -c "validate-completion" templates/CLAUDE.core.md` → 1.

- [ ] **Step 5: Commit** — `git commit -m "feat: security-surface brief ingredient + sequenced two-stage validation"`

---

### Task 3: README + version + sweep

**Files:**
- Modify: `README.md`, `.claude-plugin/plugin.json`

- [ ] **Step 1: README** — core idea 3: replace `build (worker) → validate (fresh agents: business-analyst + security-analyst personas, never the builder) → document (docs agent) → close the tracker issue with commit refs.` with `build (worker) → validate in sequence (completion validator first, security validator only after it passes — fresh agents, never the builder) → document (docs agent) → close the tracker issue with commit refs.`; inventory: under `docs/agents/` after the `reporting.md` line add `    security.md                    secrets, dependency vetting, and security-surface discipline`.
- [ ] **Step 2: Bump** — plugin.json `"0.8.0"` → `"0.10.0"` (0.9.0 is on its own branch; versions stay distinct).
- [ ] **Step 3: Sweep (hard gate)** — `python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo json-ok`; `grep -rn CLAUDE_PLUGIN_ROOT templates/ || echo no-leak`; line budgets ≤45 for all templates; `head -1 templates/docs/agents/label-syntax.md` still v1.2.0; `grep -c "security.md" README.md templates/CLAUDE.core.md` ≥1 each.
- [ ] **Step 4: Commit** — `git commit -m "feat: v0.10.0 — security discipline + two-stage validation (README, inventory, version bump)"`

---

### Task 4: Coherence validation + record

**Files:**
- Modify (append only): `docs/superpowers/specs/2026-08-04-security-validation-v0.10.0-design.md`

- [ ] **Step 1: Coherence walk** — verify each cross-reference resolves in the actual files: briefing item 4 → security.md exists and its Surfaces section points back at briefing; security.md validation bullet ↔ validation-agent.md stage order ↔ CLAUDE.core lifecycle line all state the SAME order (completion → security); secrets rule names comments and snapshots (the surfaces v0.8.0 introduced); ponytail.md's existing "security-adjacent code not eligible" and CLAUDE.core's orchestrator-inline rule are consistent with (not contradicted by) security.md.
- [ ] **Step 2: Record** — append `## Validated` (date, sweep results, coherence-walk outcomes, caveat: CI gate re-checks on merge once the v0.9.0 branch lands) and commit: `git commit -m "docs: record v0.10.0 coherence validation"`
