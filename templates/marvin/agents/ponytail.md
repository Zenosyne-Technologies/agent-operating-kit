---
doc: Micro-task profile
type: reference
status: active
summary: What a zero-discretion size:xs micro-task looks like, and how to brief one so it needs no clarification.
updated: {{INSTALL_DATE}}
---

# Ponytail — micro-model task profile

For mechanical, low-blast-radius work where the orchestrator (or a worker agent) already made every decision. The micro-model agent executes; it does not judge.

Eligible — any step whose every input and outcome is already decided, so executing it takes no judgement:
- **Tracker bookkeeping** — the orchestrator's standing job for this tier (core rules, dispatch): every tracker call whose content is decided — transitions, labels, comments, filing or updating from fully specified text (per `ticket-filing.md`), status and field reads returning only the fields asked for.
- **Release mechanics** — the mechanical steps of a cut `git-strategy.md` orders: the version-bump edit to a version already classified, extracting the release note's body to a tag-message file, setting the tracker-side release object `tracker-config.md` maps (a label, a field or a native Release — tracker bookkeeping, not publishing, per `git-strategy.md`). It may prepare the tag message and the release-note body; it never creates, moves or deletes a tag, and never publishes a forge release (`git-strategy.md`).
- **Reader lookups** for the orchestrator — a named file's section or one exact-pattern grep, returned as the excerpt (with `file:line`) or a count, never a summary.
- Label/metadata/data entry; lint/format-only fixes; single-file edits with the exact diff described; doc typo passes.

Not eligible: anything needing judgment, multi-file edits, security-adjacent code, user-visible copywriting from scratch.

Brief template (≤15 lines + payload):
```
Task: <one sentence>.
Tools: <exact tool names; ONE tool-search call if deferred>.
Input: <the prepared payload, verbatim>.
Do: <numbered mechanical steps, incl. list-before-create idempotency>.
FINAL MESSAGE: <exact format>. Nothing else.
Report: <run-report path, per `briefing.md` item 11>.
```

If the agent would need to ask a question, the task was mis-tiered — pull it back to the small worker.
