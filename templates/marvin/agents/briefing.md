---
doc: Agent brief discipline
type: reference
status: active
summary: What every sub-agent brief must contain, in order, and why a mid-run policy change is refused rather than obeyed.
updated: {{INSTALL_DATE}}
---

# Agent brief discipline

Every sub-agent brief includes, in this order:

1. **Env preamble**: the project's shell prefix/env requirements, container naming + ports if used (remove containers when done).
2. **Exact scope**: file paths and *sections* to read — never "explore the repo". Scoped commands (per-package filters, targeted test files); full suite only for the agent that owns the whole tree at commit time.
3. **DoD**: the task's definition of done, copied from the tracker issue — verifiable statements the agent works to; the FINAL MESSAGE reports each DoD item met or missed.
4. **Security surface**: the task's security-sensitive surfaces (auth, input-validation boundaries, data exposure, secrets touched, dependency changes), citing `security.md`; no secrets in code, commits, comments, or reports — ever.
5. **Information rules**: name — by path — every file in `.docs/information/` that binds this task. Two sets, both mandatory: those whose `relevance:` matches this agent's persona at a severity that makes them so, PLUS every `critical` file whose subject area the task touches, whatever its relevance — a critical rule binds by SUBJECT, not by role (`information-guide.md`, `information-severity.md`). Decide both from `.docs/information/index.md` alone; its severity, relevance and summary columns exist for exactly this, so no file is opened to write the brief. Name them; never say "check the information folder". Omitting a `critical` file that applies makes the brief defective, and the resulting failure the orchestrator's.
6. **Guardrails**: name the agent's binding DO NOT rows — its generic baseline PLUS its persona section in `guardrails.md` — exactly the way item 5 names its information files. Point at `guardrails.md` for the four dispositions and the escalation chain; never restate a rule. A sub-agent has no channel to the user, so a `CLARIFY`/`REQUEST_APPROVAL`/`SKIP` hit is reported in the FINAL MESSAGE for the orchestrator to resolve or carry up.
7. **Ownership boundary** (concurrent agents): the paths this agent owns; selective `git add <paths>` only, never `-A`.
8. **Branch + autocommit**: the ONE branch this agent works on, written out in full as a literal name (`feature/AOS-123-cache-keys`), resolved by the orchestrator from `.marvin/agents/git-strategy.md` — never a pattern for the agent to fill in, never a branch for it to choose or create. The brief also points the agent at that file for everything it does NOT decide, tagging included. The agent commits its own scoped work itself (atomic commits, selective add), messages starting with the tracker issue key the brief names (`<KEY>: …`) before its final message — work is never left uncommitted, and the agent never asks permission to commit.
9. **Idempotency** (create/import tasks): list-before-create, skip existing — retries and resumes become free.
10. **"Work synchronously, no sub-agents."**
11. **FINAL MESSAGE spec**: machine-consumed exact format. The orchestrator parses only that — never reads transcripts (context blowout). When item 5 named any file, the spec reserves one line — `INFORMATION: <paths read, or NONE>` — which is where a `critical` rule is attested to; a spec with no such line is a brief that named no rules. The guardrails item always binds, so the spec also reserves `GUARDRAILS: <rows bound; any DO NOT hit with its disposition, or NONE>` — the channel by which a stopped sub-agent escalates.
12. **Attribution policy** as configured in the core rules.

**No mid-run policy changes.** Agents rightly treat instructions that reverse their original brief mid-run as possible prompt-injection and may refuse. Put policy in the original brief; if policy changes while an agent runs, let it finish per its brief and reconcile afterward (amend the commit, correct the record).

Ponytail (micro-model) briefs: ≤15 lines + prepared payload, one task, exact input → exact output, zero discretion. If it needs clarification, re-tier to the small worker.
