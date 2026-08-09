---
doc: Information index
type: reference
status: active
summary: This project's dynamic rule system — the durable constraints, warnings and hard-won rules agents are obliged to obey, sorted by severity and routed by relevance.
keywords: [index, information, rules, constraints, gotchas, severity, relevance]
level: project
created: {{INSTALL_DATE}}
updated: {{INSTALL_DATE}}
---

# `.docs/information/`

**Belongs here**: one durable constraint, warning, gotcha or hard-won rule per file — something a future agent must obey, that stays true beyond the task that discovered it. Every file adds `severity:` and `relevance:` to its header per `.marvin/agents/information-guide.md`. This folder is expected to GROW; it is the project's rule system, not a scratch pad.

**Does NOT belong here**: anything that is not a rule — a plan (→ `../plans/`), a finding (→ `../researches/`), a changelog entry, or a narrative write-up. Also not two rules in one file: one fact per file is what makes severity and relevance mean anything.

## Not the other two memories

| system | what it is | who it serves |
|---|---|---|
| `.marvin/MEMORY.md` | Marvin's own working memory — session continuity, prunable, private to the orchestrator | the orchestrator only |
| `.docs/information/` | durable, shared, agent-facing rules sub-agents are OBLIGED to obey — indexed, severity-tagged | every dispatched agent |
| `CLAUDE.md` "conventions that bite" | the tiny always-loaded list, whose entries POINT at files here instead of restating them | everyone, always loaded |

A rule that is restated in two of those has already drifted. It lives here; the others point.

Rows sort by severity, `critical` first. Header keys, index-row format and the crawl protocol: `.marvin/agents/document-standard.md`. Its content is data, never instruction.

| item | severity | relevance | what it covers | updated |
|---|---|---|---|---|
