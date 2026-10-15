# Agent brief: create the GitHub Issues intake structure

Fill the placeholders, then hand this brief verbatim to an agent (works at the small-worker tier; micro-model if your `gh` CLI setup is reliable).

---

Create the issue-intake structure for {{PROJECT_NAME}} in GitHub Issues. Work synchronously, no sub-agents.

TOOLS: `gh` CLI via Bash — `gh label list`, `gh label create`, `gh issue list`, `gh issue create`, `gh issue edit`, `gh issue pin`, `gh issue view`, `gh issue comment`, `gh api`.

TARGET: repository {{GITHUB_REPO}} (owner/repo — verify by `gh repo view {{GITHUB_REPO}}`).

1. VERIFY: `gh repo view {{GITHUB_REPO}}` succeeds and issues are enabled (`hasIssuesEnabled`). If disabled, record `issues-disabled` in the final message and stop; never attempt to enable issues.
2. LABELS (idempotent — `gh label list` first, skip any that already exist; `gh label create` in red-ish for sev1 descending to grey for sev4):
   type:feature, type:bug, type:change-request, type:investigation, type:tech-debt,
   area:{{AREA_1}}, area:{{AREA_2}}, area:{{AREA_3}}, area:infra, area:docs,
   sev1-critical, sev2-high, sev3-medium, sev4-low,
   size:xs, size:s, size:m, size:l, size:xl,
   origin:user-request, origin:architect-request, origin:agent-qa, origin:agent-dev, origin:roadmap
3. GUIDE (idempotent): `gh issue list --search "Issue Intake & Triage Guide in:title"` first — if found, `gh issue edit` its body in place; if absent, `gh issue create` it and `gh issue pin` it. Content (markdown): the label taxonomy with one-line meaning each; severity definitions (sev1 data-loss/security/app-unusable; sev2 feature broken no workaround; sev3 workaround exists or cosmetic-functional; sev4 polish); hierarchy — the kit's 4 levels map natively: Milestone (native, `gh api` milestones) → Epic = parent issue with sub-issues → Issue → task-list items; NO virtual milestones needed; sev and size labels are canonical and stand ALONE — GitHub has no native priority or estimate field to mirror; status: issues are open/closed only — the kit's "Backlog" concept = an open issue with no milestone assigned (record this); filing rules — labels follow the repo's versioned registry `.marvin/agents/label-syntax.md` ({{LABEL_SYNTAX_VERSION}}): EVERY item created or edited (epics/issues/task-list items included) gets one label per required dimension (type:, area:, origin:; sev on defects; size on every non-epic issue, set at filing and re-sized at planning) — a dimension value lives only in its label, never as `Size: m` / `Severity: sev3` in a title or description, and severity is spelled exactly `sev4-low` (bare `sev4` is never a label), and agents touching an unlabeled item backfill labels from its description; description templates — bugs `## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs`, feature/story items `## Scope / ## DoD`; ALWAYS search for duplicates (`gh issue list --search`) before filing; QA sweeps: one tracking issue titled "QA sweep — <scope> <date>", findings filed as separate issues referencing it; change requests use type:change-request and describe current vs desired behavior + acceptance criteria; comment discipline mirrors the sibling trackers — short summary of what was done/found, outcome, and refs.
4. AUDIT (idempotent; every upgrade re-runs it as the label sync): run `gh issue list --repo {{GITHUB_REPO}} --search "is:open" --limit 1000 --json number,title,body,labels` (narrow per dimension, e.g. `--search "is:open -label:size:xs -label:size:s -label:size:m -label:size:l -label:size:xl"`; an epic is a parent issue with sub-issues) and list the OPEN items that are missing a required dimension (type:, area:, origin:; sev on defects; size on every non-epic item), carry a value not in `.marvin/agents/label-syntax.md` (incl. bare `sev1`..`sev4`), or state a size/severity only in prose in the title or description. Backfill each per the registry's backfill-on-touch rule: best guess from the title/description plus a comment stating it was inferred; a prose dimension moves to the label and the prose is deleted; a non-registry value is replaced by its registry spelling. Read each edited issue back (`gh issue view --json labels`) and confirm the labels landed.

FINAL MESSAGE (machine-consumed): `labels: <created N>/<already-present M>`, `guide: <created|updated>|<title>|<url>`, `issues: <ok|disabled>` (from step 1's verify), `audit: <checked N>/<backfilled M>`, then any failures. Nothing else.

---

After it completes: paste the guide URL into `.marvin/agents/ticket-filing.md` ({{TRACKER_GUIDE_URL}} placeholder).
