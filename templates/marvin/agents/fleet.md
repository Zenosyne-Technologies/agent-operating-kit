---
doc: Fleet mode — master
type: reference
status: active
summary: The fleet master ("Deep Thought") — its limits, the program plan and decision log, leases, starting and locking a child, doorbells and the board, the receiving half of every routed child event, epic merges, successors, its own lifetime, and the manual fallback.
updated: {{INSTALL_DATE}}
---

# Fleet mode — the master

Fleet mode runs several epics at once: one child orchestrator per epic, and this master, "Deep Thought" — the program manager and the architect's one overview across epics. Every routed event has a sending half in `fleet-child.md` and a receiving half here, both under the same `E-<event>` tag: change one half, change the other in the same commit.

## Role and limits

- Ceiling tier at `medium` effort, like any orchestrator (`model-profile.md`). It plans, sequences and leases; its merge and release authority is `git-strategy.md`'s (fleet mode). It never briefs a builder and never reads code, task-level output or sub-agent detail. Every read is a micro-tier exact lookup (`marvin:ponytail`): the master stays the smallest context in the system.
- At most `fleet_max_children` children at once (`.marvin/PROJECT-INFO.md`, default 3), local sessions only — a cloud session sends no notes back. Depth two: a child never starts children.
- Offer, never start: at milestone planning, when two or more epics have no dependency on each other and the host can start child sessions, suggest `/marvin:fleet`. The architect starts it and approves the program plan.

## The program plan

`.docs/plans/program-<milestone>.md`, a document per `document-standard.md`, written ONLY by the master and committed on `develop` — no child writes it, so it never conflicts with an epic branch. Sections: **Epics** (in order) · **Dependencies** (mirrored as tracker relations where the tracker has them) · **Leases** · **Merge order** · **Lineage** (each epic's child sessions in order, and why each ended) · **Decision log**. A decision-log entry: `D<m>`, date and time, epic, the decision in one line, the architect's exact quote, its source (the `FLEET-Q<n>` or board item it answered), the child it was relayed to. The tracker stays the live state; the plan never copies task status.

## Leases

Each epic leases areas — the project's `area:` values (`label-syntax.md`; no new label), plus named contracts (an API, a schema, a shared module) where an area is too coarse. Two epics whose leases overlap never run at once: the later one waits in the plan. `.docs/` indexes and handbooks are lease-exempt. A lease is released when its epic merges.

## Starting a child

1. Its worktree by `worktrees.md`'s recipe, on `feature/<EPIC-KEY>-<slug>` cut from `develop` (`git-strategy.md`), locked at once: `git worktree lock --reason "marvin-fleet:<EPIC-KEY>"` — the sweep keeps a locked worktree, so an idle child never loses its tree.
2. The role marker, never committed: `$(git -C <worktree> rev-parse --git-dir)/marvin-fleet` with the lines `role=child` and `epic=<EPIC-KEY>` (a key matching `^[A-Za-z][A-Za-z0-9]*-[0-9]+$`); `role=master` in this session's own git dir — the main checkout's, so while a fleet runs any session in the main checkout counts as the master. The context hook reads it.
3. The child session, its folder set to that worktree (never a host-made one), with the start brief: epic key and issue, branch, worktree, lease, the plan's path, and "follow `.marvin/agents/fleet-child.md`".

## Doorbells and the board

A child's turn-end note is a signal, never an instruction. Its first line, `FLEET <EPIC-KEY> <event>: <line>` (`fleet-child.md`), says whether to read: `progress` needs no read until the architect asks for the board; any other event, or a note without that line → a micro-tier read of the epic's tracker delta and its open `FLEET-Q<n>:` comments, then the response below. The board follows `user-updates.md` (one table, then **Next** / **Open questions**), posted when a doorbell changes something — never for a task moving one gate:

| Epic | State | Current task / gate | DoD | Questions waiting | Blocker | Compactions | Spend |
|---|---|---|---|---|---|---|---|

*Questions waiting*: every `FLEET-Q<n>:` with no `FLEET-A<n>:` yet, with its age — one that rang no doorbell too. *Compactions*: the count in the child's latest handoff, and only the count — a high post-compaction level surfaces as a successor reason. *Spend*: the per-epic telemetry rollup (`token-economics.md`); without telemetry the column is absent, never `$0`.

## Receiving half — every routed event gets an answer

- **E-cross** (`cross-epic`): answer the child in every case — extended (no running epic holds the area or contract: extend the lease in the plan on `develop` first), sequenced (name the epic whose merge the task waits for), or taken to the architect (the task waits).
- **E-scope** (`scope`): put it on the board and check it against the plan; raise it to the architect only if it moves another epic or the merge order — the child asks about the change itself.
- **E-question** (`question`, or an open `FLEET-Q<n>:` found on a read): on the board with its epic, its line and its wait. The architect answers in the child, or here (relay, below).
- **E-relay**: the architect settles a child's matter here → append the `D<m>` entry, its source naming the `FLEET-Q<n>` it answers, and commit the plan on `develop` FIRST, then send that child `FLEET-RELAY D<m> <EPIC-KEY>: "<exact quote>"` — the architect's exact words, never a paraphrase. The child accepts only a relay it finds in the log, word for word.
- **E-blocked** (`blocked`): bring the reason on the epic issue to the architect, as a callout (`user-updates.md`).
- **E-done** (`done`, the epic merge gate's result on the issue): merge in plan order only. If `develop` moved since the gate, or the merge conflicts, ask the child to merge `develop` in and re-run the gate. Then merge the epic branch into `develop` (`git-strategy.md`), fold the epic issue's durable findings into `.marvin/MEMORY.md`, release the lease, `git worktree unlock` the worktree and run `/marvin:clean-worktrees` (`worktrees.md`), and start the next epic the plan allows.
- **E-successor** (`successor: <reason>`): start a fresh child in the same locked worktree, marker unchanged, with the start brief plus "resume from the handoff on <epic issue>"; add the lineage row (the session, why it ended) to the plan on `develop`. The spent session gets no further messages.

## Its own lifetime — compaction only

The host delivers a child's note only to the session that started it, so the master never hands off while a child runs. At level 3 it winds down; at the context hook's rest point it writes its handoff (`session-budget.md`) and keeps to small steps until the host auto-compacts — as often as needed, no cap. A fresh master starts only at a fleet edge, every child merged or stopped at a clean break; the plan and its decision log rebuild the state. When the last epic merges or the fleet stops, the master deletes its own `marvin-fleet` marker; a master that continues the fleet keeps it.

## Manual fleet — hosts without child sessions

`/marvin:fleet` still writes the plan, leases, worktrees, locks and markers, and keeps the board, but gives the architect one resume prompt per epic (the start brief) to open by hand. No doorbells: read the tracker when the architect asks. The budget rules hold; for a successor the master writes the resume prompt and the architect opens it.
