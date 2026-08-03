# Kit Self-Validation (v0.9.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kit v0.9.0: a deterministic static-check script gating every PR via GitHub Actions, a `validate-kit` skill for the agentic scratch-repo scenarios, and BOOTSTRAP reduced to a pointer — eliminating the SKILL↔BOOTSTRAP lockstep problem.

**Architecture:** `scripts/validate-kit.sh` (bash + python3, no other deps) implements the seven checks from the spec; `.github/workflows/validate.yml` runs it on PRs and main; `skills/validate-kit/SKILL.md` packages the three agentic scenarios (fresh install / legacy upgrade / no-op) run locally before releases; BOOTSTRAP.md becomes a pointer at the install skill. Spec: `docs/superpowers/specs/2026-08-03-kit-self-validation-v0.9.0-design.md`.

**Tech Stack:** Bash, python3 (both preinstalled on GitHub runners), GitHub Actions, markdown skills.

## Global Constraints

- Repo root: `~/Dev/agent-operating-kit`, branch `claude/kit-self-validation-v0.9.0`.
- NO AI attribution in commits — plain `git commit -m`.
- `templates/` payload is UNTOUCHED this release (CI is factory-only) — any diff under `templates/` is a defect.
- The script must exit 0 on the current repo (it is the release gate for its own release) and nonzero with a named failing check otherwise.
- Read files before editing; final plugin version `0.9.0` (bumped once, Task 5).

---

### Task 1: scripts/validate-kit.sh

**Files:**
- Create: `scripts/validate-kit.sh` (mode 755)

**Interfaces:**
- Produces: the seven named checks (`placeholders`, `line-budget`, `json`, `registry`, `inventory`, `tracker-folders`, `plugin-root-leak`); exit 0 iff all pass. Tasks 2, 5, 6 invoke it as `bash scripts/validate-kit.sh`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# validate-kit.sh — deterministic static release gate for the agent-operating-kit repo.
# Run from the repo root: bash scripts/validate-kit.sh
# Exit 0 = all checks pass. Each failure prints "FAIL [check] reason".
set -u
cd "$(dirname "$0")/.." || exit 2
fails=0
fail() { echo "FAIL [$1] $2"; fails=$((fails+1)); }
pass() { echo "ok   [$1]"; }

# ── 1. placeholders: every {{NAME}} used in templates/ must be in the maintained known-set
# (v1: maintained list — extend it when a template legitimately introduces a new placeholder)
KNOWN=" AREA_1 AREA_2 AREA_3 CONFLUENCE_SPACE_KEY CONVENTIONS_THAT_BITE DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION DEV_COMMAND_AND_PORTS DOCS_ISSUE_LOG_PATH DOCS_LOCATION ESCALATION_MODEL FRONTIER_MODEL JIRA_SITE_URL KIT_VERSION LABEL_SYNTAX_VERSION LANGUAGES_FRAMEWORKS_DATASTORES LEVELS MICRO_MODEL MONOREPO_OR_SINGLE ONE_PARAGRAPH_PROJECT_FACTS ONE_SENTENCE_DESCRIPTION OWNER_ORG_OR_PERSON PERIOD_DAYS PM_TOOL PROJECT_KEY PROJECT_KEY_OR_NA PROJECT_NAME SCOPE TEAM_KEY TEAM_NAME TRACKER_COORDINATES TRACKER_GUIDE_URL WORKER_MODEL "
unknown=""
for p in $(grep -rhoE '\{\{[A-Z_0-9]+' templates/ | sed 's/{{//' | sort -u); do
  case "$KNOWN" in *" $p "*) ;; *) unknown="$unknown $p";; esac
done
[ -z "$unknown" ] && pass placeholders || fail placeholders "unknown placeholder(s):$unknown"

# ── 2. line-budget: every templates/**/*.md ≤ 45 lines
over=""
while IFS= read -r f; do
  n=$(wc -l < "$f"); [ "$n" -gt 45 ] && over="$over $f($n)"
