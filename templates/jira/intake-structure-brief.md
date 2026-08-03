# Agent brief: create the Jira intake structure

Fill the placeholders, then hand this brief verbatim to an agent (works at the default-worker tier; micro-model if your Jira MCP tools are reliable).

---

Create the issue-intake structure for {{PROJECT_NAME}} in Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: getVisibleJiraProjects, getJiraProjectIssueTypesMetadata, createJiraIssue, editJiraIssue, searchJiraIssuesUsingJql, getConfluenceSpaces, createConfluencePage (Atlassian MCP).

TARGET: Jira site {{JIRA_SITE_URL}}, project "{{PROJECT_NAME}}" (key {{PROJECT_KEY}}).

1. VERIFY: the project exists and lists issue types Epic, Story, Task (plus Bug and Sub-task if configured). Report any missing type in the final message; never attempt to create issue types.
2. SEED ISSUE (Jira labels are site-global and created implicitly on first use — there is no create-label API): create ONE Task titled "Issue Intake & Triage Guide", status Backlog, carrying ALL taxonomy labels so they autocomplete site-wide:
   type:bug, type:change-request, type:investigation, type:tech-debt,
   area:{{AREA_1}}, area:{{AREA_2}}, area:{{AREA_3}}, area:infra, area:docs,
   sev1-critical, sev2-high, sev3-medium, sev4-low,
   found-by:agent-qa, found-by:owner
3. GUIDE: if a Confluence space ({{CONFLUENCE_SPACE_KEY}}) is available, create page "Issue Intake & Triage Guide" there and link it from the seed issue; otherwise the guide content goes in the seed issue's description. Content (markdown): the label taxonomy with one-line meaning each; severity definitions (sev1 data-loss/security/app-unusable; sev2 feature broken no workaround; sev3 workaround exists or cosmetic-functional; sev4 polish); hierarchy — Epic = milestone-scale scope container → Story = feature under its epic → Task/Sub-task = implementation step; milestones live on epics until the Jira MCP connector supports creating releases (v2), then they move to releases (fixVersions) and epics narrow to feature groupings; filing rules — every issue gets exactly one type:, one area:, one sev label + provenance label; native issue type Bug for type:bug (Task if Bug is absent); the label taxonomy is canonical — mirror native Priority from the sev label (sev1→Highest, sev2→High, sev3→Medium, sev4→Low; JSM Impact if the field exists: Extensive/Significant/Moderate/Minor), on conflict the label wins; project {{PROJECT_KEY}} + status Backlog; ALWAYS search for duplicates (JQL) before filing; description template: "## Repro / ## Expected / ## Actual / ## Evidence (console/network/logs) / ## Suspected cause / ## Refs"; QA sweeps: one tracking issue titled "QA sweep — <scope> <date>", findings filed as separate issues linked to it; change requests use type:change-request and describe current vs desired behavior + acceptance criteria.

FINAL MESSAGE (machine-consumed): `labels: <seeded N>`, `guide: <title>|<url>` (Confluence page or seed issue), `issue-types: <missing list or ok>`, then any failures. Nothing else.

---

After it completes: paste the guide URL into `.docs/agents/ticket-filing.md` ({{TRACKER_GUIDE_URL}} placeholder).
