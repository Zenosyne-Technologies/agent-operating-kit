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
telemetry: {{TELEMETRY}}
kit_version: {{KIT_VERSION}}
label_syntax_version: {{LABEL_SYNTAX_VERSION}}
---

# {{PROJECT_NAME}} — project information

Meta overview for foreign agents, agentic OS frameworks, and reporting tools. The YAML frontmatter above is the machine contract and the source of truth for facts; this body is the human overview. Any agent that changes a fact below updates the frontmatter in the same change. Facts only — operating rules live in `CLAUDE.md` and `.marvin/agents/`.

- Repository layout: {{MONOREPO_OR_SINGLE + one-line top-level map}}
- Hierarchy details, virtual milestones, severity/size native mappings: `.marvin/agents/tracker-config.md`
- `screens_guide` points into the UI screen catalog (`.docs/handbooks/developer/screens/index.md` by default) — the declared surface source design/visual review resolves against; `visual_validation` sets when that review runs (`per-task` | `milestone` | `off`)
- Label registry: `.marvin/agents/label-syntax.md` · Filing rules: `.marvin/agents/ticket-filing.md`
- Operating rules: `CLAUDE.md` + the `.marvin/agents/` rules cascade
