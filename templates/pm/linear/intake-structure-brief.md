# Agent brief: create the Linear intake structure

Fill the placeholders, then hand this brief verbatim to an agent (works at the small-worker tier; micro-model if your Linear MCP tools are reliable).

---

Create the issue-intake structure for {{PROJECT_NAME}} in Linear. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: list_issue_labels, create_issue_label, list_documents, save_document, list_issues, get_issue, save_issue, save_comment, list_issue_statuses (Linear MCP).

TARGET: team "{{TEAM_NAME}}" (key {{TEAM_KEY}}), project "{{PROJECT_NAME}}" (verify by KEY — the tracker's display name may differ from the repo name).

1. LABELS (team-scoped; list existing first, skip any that already exist; red-ish for sev1 descending to grey for sev4):
   type:feature, type:bug, type:change-request, type:investigation, type:tech-debt,
   area:{{AREA_1}}, area:{{AREA_2}}, area:{{AREA_3}}, area:infra, area:docs,
   sev1-critical, sev2-high, sev3-medium, sev4-low,
   size:xs, size:s, size:m, size:l, size:xl,
   origin:user-request, origin:architect-request, origin:agent-qa, origin:agent-dev, origin:roadmap
2. DOCUMENT (idempotent): search the project's documents for "Issue Intake & Triage Guide" FIRST — if found, update its content in place; create it only if absent. Content (markdown): the label taxonomy with one-line meaning each; severity definitions (sev1 data-loss/security/app-unusable; sev2 feature broken no workaround; sev3 workaround exists or cosmetic-functional; sev4 polish); hierarchy — Project → Milestone → Issue → Sub-issue, all native (the kit's full 4-level target; milestones are created directly on the project); filing rules — labels follow the repo's versioned registry `.marvin/agents/label-syntax.md` ({{LABEL_SYNTAX_VERSION}}): EVERY item created or edited (milestone-level work included) gets one label per required dimension (type:, area:, origin:; sev on defects; size on every non-epic item, set at filing and re-sized at planning, mirrored to the native estimate per tracker-config) — a dimension value lives only in its label (and the native mirror tracker-config names), never as `Size: m` / `Severity: sev3` in a title or description, and severity is spelled exactly `sev4-low` (bare `sev4` is never a label), and agents touching an unlabeled item backfill labels from its description; description templates — bugs `## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs`, feature/story items `## Scope / ## DoD`; sev labels are canonical — mirror native Priority from them (sev1→Urgent, sev2→High, sev3→Medium, sev4→Low), on conflict the label wins; team + project + status Backlog (or the workflow's initial status where Backlog doesn't exist — record which in the guide); ALWAYS search for duplicates before filing; QA sweeps: one tracking issue titled "QA sweep — <scope> <date>", findings filed as separate issues related to it; change requests use type:change-request and describe current vs desired behavior + acceptance criteria.
3. AUDIT (idempotent; every upgrade re-runs it as the label sync): list_issues filtered to team {{TEAM_KEY}}, project "{{PROJECT_NAME}}" and every status that is not completed or canceled (page through every result) and list the OPEN items that are missing a required dimension (type:, area:, origin:; sev on defects; size on every non-epic item), carry a value not in `.marvin/agents/label-syntax.md` (incl. bare `sev1`..`sev4`), or state a size/severity only in prose in the title or description. Backfill each per the registry's backfill-on-touch rule: best guess from the title/description plus a comment stating it was inferred; a prose dimension moves to the label and the prose is deleted; a non-registry value is replaced by its registry spelling. Read each edited item back (get_issue) and confirm the labels landed.

FINAL MESSAGE (machine-consumed): `labels: <created N>/<skipped M>`, `doc: <created|updated>|<title>|<url>`, `audit: <checked N>/<backfilled M>`, then any failures. Nothing else.

---

After it completes: paste the document URL into `.marvin/agents/ticket-filing.md` ({{TRACKER_GUIDE_URL}} placeholder).