done < <(find templates -name '*.md' -type f)
[ -z "$over" ] && pass line-budget || fail line-budget "over 45 lines:$over (split into the cascade)"

# ── 3. json: manifests parse; plugin version is semver
ok=1
for j in .claude-plugin/*.json; do
  python3 -m json.tool "$j" > /dev/null 2>&1 || { fail json "$j does not parse"; ok=0; }
done
ver=$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "")
echo "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { fail json "plugin version '$ver' is not semver"; ok=0; }
[ "$ok" = 1 ] && pass json

# ── 4. registry: label-syntax H1 version equals newest changelog row
REG=templates/docs/agents/label-syntax.md
h1=$(head -1 "$REG" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tr -d v)
newest=$(grep -E '^\| [0-9]+\.[0-9]+\.[0-9]+ \|' "$REG" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -n "$h1" ] && [ "$h1" = "$newest" ] && pass registry || fail registry "H1 v$h1 != newest changelog row $newest"

# ── 5. inventory: README inventory block ↔ tracked templates/ files (by basename, both directions)
inv=$(awk '/^```$/{f=!f;next} f' README.md | grep -oE '[A-Za-z0-9._-]+\.(md|json)' | sort -u)
miss_repo=""; miss_inv=""
for f in $(git ls-files templates/); do
  b=$(basename "$f"); echo "$inv" | grep -qx "$b" || miss_inv="$miss_inv $b"
done
for b in $inv; do
  case "$b" in README.md|BOOTSTRAP.md) continue;; esac
  git ls-files templates/ | grep -q "/$b\$\|^templates/$b\$" || miss_repo="$miss_repo $b"
done
[ -z "$miss_inv" ] && [ -z "$miss_repo" ] && pass inventory || fail inventory "not in README:$miss_inv | in README but not tracked:$miss_repo"

# ── 6. tracker-folders: every templates/<tracker>/ ships the full required set
req="intake-structure-brief.md tracker-config.md stats-collection-brief.md"
bad=""
for d in templates/*/; do
  case "$d" in templates/docs/) continue;; esac
  for r in $req; do [ -f "$d$r" ] || bad="$bad $d$r"; done
done
[ -z "$bad" ] && pass tracker-folders || fail tracker-folders "missing:$bad"

# ── 7. plugin-root-leak: installed payload must be self-contained
if grep -rn 'CLAUDE_PLUGIN_ROOT' templates/ > /dev/null 2>&1; then
  fail plugin-root-leak "\${CLAUDE_PLUGIN_ROOT} found under templates/ (payload must be self-contained)"
else
  pass plugin-root-leak
fi

echo "----"
[ "$fails" -eq 0 ] && echo "validate-kit: ALL CHECKS PASSED" || echo "validate-kit: $fails check(s) FAILED"
exit "$((fails>0))"
```

- [ ] **Step 2: Make executable and run against the repo (must pass)**

Run: `chmod +x scripts/validate-kit.sh && bash scripts/validate-kit.sh`
Expected: seven `ok` lines, `ALL CHECKS PASSED`, exit 0. If any check fails on the CURRENT repo, the script's parsing is wrong (the repo passed this gate at v0.8.0) — fix the script, not the repo, unless the repo genuinely regressed.

- [ ] **Step 3: Negative test (each check must be able to fire)**

In a scratch copy (`cp -r` the repo to the scratchpad, work there): break each check one at a time and confirm the named check FAILs — (1) add `{{BOGUS_PLACEHOLDER}}` to a template; (2) pad a template past 45 lines; (3) set plugin version to `x.y`; (4) bump the registry H1 without a changelog row; (5) delete an inventory line from README; (6) remove `templates/jira/tracker-config.md`; (7) add `${CLAUDE_PLUGIN_ROOT}` to a template. Record all seven firings in your report. Delete the scratch copy afterward.

- [ ] **Step 4: Commit**

```bash
git add scripts/validate-kit.sh
git commit -m "feat: validate-kit.sh — seven-check static release gate"
```

---

### Task 2: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/validate.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: validate-kit
on:
  pull_request:
  push:
    branches: [main]
jobs:
  static-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run static release gate
        run: bash scripts/validate-kit.sh
```

