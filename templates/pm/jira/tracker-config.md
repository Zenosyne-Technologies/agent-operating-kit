---
doc: Tracker configuration — Jira
type: reference
status: active
summary: Jira's hierarchy against the kit's four levels, the virtual-milestone rule, and the severity mapping to Jira Priority.
updated: {{INSTALL_DATE}}
---

# Tracker configuration — Jira

## Levels: 3 of 4 → virtual milestones

Kit target hierarchy: milestone container → feature grouping → work item → sub-item.

**Epic** → **Story** → **Task/Sub-task** are native under project {{PROJECT_KEY}}. The current Jira MCP connector cannot create releases, so the milestone-container level is VIRTUAL:

- At milestone kickoff the planner creates the label `milestone:<slug>` and applies it to every epic in that milestone's scope. Planning and filing agents treat the label exactly like a milestone container (JQL: `labels = "milestone:<slug>"`).
- Milestone membership is encoded ONLY in that label — never in epic names or descriptions — so it stays losslessly convertible.
- Conversion path: when the connector supports creating releases (v2), dispatch the kit's `convert-milestones` brief (installed alongside this config, or `templates/pm/jira/convert-milestones-brief.md` in the kit) — each `milestone:<slug>` label becomes a release (fixVersion) on the same issues, labels dropped. Milestones become the native 4th level; epics stay feature groupings.

## Native field usage

- Issue type: Bug for `type:bug` (Task if Bug is absent), Task otherwise; Story only for feature slices under an epic.
- Sev labels are canonical; mirror native fields per this table (on conflict the label wins):

| Kit label | Jira Priority | JSM Impact (when the field exists) |
|---|---|---|
| sev1-critical | Highest | Extensive |
| sev2-high | High | Significant |
| sev3-medium | Medium | Moderate |
| sev4-low | Low | Minor |

- Size labels are canonical; mirror native Story Points per this table when the field exists (on conflict the label wins):

| Kit label | Jira Story Points |
|---|---|
| size:xs | 1 |
| size:s | 2 |
| size:m | 3 |
| size:l | 5 |
| size:xl | 8 |

## Release mapping: virtual, for exactly the reason milestones are

Same connector limitation, same answer. A Jira release IS a fixVersion, and the connector cannot create one — so a released version is VIRTUAL here too. The model behind the version (branches, tagging authority, semver) is `.marvin/agents/git-strategy.md`; only the Jira mapping is decided below.

- `<version>` is bare semver (`1.2.0`) everywhere in this kit; the leading `v` is part of the tag name and of the strings built from it. So the label is `release:v<version>` — literally `release:v1.2.0`, never `release:vv1.2.0`. JQL: `labels = "release:v1.2.0"`.
- At the release cut that label goes on every issue in the frozen scope — the same set the release note's `scope:` header records, which stays the source rollups resolve against; the label is a Jira-side convenience, and the annotated tag is canonical. Membership is encoded ONLY in the label, never in summaries or descriptions, so it stays losslessly convertible — the same rule the milestone label follows.
- The two axes sit at DIFFERENT levels: `milestone:<slug>` on epics only (the container is what the milestone groups), `release:v<version>` on every issue that shipped, down to the tasks. An epic in a released milestone therefore carries both, a task under it usually carries only the release label, and neither label is derivable from the other. Milestone key sets are expanded from epics to their work-carrying children before any cost rollup — an epic key alone matches no telemetry rows (`.marvin/agents/token-economics.md`).
- Conversion path: the SAME brief converts both (installed alongside this config, or `templates/pm/jira/convert-milestones-brief.md` in the kit) — each `milestone:<slug>` becomes a fixVersion named `<slug>`, each `release:v<version>` a fixVersion of that same name, labels dropped. An issue may hold several fixVersions, which is what lets the two axes coexist on one native field.
