# Reporting & Statistics (kit v0.8.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kit v0.8.0: per-tracker stats-collection briefs producing a versioned JSON snapshot, a tracker-neutral reporting cascade file (architect digest / milestone close-out / stakeholder page), a thin `report` plugin skill, and the milestone-close lifecycle hook.

**Architecture:** Collect-once, render-many. Tracker-specific query briefs (`templates/<tracker>/stats-collection-brief.md`) write `.docs/reports/<date>-stats[-<scope>].json`; a tracker-neutral cascade file (`templates/docs/agents/reporting.md`) defines the three renders consuming that snapshot; the `report` skill fills and dispatches installed briefs. Spec: `docs/superpowers/specs/2026-08-03-reporting-v0.8.0-design.md`.

**Tech Stack:** Markdown templates + skill instructions, JSON manifest. Verification via deterministic shell checks per task.

## Global Constraints

- Repo root: `/Users/spike/Dev/agent-operating-kit`, branch `claude/reporting-v0.8.0`.
- NO AI attribution in commits — plain `git commit -m`, no Co-Authored-By lines.
- `templates/` files ≤ 45 lines each; no `${CLAUDE_PLUGIN_ROOT}` and no model names in `templates/` (tier placeholders only).
- Labels are defined ONLY in `templates/docs/agents/label-syntax.md` — the new files reference dimensions, never redefine them.
- Intake/stats briefs are handed verbatim to sub-agents: each must be self-contained (TOOLS line naming exact tools, idempotent steps, machine-consumed FINAL MESSAGE).
- Snapshot contract (consumed by every task): file `.docs/reports/<YYYY-MM-DD>-stats[-<scope>].json` with top-level keys exactly: `stats_schema` (integer, this release = 1), `generated`, `scope` ("project" or "milestone:<slug>"), `pm_tool`, `project_key`, `issues_scanned`, `by_type`, `by_area`, `by_origin`, `by_size`, `sev_open`, `sev_closed`, `milestones`, `period`, `oldest_open_sev1_or_sev2`.
- Read every file with the Read tool before editing; quoted "current text" must be confirmed against disk.
- Final plugin version for this release: `0.8.0` (bumped once, in Task 6).

---

### Task 1: Jira stats-collection brief

**Files:**
- Create: `templates/jira/stats-collection-brief.md`

**Interfaces:**
- Produces: the snapshot contract (Global Constraints) — Tasks 2, 3, 5, 7 rely on the exact key set and the FINAL MESSAGE grammar `snapshot: <path>`, `issues-scanned: <n>`.

- [ ] **Step 1: Create the brief**

Write `templates/jira/stats-collection-brief.md`:

```markdown
# Agent brief: collect tracker statistics (Jira)

Fill the placeholders, then hand this brief verbatim to an agent (works at the default-worker tier; micro-model if your Jira MCP tools are reliable).

---

Collect issue statistics for {{PROJECT_NAME}} from Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: searchJiraIssuesUsingJql (Atlassian MCP).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}}. SCOPE: {{SCOPE: "project" | "milestone:<slug>"}} (milestone scope adds `AND labels = "milestone:<slug>"` to every query). PERIOD: last {{PERIOD_DAYS}} days.

1. QUERY (JQL, count-only where possible; respect SCOPE): totals per label value for each dimension — type:*, area:*, origin:*, size:*, and milestone:* labels (each with open vs done split for `milestones`); sev1..sev4 split into open (`statusCategory != Done`) and closed; `created >= -{{PERIOD_DAYS}}d` and `resolved >= -{{PERIOD_DAYS}}d` counts; oldest unresolved issue labeled sev1-critical or sev2-high (key, or "none").
2. WRITE the snapshot to `.docs/reports/<YYYY-MM-DD>-stats[-<scope-slug>].json` (create `.docs/reports/` if absent; overwrite same-day same-scope file — re-runs are idempotent) with EXACTLY these top-level keys: stats_schema (1), generated, scope, pm_tool ("jira"), project_key, issues_scanned, by_type, by_area, by_origin, by_size, sev_open, sev_closed, milestones, period ({created, closed, days}), oldest_open_sev1_or_sev2. Dimension objects map label value → count; omit zero-count values.
3. COMMIT the snapshot file (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, then any failures. Nothing else.
```

