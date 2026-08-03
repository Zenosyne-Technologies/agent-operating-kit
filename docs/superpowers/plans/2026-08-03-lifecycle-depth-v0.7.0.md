# Lifecycle Depth (kit v0.7.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kit v0.7.0: version-stamped machine-readable PROJECT-INFO (YAML frontmatter), a new `upgrade-agent-os` skill, idempotent re-runnable intake briefs, a sizing rubric (registry v1.2.0), and a prepared Jira milestone→release conversion brief.

**Architecture:** Everything is markdown templates + skill instructions in a Claude Code plugin. `templates/` is the payload installed into consumer projects (project-agnostic, tier names not model names, no `${CLAUDE_PLUGIN_ROOT}` references); `skills/` and root docs are factory machinery. Spec: `docs/superpowers/specs/2026-08-03-lifecycle-depth-v0.7.0-design.md`.

**Tech Stack:** Markdown, JSON (plugin manifest), bash/python3 for verification only. No build step, no test framework — each task verifies with deterministic shell checks.

## Global Constraints

- Repo root: `~/Dev/agent-operating-kit`, branch `claude/lifecycle-depth-v0.7.0`.
- NO AI attribution in commits (repo CLAUDE.md rule 6) — plain `git commit -m`, no Co-Authored-By lines.
- Files under `templates/` must stay lean: ≤ 45 lines each.
- `templates/` must never contain the literal string `${CLAUDE_PLUGIN_ROOT}` and never contain model names (use tier placeholders `{{FRONTIER_MODEL}}`/`{{ESCALATION_MODEL}}`/`{{WORKER_MODEL}}`/`{{MICRO_MODEL}}`).
- Labels are defined ONLY in `templates/docs/agents/label-syntax.md` (repo rule 7); any registry change bumps the registry's own version AND adds a changelog row.
- Read every file with the Read tool before editing it — quoted "current text" below is expected but must be confirmed against disk.
- Final plugin version for this release: `0.7.0` (bumped once, in Task 8).

---

### Task 1: PROJECT-INFO template — YAML frontmatter + md body

**Files:**
- Modify: `templates/docs/PROJECT-INFO.md` (full rewrite)

**Interfaces:**
- Produces: the frontmatter key set consumed by Tasks 2, 3, and 7: `project, description, owner, pm_tool, tracker_coordinates, project_key, hierarchy_levels, intake_guide_url, stack, dev_command, docs_location, kit_version, label_syntax_version` — exactly these 13 keys, in this order.

- [ ] **Step 1: Rewrite the template**

Replace the entire content of `templates/docs/PROJECT-INFO.md` with:

```markdown
---
project: {{PROJECT_NAME}}
description: {{ONE_SENTENCE_DESCRIPTION}}
owner: {{OWNER_ORG_OR_PERSON}}
pm_tool: {{PM_TOOL}}
tracker_coordinates: {{TRACKER_COORDINATES}}
project_key: {{PROJECT_KEY_OR_NA}}
hierarchy_levels: {{LEVELS}}
intake_guide_url: {{TRACKER_GUIDE_URL}}
stack: {{LANGUAGES_FRAMEWORKS_DATASTORES}}
dev_command: {{DEV_COMMAND_AND_PORTS}}
docs_location: {{DOCS_LOCATION}}
kit_version: {{KIT_VERSION}}
label_syntax_version: {{LABEL_SYNTAX_VERSION}}
---

# {{PROJECT_NAME}} — project information

Meta overview for foreign agents, agentic OS frameworks, and reporting tools. The YAML frontmatter above is the machine contract and the source of truth for facts; this body is the human overview. Any agent that changes a fact below updates the frontmatter in the same change. Facts only — operating rules live in `CLAUDE.md` and `.docs/agents/`.

- Repository layout: {{MONOREPO_OR_SINGLE + one-line top-level map}}
- Hierarchy details, virtual milestones, severity/size native mappings: `.docs/agents/tracker-config.md`
- Label registry: `.docs/agents/label-syntax.md` · Filing rules: `.docs/agents/ticket-filing.md`
- Operating rules: `CLAUDE.md` + the `.docs/agents/` rules cascade
```

