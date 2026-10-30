#!/usr/bin/env bash
# test-placeholder-check.sh — behavioural tests for scripts/marvin-placeholder-check.sh (AOS-221).
# Pins: a fully rendered install (the REAL templates, rendered here) is clean; each unresolved form is named with
# its file and line; the by-design dispatch-time placeholders are allowed; runs/ and reports/ are out of scope;
# CLAUDE.md is in scope; symlinks are never followed; usage errors exit 2; never writes. Mutations at the end.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd); ROOT="$SCRIPT_DIR/.."
SCRIPT="$SCRIPT_DIR/marvin-placeholder-check.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-phtest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
run() { OUT=$(bash "${S:-$SCRIPT}" "$@" 2>&1); RC=$?; }
rc()  { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1 ($OUT)"; fi; }
has() { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "has: $1"; else bad "missing: $1 (got: $OUT)"; fi; }
lacks() { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "unexpected: $1"; else ok "lacks: $1"; fi; }
empty() { if [ -z "$OUT" ]; then ok "no output"; else bad "output: $OUT"; fi; }

# render: the real templates, every install-time placeholder replaced; the dispatch-time ones left as shipped.
render() {  # render <project dir>
  rm -rf "$1"; mkdir -p "$1/.marvin" "$1/.docs"
  cp -R "$ROOT/templates/marvin/." "$1/.marvin/"; cp -R "$ROOT/templates/docs/." "$1/.docs/"
  cp "$ROOT/templates/pm/jira/tracker-config.md" "$ROOT/templates/pm/jira/stats-collection-brief.md" "$1/.marvin/agents/"
  printf 'see @.marvin/CLAUDE.marvin.md\n' > "$1/CLAUDE.md"
  find "$1" -name '*.md' | while read -r f; do
    sed -E -e 's/\{\{(PERIOD_DAYS|SCOPE)([^}]*)\}\}/@@\1@@/g' -e 's/\{\{[A-Z][A-Z0-9_]*(:[^}]*)?\}\}/x/g' -e 's/@@(PERIOD_DAYS|SCOPE)@@/{{\1}}/g' "$f" > "$f.new" && mv "$f.new" "$f"
  done
}
P="$WORK/p"

hd "P1 a fully rendered install is clean — silent, exit 0"
render "$P"; run "$P"; rc 0; empty
grep -rq '{{PERIOD_DAYS}}' "$P/.marvin/agents/stats-collection-brief.md" && ok "the fixture keeps the dispatch-time placeholder" || bad "fixture lost {{PERIOD_DAYS}}"

hd "P2 each unresolved form is named with file and line"
render "$P"
printf '\nauthority {{TRACKER_GUIDE_URL}}\n' >> "$P/.marvin/agents/ticket-filing.md"
printf '\n- {{TRACKER_COORDINATES: Jira → site URL + project key}}\n' >> "$P/.marvin/agents/ticket-filing.md"
printf '\nproject {{PROJECT_KEY}}\n' >> "$P/.marvin/agents/tracker-config.md"
run "$P"; rc 1
has "unresolved: .marvin/agents/ticket-filing.md:"; has "{{TRACKER_GUIDE_URL"; has "{{TRACKER_COORDINATES"
has "unresolved: .marvin/agents/tracker-config.md:"; has "{{PROJECT_KEY"
lacks "}}"; lacks "Jira"

hd "P3 dispatch-time placeholders alone are allowed, in both forms"
render "$P"; printf '\nwindow {{PERIOD_DAYS}} scope {{SCOPE: "project" | "milestone:<slug>"}}\n' >> "$P/.marvin/agents/stats-collection-brief.md"
run "$P"; rc 0; empty

hd "P4 runs/ and reports/ are out of scope"
render "$P"; mkdir -p "$P/.marvin/runs/s/K-1" "$P/.marvin/reports"
printf 'quoted {{PROJECT_KEY}}\n' > "$P/.marvin/runs/s/K-1/ledger.md"; printf 'left {{TRACKER_GUIDE_URL}}\n' > "$P/.marvin/reports/2026-10-30-install.md"
run "$P"; rc 0; empty

hd "P5 CLAUDE.md and .docs/ are in scope"
render "$P"; printf '{{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION}}\n' >> "$P/CLAUDE.md"; printf 'x {{INSTALL_DATE}}\n' >> "$P/.docs/index.md"
run "$P"; rc 1; has "unresolved: CLAUDE.md:"; has "{{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION"; has "unresolved: .docs/index.md:"

hd "P6 a symlinked file or folder is never followed"
render "$P"; printf 'out {{PROJECT_KEY}}\n' > "$WORK/outside.md"; ln -s "$WORK/outside.md" "$P/.marvin/agents/link.md"
mkdir -p "$WORK/outdir"; printf 'out {{PROJECT_KEY}}\n' > "$WORK/outdir/a.md"; ln -s "$WORK/outdir" "$P/.marvin/linkdir"
run "$P"; rc 0; empty
render "$P"; rm -rf "$P/.marvin"; ln -s "$WORK/outdir" "$P/.marvin"; run "$P"; rc 0; empty   # only .docs and CLAUDE.md are scanned

hd "P7 usage errors: no kit files, a missing root, too many arguments — exit 2, stdout empty"
mkdir -p "$WORK/bare"; OUT=$(bash "$SCRIPT" "$WORK/bare" 2>/dev/null); RC=$?; rc 2; empty
OUT=$(bash "$SCRIPT" "$WORK/none" 2>/dev/null); RC=$?; rc 2; empty
OUT=$(bash "$SCRIPT" a b 2>/dev/null); RC=$?; rc 2; empty

hd "P8 the root defaults to CLAUDE_PROJECT_DIR; odd bytes in a path are not echoed raw"
render "$P"; printf 'p {{PROJECT_KEY}}\n' > "$P/.marvin/agents/$(printf 'bad\001name').md"
OUT=$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT" 2>&1); RC=$?; rc 1; has "bad?name.md"

hd "P9 never writes"
render "$P"; printf 'x {{PROJECT_KEY}}\n' >> "$P/.marvin/agents/tracker-config.md"
b=$(find "$P" -exec ls -ldn {} + 2>/dev/null | sort | cksum); run "$P"; a=$(find "$P" -exec ls -ldn {} + 2>/dev/null | sort | cksum)
[ "$a" = "$b" ] && ok "tree unchanged" || bad "the script wrote something"

# ── mutations: break one line of the script in a copy; the named test must then fail ─────────────────
mutation() {  # mutation <name> <exact line> <replacement> <setup-fn> <expect: clean|hits>
  local d="$WORK/m-$1"; mkdir -p "$d"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$SCRIPT" > "$d/s.sh"
  if cmp -s "$d/s.sh" "$SCRIPT"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  "$4"; S="$d/s.sh" run "$P"
  if [ "$5" = hits ]; then   # the original is clean here; a caught mutant reports hits
    if [ "$RC" = 1 ]; then ok "mutation $1 caught"; else bad "mutation $1 survived"; fi
  else                       # the original reports hits here; a caught mutant goes clean
    if [ "$RC" = 0 ]; then ok "mutation $1 caught"; else bad "mutation $1 survived"; fi
  fi
}
s_allow()  { render "$P"; printf '\nw {{PERIOD_DAYS}}\n' >> "$P/.marvin/agents/stats-collection-brief.md"; }
s_colon()  { render "$P"; printf '\n- {{TRACKER_COORDINATES: x}}\n' >> "$P/.marvin/agents/ticket-filing.md"; }
s_runs()   { render "$P"; mkdir -p "$P/.marvin/runs/s"; printf '{{PROJECT_KEY}}\n' > "$P/.marvin/runs/s/l.md"; }
s_claude() { render "$P"; printf '{{PROJECT_NAME}}\n' >> "$P/CLAUDE.md"; }
s_link()   { render "$P"; printf 'o {{PROJECT_KEY}}\n' > "$WORK/outside.md"; ln -sf "$WORK/outside.md" "$P/.marvin/agents/link.md"; }
hd "M1 allowlist dropped — P3 must catch it"
mutation allow "  | LC_ALL=C grep -vE ':\\{\\{(PERIOD_DAYS|SCOPE)(\\}\\}|:)\$' \\" "  | cat \\" s_allow hits
hd "M2 the {{NAME: …}} form no longer matched — P2 must catch it"
mutation colon "  | LC_ALL=C xargs -0 grep -noE '\\{\\{[A-Z][A-Z0-9_]*(\\}\\}|:)' /dev/null 2>/dev/null \\" "  | LC_ALL=C xargs -0 grep -noE '\\{\\{[A-Z][A-Z0-9_]*\\}\\}' /dev/null 2>/dev/null \\" s_colon clean
hd "M3 runs/ and reports/ scanned — P4 must catch it"
mutation runs "hits=\$(find \$targets \\( -path .marvin/runs -o -path .marvin/reports \\) -prune -o -type f -print0 2>/dev/null \\" "hits=\$(find \$targets -type f -print0 2>/dev/null \\" s_runs hits
hd "M4 CLAUDE.md no longer scanned — P5 must catch it"
mutation claude "for t in .marvin .docs CLAUDE.md; do [ -e \"\$t\" ] && [ ! -L \"\$t\" ] && targets=\"\$targets \$t\"; done" "for t in .marvin .docs; do [ -e \"\$t\" ] && [ ! -L \"\$t\" ] && targets=\"\$targets \$t\"; done" s_claude clean
hd "M5 symlinked files read as files — P6 must catch it"
mutation link "hits=\$(find \$targets \\( -path .marvin/runs -o -path .marvin/reports \\) -prune -o -type f -print0 2>/dev/null \\" "hits=\$(find \$targets \\( -path .marvin/runs -o -path .marvin/reports \\) -prune -o \\( -type f -o -type l \\) -print0 2>/dev/null \\" s_link hits
# (a symlinked .marvin is refused twice — by the [ -L ] guard and by find, which never descends into a symlink; the
# guard alone is an equivalent mutant, so it has no row.)

printf '\n----\ntest-placeholder-check: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
