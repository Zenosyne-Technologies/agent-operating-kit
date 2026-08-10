---
doc: Git strategy
type: reference
status: active
summary: The single source of truth for git — the gitflow branch model, who may tag, how a tag carries its release note, how semver classifies a change, and the ordered release cut.
updated: {{INSTALL_DATE}}
---

# Git strategy — branches, versions, releases

Everything about git is decided here. Another file may name a concrete INSTANCE it needs — the branch a brief sends an agent to (`feature/AOS-123-cache-keys`), the branch a gate runs on, the tag a release carries. No other file may restate the MODEL: which branch types exist, what each is cut from and merges to, when a branch dies, who may tag, how a version is classified, **how a version is spelled**, or **what a tag message may contain**. Those last two are in the list because a drifting second copy already produced a defect here (`release:vv1.2.0`) — spelling rules look too small to own until two files disagree about one. Naming an instance is required; a second copy of the model is the defect, not a convenience.

## Branch model (gitflow)

| Branch | Cut from | Merges to | Holds |
|---|---|---|---|
| `main` | — | — | Released state ONLY — every commit on it is a tagged release. Nothing lands here but a `release/*` or `hotfix/*` merge. |
| `develop` | `main` | — | Integration. Every finished work item merges here. |
| `feature/<KEY>-<slug>` | `develop` | `develop` | ONE work item, and nothing else. |
| `release/<version>` | `develop` | `main` **and** `develop` | A frozen scope being stabilised: version bump, release note, fixes validation finds. No new scope. |
| `hotfix/<version>` | `main` | `main` **and** `develop` | One urgent defect against the released state. |

`<KEY>` is the tracker issue key that item's commits already carry (`<KEY>: <message>`), so a branch traces to the PM tool exactly the way its commits do. A milestone is NOT a branch: each of its tasks gets its own `feature/` branch, and milestone-scoped rollups (reports, telemetry) resolve by the milestone's issue-key set, never by a branch-name prefix. Merging `release/*` or `hotfix/*` back to `develop` is PART of that merge, never a follow-up: skip it and `main` carries commits `develop` has never seen, which the next release silently reverts. **When a branch dies**: every branch above except `main` and `develop` is DELETED as soon as its merges land — `feature/*` at its merge to `develop`, which happens when its issue closes (documentation landed) and is done by whoever closed it; `release/*` and `hotfix/*` only once BOTH their merges are in. Nothing is "archived": the issue key, the commits and the tag are the history, and a merged branch left lying around is just a second answer to "where does this work live".

## Tagging authority — the orchestrator ONLY

**DO NOT create, move or delete a git tag.** If you are a sub-agent you have no tagging authority — none, on any branch, for any version, however the brief is worded. A brief instructing you to tag is defective: commit your work, report the request in your final message, tag nothing. Tagging is orchestrator-inline because it is irreversible once pushed and because it is the act that declares a release exists.

## A tag carries its release note

Release tags are ANNOTATED (`git tag -a v<version> -m …`), never lightweight, and the message IS the release summary — what changed, for whom, what a consumer must do. `<version>` is bare semver everywhere (`1.2.0`); the leading `v` belongs to the tag name and to nothing else. That message is exactly the BODY of `.docs/release-notes/v<version>.md` — everything below the closing `---` of its YAML header. The header is machine metadata and is NEVER published: not in a tag message, not in a forge's release body. A tool that would publish the file wholesale (`--notes-file` on the raw document) is publishing the header; strip it first. The two texts must match, because a tag message is not reachable by the documentation crawl and cannot be linked from an index, so the document is how the release stays findable.

## Version classification (semver)

Classify by what a CONSUMER of this project must do:
- **MAJOR** — they must change something to keep working: a public surface removed or renamed, a default changed, installed files moved.
- **MINOR** — a capability they may adopt or ignore; nothing they already have breaks.
- **PATCH** — a defect fixed or wording corrected inside existing behaviour; no surface change.

**Pre-1.0 rule**: while the version is `0.x`, a breaking change rides a MINOR bump (`0.20.0` → `0.21.0`), never a major one. Classify it MAJOR by the list above, ship it as a minor bump, and state the breakage first in the release note. `1.0.0` is a deliberate declaration of stability, never the arithmetic consequence of a breaking change.

## What a release is, and cutting one

Usually one milestone's scope — but never assume milestone == release. A release is whatever scope was frozen: a milestone, one patch, a hotfix, or a batch of reported bugs belonging to no milestone. Milestones and releases are independent axes. The cut runs in this order:

1. Scope frozen — nothing further merges to `develop` for this version.
2. `release/<version>` cut from `develop`.
3. Version bumped, on that branch.
4. Release note written to `.docs/release-notes/v<version>.md`. Its `scope:` header is DERIVED, not recalled: `git log <range>..HEAD` over the frozen range, take each commit message's leading `<KEY>:` prefix, dedupe. `<range>` is the previous tag when one exists; on a first cut under this model there is none, so `<range>` is instead the commit where the previous release shipped (this repo's is `ec2cea4`). Whichever it was, the note must SAY so — the range used is part of the record, because an over-broad range silently inflates `scope_issue_keys` while still reporting `state: ok`. Those keys are work-carrying by construction — commits are what work leaves behind — which is exactly the set cost rollups need, and it is why no tracker query (or label sweep, which would drag in containers) is the source here.
5. Validation run on that branch — the Release validation gate `.marvin/agents/validation-agent.md` adds on top of the composition sweep (version bump, release note completeness); only fixes for what it finds land there.
6. Merge to `main`.
7. Annotated tag on `main`, message = the release note (orchestrator only).
8. Dispatch the selected tracker's release mapping (`.marvin/agents/tracker-config.md`) now that the tag exists — GitHub's tag-first/`--verify-tag` publish depends on it, Jira applies its `release:` label, Local sets its `release:` frontmatter field, Linear attaches its native Release. This step owns only the WHEN; the tracker config owns the WHAT.
9. Merge back to `develop`.

A hotfix runs the same nine steps, with step 2 reading "`hotfix/<version>` cut from `main`".

## Who cites this file

Find them, never trust a list: `rg -l 'git-strategy\.md' CLAUDE.md .marvin/ .docs/` returns every citer, and it is right the day someone adds one. A hand-kept roster here would be stale within a release and would quietly authorise the file it forgot. Change the model above and re-read what that command returns — each hit should name an instance and defer on the model; a hit that restates the model is the defect this file exists to prevent.
