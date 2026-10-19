---
doc: Session recovery
type: reference
status: active
summary: What the orchestrator does when its session's worktree vanished mid-task — recreate it from its branch, re-check the branch, confirm the run state in the project, never mark the worktree, report the loss.
updated: {{INSTALL_DATE}}
---

# Session recovery — the session's worktree vanished mid-task

**When**: a tool or the shell reports `Working directory … no longer exists`, or the checkout you stood in is gone. Committed and pushed work lives on its branch; the run state lives in the project's run folder (`briefing.md` item 11); what the worktree alone held — uncommitted edits, unpushed commits, a git-ignored file with no copy elsewhere — may be lost. Stop dispatching until the five steps below are done, in order.

**The desktop recycle.** The desktop app can resume the same session in a NEW worktree when the old one is gone. It checks out the session's ORIGINAL branch there, not the branch you last worked on. The session id is unchanged, so the same project run folder applies, and the SessionStart hook seeds the new checkout's missing local copies of the ledger and build brief from the project.

## The procedure

1. **Recreate the worktree from its branch** under `.claude/worktrees/`, anchored at the main checkout root, never wherever you stand: `git -C <main checkout> worktree add "<main checkout>/.claude/worktrees/<name>" <branch>`. If git refuses because the branch is still registered at the vanished path, `git -C <main checkout> worktree prune` clears that stale record — it touches only records whose folder is already gone. After a desktop recycle you already stand in a new worktree: skip the add.
2. **Re-check the checked-out branch** against the one you last worked on (the `MEMORY.md` handoff, the ledger's task key, the tracker issue). A recycle sits on the session's ORIGINAL branch; switch to the right one before any write, and compare its tip with origin's so an unpushed commit lost with the old worktree is noticed, not overwritten.
3. **Confirm the run state — a check, not a copy-back.** The project's `.marvin/runs/<session>/<KEY>/ledger.md` and build brief must exist and end where you last wrote them. Reconcile against any newer copy in an agent worktree under `.claude/worktrees/` and against any `<stem>.clash-*.md` sidecar beside them (`briefing.md` item 11). Without the plugin the run state lived only in the vanished checkout: rebuild what you can from the tracker comments and the final messages you hold, and say what you could not.
4. **Never mark it.** A worktree you re-create by hand is a session worktree, not Marvin's — never mark it. The marker is only for the worktrees Marvin creates for its agents, by hook or by hand (`worktrees.md`); a marked session worktree becomes sweepable.
5. **Report the loss as an issue callout** (`user-updates.md`): what vanished, what was recovered, and what is gone for good — uncommitted edits, unpushed commits, a run file with no project copy.
