# Handbook documentation system — kit v0.13.0 design

Date: 2026-08-05 · Status: owner-directed · Target plugin version: 0.13.0

## Context

The kit documents *changes* (documentation agent: architecture notes, closing comments) but builds no living product documentation. The owner directs: every task's execution checks/creates/amends three Obsidian-compatible wiki handbooks — developer (software logic), user and admin (end-user, module/function level) — with a discovery system so future sub-agents FIND existing pages and amend rather than duplicate when tasks change code or functionality.

## Goals

1. Three handbooks under `.docs/handbooks/{developer,user,admin}/`, Obsidian-compatible (wikilinks, plain md, per-folder `INDEX.md` table of contents).
2. Developer handbook = wiki of the software's logic: per-module/business-logic pages — what it does, why nuanced behavior exists, flows/steps/rules that are NOT common sense, and how parts connect architecturally.
3. User and admin handbooks = end-user documentation per module/function: plainly written, what it does and what to be aware of; admin separated from user.
4. Handbook work happens DURING the lifecycle: the per-task documentation agent checks/amends/creates pages; milestone validation includes a coverage pass.
5. Discovery: `sources:` frontmatter (code paths each page documents) + mandatory INDEX registration — a sub-agent maps its touched paths to pages with one grep, and browses by INDEX.

## Non-goals

- Publishing/rendering pipelines (Obsidian opens the folder as a vault; plain md renders anywhere).
- Retroactive full-codebase documentation on install (pages accrete with tasks; a project can seed via an explicit backfill dispatch, not auto).
- Screenshots/media conventions (per-project choice).

## Design

### 1. `templates/docs/agents/handbooks.md` (new cascade file, ≤60 lines)

The system definition:
- **Layout**: `.docs/handbooks/<audience>/` for `developer|user|admin`; one page per module/business-logic unit; `INDEX.md` per folder is the ToC — every page MUST be registered there with a one-line description (a page not in INDEX doesn't exist).
- **Page format**: YAML frontmatter — `title`, `audience` (developer|user|admin), `module`, `sources` (list of repo code paths this page documents — the discovery key), `updated` (YYYY-MM-DD), `related` (list of `[[Page]]` links). Body uses Obsidian wikilinks `[[Page Name]]` between pages; kebab-case filenames; relative-only references.
- **Audience voice**: developer pages document logic — purpose, the WHY behind nuanced behavior, flows/steps/rules that are not common sense, and connections to other modules (link them); never restate what clean code already says. User/admin pages describe what a function/module does for its audience in plain language, how to use it, and what to be aware of; admin covers operation/configuration, user covers usage; no agent/tier internals, no code.
- **Discovery rule (mandatory, before writing)**: read the three INDEX files; grep the handbooks for `sources:` entries matching every touched path (`grep -rl "<path>" .docs/handbooks/`); AMEND matching pages rather than creating near-duplicates; create only when no page owns the module; update `sources`, `updated`, `related`, and INDEX on every create/rename; fix wikilinks on rename.
- **When**: per task via the documentation agent (logic changed → developer page; user-visible behavior changed → user page; operational/config surface changed → admin page; nothing relevant changed → explicitly none). Milestone validation includes a coverage pass.
- Secrets rule applies (security.md): handbooks are shareable surfaces.

### 2. Lifecycle wiring

- `templates/CLAUDE.core.md`: ONE cascade line (file is 45/50 — budget ok): `- Checking, creating, or amending the product handbooks (developer / user / admin wikis) → \`.docs/agents/handbooks.md\``.
- `templates/docs/agents/documentation-agent.md`: scope gains item — map the task's touched paths to handbook pages per `handbooks.md` discovery; amend/create the affected developer/user/admin pages; report which pages were touched or why none.
- `templates/docs/agents/validation-agent.md`: milestone-validation sweep list gains "handbook coverage (each shipped epic's functionality has current pages in all three audiences)".

### 3. Skeleton + install/upgrade

- New `templates/docs/handbooks/INDEX.md` — one generic audience-neutral skeleton (no new placeholders): title, "register every page here" rule, empty table (Page | What it covers | Sources), pointer to `.docs/agents/handbooks.md`. Installed three times (developer/user/admin).
- `install-agent-os` step 5: create `.docs/handbooks/{developer,user,admin}/INDEX.md` from the skeleton.
- `upgrade-agent-os` step 3 installables: add the handbooks skeletons explicitly (hardening lesson: name tracker/aux files, don't imply).
- `validate-kit` scenarios: verify the three INDEX files exist post-install/upgrade.

### 4. Docs

README: core idea 11 (living handbooks with discovery-by-sources); inventory lines (`docs/agents/handbooks.md`, `docs/handbooks/INDEX.md`). plugin.json 0.13.0.

## File change list

| File | Change |
|---|---|
| `templates/docs/agents/handbooks.md` | new (system definition) |
| `templates/docs/handbooks/INDEX.md` | new (generic skeleton, installed ×3) |
| `templates/CLAUDE.core.md` | one cascade line (≤50 check) |
| `templates/docs/agents/documentation-agent.md` | handbook step in scope |
| `templates/docs/agents/validation-agent.md` | coverage item in milestone sweep |
| `skills/install-agent-os/SKILL.md`, `skills/upgrade-agent-os/SKILL.md`, `skills/validate-kit/SKILL.md` | skeleton creation / installables / scenario checks |
| `README.md`, `.claude-plugin/plugin.json` | core idea 11, inventory, 0.13.0 |

## Compatibility

Additive; existing installs receive it via `upgrade-agent-os`. Handbook content accretes from the next task onward; no retroactive obligation.

## Testing

Gate (CI) + coherence walk (cascade line ↔ handbooks.md ↔ documentation-agent ↔ validation-agent ↔ install/upgrade skeleton steps) + a live smoke: apply to the telemetry repo (create skeletons + seed one developer page for `capture.py` following the discovery rule end-to-end, verifying grep-by-source finds it afterward).

## Addendum (owner refinement, pre-merge)

Pages are per LOGICAL unit set by the orchestrator — never per code file (hundreds of files collapse into a handful of units). Units that outgrow one page become subfolders: `<unit>/<unit>.md` main page carrying the unit's full `sources` list, topic sub-files with narrower `sources`, all wiki-linked; the subfolder registers its main page in INDEX. Scope excludes framework defaults (e.g., Laravel stock structure) — only project-introduced logic is documented. User/admin handbooks structure by what a layman searches for: business capability, menu item, or screen/function. `related` frontmatter links are quoted for Obsidian-valid YAML.

## Validated

2026-08-05. Gate: all 7 checks pass on the release tree; budgets handbooks.md 43/60, CLAUDE.core.md 46/50; no placeholders in the two new templates. Coherence: cascade line ↔ handbooks.md ↔ documentation-agent item 6 ↔ validation-agent milestone coverage ↔ install/upgrade/validate-kit steps all cross-resolve (final review, full depth — no scoped reviews were run for this compact release, the whole-branch review covered task depth). Live smoke on agent-token-telemetry (commit 74503f3): three handbooks seeded, one page per audience written for the capture-pipeline logical unit; developer page's seven logic claims verified against capture.py; discovery loop proven (grep-by-source finds the pages; second-touch resolves to AMEND). The smoke's friction finding (multi-hit greps) drove the discovery-rule fix; the final review's four minors: quoted-wikilink fixed pre-merge, prose-match limitation accepted as mitigated, two consumer-repo nits deferred.
