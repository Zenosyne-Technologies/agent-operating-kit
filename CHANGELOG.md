# Changelog

What changed in each Marvin release, newest first, in fixed categories — Action needed is what you must do after upgrading. Ask Marvin "what's new" (`/marvin:whats-new`) for the changes between your project's version and the latest. Full release notes: `docs/release-notes/`.

## [0.42.1] — 2026-10-20

### Added
- `validate-kit` check `frontmatter-quoting` (23rd): the free-text `PROJECT-INFO.md` keys are quoted scalars; `fleet-pairs` also requires the fleet guides' `E-*` tag sets to be equal.
- `/marvin:info` reports a fleet marker (role, age) and flags a stale master marker.
- The master's own handoff has a home: a **Handoff** section in the program plan.

### Changed
- `PROJECT-INFO.md` writes its free-text values (`project`, `description`, `brief`, `owner`, `tracker_coordinates`, `stack`, `dev_command`) as double-quoted YAML; the install and `project-info` skills escape `\` and `"` and repair an unquoted `: ` value.
- Fleet: a child compares resolved paths for `CLAUDE_PROJECT_DIR`, treats a missing master marker as a stopped fleet and, told the fleet is stopping, hands off and ends its turn; `/marvin:fleet stop` lists the running children first, accepts a squash/rebase-merged epic with the architect's confirmation, and the Local-tracker refusal keys on `pm_tool`; resume rewrites a missing child marker.
- `git-strategy.md` scopes its `develop` row and branch death for fleet mode; the fleet guides no longer restate the branch cut or the lock command; a board item without a `FLEET-Q<n>` is never relayed; the MEMORY.md-before-compaction rule carries the fleet-child exception.

### Fixed
- `test-docker-lint.sh` and `test-ticket-lint.sh` no longer fail intermittently: the "never writes" snapshot listed the shared temp directory, which any concurrent `mktemp` changed.
- A fleet child on a symlinked project path is no longer reported blocked.

### Action needed
- Run `/marvin:upgrade-agent-os`, then `/marvin:project-info` if a free-text `PROJECT-INFO.md` value holds `: ` unquoted (`upgrades/v0.42.1.md`).

## [0.42.0] — 2026-10-20

### Added
- `worktree_sweep: on | check | off` in `PROJECT-INFO` (absent = check, report only); the upgrade writes `on` when missing.
- `docker_lint: advise | off` in `PROJECT-INFO` (absent = advise).
- Run-state hooks carry the ledger, build briefs and run reports to the project's `.marvin/runs/<UTC>-<session_id>/<KEY|adhoc>/` from any worktree (SessionStart, PostToolUse, SubagentStop, and a Stop catch-up for Bash-written ledgers); a clash keeps both copies and saves a `.clash-*` sidecar.
- `/marvin:clean-worktrees --mark <path>` and the sweep's report-only `--at-risk` mode.
- `.marvin/agents/session-recovery.md`: the procedure when a session's worktree vanishes mid-task.
- Upgrade step 6b (session readiness) and `scripts/marvin-runs-migrate.sh`: run state moved into the per-session layout, open sessions deferred, at-risk files and both sweeps' `--check` lines reported.
- A Windows CI job (Git Bash), a README Windows section and LF `.gitattributes`; the job is non-blocking until its first green run.