- [ ] **Step 2: Verify**

Run: `wc -l templates/jira/stats-collection-brief.md && grep -c "stats_schema" templates/jira/stats-collection-brief.md && grep -rn 'CLAUDE_PLUGIN_ROOT' templates/jira/ ; true`
Expected: ≤ 45 lines; ≥ 1; no CLAUDE_PLUGIN_ROOT hits.

- [ ] **Step 3: Commit**

```bash
git add templates/jira/stats-collection-brief.md
git commit -m "feat: Jira stats-collection brief — label-dimension snapshot to .docs/reports/"
```

---

### Task 2: Linear stats-collection brief

**Files:**
- Create: `templates/linear/stats-collection-brief.md`

**Interfaces:**
- Consumes: the snapshot contract from Global Constraints (identical key set to Task 1; `pm_tool` value is `"linear"`; milestone scope filters by the native milestone instead of a label).

- [ ] **Step 1: Create the brief**

Write `templates/linear/stats-collection-brief.md`:

```markdown
# Agent brief: collect tracker statistics (Linear)

Fill the placeholders, then hand this brief verbatim to an agent (works at the default-worker tier; micro-model if your Linear MCP tools are reliable).

---

Collect issue statistics for {{PROJECT_NAME}} from Linear. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: list_issues, list_issue_labels, list_milestones (Linear MCP).

TARGET: team "{{TEAM_NAME}}" (key {{TEAM_KEY}}), project "{{PROJECT_NAME}}". SCOPE: {{SCOPE: "project" | "milestone:<slug>"}} (milestone scope filters to that native project milestone). PERIOD: last {{PERIOD_DAYS}} days.

1. QUERY (paginate list_issues over the project; respect SCOPE): totals per label value for each dimension — type:*, area:*, origin:*, size:*; per native milestone the open vs done split for `milestones` (slugified milestone name as key); sev1..sev4 split into open (state not in Done/Canceled) and closed; created and completed counts within PERIOD; oldest open issue labeled sev1-critical or sev2-high (identifier, or "none").
2. WRITE the snapshot to `.docs/reports/<YYYY-MM-DD>-stats[-<scope-slug>].json` (create `.docs/reports/` if absent; overwrite same-day same-scope file — re-runs are idempotent) with EXACTLY these top-level keys: stats_schema (1), generated, scope, pm_tool ("linear"), project_key ({{TEAM_KEY}}), issues_scanned, by_type, by_area, by_origin, by_size, sev_open, sev_closed, milestones, period ({created, closed, days}), oldest_open_sev1_or_sev2. Dimension objects map label value → count; omit zero-count values.
3. COMMIT the snapshot file (selective add; attribution per the project's settings).

FINAL MESSAGE (machine-consumed): `snapshot: <path>`, `issues-scanned: <n>`, then any failures. Nothing else.
```

- [ ] **Step 2: Verify**

Run: `wc -l templates/linear/stats-collection-brief.md && grep -c "stats_schema" templates/linear/stats-collection-brief.md`
Expected: ≤ 45 lines; ≥ 1. Then Read both briefs' step-2 key lists side by side and confirm they name the same 15 top-level keys in the same order (only the pm_tool value and project_key sourcing differ).

- [ ] **Step 3: Commit**

```bash
git add templates/linear/stats-collection-brief.md
git commit -m "feat: Linear stats-collection brief — label-dimension snapshot to .docs/reports/"
```

---

### Task 3: reporting.md cascade file

**Files:**
- Create: `templates/docs/agents/reporting.md`

**Interfaces:**
- Consumes: the snapshot contract.
- Produces: the three render definitions (digest / close-out / stakeholder) that Task 4's lifecycle hook and Task 5's skill dispatch; render output paths `.docs/reports/<date>-digest.md`, `.docs/reports/<date>-closeout-<slug>.md`, stakeholder md or tracker doc.

- [ ] **Step 1: Create the cascade file**

Write `templates/docs/agents/reporting.md`:

