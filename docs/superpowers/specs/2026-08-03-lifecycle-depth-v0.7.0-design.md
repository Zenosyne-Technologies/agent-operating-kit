# Lifecycle depth — kit v0.7.0 design

Date: 2026-08-03 · Status: approved for planning · Target plugin version: 0.7.0

## Context

The kit evolved fast through v0.2.0–v0.6.1 (Linear→Jira migration, `.docs/` move, `found-by:*`→`origin:*` supersession, label registry v1.0.0→v1.1.0, sizing, planning research). Installed consumer projects are pinned snapshots with no way to follow: nothing records which kit version an install came from, tracker structures never receive labels added after install, the documented Jira milestone→release conversion has no executable artifact, and agents size tasks with no shared rubric. v0.7.0 closes these loops.

## Goals

1. Every install carries a machine-readable kit-version stamp.
2. A consumer project on any prior kit version can be migrated to current with one skill invocation.
3. Registry bumps propagate to already-created tracker structures (labels + guide).
4. Tracker-data migrations (relabel sweeps) are possible but gated behind one explicit user confirmation.
5. Agents size tasks against an objective rubric.
6. The Jira virtual-milestone→release conversion is a prepared, dispatchable brief.
7. PROJECT-INFO carries its structured facts in machine-parseable YAML frontmatter.

## Non-goals

- Reporting/statistics consumers of the label dimensions (v0.8.0, own spec).
- Kit self-validation CI + validate-kit skill + BOOTSTRAP pointer (v0.9.0, own spec).
- GitHub Issues tracker support (unscheduled).
- A BOOTSTRAP-style paste-able upgrade prompt (upgrade is plugin-only for now; parity later if needed).

## Design

### 1. Version stamping + structured PROJECT-INFO

`templates/docs/PROJECT-INFO.md` is restructured as **YAML frontmatter + markdown body**. The frontmatter carries every structured fact — the machine contract for foreign agents, frameworks, and the kit's own skills:

```yaml
---
project: {{PROJECT_NAME}}
description: {{ONE_SENTENCE_DESCRIPTION}}
owner: {{OWNER_ORG_OR_PERSON}}
pm_tool: {{PM_TOOL}}            # linear | jira | none
tracker_coordinates: {{TRACKER_COORDINATES}}
project_key: {{PROJECT_KEY_OR_NA}}
hierarchy_levels: {{LEVELS}}     # "4/4" | "3/4-virtual-milestones"
intake_guide_url: {{TRACKER_GUIDE_URL}}
stack: {{LANGUAGES_FRAMEWORKS_DATASTORES}}
dev_command: {{DEV_COMMAND_AND_PORTS}}
docs_location: {{DOCS_LOCATION}}
kit_version: {{KIT_VERSION}}
label_syntax_version: {{LABEL_SYNTAX_VERSION}}
---
```

The markdown body keeps the human overview (prose, pointers into `.docs/agents/`), no longer duplicating every field — frontmatter is the source of truth for facts; the body explains. The install skill resolves `kit_version` from the plugin's `.claude-plugin/plugin.json`; `upgrade-agent-os` rewrites the version keys after every migration; the `project-info` skill validates frontmatter keys against the repo (and adds missing keys via its fix sub-agent). One file, so facts can never drift against their own document.

### 2. `upgrade-agent-os` skill (new — third skill, `skills/upgrade-agent-os/SKILL.md`)

Flow, in order:

1. **Detect**: read the Kit version stamp from `.docs/PROJECT-INFO.md`. If absent (pre-0.7.0 install), fingerprint heuristically: `docs/agents/` vs `.docs/agents/` location; presence of `found-by:*` in taxonomy files; missing `tracker-config.md` / `label-syntax.md` / `planning-research.md` / `PROJECT-INFO.md`. Heuristics only need to distinguish pre-stamp generations; stamped installs never re-fingerprint.
2. **Diff**: compute the migration list against current `${CLAUDE_PLUGIN_ROOT}/templates/` — file moves, new cascade files to add, cascade-line updates in the consumer CLAUDE.md, label-registry version delta.
3. **Migrate repo files**: apply with the install skill's merge discipline — kit-owned files updated/moved (`git mv` for the `docs/`→`.docs/` case), project-specific content never overwritten, CLAUDE.md references rewritten. Autocommit (attribution per the project's settings).
4. **Sync tracker structure**: re-dispatch the installed tool's intake brief (now idempotent — §3) as a sub-agent to seed any new labels and refresh the in-tracker guide.
5. **Gated data migration**: if the registry delta includes supersessions (e.g. `found-by:*`→`origin:*`), query the tracker for the affected-issue count, then ask ONE yes/no question. On yes: dispatch a ponytail (micro-tier) relabel sweep with the registry's mapping as prepared payload. On no: report the pending sweep and its mapping.
6. **Restamp + report**: update Kit version + label-syntax version in PROJECT-INFO.md, commit, and report: from→to version, files migrated, labels seeded, sweep executed/pending/none, anything unresolvable.

