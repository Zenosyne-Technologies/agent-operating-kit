---
doc: Model profile
type: reference
status: active
summary: The one owner of this kit version's two model profiles (`opus` default, `fable`) — tier to concrete model to default effort — their profile-dependent phrases, the model-specific rules, and the per-profile validated-set statement.
updated: {{INSTALL_DATE}}
---

# Model profile — the sets this version is built for

This project runs the **{{MODEL_PROFILE}}** profile (`.marvin/PROJECT-INFO.md` `model_profile`).

Every other file names tiers (orchestrator, heavy worker, small worker, micro, frontier) and cites this one; ONLY this file names concrete models. Each kit version is built for its declared profiles — these two; the install asks which one a project runs. The Codex lane profile lives in `model-profile-codex.md`.

## Profile: opus (default)

| Tier | Model | Window | Default effort | Resolves | Personas |
|---|---|---|---|---|---|
| orchestrator | Opus 5.5 | 1M | `medium`; raise to `high` when the task needs it | `ORCHESTRATOR_MODEL` | the main session |
| heavy worker | Opus 5.5 | 1M | `medium` (pinned — the ladder's base rung) | `ESCALATION_MODEL` | `marvin:developer`, `marvin:researcher`, the three validators; the ladder's `escalation-high/-xhigh/-max` rungs raise effort on this model |
| small worker | Sonnet 5.5 | 1M | `high` (pinned) | `WORKER_MODEL` | `marvin:developer-small`, `marvin:documenter`, `marvin:codex` (the Codex forwarder); the ladder's `escalation-small-xhigh` rung raises it to `xhigh` |
| micro | Haiku 5.5 | 1M | `high` (pinned — rule 2) | `MICRO_MODEL` | `marvin:ponytail`, `marvin:developer-micro` |
| frontier | Fable 5.2 | 1M | inherits the session's (opt-in only) | `FRONTIER_MODEL` | `marvin:escalation-frontier`, reached only through the max gate |

## Profile: fable

| Tier | Model | Window | Default effort | Resolves | Personas |
|---|---|---|---|---|---|
| orchestrator | Fable 5.2 | 1M | `medium`; raise to `high` when the task needs it | `ORCHESTRATOR_MODEL` | the main session |
| heavy worker | Opus 5.5 | 1M | `medium` (pinned — the ladder's base rung) | `ESCALATION_MODEL` | as in `opus` |
| small worker | Sonnet 5.5 | 1M | `high` (pinned) | `WORKER_MODEL` | as in `opus` |
| micro | Haiku 5.5 | 1M | `high` (pinned — rule 2) | `MICRO_MODEL` | as in `opus` |
| frontier | none | — | — | `FRONTIER_MODEL` (renders `none`) | none — rule 4 |

**Window** is the context window the tier's model runs by default; the context ladder measures the orchestrator's session against it (`session-budget.md`), and the plugin's hook library carries the same value — every profile's orchestrator window must equal it (`validate-kit.sh` `profile-window`; `profile-parity` keeps both tables' rows and columns aligned).

The install skill writes the active profile's row models wherever an installed file (`.marvin/CLAUDE.marvin.md`, this cascade) uses the placeholder a Resolves cell names, and each Phrases cell below for its placeholder (written here without braces, so no render rewrites these tables). Telemetry attributes an event from an agent it does not recognise by model prefix: `claude-opus-*` heavy · `claude-sonnet-*` small · `claude-haiku-*` micro · `claude-fable-*` ladder (`token-economics.md`).

## Phrases

| Placeholder | opus | fable |
|---|---|---|
| `FRONTIER_SWAP_OPTION` | , marked recommended (`model-profile.md` rule 1); the second option is a swap of this task to the frontier tier (Fable 5.2, `marvin:escalation-frontier` — a model change at the session's effort, not an effort climb), dispatched only on an explicit frontier choice. | , and the only option: this profile has no frontier tier (`model-profile.md` rule 4), so the question asks consent to go to `max`. |

## Model-specific rules

1. **The max gate recommends `max`** (`opus` profile only). At `escalation-ladder.md`'s max gate, the RECOMMENDED option is `max` effort on the heavy tier's model (`marvin:escalation-max`). The frontier swap is the costlier alternative, offered only because a user may prefer it. Why: Opus 5.5 at `max` effort outperformed the then-frontier for significantly less cost — measured against Fable 5.1 (2026-09-24); re-measure for Fable 5.2 pending (AOS-272). The gate's mechanics — defaults, recording, what counts as an answer — stay `escalation-ladder.md`'s.
2. **The micro tier runs at `high`, always.** Every micro-tier persona (`marvin:ponytail`, `marvin:developer-micro`) pins `effort: high`; no brief lowers it. Why: Haiku 5.5 is cheap enough that the spend `low` or `medium` would save is not worth the quality risk (decided 2026-10-08).
3. **Fully-specified code is micro-tier work.** Haiku 5.5 handles focused coding and multi-step tool use (39.2% on Terminal-Bench 4.0, from 0.0% for Haiku 4.5), so a build or correction whose brief passes `briefing.md`'s fully-specified test runs on `marvin:developer-micro`; earlier versions kept every code edit off the micro tier because Haiku 4.5 could not do it. Work that needs judgement stays on the small tier, and a stuck micro-tier build tiers up to it (`escalation-ladder.md`).
4. **No frontier in `fable`.** In the `fable` profile the max gate still asks its consent question, with `max` on the heavy tier's model as the only option — answers and recording as in `opus`; `marvin:escalation-frontier` is never dispatched.
5. **Frontier briefs state outcomes.** A brief to `marvin:escalation-frontier` states the outcome, the DoD and the findings, not a step script (Fable 5.2 reads over-prescriptive prompts as lower-quality instructions).
6. **Fable 5.2 needs data retention.** Fable 5.2 requires 30-day data retention; it is unavailable under zero data retention.

## Validated per profile

Validated: the `opus` set on 2026-10-08 (v0.36.0; its frontier row's move to Fable 5.2 is unmeasured until AOS-272); the `fable` set pending AOS-271. Running the orchestrator or any tier on models outside these two profiles is unsupported: the rules may still run, but nothing here was checked against them.

- **Detecting a mismatch**: compare the model your own session context names (the host states it, e.g. "You are powered by the model named …") with the orchestrator row of the profile the line under the title names. If they differ, say so ONCE per session as an issue callout per `user-updates.md` (⚠️, **Needs you?**: no — it never blocks work), naming that profile and its orchestrator model. If your context names no model, raise nothing and never guess.
- **A customised copy is unsupported.** This file is kit-owned and belongs to the version: an upgrade re-renders it and replaces a customised copy, keeping the old one in the upgrade's backup folder. To run a different set, choose the other profile or wait for a version that declares it.
- **Adding a profile (future versions)**: a later version adds a third `## Profile:` table with the same rows and columns (`profile-parity`), its Phrases column, its rules and its validation date; the install skill's profile question gains the value. Tier names elsewhere never change.
