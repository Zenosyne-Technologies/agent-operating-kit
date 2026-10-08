# Changelog

What changed in each Marvin release, newest first, in fixed categories — Action needed is what you must do after upgrading. Ask Marvin "what's new" (`/marvin:whats-new`) for the changes between your project's version and the latest. Full release notes: `docs/release-notes/`.

## [0.35.1] — 2026-10-07

### Action needed
- Jira only: if you parented Tasks under Stories, re-parent them to the Epic by hand after the upgrade.

### Changed
- The kit core names the personas of the max and frontier escalation rungs.
- The attribution policy covers every outward-facing text and outranks footers a harness or tool asks for.
- Relevance rules can target the visual validator and every escalation rung; a rung also matches the build persona it replaced.

### Fixed
- Jira milestone conversion no longer fails on a query operator Jira rejects; it reads every page and filters by prefix itself.
- The Jira hierarchy now matches Jira: Story, Task and Bug are peers under the Epic, and Sub-task is the only child level.

## [0.35.0] — 2026-09-27

### Action needed
- If the upgrade stops on a blocked move, clear what its report names (commit or remove the file, even a .DS_Store) and re-run `/marvin:upgrade-agent-os`.

### Changed
- Reports (stats snapshots, digests, milestone close-outs, install and upgrade reports) move from `.docs/reports/` to `.marvin/reports/`, still committed.
- A blocked move stops the upgrade cleanly: it commits only its report naming the blocker and keeps the old version stamp.

### Security
- The move is a guarded, tested script: it refuses untracked files, collisions, symlinks and unsafe repo states before moving anything, and rolls back on failure.

## [0.34.0] — 2026-09-26

### Added
- Every sub-agent reply ends with its TRACKER lines (one per tracker write, or none); the orchestrator logs them and carries open items into rework briefs.
- A close-out check before an issue closes confirms every reported item was filed or dismissed with a reason, and no unassigned tracker write slipped through.

### Changed
- Only the orchestrator or a sub-agent whose brief assigns it one named write may touch the tracker; validators and the brief falsifier never do.
- A finding inside a task's scope is reported and carried to the task, never filed as a new issue; an unrelated defect is filed by the orchestrator, linked.

## [0.33.0] — 2026-09-24

### Action needed
- Restart Claude Code after updating the plugin, then run `/marvin:upgrade-agent-os` and confirm the one-time CLAUDE.md split when it asks.
- Skip the "re-sync CLAUDE.md" step of any older release note, including the hand edit of model names; the upgrade now does it for you.
- Keep `.marvin/` tracked, not gitignored: otherwise the CLAUDE.md import loads nothing in other clones (the upgrade flags it).

### Added
- A session hook warns when a project's install and the plugin differ in version and injects the user-update rules every session, after compaction too.

### Changed
- Kit rules move out of your CLAUDE.md into a kit-owned file it imports, so every upgrade refreshes them with no hand edit.
- The split asks before writing, shows near-copies of kit lines to keep or drop, and backs up your CLAUDE.md; declining writes only the report.
- Your own CLAUDE.md rules override kit rules, except the safety gates: validators, consent questions, destructive-operation guards, secrets and commit hygiene.

## [0.32.0] — 2026-09-24

### Action needed
- Before running the upgrade, re-sync CLAUDE.md's Model-tier dispatch section with the new model profile (skip this when upgrading to v0.33.0 or later).

### Added
- A model profile declares the version's model set and its model-specific rules; other models are unsupported, with one callout when the session's model differs.

### Changed
- This version targets Opus 5.5 as orchestrator (medium effort), Sonnet 5 and Haiku 4.5 as workers, and Fable 5.1 as the opt-in frontier tier.
- The max gate now recommends max effort on the orchestrator's model first and offers the frontier tier second, as the costlier alternative.
- Install reads tier-to-model names from the plugin's profile instead of re-checking at install time.

## [0.31.0] — 2026-09-24

### Action needed
- Re-sync CLAUDE.md's nine changed kit-authored parts with the current template (not needed when upgrading to v0.33.0 or later, which does it for you).

### Added
- Terse, visual user-update formats for every orchestrator message; install and upgrade also write a run report.

### Changed
- size:m splits into a heavy-tier core plus small and micro pieces validated together; a read-only falsifier checks the brief before any size:m+ build.
- Planning research splits into a small-tier survey plus heavy-tier synthesis, for size:l and size:xl only.
- Escalation reads a failed round's pattern (stuck, whack-a-mole, loop, cost blowout, round cap), not a count; a RETHINK step and a per-task ledger are added.
- The orchestrator is on a context diet: capped sub-agent replies, full reports in gitignored run reports, tracker and release steps go to the micro persona.

## [0.30.0] — 2026-09-23

### Action needed
- Re-sync CLAUDE.md's three changed kit-authored parts with the current template (not needed when upgrading to v0.33.0 or later, which does it for you).