Repo-file steps run without confirmation (git-revertible); the only interactive gate is step 5 (shared tracker state, not git-revertible).

### 3. Idempotent intake briefs

Both `templates/<tracker>/intake-structure-brief.md` files become fully re-runnable:

- **Linear**: labels already list-before-create; add find-first for the guide document (search by title in the project; update content if found, create only if absent).
- **Jira**: add search-first (JQL by title) for the seed issue — edit its labels/description instead of creating a duplicate; same find-or-create for the Confluence guide page.
- Final messages extend to `<created N>/<updated M>/<skipped K>` form so the orchestrator can distinguish first-run from sync-run.

Repo CLAUDE.md extension rule 2 gains: intake briefs MUST be idempotent/re-runnable — upgrade re-dispatches them as the label-sync mechanism.

### 4. Sizing rubric (registry v1.2.0)

`templates/docs/agents/label-syntax.md` bumps to v1.2.0, adding a five-line "Sizing rubric" section (size semantics are label semantics; the registry's versioning is the change-tracking they need):

- `size:xs` — single-file, mechanical, zero unknowns (ponytail-eligible).
- `size:s` — a few files, established pattern, no design decisions.
- `size:m` — multi-file feature slice, minor unknowns, contained blast radius.
- `size:l` — cross-cutting change OR real unknowns (new integration, unclear repro, schema touch).
- `size:xl` — architectural impact, multiple `area:*` values, significant unknowns or irreversible ops.

Changelog row added. `planning-research.md` keeps only the routing (already references the registry).

### 5. Jira v2 conversion brief

New `templates/jira/convert-milestones-brief.md` — prepared now, dispatched when the Jira MCP connector supports creating releases (v2):

1. Enumerate distinct `milestone:<slug>` labels in project `{{PROJECT_KEY}}` (JQL).
2. For each slug: create release (fixVersion) named `<slug>` if absent (idempotent), set it on every issue carrying the label, then remove the label from those issues.
3. Update the in-tracker guide's hierarchy section: milestones are now native releases.
4. FINAL MESSAGE (machine-consumed): `releases: <created N>/<existing M>`, `issues: <converted K>`, `labels-removed: <slugs>`, failures. Nothing else.

`templates/jira/tracker-config.md`'s conversion-path line points to this brief. The upgrade skill mentions it in its report when the connector's release capability is detected.

## File change list

| File | Change |
|---|---|
| `skills/upgrade-agent-os/SKILL.md` | new |
| `skills/install-agent-os/SKILL.md` | resolve frontmatter incl. `kit_version` stamp into PROJECT-INFO |
| `skills/project-info/SKILL.md` | validate frontmatter keys (incl. versions) against the repo |
| `templates/docs/PROJECT-INFO.md` | restructure: YAML frontmatter (facts) + md body (overview) |
| `templates/docs/agents/label-syntax.md` | v1.2.0: sizing rubric + changelog row |
| `templates/linear/intake-structure-brief.md` | idempotent guide handling; created/updated/skipped final message |
| `templates/jira/intake-structure-brief.md` | search-first seed issue + guide; created/updated/skipped final message |
| `templates/jira/convert-milestones-brief.md` | new |
| `templates/jira/tracker-config.md` | conversion-path line references the brief |
| `CLAUDE.md` (repo) | extension rule: intake briefs must be idempotent; skills list mention |
| `README.md` | skills section, inventory, core-idea touch-ups |
| `BOOTSTRAP.md` | PROJECT-INFO stamp line (keep lockstep with install steps) |
| `.claude-plugin/plugin.json` | 0.7.0 |

## Compatibility

- Pre-0.7.0 installs: handled by the heuristic branch of detection, exactly once — after the first upgrade they are stamped. A pre-0.7.0 PROJECT-INFO.md (list-style, no frontmatter) is converted to the frontmatter form by the upgrade skill (or the project-info fix sub-agent), preserving project-specific extras in the body.
- The intake-brief idempotency changes are backwards-compatible: first runs behave as today.
- No changes to consumer-facing rule semantics; only additions (rubric, stamp) and mechanics (idempotency).

## Testing

Validate per extension rule 5, three scenarios against scratch repos: (a) fresh install → verify stamp present and briefs run; (b) simulated pre-0.7.0 install (docs/agents/, found-by labels, no stamp) → upgrade → verify moves, stamp, label seeding, gated sweep prompt; (c) re-run upgrade on a current install → verify no-op idempotency.

## Validated

Date: 2026-08-03. Executed against kit commit `ec4f903` (branch `claude/lifecycle-depth-v0.7.0`, plugin version 0.7.0) by acting as the installing/upgrading agent against three scratch git repos, following `skills/install-agent-os/SKILL.md` and `skills/upgrade-agent-os/SKILL.md` literally.

- **Fresh install** (`scratch-fresh/`, Node/TS project, PM tool = none, attribution = keep default) → **PASS**. All 7 cascade files present (`briefing.md`, `validation-agent.md`, `documentation-agent.md`, `ticket-filing.md`, `ponytail.md`, `label-syntax.md`, `planning-research.md`); `tracker-config.md` correctly absent for `pm_tool: none`. `CLAUDE.md` fully resolved, no `{{` placeholders anywhere. `.docs/PROJECT-INFO.md` frontmatter parses with all 13 keys and real values (`kit_version: 0.7.0`, `label_syntax_version: 1.2.0`). No `${CLAUDE_PLUGIN_ROOT}` in any installed file. Caveat: the template gives no explicit guidance for phrasing the `tracker-config.md` cascade line or the `hierarchy_levels` frontmatter value when `pm_tool: none` — both required an installing-agent judgment call (noted "pending" / `n/a`); not a functional defect, but a minor gap worth a template note for a future pass.
- **Legacy upgrade** (`scratch-legacy/`, fabricated pre-0.7.0 shape: `docs/agents/` location, `found-by:*` labels in `ticket-filing.md`, no `PROJECT-INFO.md`, present `tracker-config.md` for Jira) → **PASS**. `git mv docs/agents → .docs/agents` applied cleanly; every `docs/agents/` reference in `CLAUDE.md` and the cascade docs rewritten to `.docs/agents/`; missing cascade files (`label-syntax.md` v1.2.0, `planning-research.md`) added with placeholders resolved; `tracker-config.md`'s conversion-path line updated to reference the new `convert-milestones` brief and gained the size→Story Points table; `.docs/PROJECT-INFO.md` created fresh (didn't exist pre-0.7.0) with all 13 frontmatter keys resolved (`pm_tool: jira`, `kit_version: 0.7.0`, `label_syntax_version: 1.2.0`). `ticket-filing.md`'s stale `found-by:*` labels line rewritten to reference the versioned registry (`origin:*`); the historical `found-by:*` string survives only inside `label-syntax.md`'s own changelog row (expected — it documents the supersession). Tracker-affecting steps 4 (re-dispatch intake brief) and 5 (gated relabel sweep) were **not live-executed** — this scratch repo has no real Jira project/connector behind it — and are recorded instead: step 4's idempotency was confirmed by inspection of `templates/jira/intake-structure-brief.md` (search-first for both the seed issue and the Confluence guide, confirmed present); step 5's gated sweep prompt (`found-by:agent-qa → origin:agent-qa`, `found-by:owner → origin:architect-request`) was recorded as the question that would be asked and left **unanswered — the sweep remains a pending offer, not executed**, per the task's scoping instruction.
- **No-op re-run** (`upgrade-agent-os` re-run against `scratch-fresh/`, already stamped `kit_version: 0.7.0`) → **PASS**. Detection step reads the frontmatter stamp (`0.7.0`), matches the plugin's current `.claude-plugin/plugin.json` version (`0.7.0`) and the label registry's current H1 (`1.2.0`) exactly; per the skill's rule ("Re-running on a current install must be a clean no-op") no files were touched. `git -C scratch-fresh status --short` returned empty — zero diffs confirmed.

No defects in the shipped skills/templates were found that block correct operation. The two caveats above (silent `pm_tool: none` gaps in the `tracker-config.md` cascade line and `hierarchy_levels` frontmatter guidance) are documentation-completeness observations, not correctness bugs — install and upgrade both produced valid, fully-resolved, self-contained installs in every scenario.
