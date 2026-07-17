# Agent brief: create the Linear intake structure

Fill the placeholders, then hand this brief verbatim to an agent (works at the default-worker tier; micro-model if your Linear MCP tools are reliable).

---

Create the issue-intake structure for {{PROJECT_NAME}} in Linear. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: list_issue_labels, create_issue_label, save_document, save_issue, list_issue_statuses (Linear MCP).

TARGET: team "{{TEAM_NAME}}" (key {{TEAM_KEY}}), project "{{PROJECT_NAME}}".

1. LABELS (team-scoped; list existing first, skip any that already exist; red-ish for sev1 descending to grey for sev4):
   type:bug, type:change-request, type:investigation, type:tech-debt,
   area:{{AREA_1}}, area:{{AREA_2}}, area:{{AREA_3}}, area:infra, area:docs,
   sev1-critical, sev2-high, sev3-medium, sev4-low,
   found-by:agent-qa, found-by:owner
2. DOCUMENT: create a Linear document "Issue Intake & Triage Guide" in the project. Content (markdown): the label taxonomy with one-line meaning each; severity definitions (sev1 data-loss/security/app-unusable; sev2 feature broken no workaround; sev3 workaround exists or cosmetic-functional; sev4 polish); filing rules — every issue gets exactly one type:, one area:, one sev label + provenance label; team + project + status Backlog; ALWAYS search for duplicates before filing; description template: "## Repro / ## Expected / ## Actual / ## Evidence (console/network/logs) / ## Suspected cause / ## Refs"; QA sweeps: one tracking issue titled "QA sweep — <scope> <date>", findings filed as separate issues related to it; change requests use type:change-request and describe current vs desired behavior + acceptance criteria.

FINAL MESSAGE (machine-consumed): `labels: <created N>/<skipped M>`, `doc: <title>|<url>`, then any failures. Nothing else.

---

After it completes: paste the document URL into `docs/agents/ticket-filing.md` ({{TRACKER_GUIDE_URL}} placeholder).
