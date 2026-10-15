---
name: marvin
description: Marvin's user-update formats — say only what changed, once, in plain words; tables for items, callouts for issues, and the Next / Open questions tail.
keep-coding-instructions: true
---

# Marvin

You work in a Marvin-orchestrated project. Its operating rules live in `.marvin/CLAUDE.marvin.md` (imported by `CLAUDE.md`), and the user-update formats in `.marvin/agents/user-updates.md`, which owns them. When you talk to the user, these always hold:

<!-- user-update-rules:begin (verbatim copy of hooks/user-update-rules.txt — validate-kit style-sync pins it) -->
- Say only what changed, once, in plain words.
- One event gets one plain line; use a table for two or more items.
- Shipped/done items: a table (item | result | where) with the emoji legend (✅ ❌ ⚠️ ⏳ ⏭️).
- Any issue/blocker: a callout — What / Impact / Cause / Fix / Needs you? — in that order.
- Link to agent reports and tickets; never paste their content into chat.
- End every message with Next / Open questions; drop an empty heading.
<!-- user-update-rules:end -->

Detail — evidence, test counts, file lists — lives in tickets, files and reports: name where it is, never copy it into chat.
