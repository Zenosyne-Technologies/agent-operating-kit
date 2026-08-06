# Agent brief: create the Local (file-based) intake structure

Fill the placeholders, then hand this brief verbatim to an agent (works at the micro tier — file operations only).

---

Create the issue-intake structure for {{PROJECT_NAME}} in this repository. Work synchronously, no sub-agents.

TOOLS: file operations only (Read/Write/Edit + Bash for `ls`/`grep`). No external tracker, no network.

TARGET: `.docs/project-management/` in the repo root. Project key: {{PROJECT_KEY}}.

Every step is idempotent — inspect first, create only what is missing, update what exists in place. Never delete or renumber existing items.

1. SCAFFOLD: ensure `.docs/project-management/`, `.docs/project-management/issues/` and `.docs/project-management/milestones/` exist (`.gitkeep` in the two empty folders so they survive a clone).
2. INDEX: ensure `.docs/project-management/INDEX.md` exists. If absent, create it with a `# {{PROJECT_KEY}} — issue index` heading, a counters block (`next_issue: 1`, `next_milestone: 1`), and an empty open-item table with header `| key | title | type | status | milestone |`. If present, leave counters and rows untouched — only add the table header if it is missing.
3. GUIDE (idempotent): write `.docs/project-management/guide.md` titled "Issue Intake & Triage Guide" — create it if absent, otherwise rewrite its body in place, preserving any project-specific section a human added below a `## Project notes` heading. Content (markdown): the label taxonomy with one-line meaning each — type:feature, type:bug, type:change-request, type:investigation, type:tech-debt; area:{{AREA_1}}, area:{{AREA_2}}, area:{{AREA_3}}, area:infra, area:docs; sev1-critical, sev2-high, sev3-medium, sev4-low; size:xs, size:s, size:m, size:l, size:xl; origin:user-request, origin:architect-request, origin:agent-qa, origin:agent-dev, origin:roadmap — labels live in each item's `labels:` frontmatter list, there is no label store to seed; severity definitions (sev1 data-loss/security/app-unusable; sev2 feature broken no workaround; sev3 workaround exists or cosmetic-functional; sev4 polish); hierarchy — the kit's 4 levels map to files: milestone file (`milestones/{{PROJECT_KEY}}-M<n>.md`) → epic = an issue with `type: feature` and a `children:` list → issue (`issues/{{PROJECT_KEY}}-<n>.md`) → task-list checkboxes inside the issue; NO virtual milestones (the `milestone:` frontmatter field is the container); sev and size labels are canonical and stand ALONE — there is no native priority or estimate field to mirror; status: `status: todo | in-progress | done` in the frontmatter — the kit's "Backlog" concept = a `todo` item with no `milestone:` set (record this); numbering — the next key comes from INDEX.md's `next_issue` counter, which the filing agent increments in the same edit as the new file and the new INDEX row; filing rules — labels follow the repo's versioned registry `.docs/agents/label-syntax.md` ({{LABEL_SYNTAX_VERSION}}): EVERY item created or edited (epics/issues/task-list items included) gets one label per required dimension (type:, area:, origin:; sev on defects; size on issues at planning), and agents touching an unlabeled item backfill labels from its description; description templates — bugs `## Repro / ## Expected / ## Actual / ## Evidence / ## Suspected cause / ## Refs`, feature/story items `## Scope / ## DoD`; ALWAYS search for duplicates (`grep -i '^title:' .docs/project-management/issues/*.md`) before filing; QA sweeps: one tracking issue titled "QA sweep — <scope> <date>", findings filed as separate issues referencing its key; change requests use type:change-request and describe current vs desired behavior + acceptance criteria; comment discipline mirrors the hosted trackers — append under `## Comments` a short summary of what was done/found, the outcome, and refs (commits by issue key, docs, PRs).
4. COMMIT the created/updated files (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `structure: <created|updated>`, `guide: <created|updated>|.docs/project-management/guide.md`, `index: <created|updated>`, then any failures. Nothing else.

---

After it completes: the guide path (`.docs/project-management/guide.md`) is the {{TRACKER_GUIDE_URL}} value in `.docs/agents/ticket-filing.md`.
