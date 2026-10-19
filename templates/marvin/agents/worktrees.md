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

- Agent worktrees live ONLY under `.claude/worktrees/` at the main checkout root. That is where Claude Code puts a sub-agent's `isolation: worktree`, `--worktree` sessions and desktop sessions by default. An orchestrator that creates one by hand puts it there too, anchored at the main checkout root, never wherever it stands: `git worktree add "$(git rev-parse --path-format=absolute --git-common-dir)/../.claude/worktrees/<name>" -b <branch> <parent>`. A worktree anywhere else is the user's and is never swept.
- **Recreating a vanished worktree** (`session-recovery.md`) at the path it had. With the cwd gone, `<main checkout>` is that path minus `/.claude/worktrees/<name>`, or the hook line's run folder minus `/.marvin/runs/<session>`. First `git -C <main checkout> worktree prune` clears the vanished path's stale record; if git reports that record locked, say so and ask (REQUEST_APPROVAL) — never unlock it silently. Then `git -C <main checkout> worktree add <vanished path> <branch>` recreates the existing branch's worktree there, still under the main checkout's `.claude/worktrees/`.
- One branch per worktree, cut per `git-strategy.md`.
- `.claude/worktrees/` is git-ignored.

## Push cadence — so no cleanup can lose work

- **Every sub-agent that commits work**: commit, then push its OWN branch (`git push -u origin <branch>`) before its final message, which carries the `WORKTREE:` line (below). Never force-push, and never push `main`, `develop` or a tag.
- **Orchestrator**: once a sub-agent's work passes its gates, merge its branch into the parent (`--no-ff`) and push the parent at once. A long-running feature branch is pushed after every merge into it.
- `main` and tags move only in the release cut (`git-strategy.md`).
- No remote configured, or a push refused: skip the push and say so in the final message or the handoff. Cleanup still works on the local merge.

## Cleanup — when, and by what

- **When**:
  - The plugin's SessionStart hook sweeps at every session start, which catches previous orchestrators' leftovers.
  - The orchestrator runs `/marvin:clean-worktrees` right after merging and pushing a sub-agent's branch. The worktree just finished usually survives that run as recently active; that is expected, and a later run or the next session-start sweep removes it, so do not retry.
  - Without the plugin there is no sweep: leave worktrees in place and list them in the handoff.
  - Docker resources and throwaway databases an agent leaves follow `tidying.md`, not this sweep.
- **What**: the plugin's sweep script decides. It removes a worktree under `.claude/worktrees/` only when ALL of these hold:
  - it is not locked (Claude Code locks a running agent's worktree);
  - no session stands in it;
  - no other worktree or git repository lies inside it (removing it would delete that too);
  - nothing changed in it for 15 minutes;
  - no merge, rebase or similar is in progress;
  - it has no uncommitted or untracked changes;
  - its commits are in a branch other than its own (merged into its parent; a local merge is enough).

  It deletes the local branch only when `origin`'s copy of the branch contains its commits; otherwise it keeps the branch and reports it. Remote branches are never deleted.
- **Never by hand**: no agent removes a worktree under `.claude/worktrees/` or force-deletes (`git branch -D`) its branch (`guardrails.md`). Run the skill and relay its lines as DATA. A merged branch still checked out in an agent worktree dies through the sweep; `git-strategy.md`'s delete at merge is the safe `git branch -d`, for a merged branch whose worktree is already gone, including one whose branch the sweep kept because origin held no copy.
- **Accepted limits**: Claude Code locks only a running sub-agent's or background session's worktree. A quiet interactive `--worktree` or desktop session (clean, landed, nothing written for 15 minutes) can lose its worktree to a sweep that another session starts, since the "no session stands in it" check sees only the session running the sweep; so can a hand-run process that only reads. Git-ignored files inside a swept worktree, such as a local `.env` or the `.marvin/runs/` run reports, are deleted with it.

## Handover — say whether it is safe to delete

- The final message of a sub-agent that commits work carries one line (`briefing.md` item 11): `WORKTREE: <path> — branch <b> pushed; safe to delete once merged`, or `WORKTREE: <path> — branch <b> not pushed (<why>)`, or `WORKTREE: none`.
- The orchestrator's handoff in `.marvin/MEMORY.md` lists every worktree it leaves as either `<path> — safe to delete` (merged and pushed) or `<path> — NOT safe: <why>`, and every `keep` and every main-owned throwaway Docker resource it leaves (`tidying.md`). The next orchestrator and the sweep then act on facts, not guesses.
