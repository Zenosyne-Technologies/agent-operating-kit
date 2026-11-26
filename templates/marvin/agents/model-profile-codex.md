---
doc: Codex model profile
type: reference
status: active
summary: The Codex lanes' tier to concrete model to default effort table, its Astra and effort-ceiling rules, and the validated-set statement — read by scripts/marvin-codex.sh.
updated: {{INSTALL_DATE}}
---

# Codex model profile

## Codex profile

Templates name only the tiers `codex fast`, `codex workhorse` and `codex frontier` and cite this table; `scripts/marvin-codex.sh` reads it for each lane's default model and effort.

| Lane | Tier | Model | Effort | Why |
|---|---|---|---|---|
| build-micro | codex fast | gpt-5.6-luna | high | mechanical, fully specified work (`xs`); Luna's top effort still costs pennies |
| build | codex workhorse | gpt-5.6-sol | medium | the Codex default; about 73% DeepSWE at `medium` |
| plan | codex workhorse | gpt-5.6-sol | high | falsifying a plan needs depth |
| review | codex workhorse | gpt-5.6-sol | high | adversarial falsification; `high` is the measured gain over `medium` |
| security | codex workhorse | gpt-5.6-sol | high | same as review |
| design | codex workhorse | gpt-5.6-sol | medium | checklist judgement, not deep search |
| diagnose | codex workhorse | gpt-5.6-sol | xhigh | recommended for tangled debugging; the companion cap |
| astra | codex frontier | gpt-6-astra | high | about 5x Sol per token; architect command only, effort the architect's pick up to `xhigh` |

1. **Astra is never routed by a rule.** No ladder, tollgate or strategy reaches `astra`; only the architect's `/marvin:codex-astra` does, passing `--astra`.
2. **The Codex effort ceiling is `xhigh`.** The models accept `max`, but the Codex companion rejects anything above `xhigh`, so no row or flag goes higher.
3. **Validated set.** The Codex models above were checked live on 2026-10-16 against a ChatGPT login; the `astra` row is unverified.
