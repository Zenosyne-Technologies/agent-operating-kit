# Filing tracker issues

Authoritative rules live in the tracker document **"Issue Intake & Triage Guide"** ({{TRACKER_GUIDE_URL}}). Every brief that has an agent create or update issues MUST tell the agent to fetch and follow that document — and to label per `label-syntax.md`.

Non-negotiables (mirror of the guide — the guide wins on filing workflow; `label-syntax.md` wins on labels):
- {{TRACKER_COORDINATES: Jira → site URL + project key · Linear → team + project}}; new issues → Backlog.
- Hierarchy levels, virtual-milestone rule (for tools exposing only 3 of the kit's 4 target levels), native type/field usage, and severity→native mapping: `.docs/agents/tracker-config.md`.
- Labels: per the versioned registry `.docs/agents/label-syntax.md` — one label per required dimension (`type:*`, `area:*`, `origin:*`; `sev1..sev4` on defects) on EVERY item you create or edit, epics and stories included. Touching an unlabeled issue → backfill from its description.
- Severity: sev1 data-loss/security/app-unusable · sev2 feature broken, no workaround · sev3 workaround exists or cosmetic-functional · sev4 polish. Sev labels are canonical; mirror the native field per `tracker-config.md` — on conflict the label wins.
- Search for duplicates BEFORE filing.
- Description template: `## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs`. Change requests: current vs desired behavior + acceptance criteria.
- QA sweeps: one tracking issue ("QA sweep — <scope> <date>"), findings filed as related issues.

Filing with fully-prepared content is ponytail (micro-model) work; drafting content from raw findings is default-worker work.
