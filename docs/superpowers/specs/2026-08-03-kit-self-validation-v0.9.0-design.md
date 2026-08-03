# Kit self-validation — v0.9.0 design

Date: 2026-08-03 · Status: approved for planning · Target plugin version: 0.9.0 · Depends on: v0.7.0 (upgrade skill exists to be tested)

## Context

The kit's quality gates are discipline-only: extension rule 5 (scratch-repo install validation) is manual, SKILL↔BOOTSTRAP lockstep relies on contributors reading a rule, and template invariants (placeholder resolvability, lean-file budgets, registry-changelog consistency) are unchecked. v0.9.0 automates the deterministic checks in CI, packages the agentic test as a skill, and eliminates the lockstep problem at its source.

## Goals

1. Every PR is gated by deterministic static checks.
2. The agentic scratch-repo test is one skill invocation, run before releases.
3. SKILL↔BOOTSTRAP duplication is eliminated, not checked.

## Non-goals

- Agentic tests in CI (cost, keys, flakiness — deliberately local).
- Testing consumer projects (that's the upgrade/install skills' own reporting).

## Design

### 1. Static CI gate — `scripts/validate-kit.sh` + GitHub Actions workflow

A dependency-free script (bash + python3, both preinstalled on runners) run by `.github/workflows/validate.yml` on every PR and push to main. Checks, each with a clear failure message:

1. **Placeholder resolvability**: every `{{PLACEHOLDER}}` used across `templates/` appears in the install/upgrade skills' gathering instructions (extracted by convention: a maintained list in the script header is acceptable v1).
2. **Lean-file budget**: files under `templates/` ≤ 45 lines (40-line rule + tolerance); failures name the cascade-split rule.
3. **JSON validity**: `.claude-plugin/*.json` parse; `plugin.json` version is semver and strictly greater than the last git tag if tags are used.
4. **Registry consistency**: the version in `label-syntax.md`'s H1 equals its newest changelog row.
5. **Inventory sync**: every file under `templates/` appears in README's inventory block and vice versa.
6. **Tracker folder completeness**: each `templates/<tracker>/` contains the required set (intake brief, tracker-config; stats brief once v0.8.0 lands).
7. **No plugin-path leakage**: `templates/` contains no `${CLAUDE_PLUGIN_ROOT}` references.

### 2. `validate-kit` skill (`skills/validate-kit/SKILL.md`)

Runs the agentic scenarios locally before a release, against a temp scratch repo (git-initialized, throwaway):

- (a) fresh install: dispatch `install-agent-os`, verify every placeholder resolved, frontmatter stamp present, cascade complete, no plugin-path leakage in installed files.
- (b) legacy upgrade: fabricate a pre-0.7.0 install shape (`docs/agents/`, `found-by:*` in files, no frontmatter), dispatch `upgrade-agent-os`, verify moves, frontmatter conversion, stamp, and that the tracker-data sweep was OFFERED not executed.
- (c) idempotency: re-run upgrade on the result of (a); verify clean no-op.

Tracker steps run in dry-run form (briefs filled and shown, not dispatched) unless the user points the skill at a sandbox tracker project. FINAL report: pass/fail per scenario with diffs.

### 3. BOOTSTRAP becomes a pointer

`BOOTSTRAP.md` shrinks to a short paste-able prompt: clone/locate the kit repo, read `skills/install-agent-os/SKILL.md`, follow it treating `${CLAUDE_PLUGIN_ROOT}` as the repo root. The duplicated step list is deleted; the repo CLAUDE.md's "keep the two in lockstep" requirement is replaced by "BOOTSTRAP is a pointer — flow changes edit the skill only."

## File change list

| File | Change |
|---|---|
| `scripts/validate-kit.sh` | new |
| `.github/workflows/validate.yml` | new |
| `skills/validate-kit/SKILL.md` | new |
| `BOOTSTRAP.md` | reduce to pointer prompt |
| `CLAUDE.md` (repo) | replace lockstep rule; reference the CI gate in extension rules |
| `README.md` | skills list, inventory, contributor note about the gate |
| `.claude-plugin/plugin.json` | 0.9.0 |

## Compatibility

CI is factory-only — consumers see nothing. BOOTSTRAP users need the repo cloned, which the manual path already required.

## Testing

The validator validates itself: run `scripts/validate-kit.sh` against the repo at this release (must pass), then against a deliberately broken fixture branch (each check must fire once).

## Validated

Date: 2026-08-04

The release tree passes all seven static checks (`bash scripts/validate-kit.sh`):
- ✓ placeholders
- ✓ line-budget
- ✓ json
- ✓ registry
- ✓ inventory
- ✓ tracker-folders
- ✓ plugin-root-leak

Exit code 0; git diff main..HEAD --stat -- templates/ shows zero modifications.

All seven negative-firing scenarios from Task 1 (scratch-repo isolation) confirmed:
1. placeholders — appended `{{BOGUS_PLACEHOLDER}}` to `templates/CLAUDE.core.md` → caught with FAIL [placeholders]
2. line-budget — padded `templates/CLAUDE.core.md` to 83 lines → caught with FAIL [line-budget]
3. json — set `.claude-plugin/plugin.json` version to `"x.y"` (non-semver) → caught with FAIL [json]
4. registry — bumped `templates/docs/agents/label-syntax.md` H1 to v9.9.9 without changelog row → caught with FAIL [registry]
5. inventory — deleted `briefing.md` line from README inventory → caught with FAIL [inventory]
6. tracker-folders — removed `templates/jira/tracker-config.md` → caught with FAIL [tracker-folders]
7. plugin-root-leak — appended `${CLAUDE_PLUGIN_ROOT}/foo` to `templates/CLAUDE.core.md` → caught with FAIL [plugin-root-leak]

Each negative test fired independently; all others remained `ok`. Scratch copy isolated via `cp -r` and cleaned (`rm -rf`) post-testing.

Note: the agentic scenarios (fresh install, legacy upgrade, idempotency) ship as the `validate-kit` skill and were exercised for v0.7.0; a full re-run is deferred to the next release that touches install/upgrade flows.
