---
doc: User updates
type: reference
status: active
summary: The concrete formats the orchestrator uses when talking to the user — a fixed emoji legend, the shipped table, the issue callout with its five ordered points, the Next / Open questions tail, and when a plain line beats a table.
updated: {{INSTALL_DATE}}
---

# User updates — formats

The binding rule is CLAUDE.md's "Talking to the user" standing rule: say only what changed, say it once, say it plain, and leave detail in tickets and files. This file owns the formats. They are plain Markdown and render in any Markdown chat surface; no tool-specific visuals are needed.

**Legend** (fixed; use no other status emoji): ✅ done / passed · ❌ failed · ⚠️ needs attention · ⏳ in progress · ⏭️ skipped / deferred

**Table or line?** One event gets one plain line with its emoji (`✅ AOS-12 merged to develop.`). Use a table when there are two or more items in the same message, and a callout for every issue or blocker, however small.

## Shipped / done: a table, one row per item

Columns are `item | result | where`. `where` names the ticket, commit, file or report that holds the detail; the table never copies that detail. A sub-agent's summary is never pasted into chat, not even folded (a `<details>` fold does not render collapsed in every chat surface): link its run report instead.

| item | result | where |
|---|---|---|
| AOS-12 cache keys | ✅ documented | AOS-12 comment |
| AOS-13 export CSV | ❌ validator failed | AOS-13 comment |
| AOS-14 docs | ⏭️ deferred | `.docs/future/export.md` |

## Issue / blocker: a callout with five points

This is a blockquote with a bold ⚠️ (needs attention) or ❌ (failed) lead. The points always appear in this order, one line each. Write `unknown` for a Cause that is not yet known. **Needs you?** names the decision required, or says `no`.

> **❌ AOS-13 blocked: completion validator failed**
> - **What**: the CSV export drops rows with unicode names.
> - **Impact**: AOS-13 cannot close; the release waits on it.
> - **Cause**: the encoder defaults to latin-1.
> - **Fix**: rebuild with UTF-8 (round 2, converging — same tier).
> - **Needs you?**: no.

A two-column table (`point | detail`) with the same five rows is an equal alternative when blockquotes render poorly.

## Next / Open questions: the tail of every message

This is a short list at the end of the message. It is the ONLY part that repeats across messages. Everything above it is said once.

**Next**

- merge AOS-12

**Open questions**

- ship AOS-14 docs in this release or the next?

Leave a heading out when its list is empty. A message that changes nothing the user cares about is not sent.
