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
KNOWN=" AREA_1 AREA_2 AREA_3 CONFLUENCE_SPACE_KEY CONVENTIONS_THAT_BITE DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION DEV_COMMAND_AND_PORTS DOCS_ISSUE_LOG_PATH DOCS_LOCATION ESCALATION_MODEL FRONTIER_MODEL JIRA_SITE_URL KIT_VERSION LABEL_SYNTAX_VERSION LANGUAGES_FRAMEWORKS_DATASTORES LEVELS MICRO_MODEL MONOREPO_OR_SINGLE ONE_PARAGRAPH_PROJECT_FACTS ONE_SENTENCE_DESCRIPTION OWNER_ORG_OR_PERSON PERIOD_DAYS PM_TOOL PROJECT_KEY PROJECT_KEY_OR_NA PROJECT_NAME SCOPE TEAM_KEY TEAM_NAME TELEMETRY TRACKER_COORDINATES TRACKER_GUIDE_URL WORKER_MODEL "
unknown=""
for p in $(grep -rhoE '\{\{[A-Z_0-9]+' templates/ | sed 's/{{//' | sort -u); do
  case "$KNOWN" in *" $p "*) ;; *) unknown="$unknown $p";; esac
done
[ -z "$unknown" ] && pass placeholders || fail placeholders "unknown placeholder(s):$unknown"

# ── 2. line-budget: every templates/**/*.md ≤ 60 lines, CLAUDE.core.md ≤ 50
over=""
while IFS= read -r f; do
  lim=60; [ "$f" = "templates/CLAUDE.core.md" ] && lim=50
  n=$(wc -l < "$f"); [ "$n" -gt "$lim" ] && over="$over $f($n)"
done < <(find templates -name '*.md' -type f)
[ -z "$over" ] && pass line-budget || fail line-budget "over budget (60, CLAUDE.core.md 50):$over (split into the cascade)"

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
  git ls-files templates/ | grep -qE "/$b\$|^templates/$b\$" || miss_repo="$miss_repo $b"
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
