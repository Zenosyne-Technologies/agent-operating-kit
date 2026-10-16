---
name: codex
description: Run one OpenAI Codex lane on demand — plan, review, security, design, diagnose or build — for a tracker issue or a diff against a base ref, through the marvin:codex forwarder; build runs the Codex build ladder with Claude validators. Use when the user asks for a Codex (second-vendor) review, plan check, security pass, design critique or diagnosis, or for Codex to build an issue.
argument-hint: '<plan|review|security|design|diagnose|build> [issue|--base <ref>]'
---

# Run a Codex lane for the architect

The rules are `.marvin/agents/codex.md`; the forwarder is `marvin:codex` (`${CLAUDE_PLUGIN_ROOT}/agents/codex.md`). The command is the architect's consent: `codex_handover` never gates it. Never call the Codex companion or the `codex` CLI yourself, and never pass `astra: yes` — the frontier tier is `/marvin:codex-astra` only; an `effort` goes in the brief only on a `build` rung (step 5).

1. **Parse.** Lane: exactly one of `plan`, `review`, `security`, `design`, `diagnose`, `build`; anything else → one line listing the six and stop. Target: an issue key, or `--base <ref>` (not for `build`). A ref must not start with `-` and must pass `git rev-parse --verify --quiet '<ref>^{commit}'`; otherwise say so and stop. No target → ask for one.
2. **Run-report path** per `.marvin/agents/briefing.md` item 11: `.marvin/runs/<KEY|adhoc>/<UTC timestamp>-codex[-<rung>].md` (`adhoc` for a `--base` target), absolute under this checkout when the forwarder runs in a worktree. `<base>` is that path without `.md`.
3. **Gather the DATA through a reader — never read bulk yourself.** Dispatch `marvin:ponytail` (exact-lookup reads; `marvin:developer-small` when picking what to read needs judgement) to write four files under item 11's run-report rules, and to return only their paths and line counts:
   - `<base>.brief.txt`:
     - `build`, every rung and correction included: the build brief YOU author per `briefing.md` — files to touch, environment preamble, checks to run, security surface, which `codex/build.md` reads — handed to the reader verbatim, never an issue extract.
     - `diagnose`: the current build brief, plus the original one when it changed.
     - `review`, `security`, `design` on an issue: its title, scope and description plus the files the task scopes (`design`: the surfaces and breakpoints); a `--base` target: the commit subjects `<ref>..HEAD` and the changed paths.
     - `plan`: line 1 is `mode: falsifier|plan-validation|solution` — the mode the user named, else `falsifier` — then the build brief or the plan under review.
   - `<base>.dod.txt` — the tracker DoD lines verbatim; you then mark each line a kit rule schedules for a later step with ` (scheduled: <step>)`.
   - `<base>.findings.txt` — from `.marvin/runs/<KEY>/ledger.md`, one `F<id> open|closed — <line>` per finding (`diagnose`: the ledger lines as given); none → `none`.
   - `<base>.evidence.txt`:
     - a `--base` target: `git diff '<ref>'...HEAD`.
     - `review`, `security` on an issue: the latest round's gate output and run-report paths; with `codex_evidence: claude`, add a `marvin:ponytail` pre-flight gate run's output (`codex.md` *Settings*).
     - `plan`: `falsifier` → `none`; `plan-validation`/`solution` → the `marvin:developer-small` survey report (`planning-research.md`), one `<file:line or source> — <fact>` per line — none for this task → dispatch that survey first.
     - `diagnose`: the failing round's reports — reviewer findings, gate and test output.
     - `design`: Codex reads a PNG only inside its working directory (`codex/design.md`). The reader copies each screenshot the Claude side captured (`visual-validation.md`) into `<base>.shots/` — first checking with `test -L` that no part of it is a symlink, that it lies under `git rev-parse --show-toplevel` (the forwarder's `--cwd`) and that `git check-ignore -q` passes — and lists those paths, one per surface and breakpoint, with the console notes. The copies stay under `.marvin/runs/` for the run-report prune (`briefing.md` item 11) — never delete them yourself.
4. **Dispatch `marvin:codex`** with a brief per `briefing.md`: `lane`, `issue` (the key, or `adhoc --base <ref>`), the run-report path, `architect: yes`, and the four DATA files by path — the forwarder copies each into its block. Add `write-evidence: yes` only when PROJECT-INFO's `codex_evidence` is `codex` and the lane is `review` or `security`; that run, like every build, is dispatched with `isolation: worktree`. `design` always runs read-only in this checkout, over Claude's screenshots (`codex.md` *Strategies and lanes*).
5. **`build`** runs the ladder exactly as `codex.md` *Codex builds* says — never restated here: base rung from the issue's size, one forwarder round per rung (`lane: build-micro`, or `lane: build` with `effort: medium|high|xhigh`), each in its own worktree with the full build brief (step 3; branch, pre-flight gates, ownership); merge it per `worktrees.md`, then the Claude validators (`validation-agent.md`) validate the round; the round signals (`escalation.md`) decide climb, RETHINK or done; you append the ledger row; past `xhigh`, the user gate with the host's question tool.
6. **Report the forwarder's lines — never re-judge them.** Relay the verdict line, finding lines and gate lines as given, and cite the run report. Then:
   - `CODEX: PASS|FAIL`, `ADVISORY`, `diagnosis`, `built`, `no change` — as given.
   - `plan` in `plan-validation` or `solution` mode with a PASS or FAIL: the memo lands where the researcher's would (`codex.md` *Strategies and lanes*) — dispatch `marvin:ponytail` to post the run report's `## Memo` as the issue comment, or, with no issue (`--base`), to write and index `.docs/researches/<slug>-{validation|solution}.md`, exactly as `planning-research.md` says for the researcher.
   - `CODEX: refused <reason>` → one line with what would unblock it (`astra needs --astra` → `/marvin:codex-astra`; `effort above xhigh`/`unknown effort` → an effort up to `xhigh`; `not-isolated` → re-dispatch with `isolation: worktree`). Never route a refusal to Claude silently: the architect asked for Codex.
   - `CODEX: unavailable pending <id> <worktree>`, or `CODEX: unavailable timeout (job may be queued; check status)` on `build` or a `write-evidence` run → the Codex job may still be writing: keep that worktree, hold the task's files, raise the ⚠️ callout and release only as `codex.md` *Verdicts, availability and fallback* says (`result <id>` from that worktree, or the user's answer); no climb, no merge, no `/marvin:codex-setup` offer.
   - `CODEX: unavailable wrote-tracked-files` → the evidence run changed tracked code: name it, never merge that worktree, and offer a re-run with Claude-gathered evidence (step 3's gate run, no `write-evidence`) — not `/marvin:codex-setup`.
   - Any other `CODEX: unavailable <reason>` → the status line, and offer `/marvin:codex-setup` (`codex.md` *Verdicts, availability and fallback*).
   - `CODEX: evidence-fallback <capability>` → name the missing capability and offer a re-run with Claude-gathered evidence (step 3's gate run, no `write-evidence`).
