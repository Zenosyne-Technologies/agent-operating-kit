---
name: codex-astra
description: Run one Codex lane on the frontier Codex tier (Astra) — the same lanes and targets as /marvin:codex, with an optional effort up to xhigh. The ONLY path that reaches the frontier tier; nothing routes to it automatically. Use when the user explicitly asks for Astra or the frontier Codex model, or picks it at the Codex build ladder's user gate.
argument-hint: '<plan|review|security|design|diagnose|build> [issue|--base <ref>] [--effort <none|minimal|low|medium|high|xhigh>]'
---

# Run a Codex lane on the frontier tier

Astra (`codex frontier`, `.marvin/agents/model-profile.md` *Codex profile*) is never routed automatically — no rule, ladder, tollgate or strategy reaches it (`.marvin/agents/codex.md` *Codex builds*). This skill is the only path that passes `astra: yes`, and so the only one whose forwarder run carries `--astra`.

1. **Effort, before anything is dispatched.** `--effort` is optional. `max` or `ultra` → refuse in one line ("Codex effort stops at xhigh") and stop. Any other value outside `none`, `minimal`, `low`, `medium`, `high`, `xhigh` → refuse in one line listing them and stop. Absent → the astra row's effort.
2. **Everything else is `/marvin:codex`** (`${CLAUDE_PLUGIN_ROOT}/skills/codex/SKILL.md`): parse, run-report path, the reader gathering the DATA, the dispatch and the reporting, word for word — with `astra: yes` and, when given, `effort: <E>` added to the forwarder's brief.
3. **`build`** — `/marvin:codex` step 5 for a single rung: no climb, no user gate. The full build brief, its own worktree, the merge per `worktrees.md`, the Claude validators and your ledger row all stand as written there. After a FAIL, report it; the next step is the architect's.