### Added
- An escalation ladder: a build task that fails twice climbs effort levels (high, xhigh) on the orchestrator's model; research, docs and validation never climb.

### Changed
- The orchestrator's model is the ceiling: before max effort the orchestrator asks whether to swap this task to the frontier tier, and no answer means max.
- Heavy workers and the validators pin medium effort instead of inheriting the session's.
- Stats snapshots move to schema v4 with cost tiers assigned by role and a ladder bucket; read the first tier trend across the upgrade with care.

## [0.29.0] — 2026-09-23

### Added
- `/marvin:play visual-sweep` fans out visual validators across every UI surface (at most 4 per round) and aggregates one whole-project design report.
- Visual capture can fall back to Playwright when a project already scripts E2E, which also surfaces console and network errors a screenshot misses.

### Changed
- The visual-validation capture procedure is executable: it names the concrete browser-pane tools and ties each degradation exit to an observable browser outcome.

## [0.28.0] — 2026-09-22

### Action needed
- Merge the conditional visual-validation lifecycle step into CLAUDE.md, keeping your own rules (not needed when upgrading to v0.33.0 or later).

### Added
- An advisory visual and design validation stage for UI tasks, with its own validator persona and rules guide; it gates only at the UI release gate (sev1, sev2).
- A screen catalog that surfaces are resolved against, plus two new PROJECT-INFO keys, screens_guide and visual_validation (per-task, milestone or off).
- Builders declare the screens they touched in a SURFACES line of their final message.
- A new finding:visual label (registry v1.4.0), an orthogonal axis for slicing design findings.

## [0.27.0] — 2026-09-22

### Added
- The install's attribution question gains a third option, "Emprove Marvin (Claude)", a branded commit and PR trailer.

### Changed
- The greenfield install interview asks what you are building first, so the stack suggestion reasons from that brief. New installs only.

## [0.26.1] — 2026-09-03

### Changed
- The plugin manifest now declares its licence, PolyForm Noncommercial 1.0.0, matching the LICENSE file; no behaviour or installed-file changes.

## [0.26.0] — 2026-09-02

### Action needed
- If you customised the installed licence notice, reconcile it from the upgrade's backup after the refresh.

### Added
- `/marvin:play` runs five bounded, self-terminating scenarios (research-solo, research-deep, quick-fix, taskforce, bug-hunt), each with a goal, limits and exits.
- bug-hunt only finds and reports: it never attacks, exploits, touches a live system or makes a state-changing call to prove a finding.

### Changed
- The licence holder becomes Emprove Services Kft. (maintained by Zenosyne Kft.); the installed notice is re-rendered, with the PolyForm body unchanged.

### Security
- A new static check fails the build if any tracked file embeds a contributor's local home path, and the one already in the history was scrubbed.

## [0.24.0] — 2026-09-02

### Action needed
- Optional: drop the `.marvin/` pointers from your own `.docs/` index files by hand, so `.docs/` can be shared without exposing the agent machinery.

### Added
- Greenfield installs interview you (audience, size, app type, stack) and can scaffold the chosen stack as a tracked Milestone 0; existing projects are unchanged.

### Changed
- The `.docs/` estate is self-contained: Marvin guides may point into it, but nothing in it references Marvin, and a check fails the build if that returns.
- Marvin's persona leans into work-directed skepticism: unverified work is assumed broken until the evidence says otherwise. New installs get it.

## [0.23.0] — 2026-09-02

### Action needed
- Add the new guardrails row to your CLAUDE.md rules cascade, verbatim from the template (not needed when upgrading to v0.33.0 or later).

### Added
- A guardrails guide: a DO NOT framework with four dispositions, an escalation chain and per-persona rows; briefs carry a GUARDRAILS line in the final message.
- Every install carries its own copy of the kit's licence notice, PolyForm Noncommercial 1.0.0.

### Changed
- Builders document the API surface: every new or modified public class or method gets a docblock in the language's own standard (PHPDoc, TSDoc, Javadoc…).

## [0.22.0] — 2026-08-10

### Action needed
- Cut new work from develop on gitflow branches; finish and merge any in-flight `milestone/*` branch as it is.
- Merge the git cascade row, the Git, branches, releases standing rule and a lifecycle sentence into CLAUDE.md (not needed when upgrading to v0.33.0 or later).
- Make two small prose edits by hand in your `.docs/index.md` (the release-notes folder row is merged for you), so writers are routed to release notes.

### Added
- A release-notes folder in the docs estate: one document per released version, with a mandatory scope header listing that version's issue keys.

### Changed
- Gitflow replaces the milestone branch: one guide owns the branch model, orchestrator-only annotated tags and semver classified by consumer impact.

### Fixed
- Stats snapshots (schema 3) no longer render an unexplained zero as $0.00: a missing telemetry DB, an unresolved scope and no rows are now distinct states.

## [≤0.21.x]

- Releases before v0.22.0 carry no brief here — see the git history and `upgrades/`.
