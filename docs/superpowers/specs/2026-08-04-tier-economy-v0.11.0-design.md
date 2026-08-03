# Size-routed tier economy — kit v0.11.0 design

Date: 2026-08-04 · Status: owner-directed · Target plugin version: 0.11.0

## Context

Anthropic's new pricing/usage system pools Fable and Opus under one "other/all models" counter (Opus no longer has its own). The kit's dispatch philosophy — Opus as a reluctant escalation-only tier, Sonnet as the default for everything — no longer matches the economics. The owner directs: Haiku for trivial (ponytail-sized) work only; Sonnet for small, clearly-defined executions; Opus for medium and big executions and well-defined research; Fable as the recommended orchestrator the architect runs sessions on.

## Design

Tier placeholders keep their names (no ripple through the install skill or the gate's known-list); their SEMANTICS change, and the `size:` label becomes the dispatch key:

- `{{FRONTIER_MODEL}}` — orchestrator; explicitly the architect's recommended session model.
- `{{ESCALATION_MODEL}}` — reframed as the **heavy worker**: `size:m` and larger executions, ALL planning-research passes, cross-cutting debugging; remains the escalation target after two small-worker failures.
- `{{WORKER_MODEL}}` — **small worker**: `size:s` and clearly-defined small executions, validators, tests, QA sweeps, imports, docs.
- `{{MICRO_MODEL}}` — unchanged ponytail (`size:xs` mechanical).

Consequence: `planning-research.md`'s `size:l` research row moves from `{{WORKER_MODEL}}` to `{{ESCALATION_MODEL}}` (research is heavy-worker work).

## File change list

| File | Change |
|---|---|
| `templates/CLAUDE.core.md` | dispatch table reworded to size-routed tiers (same line count, stays ≤45) |
| `templates/docs/agents/planning-research.md` | `size:l` research → `{{ESCALATION_MODEL}}` |
| `skills/install-agent-os/SKILL.md` | tier-mapping step gains today's concrete recommendation (Fable/Opus/Sonnet/Haiku) with a re-check-at-install note |
| `README.md` | core idea 1 + portability tier names reworded |
| `.claude-plugin/plugin.json` | 0.11.0 |

## Non-goals

No placeholder renames; no label/registry changes (sizing semantics untouched — only which tier executes each size); no changes to orchestrator-inline or ponytail eligibility rules.

## Testing

`bash scripts/validate-kit.sh` (CI re-checks on PR); independent review of the five edits against this spec.
