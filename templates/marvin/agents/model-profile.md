---
doc: Model profile
type: reference
status: active
summary: The one owner of this kit version's target model set — tier to concrete model to default effort — its model-specific rules, the validated-set statement, and how a later version adds a profile.
updated: {{INSTALL_DATE}}
---

# Model profile — the set this version is built for

Every other file names tiers (orchestrator, heavy worker, small worker, micro, frontier) and cites this one; ONLY this file names concrete models. Each kit version is built and validated for ONE declared model set — this is it.

## Target set

| Tier | Model | Default effort | Resolves | Personas |
|---|---|---|---|---|
| orchestrator | Opus 5.5 | `medium`; raise to `high` when the task needs it | `ESCALATION_MODEL` | the main session |
| heavy worker | Opus 5.5 | `medium` (pinned — the ladder's base rung) | `ESCALATION_MODEL` | `marvin:developer`, `marvin:researcher`, the three validators; the ladder's `escalation-high/-xhigh/-max` rungs raise effort on this model |
| small worker | Sonnet 5 | host default (unpinned) | `WORKER_MODEL` | `marvin:developer-small`, `marvin:documenter` |
| micro | Haiku 4.5 | host default (unpinned) | `MICRO_MODEL` | `marvin:ponytail` |
| frontier | Fable 5.1 | inherits the session's (opt-in only) | `FRONTIER_MODEL` | `marvin:escalation-frontier`, reached only through the max gate |

The install skill writes each row's model wherever an installed file (`.marvin/CLAUDE.marvin.md`, this cascade) uses the placeholder its Resolves column names (written here without braces, so no render rewrites this table). Telemetry attributes an event from an agent it does not recognise by model prefix: `claude-opus-*` heavy · `claude-sonnet-*` small · `claude-haiku-*` micro · `claude-fable-*` ladder (`token-economics.md`).

## Model-specific rules

1. **The max gate recommends `max`.** At `escalation-ladder.md`'s max gate, the RECOMMENDED option is `max` effort on the orchestrator's model (`marvin:escalation-max`). The frontier swap is the costlier alternative, offered only because a user may prefer it. Why: Opus 5.5 at `max` effort outperforms Fable 5.1 for significantly less cost (observed 2026-09-24). The gate's mechanics — defaults, recording, what counts as an answer — stay `escalation-ladder.md`'s.

## Validated for this set only

This version is validated ONLY for the set above. Running the orchestrator or any tier on other models is unsupported: the rules may still run, but nothing here was checked against them.

- **Detecting a mismatch**: compare the model your own session context names (the host states it, e.g. "You are powered by the model named …") with the orchestrator row above. If they differ, say so ONCE per session as an issue callout per `user-updates.md` (⚠️, **Needs you?**: no — it never blocks work). If your context names no model, raise nothing and never guess.
- **A customised copy is unsupported.** This file is kit-owned and belongs to the version: an upgrade re-renders it and replaces a customised copy, keeping the old one in the upgrade's backup folder. To run a different set, wait for a version that declares it.

## Adding a profile (future versions)

A later version that supports another set adds it here as a second named profile — its own table, rules and validation date — and the install skill asks which profile to install. Tier names elsewhere never change.