Frontmatter values notes for the installer (`pm_tool`: `linear | jira | none`; `hierarchy_levels`: `4/4` or `3/4-virtual-milestones`) live in the install skill (Task 2), NOT in this template — keep the template lean.

- [ ] **Step 2: Verify structure**

Run: `python3 -c "import re,sys; t=open('templates/docs/PROJECT-INFO.md').read(); m=re.match(r'^---\n(.*?)\n---\n',t,re.S) or sys.exit('no frontmatter'); keys=[l.split(':')[0] for l in m.group(1).splitlines()]; expect='project description owner pm_tool tracker_coordinates project_key hierarchy_levels intake_guide_url stack dev_command docs_location kit_version label_syntax_version'.split(); sys.exit(0 if keys==expect else 'keys mismatch: %s'%keys)" && wc -l templates/docs/PROJECT-INFO.md`
Expected: no error; line count ≤ 45.

- [ ] **Step 3: Commit**

```bash
git add templates/docs/PROJECT-INFO.md
git commit -m "feat: PROJECT-INFO template — YAML frontmatter machine contract + human body"
```

---

### Task 2: Install skill + BOOTSTRAP resolve the frontmatter and stamp versions

**Files:**
- Modify: `skills/install-agent-os/SKILL.md` (step 5 text)
- Modify: `BOOTSTRAP.md` (step 5 text)

**Interfaces:**
- Consumes: Task 1's 13 frontmatter keys.
- Produces: the stamping convention used by Tasks 3 and 7: `kit_version` ← `version` field of `.claude-plugin/plugin.json`; `label_syntax_version` ← the `vX.Y.Z` in the H1 of `templates/docs/agents/label-syntax.md`.

- [ ] **Step 1: Update the install skill**

In `skills/install-agent-os/SKILL.md`, find the step-5 sentence beginning `Also create **\`.docs/PROJECT-INFO.md\`**` (currently: "Also create **`.docs/PROJECT-INFO.md`** from `templates/docs/PROJECT-INFO.md` with every fact resolved — the quick meta page foreign agents, agentic OS frameworks, and reporting tools read first; if it already exists (re-install), do NOT recreate it — validate it and auto-fix discrepancies via a sub-agent per the `project-info` skill.") and replace it with:

```markdown
Also create **`.docs/PROJECT-INFO.md`** from `templates/docs/PROJECT-INFO.md` with every fact resolved — its YAML frontmatter is the machine contract foreign agents and reporting tools parse: resolve EVERY key (`pm_tool`: linear | jira | none; `hierarchy_levels`: `4/4` or `3/4-virtual-milestones`; `kit_version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`'s `version`; `label_syntax_version` from the registry's H1) and keep the body prose human. If it already exists (re-install), do NOT recreate it — validate it and auto-fix discrepancies via a sub-agent per the `project-info` skill.
```

- [ ] **Step 2: Update BOOTSTRAP step 5**

In `BOOTSTRAP.md`, find the sentence beginning `Create \`.docs/PROJECT-INFO.md\` from` (currently: "Create `.docs/PROJECT-INFO.md` from `templates/docs/PROJECT-INFO.md` with every fact resolved (the quick meta page for foreign agents and reporting tools); if it already exists, do NOT recreate it — validate its facts against the repo and dispatch a sub-agent to apply line-level fixes for discrepancies (never regenerate the file).") and replace it with:

```markdown
Create `.docs/PROJECT-INFO.md` from `templates/docs/PROJECT-INFO.md` with every fact resolved — its YAML frontmatter is the machine contract: resolve every key (`kit_version` from the kit repo's `.claude-plugin/plugin.json`, `label_syntax_version` from the registry's H1). If it already exists, do NOT recreate it — validate its facts against the repo and dispatch a sub-agent to apply line-level fixes for discrepancies (never regenerate the file).
```

- [ ] **Step 3: Verify**

