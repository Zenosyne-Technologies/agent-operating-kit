# Agent brief: create the Jira intake structure

Fill the placeholders, then hand this brief verbatim to an agent (works at the small-worker tier; micro-model if your Jira MCP tools are reliable).

---

Create the issue-intake structure for {{PROJECT_NAME}} in Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: getVisibleJiraProjects, getJiraProjectIssueTypesMetadata, createJiraIssue, editJiraIssue, searchJiraIssuesUsingJql, getConfluenceSpaces, searchConfluenceUsingCql, createConfluencePage, updateConfluencePage (Atlassian MCP).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}} (verify by KEY — the tracker's display name may differ from the repo name).

1. VERIFY: the project exists and lists issue types Epic, Story, Task (plus Bug and Sub-task if configured). Report any missing type in the final message; never attempt to create issue types.
2. SEED ISSUE (idempotent; Jira labels are site-global and created implicitly on first use — there is no create-label API): search FIRST (JQL: project = {{PROJECT_KEY}} AND summary ~ "Issue Intake & Triage Guide") — if found, edit it to carry ALL taxonomy labels; only if absent create ONE Task so titled, status Backlog (or the workflow's initial status where Backlog doesn't exist — record which in the guide), carrying ALL taxonomy labels so they autocomplete site-wide:
   type:feature, type:bug, type:change-request, type:investigation, type:tech-debt,
   area:{{AREA_1}}, area:{{AREA_2}}, area:{{AREA_3}}, area:infra, area:docs,
   sev1-critical, sev2-high, sev3-medium, sev4-low,
   size:xs, size:s, size:m, size:l, size:xl,
   origin:user-request, origin:architect-request, origin:agent-qa, origin:agent-dev, origin:roadmap
3. GUIDE (idempotent): if a Confluence space ({{CONFLUENCE_SPACE_KEY}}) is available, search it for page "Issue Intake & Triage Guide" — update it if found, create it otherwise — and link it from the seed issue; otherwise the guide content goes in the seed issue's description. Content (markdown): the label taxonomy with one-line meaning each; severity definitions (sev1 data-loss/security/app-unusable; sev2 feature broken no workaround; sev3 workaround exists or cosmetic-functional; sev4 polish); hierarchy — the kit targets 4 levels (milestone → epic → story → task); Epic = feature grouping → Story = feature slice → Task/Sub-task = implementation step, all native; milestones are VIRTUAL: a `milestone:<slug>` label applied to every epic in the milestone (created by the planner at milestone kickoff, queried via JQL `labels = "milestone:<slug>"`), encoded ONLY in that label so each one converts losslessly to a release (fixVersion) when the Jira MCP connector supports creating releases (v2); filing rules — labels follow the repo's versioned registry `.docs/agents/label-syntax.md` ({{LABEL_SYNTAX_VERSION}}): EVERY item created or edited (epics/stories/tasks included) gets one label per required dimension (type:, area:, origin:; sev on defects; size on stories/tasks at planning, mirrored to Story Points per tracker-config), and agents touching an unlabeled item backfill labels from its description; description templates — bugs `## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs`, feature/story items `## Scope / ## DoD`; native issue type Bug for type:bug (Task if Bug is absent); the label taxonomy is canonical — mirror native Priority from the sev label (sev1→Highest, sev2→High, sev3→Medium, sev4→Low; JSM Impact if the field exists: Extensive/Significant/Moderate/Minor), on conflict the label wins; project {{PROJECT_KEY}} + status Backlog (or the workflow's initial status where Backlog doesn't exist — record which in the guide); ALWAYS search for duplicates (JQL) before filing; QA sweeps: one tracking issue titled "QA sweep — <scope> <date>", findings filed as separate issues linked to it; change requests use type:change-request and describe current vs desired behavior + acceptance criteria.

FINAL MESSAGE (machine-consumed): `labels: <seeded N>/<already-present M>`, `seed: <created|updated>`, `guide: <created|updated>|<title>|<url>`, `issue-types: <missing list or ok>`, then any failures. Nothing else.

---

After it completes: paste the guide URL into `.docs/agents/ticket-filing.md` ({{TRACKER_GUIDE_URL}} placeholder).
