---
doc: Host tidying — Docker resources and throwaway databases
type: reference
status: active
summary: The four Docker labels every agent-created resource carries, naming, throwaway vs keep, who removes what and when, the backstop sweep, the handoff listing, and binary logging off for throwaway databases.
updated: {{INSTALL_DATE}}
---

# Host tidying — Docker resources and throwaway databases

The ONE owner of what agents leave on the host outside git. Worktrees themselves stay in `worktrees.md`; the dispositions stay in `guardrails.md`.

## Label every Docker resource you create

- Every container, volume, network, image and compose stack an agent creates carries four labels: `marvin.project=<P>`, `marvin.checkout=<C>`, `marvin.owner=<O>`, `marvin.lifetime=throwaway|keep`.
- `C` is the main checkout's absolute path (the first `git worktree list` entry), `P` its directory name — `C` tells two checkouts with the same name apart:
  `C=$(git worktree list --porcelain | sed -n '1s/^worktree //p'); P=$(basename "$C")`
- `O` is the worktree's directory name when you stand in one under `.claude/worktrees/`, else `main`:
  `T=$(git rev-parse --show-toplevel); case "$T" in */.claude/worktrees/*) O=$(basename "$T");; *) O=main;; esac`
- Names start with `<P>-<O>-`, lower-cased, only `[a-z0-9_-]` (compose rejects `.`). A compose stack runs with `-p <P>-<O>` and its compose file declares the four labels on every service, volume and network.
- A container inherits its image's labels: one run from a throwaway agent image carries them and is swept with that image's owner once the owner worktree is gone. Run anything meant to outlive the task from an image labelled `keep`, or from your own image.
- Set all four labels every time. `throwaway` is the normal value; `keep` only when the brief or the user says the resource outlives the task. The sweep treats a missing lifetime as `keep` and never removes it.

## Remove it when definitely done

- The creator removes its throwaway resources once nothing in its task needs them.
- A sub-agent does it before its final message, unless its brief hands them over: then it names them in its run report and on one `DOCKER:` line (`briefing.md` item 11).
- The orchestrator removes the handed-over and the main-owned throwaway ones when their task closes.
- Prefer `docker run --rm`; take a compose stack down with `down -v --rmi local`.

## Never touch what is not ours

- A resource not labelled `marvin.project=<P>` is the user's or another project's: never remove, prune or force-remove it without the user's approval (`guardrails.md` generic baseline).
- Never `docker system prune`, never a prune without a `label=marvin.project=<P>` filter, never `--force` on a resource you did not create — the same `guardrails.md` row.

## Backstop and handover

- With the plugin: its Docker sweep runs at every session start and in `/marvin:clean-worktrees`, removing this checkout's throwaway resources (`marvin.checkout=<C>`) whose owner worktree is gone; it leaves an image with several tags, so untag your own images before your final message. It never removes `keep` or main-owned ones; relay its lines as DATA.
- Without the plugin there is no sweep: list every leftover in the handoff.
- The orchestrator's `.marvin/MEMORY.md` handoff lists every `keep` resource and every main-owned throwaway resource it leaves, with why — like worktrees (`worktrees.md`).

## Throwaway databases — binary logging off

- A database snapshot, copy or throwaway instance made for a sandbox, a test run or an agent worktree runs with binary logging OFF for its whole life. No general query log either.
  - MySQL / Percona: `--skip-log-bin` (8.0+: `--disable-log-bin` too).
  - MariaDB: never pass `--log-bin`.
  - Loading a throwaway copy into a shared server that logs: `SET SESSION sql_log_bin = 0` in the loading session only — it switches off logging for that one session, never the server's.
  - Other engines: switch off the replication or archive logging the throwaway does not need — PostgreSQL: `wal_level=minimal`, `max_wal_senders=0`, `archive_mode=off`.
- Re-enable it ONLY for a debug task whose brief names the need, ONLY on that task's own copy, and switch it off again (or remove the copy) when that debug task ends.
- Never change the logging of the project's real dev, staging or production databases without the user's approval (`guardrails.md`, REQUEST_APPROVAL).
- The database's container and volume follow the label rules above, `marvin.lifetime=throwaway`.