```markdown
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
```

- [ ] **Step 2: Verify**

Run: `wc -l templates/docs/agents/reporting.md && grep -c "WORKER_MODEL" templates/docs/agents/reporting.md && grep -c "snapshot" templates/docs/agents/reporting.md`
Expected: ≤ 45 lines; 1; ≥ 3.

- [ ] **Step 3: Commit**

```bash
git add templates/docs/agents/reporting.md
git commit -m "feat: reporting cascade — collect-once render-many (digest, close-out, stakeholder)"
```

---

### Task 4: CLAUDE.core.md wiring (cascade line + lifecycle hook)

**Files:**
- Modify: `templates/CLAUDE.core.md` (currently 40 lines — result must stay ≤ 45)

**Interfaces:**
- Consumes: Task 3's render definitions.

- [ ] **Step 1: Add the cascade line**

After the line `- Planning a \`size:l\`/\`size:xl\` task → \`.docs/agents/planning-research.md\` (plan-validation + solution research, tier-routed by size)` insert:

```markdown
- Producing any report (digest / close-out / stakeholder) → `.docs/agents/reporting.md` (snapshot first, render second)
```

- [ ] **Step 2: Extend the milestone-branching bullet in place**

Replace `- **Milestone feature branching**: each milestone gets a \`milestone/<slug>\` branch off the default branch; all task work commits land there; merge back only at milestone close, after validation.` with:

```markdown
- **Milestone feature branching**: each milestone gets a `milestone/<slug>` branch off the default branch; all task work commits land there; merge back only at milestone close, after validation. At milestone close, dispatch stats collection + the close-out render per `.docs/agents/reporting.md` before archiving the branch.
```

- [ ] **Step 3: Verify**

Run: `wc -l templates/CLAUDE.core.md && grep -c "reporting.md" templates/CLAUDE.core.md`
Expected: ≤ 45 lines (should be 41); 2.

- [ ] **Step 4: Commit**

```bash
git add templates/CLAUDE.core.md
git commit -m "feat: wire reporting into the cascade and the milestone-close lifecycle"
```

---

### Task 5: report skill

**Files:**
- Create: `skills/report/SKILL.md`

**Interfaces:**
- Consumes: PROJECT-INFO frontmatter keys (`pm_tool`, `project_key`, `tracker_coordinates`, `project_key`), the installed stats brief, Task 3's render types.

- [ ] **Step 1: Create the skill**

Write `skills/report/SKILL.md`:

```markdown
---
name: report
description: Produce a project report from tracker statistics — architect digest (default), milestone close-out, or stakeholder page. Fills and dispatches the project's installed stats-collection brief, then the requested render per .docs/agents/reporting.md. Use when the user asks for a report, digest, project stats, milestone close-out, or stakeholder update.
---

# Produce a report

Thin fill-and-dispatch — all reporting logic lives in the installed project files, so projects without this plugin dispatch the same briefs manually.

1. **Read the project's facts**: `.docs/PROJECT-INFO.md` frontmatter (`pm_tool`, `project_key`, `tracker_coordinates`). `pm_tool: none` → no tracker stats; offer a docs/git-history digest instead and stop.
2. **Parse the request**: render type — digest (default) | closeout <slug> | stakeholder; scope (whole project unless a milestone is named); period (default 30 days).
3. **Collect**: fill the installed tool's `stats-collection-brief` from the kit templates for the project's `pm_tool` (`${CLAUDE_PLUGIN_ROOT}/templates/<tracker>/stats-collection-brief.md`), resolving placeholders from the frontmatter, and dispatch it as a sub-agent. Skip when a same-day snapshot for the same scope already exists in `.docs/reports/` unless the user asks for fresh numbers.
4. **Render**: dispatch one worker sub-agent per `.docs/agents/reporting.md` with the snapshot path and render type. For close-outs, pass the milestone container reference so the comment lands.
5. **Report**: the render's output path (and comment URL for close-outs), plus `issues-scanned` from the collection final message.
```

- [ ] **Step 2: Verify**