Run: `grep -c "kit_version" skills/install-agent-os/SKILL.md BOOTSTRAP.md`
Expected: `1` in each file.

- [ ] **Step 4: Commit**

```bash
git add skills/install-agent-os/SKILL.md BOOTSTRAP.md
git commit -m "feat: install flow resolves PROJECT-INFO frontmatter and stamps kit/registry versions"
```

---

### Task 3: project-info skill validates frontmatter + converts legacy pages

**Files:**
- Modify: `skills/project-info/SKILL.md`

**Interfaces:**
- Consumes: Task 1 key set; Task 2 stamping convention.
- Produces: the legacy-conversion behavior Task 7's upgrade skill delegates to ("convert list-style PROJECT-INFO to frontmatter form").

- [ ] **Step 1: Update the create branch**

In `skills/project-info/SKILL.md`, in the "If the target does NOT exist → create" section, replace step 2 (currently: "Write `.docs/PROJECT-INFO.md` from the template with every placeholder resolved; facts only, no operating rules.") with:

```markdown
2. Write `.docs/PROJECT-INFO.md` from the template with every placeholder resolved — every YAML frontmatter key filled (`kit_version` from the plugin's `.claude-plugin/plugin.json` when installed via plugin, else the kit repo's; `label_syntax_version` from `.docs/agents/label-syntax.md`'s H1); body stays facts-only prose, no operating rules.
```

- [ ] **Step 2: Update the validate branch**

In the "If the target EXISTS" section, replace step 1 (currently: "**Validate**: every template field is present (extra project-specific fields are fine — leave them); each stated fact checked against the repo — stack, dev command/ports, tracker coordinates and hierarchy (vs `tracker-config.md`), intake guide URL, label-syntax version (vs the registry header), docs paths.") with:

```markdown
1. **Validate**: the YAML frontmatter parses and contains every template key (extra project-specific keys are fine — leave them); each frontmatter fact checked against the repo — `stack`, `dev_command`, `tracker_coordinates`/`project_key`/`hierarchy_levels` (vs `tracker-config.md`), `intake_guide_url`, `label_syntax_version` (vs the registry H1), `docs_location`; body statements must not contradict frontmatter. **Legacy page (no frontmatter)**: treat every missing key as a discrepancy — the fix sub-agent adds the frontmatter block from the template (facts lifted from the existing list) and keeps project-specific extras in the body; the file is converted, never regenerated.
```

- [ ] **Step 3: Verify**

Run: `grep -c "frontmatter" skills/project-info/SKILL.md`
Expected: ≥ 3.

- [ ] **Step 4: Commit**

```bash
git add skills/project-info/SKILL.md
git commit -m "feat: project-info skill validates frontmatter and converts legacy pages"
```

---

### Task 4: Sizing rubric — label registry v1.2.0

**Files:**
- Modify: `templates/docs/agents/label-syntax.md`

