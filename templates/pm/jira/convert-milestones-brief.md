---
doc: Convert virtual milestones to Jira releases
type: reference
status: active
summary: The dispatchable brief that turns every milestone slug label into a Jira release once the connector supports creating them, retiring the virtual-milestone workaround.
updated: {{INSTALL_DATE}}
---

# Agent brief: convert virtual milestones to Jira releases

Dispatch ONLY when the Jira MCP connector supports creating releases (v2). Fill the placeholders, then hand this brief verbatim to an agent (small-worker tier).

---

Convert {{PROJECT_NAME}}'s virtual milestones to native releases in Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: searchJiraIssuesUsingJql, editJiraIssue, getVisibleJiraProjects, plus the v2 release-creation tool (name it from the tool search).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}}.

1. ENUMERATE: JQL `project = {{PROJECT_KEY}} AND labels ~ "milestone:"` → collect the distinct `milestone:<slug>` labels and the issues carrying each.
2. For each slug, idempotently: create release (fixVersion) named `<slug>` if absent; set that fixVersion on every issue carrying the label (keep existing fixVersions); then remove the `milestone:<slug>` label from those issues.
3. GUIDE: update the in-tracker "Issue Intake & Triage Guide" hierarchy section — milestones are now native releases (4/4 kit levels); the virtual-milestone rule is retired.

FINAL MESSAGE (machine-consumed): `releases: <created N>/<existing M>`, `issues: <converted K>`, `labels-removed: <slug list>`, then any failures. Nothing else.

---

After it completes: update `.marvin/agents/tracker-config.md` (levels 4 of 4, virtual-milestone section removed) and `.marvin/PROJECT-INFO.md` frontmatter (`hierarchy_levels: 4/4`).
