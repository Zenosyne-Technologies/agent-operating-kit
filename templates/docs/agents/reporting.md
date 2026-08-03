# Producing reports

All reports render FROM a stats snapshot — never query the tracker directly. Collect first: dispatch the tracker's `stats-collection-brief` (installed knowledge: coordinates in `.docs/PROJECT-INFO.md` frontmatter), which writes `.docs/reports/<date>-stats[-<scope>].json` (schema v1). Then dispatch ONE {{WORKER_MODEL}} render agent briefed with the snapshot path and the render type below. Renders are md files committed like any doc work.

## Renders

1. **Architect digest** (on-demand) → `.docs/reports/<date>-digest.md`. One page for the human running the sessions: what shipped in the period; demand-source mix (by_origin); quality posture (sev_open vs sev_closed, oldest_open_sev1_or_sev2, trend vs the previous digest's snapshot if one exists in `.docs/reports/`); where effort went (by_area × by_size); milestone progress. End with ≤3 actionable observations, not summaries.
2. **Milestone close-out** (lifecycle-triggered at milestone close — see CLAUDE.md standing rules) → `.docs/reports/<date>-closeout-<slug>.md` PLUS a comment on the milestone container (epic/milestone). Contents: delivered vs planned scope (milestones[slug] open vs done), defects by area, sizing distribution of shipped work, research-pass outcomes if recorded, notable deviations.
3. **Stakeholder page** (on-demand) → polished md at `.docs/reports/<date>-stakeholder.md`, or a tracker/Confluence doc where connected. Progress, roadmap position, quality summary. STRIP agent internals: no origin:/size: labels, no tier or escalation talk, no agent names — a reader outside the team must see product progress only.

## Rules

- Snapshot first, always — a render without a fresh same-day snapshot starts by dispatching collection.
- Render briefs follow `briefing.md` (machine-consumed FINAL MESSAGE: `report: <path>` plus `comment: <url>` for close-outs).
- Numbers come from the snapshot verbatim — an agent that recomputes or estimates figures is doing it wrong.
