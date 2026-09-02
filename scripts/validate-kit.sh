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
KNOWN=" APP_TYPE AREA_1 AREA_2 AREA_3 AUDIENCE CONFLUENCE_SPACE_KEY CONVENTIONS_THAT_BITE DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION DEV_COMMAND_AND_PORTS DOCS_ISSUE_LOG_PATH DOCS_LOCATION ESCALATION_MODEL FRONTIER_MODEL GITHUB_REPO INSTALL_DATE JIRA_SITE_URL KIT_VERSION LABEL_SYNTAX_VERSION LANGUAGES_FRAMEWORKS_DATASTORES LEVELS MICRO_MODEL MONOREPO_OR_SINGLE ONE_PARAGRAPH_PROJECT_FACTS ONE_SENTENCE_DESCRIPTION OWNER_ORG_OR_PERSON PERIOD_DAYS PM_TOOL PROJECT_KEY PROJECT_KEY_OR_NA PROJECT_NAME PROJECT_SIZE SCOPE TEAM_KEY TEAM_NAME TELEMETRY TRACKER_COORDINATES TRACKER_GUIDE_URL WORKER_MODEL "
unknown=""
for p in $(grep -rhoE '\{\{[A-Z_0-9]+' templates/ | sed 's/{{//' | sort -u); do
  case "$KNOWN" in *" $p "*) ;; *) unknown="$unknown $p";; esac
done
[ -z "$unknown" ] && pass placeholders || fail placeholders "unknown placeholder(s):$unknown"

# ── 2. line-budget: every templates/**/*.md ≤ 60 lines, CLAUDE.core.md ≤ 55
over=""
while IFS= read -r f; do
  lim=60; [ "$f" = "templates/CLAUDE.core.md" ] && lim=55
  n=$(wc -l < "$f"); [ "$n" -gt "$lim" ] && over="$over $f($n)"
done < <(find templates -name '*.md' -type f)
[ -z "$over" ] && pass line-budget || fail line-budget "over budget (60, CLAUDE.core.md 55):$over (split into the cascade)"

# ── 3. json: manifests parse; plugin version is semver
ok=1
for j in .claude-plugin/*.json; do
  python3 -m json.tool "$j" > /dev/null 2>&1 || { fail json "$j does not parse"; ok=0; }
done
ver=$(python3 -c "import json;print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "")
echo "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { fail json "plugin version '$ver' is not semver"; ok=0; }
[ "$ok" = 1 ] && pass json

# ── 4. registry: label-syntax H1 version equals newest changelog row
REG=templates/marvin/agents/label-syntax.md
# the H1 is no longer line 1 — a reduced document header precedes it (document-standard.md)
h1=$(grep -m1 '^# ' "$REG" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tr -d v)
newest=$(grep -E '^\| [0-9]+\.[0-9]+\.[0-9]+ \|' "$REG" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -n "$h1" ] && [ "$h1" = "$newest" ] && pass registry || fail registry "H1 v$h1 != newest changelog row $newest"

# ── 5. inventory: README inventory block ↔ tracked templates/ files (by basename, both directions)
# basenames are .md/.json OR an extensionless kit file the payload legitimately ships (LICENSE)
inv=$(awk '
  /^## Inventory$/ { inventory=1; next }
  inventory && /^```$/ { if (!fence) { fence=1; next }; exit }
  inventory && fence { print }
' README.md | grep -oE '[A-Za-z0-9._-]+\.(md|json)|LICENSE' | sort -u)
miss_repo=""; miss_inv=""
for f in $(git ls-files templates/); do
  b=$(basename "$f"); echo "$inv" | grep -qx "$b" || miss_inv="$miss_inv $b"
done
for b in $inv; do
  case "$b" in README.md|BOOTSTRAP.md) continue;; esac
  git ls-files templates/ | grep -qE "/$b\$|^templates/$b\$" || miss_repo="$miss_repo $b"
done
[ -z "$miss_inv" ] && [ -z "$miss_repo" ] && pass inventory || fail inventory "not in README:$miss_inv | in README but not tracked:$miss_repo"

# ── 6. tracker-folders: every templates/pm/<tracker>/ ships the full required set
req="intake-structure-brief.md tracker-config.md stats-collection-brief.md"
bad=""
for d in templates/pm/*/; do
  [ -d "$d" ] || continue                       # skip non-directories (e.g. templates/pm/INSTALL.md)
  for r in $req; do [ -f "$d$r" ] || bad="$bad $d$r"; done
done
[ -z "$bad" ] && pass tracker-folders || fail tracker-folders "missing:$bad"

# ── 7. plugin-root-leak: installed payload must be self-contained
if grep -rn 'CLAUDE_PLUGIN_ROOT' templates/ > /dev/null 2>&1; then
  fail plugin-root-leak "\${CLAUDE_PLUGIN_ROOT} found under templates/ (payload must be self-contained)"
else
  pass plugin-root-leak
fi

# ── 8. upgrade-files: the current version's upgrades/v<version>.md must exist
[ -f "upgrades/v$ver.md" ] && pass upgrade-files || fail upgrade-files "upgrades/v$ver.md missing (add it — see CLAUDE.md extension rule 9)"

