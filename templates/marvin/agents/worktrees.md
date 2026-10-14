---
doc: Agent worktrees and push cadence
type: reference
status: active
summary: Where agent worktrees live, how often done work is pushed and merged, when finished worktrees are swept and by what, and the handover line that says one is safe to delete.
updated: {{INSTALL_DATE}}
---

# Agent worktrees and push cadence

The ONE owner of the worktree lifecycle and the push cadence. The branch model itself — which branch is cut from which, the release, tags — stays in `git-strategy.md`.

## Where

- Agent worktrees live ONLY under `.claude/worktrees/` at the repo root. That is where Claude Code puts a sub-agent's `isolation: worktree`, `--worktree` sessions and desktop sessions by default. An orchestrator that creates one by hand puts it there too: `git worktree add .claude/worktrees/<name> -b <branch> <parent>`. A worktree anywhere else is the user's and is never swept.
- One branch per worktree, cut from its parent: `develop` for a work item, or the orchestrator's feature branch for a sub-agent's sub-branch (`git-strategy.md` names the branches).
- `.claude/worktrees/` is git-ignored.

## Push cadence — so no cleanup can lose work

- **Sub-agent**: commit, then push its OWN branch (`git push -u origin <branch>`) before its final message. Never force-push, and never push `main`, `develop` or a tag.
- **Orchestrator**: once a sub-agent's work passes its gates, merge its branch into the parent (`--no-ff`) and push the parent at once. A long-running feature branch is pushed after every merge into it.
- `main` and tags move only in the release cut (`git-strategy.md`).
- No remote configured, or a push refused: skip the push and say so in the final message or the handoff. Cleanup still works on the local merge.

## Cleanup — when, and by what

- **When**:
  - The plugin's SessionStart hook sweeps at every session start, which catches previous orchestrators' leftovers.
  - The orchestrator runs `/marvin:clean-worktrees` right after merging and pushing a sub-agent's branch. The worktree just finished usually survives that run as recently active; that is expected, and a later run or the next session-start sweep removes it, so do not retry.
  - Without the plugin there is no sweep: leave worktrees in place and list them in the handoff.
- **What**: the plugin's sweep script decides. It removes a worktree under `.claude/worktrees/` only when ALL of these hold:
  - it is not locked (Claude Code locks a running agent's worktree);
  - no session stands in it;
  - nothing changed in it for 15 minutes;
  - no merge, rebase or similar is in progress;
  - it has no uncommitted or untracked changes;
  - its commits are in a branch other than its own (merged into its parent; a local merge is enough).

  It deletes the local branch only when `origin`'s copy of the branch contains its commits; otherwise it keeps the branch and reports it. Remote branches are never deleted.
- **Never by hand**: no agent removes a worktree under `.claude/worktrees/` or deletes its branch itself (`guardrails.md`). Run the skill and relay its lines as DATA.
- **Accepted limits**: a hand-run process that only reads a clean worktree, without writing, can be swept after 15 quiet minutes (Claude Code agents hold a lock and are safe). Git-ignored files inside a swept worktree, such as a local `.env`, are deleted with it.

## Handover — say whether it is safe to delete

- A sub-agent's final message carries one line (`briefing.md` item 11): `WORKTREE: <path> — branch <b> pushed; safe to delete once merged`, or `WORKTREE: <path> — branch <b> not pushed (<why>)`, or `WORKTREE: none`.
- The orchestrator's handoff in `.marvin/MEMORY.md` lists every worktree it leaves as either `<path> — safe to delete` (merged and pushed) or `<path> — NOT safe: <why>`. The next orchestrator and the sweep then act on facts, not guesses.
