---
doc: Convert virtual milestones and releases to Jira fixVersions
type: reference
status: active
summary: The dispatchable brief that turns every milestone slug label and every release version label into a Jira fixVersion once the connector supports creating them, retiring both virtual workarounds.
updated: {{INSTALL_DATE}}
---

# Agent brief: convert virtual milestones and releases to Jira fixVersions

Dispatch ONLY when the Jira MCP connector supports creating releases (v2). Fill the placeholders, then hand this brief verbatim to an agent (small-worker tier).

---

Convert {{PROJECT_NAME}}'s virtual milestones AND virtual releases to native fixVersions in Jira. Both axes ride the one fixVersion field — an issue may hold several, which is what lets them coexist. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: searchJiraIssuesUsingJql, editJiraIssue, getVisibleJiraProjects, plus the v2 release-creation tool (name it from the tool search).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}}.

1. ENUMERATE, two passes: JQL `project = {{PROJECT_KEY}} AND labels ~ "milestone:"` → the distinct `milestone:<slug>` labels and the issues carrying each; JQL `project = {{PROJECT_KEY}} AND labels ~ "release:"` → the distinct `release:<version>` labels and their issues.
2. For each label, idempotently: create the fixVersion if absent — named `<slug>` for a milestone label, `v<version>` for a release label (mark a release fixVersion released, with the tag's date, where the tool exposes it); set it on every issue carrying that label (KEEP existing fixVersions — an issue in both a milestone and a release must end with both); then remove that label from those issues.
3. GUIDE: update the in-tracker "Issue Intake & Triage Guide" hierarchy section — milestones are now native fixVersions (4/4 kit levels) and released versions are native fixVersions too; both virtual rules are retired.

FINAL MESSAGE (machine-consumed): `milestones: <created N>/<existing M>`, `releases: <created N>/<existing M>`, `issues: <converted K>`, `labels-removed: <label list>`, then any failures. Nothing else.

---

After it completes: update `.marvin/agents/tracker-config.md` (levels 4 of 4, virtual-milestone section removed, release mapping now native — cite `.marvin/agents/git-strategy.md`, restate nothing) and `.marvin/PROJECT-INFO.md` frontmatter (`hierarchy_levels: 4/4`). The tag stays canonical whichever way the labels went.
