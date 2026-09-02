---
description: Run a bounded Marvin play scenario — research, fixes, taskforce, or bug-hunt
argument-hint: [research-solo|research-deep|quick-fix|taskforce|bug-hunt]
---

Run a Marvin **play scenario** — a bounded, orchestrated multi-round run. The scenario to run is
the command argument: `$ARGUMENTS`.

1. **Read the contract first.** Read `${CLAUDE_PLUGIN_ROOT}/scenarios/contract.md` and follow it
   for the ENTIRE run — the bounded-execution contract (GOAL / LIMITS / POSITIVE exit / NEGATIVE
   exit declared before any dispatch), the periodic-report schema evaluated between rounds, the
   mode model, the find-never-attack safety rule, and the dispatch/round-gating loop. It is
   authoritative; nothing below overrides it.

2. **Resolve the scenario from the argument.** The requested scenario is `$ARGUMENTS` (trim
   whitespace). List the scenario files in `${CLAUDE_PLUGIN_ROOT}/scenarios/` — every `*.md`
   there EXCEPT `contract.md`.
   - If `$ARGUMENTS` is empty, or names no file that exists in that directory, **show the menu
     and STOP** — do not guess a scenario. The menu is one line per available scenario file:
     its name (filename without `.md`) followed by that file's `summary:` line, read from the
     file. If the only file present is `contract.md` (no scenario files exist yet — F2/F3 add
     them), print exactly `no scenarios available yet` instead of a menu, and stop. Never error.
   - Otherwise continue.

3. **Run the matched scenario.** Read `${CLAUDE_PLUGIN_ROOT}/scenarios/<scenario>.md` for that
   scenario's specific shape (its GOAL / LIMITS / exit defaults and which `marvin:*` persona(s)
   it dispatches per round) and run it per the contract's gated-round loop.

4. **Determine execution mode per the contract's mode model.** Sub-agent mode by DEFAULT.
   Agent-teams mode activates ONLY if the project's execution-mode setting (Milestone E) says so;
   absent today → sub-agent. Do not infer agent-teams mode.