Run: `grep -c "stats-collection-brief" skills/report/SKILL.md && grep -c "reporting.md" skills/report/SKILL.md`
Expected: ≥ 2; ≥ 2.

- [ ] **Step 3: Commit**

```bash
git add skills/report/SKILL.md
git commit -m "feat: report skill — fill-and-dispatch collection + render"
```

---

### Task 6: Factory docs + 0.8.0 bump + release sweep

**Files:**
- Modify: `CLAUDE.md` (repo), `README.md`, `.claude-plugin/plugin.json`

- [ ] **Step 1: Repo CLAUDE.md extension rule**

In extension rule 2, replace `new folder \`templates/<tracker>/\` mirroring the existing ones: intake brief + \`tracker-config.md\`` with:

```markdown
new folder `templates/<tracker>/` mirroring the existing ones: intake brief + `tracker-config.md` + `stats-collection-brief.md` (same snapshot schema)
```

- [ ] **Step 2: README**

- Skills paragraph: after the `upgrade-agent-os` sentence add: "A fourth skill, **`report`**, produces an architect digest, milestone close-out, or stakeholder page from tracker statistics via the installed stats-collection brief."
- Core ideas: append as item 8: `8. **Collect-once reporting** — a per-tracker stats brief snapshots every label dimension into versioned JSON under \`.docs/reports/\`; audience renders (architect digest, milestone close-out at milestone close, internals-free stakeholder page) consume the snapshot, never the tracker.`
- Inventory: under `docs/agents/` add line `    reporting.md                   collect-once render-many report definitions (digest, close-out, stakeholder)`; under `linear/` add `    stats-collection-brief.md      label-dimension stats snapshot (schema v1) to .docs/reports/`; under `jira/` add the same line.

- [ ] **Step 3: Version bump**

In `.claude-plugin/plugin.json` change `"version": "0.7.0"` to `"version": "0.8.0"`.

- [ ] **Step 4: Release sweep (hard gate)**

```bash
python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo json-ok
grep -rn 'CLAUDE_PLUGIN_ROOT' templates/ && echo LEAK || echo no-leak
for f in $(find templates -name '*.md'); do n=$(wc -l < "$f"); [ "$n" -gt 45 ] && echo "OVER: $f $n"; done; echo budget-done
grep -c "stats-collection-brief" README.md CLAUDE.md skills/report/SKILL.md   # ≥1 each
grep -c "reporting.md" README.md templates/CLAUDE.core.md                     # ≥1 each
head -1 templates/docs/agents/label-syntax.md                                 # still v1.2.0 — this release adds no labels
```

Expected: all pass; fix causes before committing.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md .claude-plugin/plugin.json
git commit -m "feat: v0.8.0 — reporting release (docs, inventory, tracker-folder rule, version bump)"
```

---

### Task 7: Scratch validation (spec Testing section, adapted to no live tracker)

**Files:**
- Modify (append only): `docs/superpowers/specs/2026-08-03-reporting-v0.8.0-design.md`

- [ ] **Step 1: Snapshot + render simulation** — in a scratch dir, fabricate a valid schema-v1 snapshot (`2026-08-03-stats.json`, all 15 keys, plausible counts across every dimension, one milestone slug). Acting as the render agent per `templates/docs/agents/reporting.md`, produce all three renders from it. Verify: digest ends with ≤3 actionable observations and cites only snapshot numbers; close-out covers delivered-vs-planned from `milestones`; stakeholder contains NO occurrence of `origin:`, `size:`, tier names, or agent terminology (grep for `origin:\|size:\|worker\|escalation\|ponytail` → zero hits).
- [ ] **Step 2: Brief fill check** — resolve every placeholder of both stats briefs against a fabricated PROJECT-INFO frontmatter (jira + linear variants); verify no `{{` remains and the JQL/API instructions reference only label values that exist in the registry.
- [ ] **Step 3: Record** — append "## Validated" to the v0.8.0 spec (date, scenario outcomes, the explicit caveat that live tracker queries were not executed) and commit:

```bash
git add docs/superpowers/specs/2026-08-03-reporting-v0.8.0-design.md
git commit -m "docs: record v0.8.0 render/brief validation results"
```
