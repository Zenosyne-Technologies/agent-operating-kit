---
project: {{PROJECT_NAME}}
description: {{ONE_SENTENCE_DESCRIPTION}}
brief: {{PROJECT_BRIEF}}
owner: {{OWNER_ORG_OR_PERSON}}
pm_tool: {{PM_TOOL}}
tracker_coordinates: {{TRACKER_COORDINATES}}
project_key: {{PROJECT_KEY_OR_NA}}
hierarchy_levels: {{LEVELS}}
intake_guide_url: {{TRACKER_GUIDE_URL}}
stack: {{LANGUAGES_FRAMEWORKS_DATASTORES}}
dev_command: {{DEV_COMMAND_AND_PORTS}}
audience: {{AUDIENCE}}
project_size: {{PROJECT_SIZE}}
app_type: {{APP_TYPE}}
screens_guide: {{SCREENS_GUIDE}}
visual_validation: {{VISUAL_VALIDATION}}
docs_location: {{DOCS_LOCATION}}
issue_log_path: {{DOCS_ISSUE_LOG_PATH}}
telemetry: {{TELEMETRY}}
update_gate: advise
ticket_lint: block
worktree_sweep: on
docker_lint: advise
codex_handover: off
validation_strategy: claude
codex_lanes: []
codex_evidence: claude
# Optional: overrides the window the context ladder measures (.marvin/agents/session-budget.md)
# context_window_ktokens: 1000
# Optional: fleet overrides (.marvin/agents/fleet.md, fleet-child.md)
# fleet_max_children: 3
# fleet_max_compactions: 3
# fleet_restart_max_pct: 33
kit_version: {{KIT_VERSION}}
label_syntax_version: {{LABEL_SYNTAX_VERSION}}
---

# {{PROJECT_NAME}} — project information

Meta overview for foreign agents, agentic OS frameworks, and reporting tools. The YAML frontmatter above is the machine contract and the source of truth for facts; this body is the human overview. Any agent that changes a fact below updates the frontmatter in the same change. Facts only — operating rules live in `.marvin/CLAUDE.marvin.md` (imported by `CLAUDE.md`), `CLAUDE.md`'s project rules and `.marvin/agents/`.

- Repository layout: {{MONOREPO_OR_SINGLE + one-line top-level map}}
- Hierarchy details, virtual milestones, severity/size native mappings: `.marvin/agents/tracker-config.md`
- `screens_guide` points into the UI screen catalog (`.docs/handbooks/developer/screens/index.md` by default) — the declared surface source design/visual review resolves against; `visual_validation` sets when that review runs (`per-task` | `milestone` | `off`)
- `update_gate` sets the user-update format check (`advise` | `block` | `off`, `.marvin/agents/user-updates.md` *Enforcement*); `context_window_ktokens`, `session_soft_ktokens` and `session_hard_ktokens` are optional overrides for `.marvin/agents/session-budget.md`; `fleet_max_children` (1–9), `fleet_max_compactions` (0–9) and `fleet_restart_max_pct` (1–99) are optional overrides for `.marvin/agents/fleet.md` / `fleet-child.md`
- `ticket_lint` sets the tracker-write label check (`block` | `advise` | `off`; absent or empty = `advise`; an unknown value = `block`) — `.marvin/agents/ticket-filing.md`
- `worktree_sweep` sets the automatic worktree sweep (`on` | `check` | `off`; absent or invalid = `check`, which reports what it would remove and removes nothing) — `.marvin/agents/worktrees.md`
- `docker_lint` sets the Docker-label check (`advise` | `off`; absent or invalid = `advise`; `off` silences it) — `.marvin/agents/tidying.md`
- `codex_handover` (`off` | `ask` | `auto`), `validation_strategy` (`claude` | `codex` | `four-eye` | `claude+lanes`), `codex_lanes` (any of `plan`, `review`, `security`, `design`) and `codex_evidence` (`claude` | `codex`) set the Codex handover — `.marvin/agents/codex.md`
- Label registry: `.marvin/agents/label-syntax.md` · Filing rules: `.marvin/agents/ticket-filing.md`
- Operating rules: `.marvin/CLAUDE.marvin.md` (imported by `CLAUDE.md`) + the `.marvin/agents/` rules cascade
