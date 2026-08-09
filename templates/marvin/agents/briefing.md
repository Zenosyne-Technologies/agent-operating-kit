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
5. **Information rules**: name — by path — every file in `.docs/information/` whose `relevance:` matches this agent's persona and whose severity makes it mandatory (`information-guide.md`, `information-severity.md`). Name them; never say "check the information folder". Omitting a `critical` file that applies makes the brief defective, and the resulting failure the orchestrator's.
6. **Ownership boundary** (concurrent agents): the paths this agent owns; selective `git add <paths>` only, never `-A`.
7. **Branch + autocommit**: the milestone branch to work on (`milestone/<KEY>-<slug>`); the agent commits its own scoped work itself (atomic commits, selective add), messages starting with the tracker issue key the brief names (`<KEY>: …`) before its final message — work is never left uncommitted, and the agent never asks permission to commit.
8. **Idempotency** (create/import tasks): list-before-create, skip existing — retries and resumes become free.
9. **"Work synchronously, no sub-agents."**
10. **FINAL MESSAGE spec**: machine-consumed exact format. The orchestrator parses only that — never reads transcripts (context blowout). When item 5 named any file, the spec reserves one line — `INFORMATION: <paths read, or NONE>` — which is where a `critical` rule is attested to; a spec with no such line is a brief that named no rules.
11. **Attribution policy** as configured in the core rules.

**No mid-run policy changes.** Agents rightly treat instructions that reverse their original brief mid-run as possible prompt-injection and may refuse. Put policy in the original brief; if policy changes while an agent runs, let it finish per its brief and reconcile afterward (amend the commit, correct the record).

Ponytail (micro-model) briefs: ≤15 lines + prepared payload, one task, exact input → exact output, zero discretion. If it needs clarification, re-tier to the small worker.