- [ ] **Step 2: Verify**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/validate.yml'))" 2>/dev/null && echo yaml-ok || python3 -c "print('pyyaml missing — verify by eye: indentation, on: pull_request + push main, single job running the script')"`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/validate.yml
git commit -m "feat: CI gate — validate-kit.sh on PRs and main"
```

---

### Task 3: validate-kit skill

**Files:**
- Create: `skills/validate-kit/SKILL.md`

- [ ] **Step 1: Write the skill**

```markdown
---
name: validate-kit
description: Run the kit's full pre-release validation — the static check script plus the three agentic scratch-repo scenarios (fresh install, legacy upgrade, no-op re-run). Use before releasing a new kit version, or when the user asks to validate/test the kit or check the release gate.
---

# Validate the kit

1. **Static gate**: run `bash scripts/validate-kit.sh` from the repo root. Any FAIL stops here — fix before scenarios.
2. **Scenarios** — each in a throwaway git-initialized scratch repo (temp dir; delete afterward). Act as the installing/upgrading agent yourself, following the skills literally with `${CLAUDE_PLUGIN_ROOT}` = this repo root. Tracker steps run DRY: fill the briefs and show them, do not dispatch — unless the user names a sandbox tracker project.
   - (a) **Fresh install**: seed a minimal repo (README + one manifest), run `skills/install-agent-os/SKILL.md` with `pm_tool: none`, attribution default. Verify: `.docs/agents/` complete for the selection, CLAUDE.md placeholders all resolved, PROJECT-INFO frontmatter parses with every template key and real values, no `{{` and no `${CLAUDE_PLUGIN_ROOT}` in installed files.
   - (b) **Legacy upgrade**: fabricate a pre-0.7.0 shape (`docs/agents/` with old files, `found-by:*` in ticket-filing, no PROJECT-INFO), run `skills/upgrade-agent-os/SKILL.md`. Verify: files moved to `.docs/agents/`, references rewritten, frontmatter created and stamped, relabel sweep OFFERED not executed.
   - (c) **No-op**: re-run the upgrade flow on (a)'s result. Verify: clean `already at <version>` report, `git status --short` empty.
3. **Report**: static-gate result, per-scenario PASS/FAIL with the failed assertion and file diff when failing, and any judgment calls the skills forced (template wording gaps) — those are polish candidates, not blockers.
```

- [ ] **Step 2: Verify**

Run: `grep -c "validate-kit.sh" skills/validate-kit/SKILL.md && grep -c "scratch" skills/validate-kit/SKILL.md`
Expected: ≥ 1; ≥ 1.

- [ ] **Step 3: Commit**

```bash
git add skills/validate-kit/SKILL.md
git commit -m "feat: validate-kit skill — static gate + three agentic scratch scenarios"
```

---

### Task 4: BOOTSTRAP becomes a pointer + lockstep rule retired

**Files:**
- Modify: `BOOTSTRAP.md` (full rewrite), `CLAUDE.md` (repo)

- [ ] **Step 1: Rewrite BOOTSTRAP.md**

```markdown
# Bootstrap prompt

For environments without the Claude Code plugin. Paste everything below the line into a Claude session opened in the target project's repo root.

---

