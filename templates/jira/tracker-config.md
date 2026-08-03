# Tracker configuration — Jira

## Levels: 3 of 4 → virtual milestones

Kit target hierarchy: milestone container → feature grouping → work item → sub-item.

**Epic** → **Story** → **Task/Sub-task** are native under project {{PROJECT_KEY}}. The current Jira MCP connector cannot create releases, so the milestone-container level is VIRTUAL:

- At milestone kickoff the planner creates the label `milestone:<slug>` and applies it to every epic in that milestone's scope. Planning and filing agents treat the label exactly like a milestone container (JQL: `labels = "milestone:<slug>"`).
- Milestone membership is encoded ONLY in that label — never in epic names or descriptions — so it stays losslessly convertible.
- Conversion path: when the connector supports creating releases (v2), convert each `milestone:<slug>` label into a release (fixVersion) on the same issues, then drop the label. Milestones become the native 4th level; epics stay feature groupings.

## Native field usage

- Issue type: Bug for `type:bug` (Task if Bug is absent), Task otherwise; Story only for feature slices under an epic.
- Sev labels are canonical; mirror native fields per this table (on conflict the label wins):

| Kit label | Jira Priority | JSM Impact (when the field exists) |
|---|---|---|
| sev1-critical | Highest | Extensive |
| sev2-high | High | Significant |
| sev3-medium | Medium | Moderate |
| sev4-low | Low | Minor |
