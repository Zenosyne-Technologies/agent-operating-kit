---
doc: Information system guide
type: reference
status: active
summary: How the project's dynamic rule system works — what earns a file under .docs/information/, how files are tagged and indexed, who must read them, and the orchestrator's duty to name them in briefs.
updated: {{INSTALL_DATE}}
---

# The information system (`.docs/information/`)

The orchestrator follows this at all times, not only when writing documentation. This folder is the project's DYNAMIC rule system: the constraints and warnings that were learned here, that no framework manual contains, and that a fresh agent has no way to guess. It is expected to grow.

## What earns a file

A durable constraint, warning, gotcha or hard-won rule a future agent must obey — true beyond the task that discovered it. **One fact per file.** Not a plan (→ `.docs/plans/`), not a research memo (→ `.docs/researches/`), not a changelog entry, not a narrative. If the file needs the word "and" to state what it is about, it is two files.

Three memories overlap here, and this is where the system rots first. Each holds one thing, and a rule restated in two of them has already drifted:

| system | what it holds | who it serves |
|---|---|---|
| `.marvin/MEMORY.md` | Marvin's working memory — session continuity, prunable at will | the orchestrator, privately |
| `.docs/information/` | the durable rule itself, in full, exactly once — indexed and severity-tagged | every dispatched agent |
| `CLAUDE.md` conventions | the always-loaded one-liner that POINTS at a file here, never a copy of it | everyone, on every turn |

## Header additions

On top of the full header of `document-standard.md`, every file here carries:

- `severity:` — one of the four levels defined, with their obligations, in `information-severity.md`. That file owns them; never restate, extend or re-tune a level anywhere else.
- `relevance:` — one or more of the values below, or `all`.

## Relevance values (owned by the core dispatch rules)

`orchestrator` · `developer` · `developer-small` · `ponytail` · `researcher` · `validator-completion` · `validator-security` · `documenter` · `all`

These are EXACTLY the dispatch personas of the model-tier rules in `CLAUDE.md` — one source of truth for the Marvin workflow. They are never redefined, extended or renamed here: a new persona appears in the dispatch rules first, and only then becomes a legal `relevance:` value. `all` means every persona including the orchestrator.

## Index maintenance

`.docs/information/index.md` uses the canonical row of `document-standard.md` with `severity` and `relevance` inserted after `item` — one of the two deviations that standard sanctions, and the shape it defines:

`| item | severity | relevance | what it covers | status | updated |`

Rows sort by severity, `critical` first. Every create, retag or prune updates that table in the same commit. An information file not in the index does not exist — nobody will be briefed with it.

## Read obligation

`relevance:` selects WHO, `severity:` selects WHEN and how binding. The combined matrix lives in `information-severity.md`.

## Briefing duty (the reason any of this works)

When the orchestrator briefs a sub-agent, it NAMES — by path, in the brief — every information file whose `relevance:` matches that agent's persona and whose severity makes it mandatory. The agent is never left to discover them, and never told to "check the information folder". A brief that omits a `critical` file that applies is a defective brief; a validator failing work against a rule that was never named is the orchestrator's miss, not the builder's. This is item 5 of `briefing.md`, which also reserves the FINAL MESSAGE line the agent reports them back on.

## Lifecycle

Review the folder at every milestone close. A rule that has become permanent gets promoted — into a handbook page (`handbooks.md`) or a core convention — and the information file is then marked `superseded_by:` the thing that absorbed it. A rule that stopped being true is pruned, not softened. Severity is re-tuned as evidence arrives; the index row moves with it.
