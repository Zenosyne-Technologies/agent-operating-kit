---
project: {{PROJECT_NAME}}
description: {{ONE_SENTENCE_DESCRIPTION}}
owner: {{OWNER_ORG_OR_PERSON}}
pm_tool: {{PM_TOOL}}
tracker_coordinates: {{TRACKER_COORDINATES}}
project_key: {{PROJECT_KEY_OR_NA}}
hierarchy_levels: {{LEVELS}}
intake_guide_url: {{TRACKER_GUIDE_URL}}
stack: {{LANGUAGES_FRAMEWORKS_DATASTORES}}
dev_command: {{DEV_COMMAND_AND_PORTS}}
docs_location: {{DOCS_LOCATION}}
kit_version: {{KIT_VERSION}}
label_syntax_version: {{LABEL_SYNTAX_VERSION}}
---

# {{PROJECT_NAME}} — project information

Meta overview for foreign agents, agentic OS frameworks, and reporting tools. The YAML frontmatter above is the machine contract and the source of truth for facts; this body is the human overview. Any agent that changes a fact below updates the frontmatter in the same change. Facts only — operating rules live in `CLAUDE.md` and `.docs/agents/`.

- Repository layout: {{MONOREPO_OR_SINGLE + one-line top-level map}}
- Hierarchy details, virtual milestones, severity/size native mappings: `.docs/agents/tracker-config.md`
- Label registry: `.docs/agents/label-syntax.md` · Filing rules: `.docs/agents/ticket-filing.md`
- Operating rules: `CLAUDE.md` + the `.docs/agents/` rules cascade