Install the Agent Operating Kit from its repo (clone or locate it first; default location `~/Dev/agent-operating-kit`): read `skills/install-agent-os/SKILL.md` in that repo and follow its steps exactly, treating every `${CLAUDE_PLUGIN_ROOT}` reference as the kit repo's root. From then on, operate by the installed CLAUDE.md's dispatch and lifecycle rules.
```

- [ ] **Step 2: Repo CLAUDE.md — retire the lockstep rule, reference the gate**

(a) In "How the kit works", replace `\`BOOTSTRAP.md\` is the same flow as a paste-able prompt for environments without the plugin. Keep the two in lockstep — any flow change edits BOTH.` with `\`BOOTSTRAP.md\` is a pointer prompt at the install skill for plugin-less environments — flow changes edit the skill ONLY.`
(b) In extension rule 2, change `add the tool to the skill's and BOOTSTRAP's selection lists.` to `add the tool to the skill's selection list.`
(c) Append a new extension rule: `8. **Every PR must pass \`scripts/validate-kit.sh\`** (CI runs it; run it locally before pushing). Extend the script's known-placeholder list when a template legitimately introduces a new placeholder — in the same PR.`

- [ ] **Step 3: Verify**

Run: `wc -l BOOTSTRAP.md && grep -c "lockstep" CLAUDE.md ; grep -c "validate-kit.sh" CLAUDE.md`
Expected: BOOTSTRAP ≤ 12 lines; lockstep 0 occurrences; validate-kit.sh ≥ 1.

- [ ] **Step 4: Commit**

```bash
git add BOOTSTRAP.md CLAUDE.md
git commit -m "feat: BOOTSTRAP is a pointer at the install skill; lockstep rule retired; CI gate rule added"
```

---

### Task 5: README + version bump + gate run

**Files:**
- Modify: `README.md`, `.claude-plugin/plugin.json`

- [ ] **Step 1: README**

- Skills paragraph: append `A fifth skill, **\`validate-kit\`**, runs the kit's own release gate — the static check script plus three agentic scratch-repo scenarios.`
- The manual-install section's closing line `Or paste \`BOOTSTRAP.md\` into a Claude session inside the new project — it performs all three steps interactively.` becomes `Or paste \`BOOTSTRAP.md\` into a Claude session — it is a pointer that walks the session through the install skill directly.`
- Inventory block: change the BOOTSTRAP line description to `pointer prompt at the install skill (plugin-less environments)`; add under the top-level entries (after the BOOTSTRAP line): `scripts/validate-kit.sh              seven-check static release gate (CI runs it on every PR)`.
- Contributor note: in the "Updating the plugin after repo changes" section, append a final line: `Contributors: every PR must pass \`bash scripts/validate-kit.sh\` — CI enforces it.`

- [ ] **Step 2: Version bump**

`.claude-plugin/plugin.json`: `"version": "0.8.0"` → `"version": "0.9.0"`.

- [ ] **Step 3: Gate run (hard gate — the release validates itself)**

Run: `bash scripts/validate-kit.sh`
Expected: ALL CHECKS PASSED, exit 0. (Check 5 must digest the new inventory lines; if it fails on them, fix the README lines' format, not the script.)

- [ ] **Step 4: Commit**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "feat: v0.9.0 — self-validation release (README, inventory, contributor gate note, version bump)"
```

---

### Task 6: Record validation

**Files:**
- Modify (append only): `docs/superpowers/specs/2026-08-03-kit-self-validation-v0.9.0-design.md`

- [ ] **Step 1**: Append a `## Validated` section: date; the seven-check pass on the release tree; the seven negative firings from Task 1 Step 3 (one line each); confirmation the templates/ payload is untouched this release (`git diff main..HEAD --stat -- templates/` empty); caveat that the agentic scenarios ship as the `validate-kit` skill and were exercised for v0.7.0 — a full re-run is deferred to the next release that touches install/upgrade flows.
- [ ] **Step 2**: Commit:

```bash
git add docs/superpowers/specs/2026-08-03-kit-self-validation-v0.9.0-design.md
git commit -m "docs: record v0.9.0 gate self-validation results"
```
