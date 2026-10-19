---
doc: Session budget
type: reference
status: active
summary: How long an orchestrator session runs — the absolute context budgets, the 70 / 80 / 90 % context ladder, keeping the work rate stoppable, the stop-and-compact nudge, and what a handoff carries.
updated: {{INSTALL_DATE}}
---

# Session budget — stop cleanly before the context fills

Session length is governed by CONTEXT SIZE, never by a task count. Re-reading a long context is the orchestrator's largest cost, and a session that fills mid-task is the hardest one to stop. So plan the work so that you are always one **clean logical break** away from stopping: all work committed, the tracker current, no sub-agent running.

## Two scales — the stricter one speaks

The marvin plugin's context hook measures your context after every tool call and on every prompt, and maps it to a level:

| level | absolute budget | context ladder | what you do |
|---|---|---|---|
| 1 plan | past the soft budget (400k) | 70 % of the window | plan only work that can finish before level 2 (the 80 % step or the hard budget, whichever comes first); split or defer anything larger; dispatch no `size:l` or `size:xl` task; at the next clean logical break tell the user where the session stands |
| 2 wind down | past the hard budget (700k) | 80 % | start no new task; finish the in-flight one to the next clean logical break; write the handoff now |
| 3 stop | — | 90 % | stop at the next clean logical break; lead every reply with the nudge (below) until the user acts |

The window is the one this session compacts against: `context_window_ktokens` in `.marvin/PROJECT-INFO.md` when set; else the host's compaction window (`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, or 200k under `CLAUDE_CODE_DISABLE_1M_CONTEXT=1`); else the orchestrator model's window (`model-profile.md`). A lower auto-compact percentage (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`) scales every step down with it, so level 3 still comes before compaction. A project moves the budgets with `session_soft_ktokens` / `session_hard_ktokens`. On a default session the budgets lead; the ladder protects a smaller window.

## Keep the work rate stoppable

- Before each dispatch, ask whether the task can reach a clean logical break before the next step. If not, split it or defer it to the next session.
- From level 1 on, start no `size:l` or `size:xl` task and no new parallel batch, and keep sub-agent results to their digest (`briefing.md` item 11) — every final message lands in your context.
- Never let level 3 find a sub-agent running or work uncommitted: that is the stuck state this file exists to prevent.

## The nudge

At level 3, say it plainly at the top of every reply until the user acts:

- **Mid-epic → `/compact`.** Write the handoff FIRST, then ask the user to run `/compact`; compaction keeps the thread, and the handoff keeps what compaction would lose.
- **At an epic or release edge → a fresh session**, with the one-line prompt that resumes.

Without the plugin's hook, check at milestone close and act on the same table.

## The handoff

What the next session — or the compacted one — cannot rebuild from the repo, tracker or handbooks: work in flight (issue key, branch, the gate each task stands at, each in-flight task's ledger path `<session>/<KEY>/ledger.md`), open decisions and blockers, every worktree you leave and whether it is safe to delete (`worktrees.md`), and the next step. Write noteworthy findings to `.marvin/MEMORY.md` before compaction — it is the continuity.