### Changed
- The worktree sweep removes only worktrees Marvin marked as its own (agent worktrees at stop, hand-made ones via `--mark`); session and older worktrees are never touched. G8/G9 keep a worktree whose ignored `.env*` or carried run file is not safely in the main checkout.
- Ledgers chain across sessions (the newest earlier ledger for a key is authoritative), and the milestone prune follows the per-session layout.
- An absent `ticket_lint` now means advise; an unknown explicit value still blocks.
- The update gate checks the structure of callouts and tails, not their English labels, so a project may write them in its own language.
- The precedence clause gates only selective staging and the tagging authority; the branch model, merge style and push cadence are project-refinable.
- Hook stdin paths are decoded and compared in one form (`mh_path`), so Windows `C:\` paths work.
- The task key rule admits single-letter prefixes and bare GitHub issue numbers.
- Codex: the forwarder's prompt file is `<base>.prompt.txt`, and its DATA files are passed as absolute paths under the orchestrator's checkout.

### Action needed
- Pre-set `ticket_lint`, `worktree_sweep` and `docker_lint` before updating the plugin if you want other than the defaults. Restart other open sessions after `/marvin:upgrade-agent-os`, and run the upgrade again once deferred sessions have finished.

## [0.41.0] — 2026-10-20

### Added
- Fleet mode: a master orchestrator runs up to three child orchestrators, one per epic, started by `/marvin:fleet` (set up, resume, stop). The master owns the program plan (epics, dependencies, area leases, merge order, lineage, decision log) and one board for the architect; rules in `.marvin/agents/fleet.md` and `.marvin/agents/fleet-child.md`.
- Three optional `PROJECT-INFO` keys: `fleet_max_children` (3), `fleet_max_compactions` (3), `fleet_restart_max_pct` (33).
- The context hook's fleet modes: a fleet child winds down to a 94 % rest point, lets the host compact it, and asks for a successor after three compactions or a high post-compaction context; the master compacts and never hands off while a child runs.
- `validate-kit.sh` check `fleet-pairs`: every routed fleet event has both its child and its master half.

### Changed
- `git-strategy.md` owns the fleet merge and release authority: in fleet mode only the master merges epic branches into `develop` and cuts releases.
- `session-budget.md`, `worktrees.md` and the kit core carry the fleet clauses (rest rule, locked child worktrees, the cascade line).
- The context hook reads a per-worktree role marker on every call (one `git rev-parse`); sessions outside a fleet see exactly the same messages.

### Security
- In fleet mode the consent questions in `escalation.md`, `escalation-ladder.md`, `guardrails.md` and `codex.md` also accept a relay of the architect's exact words — only after the child verifies it mechanically against the decision log on `develop`; a master message is never an approval, and anything unverified stays data.

### Action needed
- After `/marvin:upgrade-agent-os`, start a new session so the rules load. Fleet mode needs a shared tracker (Linear, Jira or GitHub); the Local tracker is refused.

## [0.40.0] — 2026-10-19

### Added
- Codex (ChatGPT) handover through the `codex` plugin, opt-in per project: a consent switch (`codex_handover: off | ask | auto`), a validation strategy (`claude`, `codex`, `four-eye` or `claude+lanes` with chosen lanes) and an evidence setting (`codex_evidence`), owned by `.marvin/agents/codex.md`.
- Six Codex lane briefs (plan, review, security, design, diagnose, build) in `.marvin/agents/codex/`, and a Codex profile in `model-profile.md` with each lane's model and effort.
- Auto-debug tollgates: a Stuck signal and the max gate on the Claude escalation ladder, and an off-ladder validator failing twice, ask Codex for a read-only diagnosis.
- `/marvin:codex <lane>` (architect-commanded handover; `build` runs the Codex build ladder), `/marvin:codex-astra` (the only path to the frontier Codex model) and `/marvin:codex-setup` (availability check and an install runbook that asks before each step).
- The `marvin:codex` forwarder persona and the guarded runner `scripts/marvin-codex.sh`.

### Changed
- `/marvin:info` shows the Codex status and the four Codex settings.
- Install asks the Codex round in step 6c, and upgrade asks it once in step 4a; with no answer, the defaults change nothing.

### Security
- Codex runs read-only except for an architect-commanded build or a review/security evidence run. Effort is capped at `xhigh`, the frontier model is reachable only via `/marvin:codex-astra`, a security FAIL is never overruled by the orchestrator, and an evidence run that changes tracked code is discarded.

### Action needed
- Answer the upgrade's Codex question (or leave it unanswered to keep Codex off); to use Codex, run `/marvin:codex-setup` and log in yourself (`!codex login`).
- After `/marvin:upgrade-agent-os`, start a new session so the rules and persona load.

## [0.39.0] — 2026-10-15

### Added
- A Docker sweep (session start and `/marvin:clean-worktrees`) removes the throwaway containers, networks, volumes and images of finished agent worktrees, keeping anything that is another checkout's, not `throwaway`, main-owned, still in use, or an image with several tags.
- Four Docker labels (`marvin.project`, `marvin.checkout`, `marvin.owner`, `marvin.lifetime`) that every agent-created resource carries; the new `.marvin/agents/tidying.md` owns them.
- A Docker lint advises on unlabelled resources, compose stacks without a project name, and throwaway MySQL/MariaDB containers with binary logging on; throwaway databases now run with binary logging off.
- A ticket lint checks tracker writes to the project's own tracker for the required labels and registry values (`ticket_lint: block | advise | off`); a `gh` command it cannot parse with certainty only gets advice.
- The intake brief's label audit: it reports non-conforming open items by default and backfills only after you say yes.

### Changed
- Label registry v1.5.0: `size:` on every non-epic item at filing, labels never prose, severity spelled exactly (`sev4-low`).
- When the upgrade's label audit flags items on your tracker, it asks ONE yes/no on backfilling them.

### Fixed
- Tracker items filed with a size or severity only in prose, or with bare `sev4`, are now flagged instead of passing as labelled — denied under `ticket_lint: block` when the write can be read with certainty, advised otherwise.

### Action needed
- Label your Docker resources per `tidying.md`; resources created before this upgrade carry no labels and are never swept, so remove them by hand.
- After `/marvin:upgrade-agent-os`, start a new session so the new hooks and rules load.

## [0.38.0] — 2026-10-15

### Added
- A Marvin output style (`marvin:marvin`); install and upgrade offer it per project, and offer — never silently apply — a per-user disable of plugins that inject a competing style.
- A user-update check on every message to the user: by default a note rides on your next prompt; `update_gate: block` sends a failing message back once and also advises on the next prompt; `off` disables it.
- Sub-agent checks: a final message missing a reserved line (`TRACKER:`, `GUARDRAILS:`, or one its brief reserves) or over 25 lines goes back to the agent once; every persona gets a constant rules block; briefs are linted at dispatch.
- A context ladder: at 70 / 80 / 90 % of the compaction window Marvin plans, winds down, then stops at a clean point and nudges you to `/compact` (or a fresh session at an epic edge).

### Changed
- The SessionStart rules block prints only when the project's output style is not Marvin's own.
- The 400k / 700k session budgets now share the ladder's wording; the stricter of the two speaks.
- Every upgrade re-runs the competing-style scan and offers the Marvin style when the project has none.

### Action needed
- After `/marvin:upgrade-agent-os`, start a new session so the new hooks, the style and the rules load.

## [0.37.0] — 2026-10-14

### Added
- Finished agent worktrees under `.claude/worktrees/` are removed at session start and by `/marvin:clean-worktrees`, and only when seven guards all hold.
- The sweep keeps any worktree that is locked, in use, holding another worktree or repository, active in the last 15 minutes, mid-merge or rebase, dirty, or not yet merged into another branch.
- A local branch is deleted only when origin's copy contains the worktree's commits; otherwise it is kept and reported.
- Every sub-agent that commits work ends with a `WORKTREE:` line saying whether its worktree is safe to delete; the session handoff lists the ones left.

### Changed
- Agents push done work often: each committing sub-agent pushes its own branch, the orchestrator merges it and pushes the parent at once; main and tags still move only at a release.
- `.gitignore` now also ignores `.claude/worktrees/`.

### Action needed
- Update promptly: the personas and the sweep ship with the plugin and act at once, before `/marvin:upgrade-agent-os` installs `worktrees.md`.
- After `/marvin:upgrade-agent-os`, start a new session so the new hook, skill and rules load.

## [0.36.1] — 2026-10-08

### Fixed
- The kit's own CI test suites run fully on Linux again; nothing changes in installed projects.

## [0.36.0] — 2026-10-08

### Added
- A micro-tier developer (`marvin:developer-micro`, Haiku 5.5 at high effort) builds fully-specified small tasks, pieces and corrections.
- A small-tier escalation rung (`marvin:escalation-small-xhigh`, Sonnet 5.5 at xhigh) before a stuck small task reaches the Opus rungs.
- `/marvin:whats-new` explains what changed between your version and the latest, Action needed first.

### Changed
- Marvin targets the Claude 5.5 family: Opus 5.5 orchestrates, Sonnet 5.5 and Haiku 5.5 run their personas at high effort.
- A stuck build climbs effort within its tier, then tiers up toward the orchestrator's model, never above it by default.
- The update notice now carries the safe update procedure: when to start a new session and when to upgrade.
- Session length follows context size: past 400k tokens Marvin suggests a fresh session at a clean break; past 700k it starts no new task first. Nothing blocks.

### Action needed
- After `/marvin:upgrade-agent-os`, start a new session so the refreshed rules, personas and hooks load.

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
