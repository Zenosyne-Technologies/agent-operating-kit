# Filing tracker issues

Authoritative rules live in the tracker document **"Issue Intake & Triage Guide"** ({{TRACKER_GUIDE_URL}}). Every brief that has an agent create or update issues MUST tell the agent to fetch and follow that document.

Non-negotiables (mirror of the guide — the guide wins on conflict):
- Jira site {{JIRA_SITE_URL}} + project {{TRACKER_PROJECT}} (key {{PROJECT_KEY}}); new issues → Backlog.
- Hierarchy: Epic (milestone-scale scope) → Story → Task/Sub-task. Milestones live on epics until the Jira MCP connector supports creating releases (v2); then they move to releases (fixVersions).
- Native issue type: Bug for `type:bug` (Task if Bug is absent), Task otherwise.
- Labels: exactly one `type:*` (bug | change-request | investigation | tech-debt), one `area:*`, one `sev1..sev4`, one `found-by:*` (agent-qa | owner).
- Severity: sev1 data-loss/security/app-unusable · sev2 feature broken, no workaround · sev3 workaround exists or cosmetic-functional · sev4 polish. Sev labels are canonical; mirror the tracker's native field per its mapping table (Jira Priority: sev1→Highest · sev2→High · sev3→Medium · sev4→Low) — on conflict the label wins.
- Search for duplicates BEFORE filing.
- Description template: `## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs`. Change requests: current vs desired behavior + acceptance criteria.
- QA sweeps: one tracking issue ("QA sweep — <scope> <date>"), findings filed as related issues.

Filing with fully-prepared content is ponytail (micro-model) work; drafting content from raw findings is default-worker work.