# ── 9. doc-headers: every consumer-bound template document carries its standard's header keys
# (templates/marvin/agents/document-standard.md — full under templates/docs/, reduced for the cascade)
FULL_KEYS="doc type status summary keywords level created updated"
RED_KEYS="doc type status summary updated"
# Headerless by exception, listed one exact path at a time: files with their own machine format,
# and briefs that are dispatched from the plugin rather than installed. EVERY other templates/**/*.md
# is treated as consumer-bound and MUST carry a header — a new file is classified here deliberately
# or it fails (extension rule 2 adds per-tracker files; extend this list in the same PR).
NOHDR=" templates/CLAUDE.core.md templates/marvin/PROJECT-INFO.md templates/marvin/MEMORY.md templates/pm/INSTALL.md templates/pm/github/intake-structure-brief.md templates/pm/jira/intake-structure-brief.md templates/pm/linear/intake-structure-brief.md templates/pm/local/intake-structure-brief.md "
missing=""
while IFS= read -r f; do
  case "$NOHDR" in *" $f "*) continue;; esac
  # default is the reduced header: anything consumer-bound that is not a .docs/ document
  case "$f" in
    templates/docs/*) keys="$FULL_KEYS";;
    *) keys="$RED_KEYS";;
  esac
  if [ "$(head -1 "$f")" != "---" ]; then missing="$missing $f(no-header)"; continue; fi
  hdr=$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")
  for k in $keys; do
    printf '%s\n' "$hdr" | grep -qE "^$k:" || missing="$missing $f($k)"
  done
done < <(find templates -name '*.md' -type f | sort)
[ -z "$missing" ] && pass doc-headers || fail doc-headers "missing header key(s):$missing"

# ── 10. release-note: this repo runs its own payload's release cut, so the current version
# owes docs/release-notes/v<version>.md — the text the annotated tag carries (git-strategy.md,
# cut step 4). Its scope: header is what release-scoped rollups resolve against, so an empty
# one is not a complete note (templates/docs/release-notes/index.md).
RN="docs/release-notes/v$ver.md"
if [ ! -f "$RN" ]; then
  fail release-note "$RN missing (the release cut writes it — templates/marvin/agents/git-strategy.md step 4)"
elif [ "$(head -1 "$RN")" != "---" ]; then
  fail release-note "$RN has no YAML header"
else
  rnhdr=$(awk 'NR==1{next} /^---$/{exit} {print}' "$RN")
  rnbad=""
  printf '%s\n' "$rnhdr" | grep -qE '^type: *release-note *$' || rnbad="$rnbad type:(must be release-note)"
  # scope: may be a flow list on one line or a block list on the lines under it — either way it
  # must resolve to at least one issue key; anything less is a note a release rollup cannot use.
  scopeval=$(printf '%s\n' "$rnhdr" | awk '/^scope:/{s=1;print;next} s&&/^[a-z_]+:/{exit} s{print}')
  printf '%s\n' "$scopeval" | grep -qE '[A-Z][A-Z0-9]*-[0-9]+' \
    || rnbad="$rnbad scope:(missing or empty — derive it per git-strategy.md cut step 4)"
  [ -z "$rnbad" ] && pass release-note || fail release-note "$RN:$rnbad"
fi

# ── 11. docs-self-contained: the .docs/ estate is tool-agnostic and must ship without Marvin,
# so nothing under templates/docs/ may reference .marvin/ or name the orchestrator. The dependency
# runs ONE WAY (.marvin → .docs); an agent reaches the document standard via the cascade, not via a
# pointer embedded in a doc (templates/marvin/agents/document-standard.md). {{...}} placeholders are
# fine — only .marvin and the word Marvin are forbidden.
hits=$(grep -rnE '\.marvin|\bMarvin\b' templates/docs/ 2>/dev/null)
if [ -z "$hits" ]; then
  pass docs-self-contained
else
  fail docs-self-contained "templates/docs/ must not reference .marvin or name Marvin:"
  printf '%s\n' "$hits" | sed 's/^/       /'
fi

# ── 12. no-local-paths: no tracked file may embed a contributor's local home path
# (/Users/<name>, /home/<name>); the intended doc placeholders /Users/me and /home/user are
# allowed. Keeps a local username out of the published repo. Scans the WHOLE repo, not just
# templates/, and excludes this script (which necessarily names the patterns).
lp=$(git grep -hoIE '/(Users|home)/[A-Za-z0-9._-]+' -- . ':(exclude)scripts/validate-kit.sh' 2>/dev/null \
  | grep -vxE '/Users/me|/home/user' | sort -u)
if [ -z "$lp" ]; then
  pass no-local-paths
else
  fail no-local-paths "local home path(s) in tracked files (use ~ or the /Users/me placeholder):"
  printf '%s\n' "$lp" | sed 's/^/       /'
fi

echo "----"
[ "$fails" -eq 0 ] && echo "validate-kit: ALL CHECKS PASSED" || echo "validate-kit: $fails check(s) FAILED"
exit "$((fails>0))"