**Interfaces:**
- Produces: registry version string `v1.2.0` (consumed by Task 7's heuristics and by installers reading the H1).

- [ ] **Step 1: Bump the H1**

Change `# Label syntax registry — v1.1.0` to `# Label syntax registry — v1.2.0`.

- [ ] **Step 2: Add the rubric section**

Insert immediately after the "## Reporting intent" paragraph (before "## Changelog"):

```markdown
## Sizing rubric

- `size:xs` — single-file, mechanical, zero unknowns (ponytail-eligible).
- `size:s` — a few files, established pattern, no design decisions.
- `size:m` — multi-file feature slice, minor unknowns, contained blast radius.
- `size:l` — cross-cutting change OR real unknowns (new integration, unclear repro, schema touch).
- `size:xl` — architectural impact, multiple `area:*` values, significant unknowns or irreversible ops.

When torn between two sizes, take the larger — under-sizing skips the research pass that would have caught the unknowns.
```

- [ ] **Step 3: Add the changelog row**

In the changelog table, insert above the `| 1.1.0 |` row:

```markdown
| 1.2.0 | Adds the sizing rubric (objective xs..xl criteria; round up when torn). No dimension/value changes. |
```

- [ ] **Step 4: Verify**

Run: `head -1 templates/docs/agents/label-syntax.md && grep -c "^| 1\." templates/docs/agents/label-syntax.md && wc -l templates/docs/agents/label-syntax.md`
Expected: H1 ends `v1.2.0`; 3 changelog rows; ≤ 45 lines.

- [ ] **Step 5: Commit**

```bash
git add templates/docs/agents/label-syntax.md
git commit -m "feat: label registry v1.2.0 — objective sizing rubric"
```

---

### Task 5: Idempotent intake briefs (Linear + Jira)

**Files:**
- Modify: `templates/linear/intake-structure-brief.md`
- Modify: `templates/jira/intake-structure-brief.md`

**Interfaces:**
- Produces: re-runnable briefs Task 7's upgrade skill dispatches as its label-sync mechanism; final-message grammar `created N/updated M/skipped K`.

- [ ] **Step 1: Linear — find-first guide**

In `templates/linear/intake-structure-brief.md`, step 2 begins `2. DOCUMENT: create a Linear document "Issue Intake & Triage Guide" in the project.` Replace that opening with:

```markdown
2. DOCUMENT (idempotent): search the project's documents for "Issue Intake & Triage Guide" FIRST — if found, update its content in place; create it only if absent.
```

Replace the FINAL MESSAGE line (currently `` FINAL MESSAGE (machine-consumed): `labels: <created N>/<skipped M>`, `doc: <title>|<url>`, then any failures. Nothing else. ``) with:

```markdown
FINAL MESSAGE (machine-consumed): `labels: <created N>/<skipped M>`, `doc: <created|updated>|<title>|<url>`, then any failures. Nothing else.
```

- [ ] **Step 2: Jira — search-first seed issue and guide**

In `templates/jira/intake-structure-brief.md`, step 2 begins `2. SEED ISSUE (Jira labels are site-global and created implicitly on first use — there is no create-label API): create ONE Task titled "Issue Intake & Triage Guide"`. Replace that opening with:

```markdown
2. SEED ISSUE (idempotent; Jira labels are site-global and created implicitly on first use — there is no create-label API): search FIRST (JQL: project = {{PROJECT_KEY}} AND summary ~ "Issue Intake & Triage Guide") — if found, edit it to carry ALL taxonomy labels; only if absent create ONE Task so titled, status Backlog, carrying ALL taxonomy labels so they autocomplete site-wide:
```

In step 3 (GUIDE), replace the opening `3. GUIDE: if a Confluence space ({{CONFLUENCE_SPACE_KEY}}) is available, create page "Issue Intake & Triage Guide" there` with:

```markdown
3. GUIDE (idempotent): if a Confluence space ({{CONFLUENCE_SPACE_KEY}}) is available, search it for page "Issue Intake & Triage Guide" — update it if found, create it otherwise —
```

Replace the FINAL MESSAGE line (currently `` FINAL MESSAGE (machine-consumed): `labels: <seeded N>`, `guide: <title>|<url>` (Confluence page or seed issue), `issue-types: <missing list or ok>`, then any failures. Nothing else. ``) with:

```markdown
FINAL MESSAGE (machine-consumed): `labels: <seeded N>/<already-present M>`, `seed: <created|updated>`, `guide: <created|updated>|<title>|<url>`, `issue-types: <missing list or ok>`, then any failures. Nothing else.
```

- [ ] **Step 3: Verify**

Run: `grep -c "idempotent" templates/linear/intake-structure-brief.md templates/jira/intake-structure-brief.md && wc -l templates/linear/intake-structure-brief.md templates/jira/intake-structure-brief.md`
Expected: ≥1 per file; both ≤ 45 lines.

- [ ] **Step 4: Commit**

```bash
git add templates/linear/intake-structure-brief.md templates/jira/intake-structure-brief.md
git commit -m "feat: intake briefs are idempotent and re-runnable (find-first, created/updated final messages)"
```

---

### Task 6: Jira v2 conversion brief

**Files:**
- Create: `templates/jira/convert-milestones-brief.md`
- Modify: `templates/jira/tracker-config.md` (conversion-path bullet)

**Interfaces:**
- Consumes: `milestone:<slug>` convention from `templates/jira/tracker-config.md`.
- Produces: the dispatchable conversion artifact referenced by tracker-config and by Task 7's upgrade report.

- [ ] **Step 1: Create the brief**

Write `templates/jira/convert-milestones-brief.md`:

```markdown
# Agent brief: convert virtual milestones to Jira releases

Dispatch ONLY when the Jira MCP connector supports creating releases (v2). Fill the placeholders, then hand this brief verbatim to an agent (default-worker tier).

---

Convert {{PROJECT_NAME}}'s virtual milestones to native releases in Jira. Work synchronously, no sub-agents.

TOOLS: one tool-search call for: searchJiraIssuesUsingJql, editJiraIssue, getVisibleJiraProjects, plus the v2 release-creation tool (name it from the tool search).

TARGET: Jira site {{JIRA_SITE_URL}}, project key {{PROJECT_KEY}}.

1. ENUMERATE: JQL `project = {{PROJECT_KEY}} AND labels ~ "milestone:"` → collect the distinct `milestone:<slug>` labels and the issues carrying each.
2. For each slug, idempotently: create release (fixVersion) named `<slug>` if absent; set that fixVersion on every issue carrying the label (keep existing fixVersions); then remove the `milestone:<slug>` label from those issues.
3. GUIDE: update the in-tracker "Issue Intake & Triage Guide" hierarchy section — milestones are now native releases (4/4 kit levels); the virtual-milestone rule is retired.

FINAL MESSAGE (machine-consumed): `releases: <created N>/<existing M>`, `issues: <converted K>`, `labels-removed: <slug list>`, then any failures. Nothing else.

---

After it completes: update `.docs/agents/tracker-config.md` (levels 4 of 4, virtual-milestone section removed) and `.docs/PROJECT-INFO.md` frontmatter (`hierarchy_levels: 4/4`).
```

- [ ] **Step 2: Point tracker-config at it**

In `templates/jira/tracker-config.md`, replace the conversion bullet (currently: "- Conversion path: when the connector supports creating releases (v2), convert each `milestone:<slug>` label into a release (fixVersion) on the same issues, then drop the label. Milestones become the native 4th level; epics stay feature groupings.") with:

```markdown
- Conversion path: when the connector supports creating releases (v2), dispatch the kit's `convert-milestones` brief (installed alongside this config, or `templates/jira/convert-milestones-brief.md` in the kit) — each `milestone:<slug>` label becomes a release (fixVersion) on the same issues, labels dropped. Milestones become the native 4th level; epics stay feature groupings.
```

- [ ] **Step 3: Verify**

Run: `wc -l templates/jira/convert-milestones-brief.md && grep -c "convert-milestones" templates/jira/tracker-config.md && grep -rc 'CLAUDE_PLUGIN_ROOT' templates/ | grep -v ':0' ; true`
Expected: ≤ 45 lines; 1 reference; no CLAUDE_PLUGIN_ROOT hits under templates/.

- [ ] **Step 4: Commit**

```bash
git add templates/jira/convert-milestones-brief.md templates/jira/tracker-config.md
git commit -m "feat: prepared Jira v2 conversion brief — milestone labels to releases"
```

---

### Task 7: upgrade-agent-os skill

**Files:**
- Create: `skills/upgrade-agent-os/SKILL.md`

**Interfaces:**
- Consumes: frontmatter keys (Task 1), stamping convention (Task 2), legacy conversion (Task 3), registry v1.2.0 (Task 4), idempotent briefs (Task 5), conversion brief (Task 6).

- [ ] **Step 1: Write the skill**

Create `skills/upgrade-agent-os/SKILL.md`:

```markdown
---
name: upgrade-agent-os
description: Upgrade an existing Agent Operating Kit install in the current project to the plugin's current version — migrates files (docs/ → .docs/, new cascade docs), re-syncs tracker labels via the idempotent intake brief, offers gated relabel sweeps for label supersessions, and restamps versions in PROJECT-INFO frontmatter. Use when the user asks to upgrade/update/migrate the agent operating kit in a repo.
---

# Upgrade the Agent Operating Kit install

Current templates: `${CLAUDE_PLUGIN_ROOT}/templates/`. Never overwrite project-specific content — same merge discipline as install.

## Steps

1. **Detect installed state**: read `kit_version` from `.docs/PROJECT-INFO.md` frontmatter. No stamp? Fingerprint once: `docs/agents/` vs `.docs/agents/` location; `found-by:` present in taxonomy files (pre-registry); missing `label-syntax.md` / `tracker-config.md` / `planning-research.md` / `PROJECT-INFO.md`; list-style PROJECT-INFO without frontmatter. Report what was detected before changing anything.
2. **Diff against current templates**: file moves, cascade files to add, cascade lines to add/update in the consumer CLAUDE.md, label-registry delta (installed `label_syntax_version` → current registry H1), tracker-config/brief updates for the installed `pm_tool`.
3. **Migrate repo files** (no confirmation — git-revertible): `git mv docs/agents → .docs/agents` where applicable and rewrite CLAUDE.md references; add missing cascade files with placeholders resolved from existing install facts; merge CLAUDE.md rule updates without touching project rules; convert a legacy PROJECT-INFO to frontmatter form per the `project-info` skill. Autocommit (attribution per project settings).
4. **Sync tracker structure**: re-dispatch the installed tool's intake brief (idempotent) as a sub-agent to seed new labels and refresh the guide. Skip when `pm_tool: none`.
5. **Gated data migration**: if the registry delta includes supersessions (mappings in the registry changelog, e.g. `found-by:agent-qa → origin:agent-qa`, `found-by:owner → origin:architect-request`), query the tracker for the affected-issue count and ask ONE yes/no. Yes → dispatch a ponytail (micro-tier) relabel sweep with the mapping as prepared payload. No → report the pending sweep and mapping. Never sweep unasked.
6. **Restamp + report**: update `kit_version` (from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`) and `label_syntax_version` in the frontmatter; commit. Report: from→to versions, files migrated, labels seeded (from the brief's machine message), sweep executed/pending/none, and — if Jira and the connector now supports release creation — that the `convert-milestones` brief is ready to dispatch.

## Rules

- Steps 1–4 and 6 run without confirmation; step 5 is the ONLY interactive gate (shared tracker state is not git-revertible).
- Re-running on a current install must be a clean no-op (report `already at <version>`).
- Installed files stay self-contained: never write `${CLAUDE_PLUGIN_ROOT}` paths into the consumer repo.
```

- [ ] **Step 2: Verify**

Run: `wc -l skills/upgrade-agent-os/SKILL.md && grep -c "yes/no" skills/upgrade-agent-os/SKILL.md`
Expected: ≈ 30 lines (no hard cap — skills are factory, not payload); ≥ 1.

- [ ] **Step 3: Commit**

```bash
git add skills/upgrade-agent-os/SKILL.md
git commit -m "feat: upgrade-agent-os skill — stamped/heuristic detection, file migration, label sync, gated sweeps"
```

---

### Task 8: Factory docs + version bump + release sweep

**Files:**
- Modify: `CLAUDE.md` (repo), `README.md`, `.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: everything above; produces the released 0.7.0 manifest.

- [ ] **Step 1: Repo CLAUDE.md**

In "How the kit works", extend the parenthetical about helper skills — replace `(\`skills/project-info/SKILL.md\` is a standalone helper: create-if-missing / validate-and-auto-fix for \`.docs/PROJECT-INFO.md\`)` with:

```markdown
(`skills/project-info/SKILL.md`: create-if-missing / validate-and-auto-fix for `.docs/PROJECT-INFO.md`; `skills/upgrade-agent-os/SKILL.md`: migrate an existing install to the current kit version)
```

In extension rule 2, append after "add the tool to the skill's and BOOTSTRAP's selection lists.":

```markdown
Intake briefs MUST be idempotent/re-runnable — the upgrade skill re-dispatches them as the label-sync mechanism.
```

- [ ] **Step 2: README**

- Skills paragraph: after the `project-info` sentence, add: "A third skill, **`upgrade-agent-os`**, migrates an existing install to the current kit version — file moves, new cascade docs, tracker label re-sync, and (gated behind one confirmation) relabel sweeps for superseded labels."
- Inventory block: under `docs/`, PROJECT-INFO line becomes `PROJECT-INFO.md                project meta page — YAML frontmatter machine contract + human body (installed to .docs/PROJECT-INFO.md)`; under `jira/`, add `convert-milestones-brief.md    dispatchable when the v2 connector adds release creation: milestone labels → releases`.
- Portability notes: in the hierarchy bullet, append: "The conversion is a prepared brief (`jira/convert-milestones-brief.md`), not just a rule."

- [ ] **Step 3: Version bump**

In `.claude-plugin/plugin.json` change `"version": "0.6.1"` to `"version": "0.7.0"`.

- [ ] **Step 4: Release sweep (release gate — all must pass)**

```bash
python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo json-ok
grep -rn 'CLAUDE_PLUGIN_ROOT' templates/ && echo LEAK || echo no-leak
for f in $(find templates -name '*.md'); do n=$(wc -l < "$f"); [ "$n" -gt 45 ] && echo "OVER: $f $n"; done; echo budget-done
head -1 templates/docs/agents/label-syntax.md   # must say v1.2.0
grep -rn "found-by" templates/ | grep -v label-syntax.md ; true   # only the registry changelog may mention it
grep -c "convert-milestones" README.md templates/jira/tracker-config.md   # ≥1 each
```

Expected: `json-ok`, `no-leak`, `budget-done` with no OVER lines, v1.2.0 header, no stray found-by, references present. Fix anything that fails before committing.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md .claude-plugin/plugin.json
git commit -m "feat: v0.7.0 — lifecycle depth release (docs, inventory, idempotency rule, version bump)"
```

---

### Task 9: Scratch-repo validation (spec Testing section)

**Files:**
- None in-repo (scratch repos under the session scratchpad directory).

- [ ] **Step 1: Fresh-install scenario** — create a scratch git repo with a minimal README + package.json; follow `skills/install-agent-os/SKILL.md` end-to-end against it (act as the installing agent; pick PM tool `none` to skip tracker dispatch). Verify: `.docs/agents/` complete — 7 cascade files (briefing, validation-agent, documentation-agent, ticket-filing, ponytail, label-syntax, planning-research; tracker-config is absent for `none`, note it in the report), CLAUDE.md placeholders all resolved, PROJECT-INFO frontmatter parses with all 13 keys and real values, no `{{` remaining, no `${CLAUDE_PLUGIN_ROOT}` in installed files.
- [ ] **Step 2: Legacy-upgrade scenario** — fabricate a pre-0.7.0 shape in a second scratch repo: `docs/agents/` with the v0.4.0-era files, `found-by:*` in ticket-filing, list-style PROJECT-INFO absent. Follow `skills/upgrade-agent-os/SKILL.md`. Verify: files moved to `.docs/agents/`, CLAUDE.md references rewritten, PROJECT-INFO created with frontmatter + stamps, sweep OFFERED (not executed) in the report.
- [ ] **Step 3: No-op scenario** — re-run the upgrade flow on the repo from Step 1. Verify clean `already at 0.7.0` no-op, zero diffs (`git -C <scratch> status --short` empty).
- [ ] **Step 4: Record results** — append a "## Validated" section with the three scenario outcomes to the v0.7.0 spec and commit:

```bash
git add docs/superpowers/specs/2026-08-03-lifecycle-depth-v0.7.0-design.md
git commit -m "docs: record v0.7.0 scratch-repo validation results"
```
