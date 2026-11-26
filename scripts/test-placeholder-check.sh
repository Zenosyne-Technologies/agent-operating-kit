#!/usr/bin/env bash
# test-placeholder-check.sh — behavioural tests for scripts/marvin-placeholder-check.sh (AOS-221).
# Pins: a fully rendered install (the REAL templates, rendered here) is clean; each unresolved form is named with
# its file and line; the by-design dispatch-time placeholders are allowed; runs/ and reports/ are out of scope;
# CLAUDE.md is in scope; only the kit-written set is scanned (never backups, run state or consumer-owned docs);
# every {{NAME…}} form is caught; the dispatch-time allowlist is exact and cannot drift; an unreadable file is exit 2,
# never a false clean; symlinks are never followed; usage errors exit 2; never writes. Mutations at the end.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd); ROOT="$SCRIPT_DIR/.."
SCRIPT="$SCRIPT_DIR/marvin-placeholder-check.sh"
INSTALL_SKILL="$ROOT/skills/install-agent-os/SKILL.md"; UPGRADE_SKILL="$ROOT/skills/upgrade-agent-os/SKILL.md"
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
  # as the install seeds them: three audience indexes from the one template, which itself never lands in a consumer
  for aud in developer user admin; do mkdir -p "$1/.docs/handbooks/$aud"; cp "$ROOT/templates/docs/handbooks/audience-index.md" "$1/.docs/handbooks/$aud/index.md"; done
  rm -f "$1/.docs/handbooks/audience-index.md"
  cp "$ROOT/templates/pm/jira/tracker-config.md" "$ROOT/templates/pm/jira/stats-collection-brief.md" "$1/.marvin/agents/"
  printf 'see @.marvin/CLAUDE.marvin.md\n' > "$1/CLAUDE.md"
  find "$1" -name '*.md' | while read -r f; do render_file "$f" > "$f.new" && mv "$f.new" "$f"; done
}
# every {{NAME…}} form (any text up to the closing braces) becomes x, except the two dispatch-time ones, kept as shipped
render_file() {  # render_file <file> -> stdout
  sed -E -e 's/\{\{(PERIOD_DAYS|SCOPE)([^}]*)\}\}/@@\1@@/g' -e 's/\{\{[A-Z][A-Z0-9_]*[^}]*\}\}/x/g' -e 's/@@(PERIOD_DAYS|SCOPE)@@/{{\1}}/g' "$1"
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
has "unresolved: .marvin/agents/tracker-config.md:"; lacks "{{PROJECT_KEY}"
# the output format is pinned: path:line:{{NAME, nothing after the name (the header comment says the same)
printf '%s\n' "$OUT" | grep -Eq '^unresolved: \.marvin/agents/tracker-config\.md:[0-9]+:\{\{PROJECT_KEY$' && ok "format: unresolved: <path>:<line>:{{NAME" || bad "format drifted: $OUT"
render "$P"; printf '\n- Repository layout: {{MONOREPO_OR_SINGLE + one-line top-level map}}\n' >> "$P/.marvin/PROJECT-INFO.md"
run "$P"; rc 1; has "unresolved: .marvin/PROJECT-INFO.md:"; has "{{MONOREPO_OR_SINGLE"; lacks "one-line"
# the real shipped template line, unrendered, is a hit (the form that once slipped through)
render "$P"; cp "$ROOT/templates/marvin/PROJECT-INFO.md" "$P/.marvin/PROJECT-INFO.md"; run "$P"; rc 1; has "{{MONOREPO_OR_SINGLE"

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

hd "P10 scope: only the kit-written set — never backups, run state or consumer-owned docs"
render "$P"; mkdir -p "$P/.marvin/backups/2026-10-30" "$P/.docs/project-management/issues"
printf 'old {{PROJECT_KEY}}\n' > "$P/.marvin/backups/2026-10-30/ticket-filing.md"
printf 'mine {{PROJECT_KEY}}\n' > "$P/.docs/project-management/issues/x.md"; printf 'mine {{PROJECT_KEY}}\n' > "$P/.docs/guide.md"
run "$P"; rc 0; empty
printf 'x {{INSTALL_DATE}}\n' >> "$P/.docs/index.md"; run "$P"; rc 1; has "unresolved: .docs/index.md:"; lacks "backups"; lacks "issues/x.md"; lacks "guide.md"
# the audience indexes are seeded from handbooks/audience-index.md as three files: all three are scanned
for a in developer user admin; do render "$P"; printf 'x {{INSTALL_DATE}}\n' >> "$P/.docs/handbooks/$a/index.md"; run "$P"; rc 1; has "unresolved: .docs/handbooks/$a/index.md:"; done
# the seeded set is derived from the plugin's own templates/docs, at depth too
nested=$(cd "$ROOT/templates/docs" && find . -mindepth 2 -type f | head -n 1 | sed 's|^\./||')
if [ -n "$nested" ]; then render "$P"; printf 'x {{INSTALL_DATE}}\n' >> "$P/.docs/$nested"; run "$P"; rc 1; has "unresolved: .docs/$nested:"; else ok "no nested seeded doc to pin (skipped)"; fi

hd "P11 the allowlist is exact: a longer name or another form still hits"
render "$P"; printf '\nw {{SCOPE_X}} v {{PERIOD_DAYS2}}\n' >> "$P/.marvin/agents/stats-collection-brief.md"
run "$P"; rc 1; has "{{SCOPE_X"; has "{{PERIOD_DAYS2"
render "$P"; printf '\nw {{SCOPE + extra}}\n' >> "$P/.marvin/agents/stats-collection-brief.md"; run "$P"; rc 1; has "{{SCOPE"

hd "P12 allowlist drift: what the briefs keep after install-time rendering equals the script's dispatch-time allowlist"
# install-time names = those the install resolves for the tracker briefs; anything else left over must be allowlisted
inst='INSTALL_DATE PROJECT_NAME PROJECT_KEY JIRA_SITE_URL GITHUB_REPO TEAM_KEY TEAM_NAME'
left=$(for f in "$ROOT"/templates/pm/*/stats-collection-brief.md; do
  render_file "$f" | cat; done | grep -oE '\{\{[A-Z][A-Z0-9_]*' | sort -u | tr -d '{' | tr '\n' ' ')
allow=$(grep -E "grep -vE ':\[0-9\]\+:" "$SCRIPT" | sed -E 's/.*\(([A-Z_|]+)\)\(.*/\1/' | tr '|' '\n' | sort -u | tr '\n' ' ')
[ "$left" = "$allow" ] && ok "kept placeholders = allowlist ($allow)" || bad "briefs keep [$left] but the script allows [$allow]"
unleft=$(for f in "$ROOT"/templates/pm/*/stats-collection-brief.md; do sed -E 's/\{\{(PERIOD_DAYS|SCOPE)([^}]*)\}\}//g' "$f"; done | grep -oE '\{\{[A-Z][A-Z0-9_]*' | tr -d '{' | sort -u)
for n in $unleft; do case " $inst " in *" $n "*) ok "install-time: $n";; *) bad "stats brief has $n: neither install-time ($inst) nor allowlisted";; esac; done

hd "P13 an unreadable file or folder is exit 2 with a one-line reason — never a clean 0"
if [ "$(id -u)" = 0 ]; then ok "running as root: chmod 000 cannot make a file unreadable (skipped)"; else
  render "$P"; printf 'x\n' > "$P/.marvin/agents/secret.md"; chmod 000 "$P/.marvin/agents/secret.md"
  OUT=$(bash "$SCRIPT" "$P" 2>"$WORK/err"); RC=$?; rc 2; empty
  [ "$(wc -l < "$WORK/err" | tr -d ' ')" = 1 ] && ok "one stderr line" || bad "stderr: $(cat "$WORK/err")"
  grep -q 'could not read' "$WORK/err" && ok "reason names the failure" || bad "no reason: $(cat "$WORK/err")"
  chmod 644 "$P/.marvin/agents/secret.md"
  render "$P"; mkdir -p "$P/.marvin/agents/d"; printf 'x\n' > "$P/.marvin/agents/d/a.md"; chmod 000 "$P/.marvin/agents/d"
  OUT=$(bash "$SCRIPT" "$P" 2>/dev/null); RC=$?; rc 2; chmod 755 "$P/.marvin/agents/d"
  render "$P"; printf 'x {{PROJECT_KEY}}\n' >> "$P/.marvin/agents/tracker-config.md"; printf 'x\n' > "$P/.marvin/agents/secret.md"; chmod 000 "$P/.marvin/agents/secret.md"
  OUT=$(bash "$SCRIPT" "$P" 2>/dev/null); RC=$?; rc 2; chmod 644 "$P/.marvin/agents/secret.md"   # hits do not mask the failure
fi

hd "P14 both skills call the script with an explicit . root"
calls_dot() { grep -Fq 'marvin-placeholder-check.sh" .' "$1"; }
calls_dot "$INSTALL_SKILL" && ok "install skill passes ." || bad "install skill lacks the explicit . root"
calls_dot "$UPGRADE_SKILL" && ok "upgrade skill passes ." || bad "upgrade skill lacks the explicit . root"

hd "P15 the script's audience list equals the skills' wording, and the template exists"
aud=$(grep -E '^AUDIENCES=' "$SCRIPT" | sed -E 's/^AUDIENCES="([^"]*)"/\1/' | tr ' ' ',')
[ -f "$ROOT/templates/docs/handbooks/audience-index.md" ] && ok "template handbooks/audience-index.md exists" || bad "template missing"
for sk in "$INSTALL_SKILL" "$UPGRADE_SKILL"; do
  grep -Fq ".docs/handbooks/{$aud}/" "$sk" && ok "$(basename "$(dirname "$sk")") names .docs/handbooks/{$aud}/" || bad "$sk does not name .docs/handbooks/{$aud}/ — the script's AUDIENCES drifted"
done

hd "P16 an unreadable templates/docs is exit 2 with a one-line reason — never a quietly narrower scan"
if [ "$(id -u)" = 0 ]; then ok "running as root (skipped)"; else
  d="$WORK/m-lsfail"; mkdir -p "$d/scripts"; cp "$SCRIPT" "$d/scripts/s.sh"; cp -R "$ROOT/templates" "$d/templates"
  render "$P"; chmod 000 "$d/templates/docs/handbooks/developer"
  OUT=$(bash "$d/scripts/s.sh" "$P" 2>"$WORK/err"); RC=$?; rc 2; empty
  grep -q 'could not list templates/docs' "$WORK/err" && ok "reason names the failure" || bad "no reason: $(cat "$WORK/err")"
  chmod 755 "$d/templates/docs/handbooks/developer"
fi

# ── mutations: break one line of the script in a copy; the named test must then fail ─────────────────
# The copy lives in $d/scripts/ beside a templates symlink, so its plugin-root derivation still finds templates/docs.
mutation() {  # mutation <name> <exact line> <replacement> <setup-fn> <expect: clean|hits|lost|exit2>
  local d="$WORK/m-$1"; mkdir -p "$d/scripts"; ln -sfn "$ROOT/templates" "$d/templates"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$SCRIPT" > "$d/scripts/s.sh"
  if cmp -s "$d/scripts/s.sh" "$SCRIPT"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  "$4"; S="$d/scripts/s.sh" run "$P"
  case "$5" in
    hits)  if [ "$RC" = 1 ]; then ok "mutation $1 caught"; else bad "mutation $1 survived"; fi ;;   # original clean here
    clean) if [ "$RC" = 0 ]; then ok "mutation $1 caught"; else bad "mutation $1 survived"; fi ;;   # original reports hits here
    lost)  if [ "$RC" = 0 ]; then ok "mutation $1 caught"; else bad "mutation $1 survived"; fi ;;   # original reports hits here; the mutant must exit 0 exactly (a mutant that merely errs is no catch)
    exit2) if [ "$RC" != 2 ]; then ok "mutation $1 caught"; else bad "mutation $1 survived"; fi ;;  # original fails the check here
  esac
}
s_allow()  { render "$P"; printf '\nw {{PERIOD_DAYS}}\n' >> "$P/.marvin/agents/stats-collection-brief.md"; }
s_colon()  { render "$P"; printf '\n- {{TRACKER_COORDINATES: x}}\n' >> "$P/.marvin/agents/ticket-filing.md"; }
s_plus()   { render "$P"; printf '\n- {{MONOREPO_OR_SINGLE + map}}\n' >> "$P/.marvin/PROJECT-INFO.md"; }
s_runs()   { render "$P"; mkdir -p "$P/.marvin/runs/s"; printf '{{PROJECT_KEY}}\n' > "$P/.marvin/runs/s/l.md"; }
s_back()   { render "$P"; mkdir -p "$P/.marvin/backups/d"; printf '{{PROJECT_KEY}}\n' > "$P/.marvin/backups/d/l.md"; }
s_claude() { render "$P"; printf '{{PROJECT_NAME}}\n' >> "$P/CLAUDE.md"; }
s_link()   { render "$P"; printf 'o {{PROJECT_KEY}}\n' > "$WORK/outside.md"; ln -sf "$WORK/outside.md" "$P/.marvin/agents/link.md"; }
s_owned()  { render "$P"; mkdir -p "$P/.docs/project-management/issues"; printf '{{PROJECT_KEY}}\n' > "$P/.docs/project-management/issues/x.md"; }
s_seeded() { render "$P"; printf 'x {{INSTALL_DATE}}\n' >> "$P/.docs/index.md"; }
s_term()   { render "$P"; printf '\nw {{SCOPE_X}}\n' >> "$P/.marvin/agents/stats-collection-brief.md"; }
s_unread() { render "$P"; printf 'x\n' > "$P/.marvin/agents/secret.md"; chmod 000 "$P/.marvin/agents/secret.md"; }
s_aud()    { render "$P"; printf 'x {{INSTALL_DATE}}\n' >> "$P/.docs/handbooks/developer/index.md"; }
s_lsfail() { render "$P"; local d="$WORK/m-lsfail"; rm -rf "$d/templates"; cp -R "$ROOT/templates" "$d/templates"; chmod 000 "$d/templates/docs/handbooks/developer"; }
# target lines are read from the script itself (exact), then edited with a literal first-occurrence replace
ed() { S="$1" A="$2" B="$3" awk 'BEGIN{s=ENVIRON["S"];a=ENVIRON["A"];i=index(s,a); if(i) s=substr(s,1,i-1) ENVIRON["B"] substr(s,i+length(a)); print s}'; }
L_ALLOW=$(grep -F "grep -vE ':[0-9]+:" "$SCRIPT"); L_GREP=$(grep -F "xargs -0 grep -noE" "$SCRIPT"); L_FIND=$(grep -F 'find .marvin' "$SCRIPT")
L_DOCS=$(grep -F 'find .docs' "$SCRIPT"); L_CLAUDE=$(grep -F "printf 'CLAUDE.md" "$SCRIPT"); L_BAD=$(grep -F 'if [ -n "$bad" ]' "$SCRIPT")
L_AUD=$(grep -F 'handbooks/audience-index.md)' "$SCRIPT"); L_LS=$(grep -F "could not list templates/docs" "$SCRIPT")
hd "M1 allowlist dropped — P3 must catch it"
mutation allow "$L_ALLOW" "  | cat \\" s_allow hits
hd "M2 only {{NAME}} / {{NAME: matched, or only {{NAME}} — P2 must catch the {{NAME + …}} and : forms"
# realistic mutants: each drops ONE form and must exit 0 on its own fixture (not a bad-line exit 2)
mutation plus "$L_GREP" "$(ed "$L_GREP" '[^A-Za-z0-9_]|$)' '[}:]|$)')" s_plus lost
mutation colon "$L_GREP" "$(ed "$L_GREP" '[^A-Za-z0-9_]|$)' '[^A-Za-z0-9_:]|$)')" s_colon lost
hd "M3 runs/ and reports/ scanned — P4 must catch it"
mutation runs "$L_FIND" "$(ed "$L_FIND" '-path .marvin/runs -o ' '')" s_runs hits
hd "M3b backups/ scanned — P10 must catch it"
mutation backups "$L_FIND" "$(ed "$L_FIND" ' -o -path .marvin/backups' '')" s_back hits
hd "M4 CLAUDE.md no longer scanned — P5 must catch it"
mutation claude "$L_CLAUDE" "  :" s_claude clean
hd "M5 symlinked files read as files — P6 must catch it"
mutation link "$L_FIND" "$(ed "$L_FIND" '-type f' '\( -type f -o -type l \)')" s_link hits
# (a symlinked .marvin is refused twice — by the [ -L ] guard and by find, which never descends into a symlink; the
# guard alone is an equivalent mutant, so it has no row.)
hd "M6 every .docs/ file scanned, not just the seeded set — P10 must catch it"
mutation owned "$L_DOCS" '  if [ -d .docs ] && [ ! -L .docs ]; then find .docs -type f -print0; fi' s_owned hits
hd "M7 .docs/ dropped altogether — P5 must catch it"
mutation docs "$L_DOCS" '  :' s_seeded clean
hd "M8 allowlist terminator dropped (a longer name is allowed) — P11 must catch it"
mutation term "$L_ALLOW" "$(ed "$L_ALLOW" '(\}|:)$' '')" s_term clean
hd "M9 read failures swallowed — P13 must catch it"
mutation swallow "$L_GREP" "$(ed "$L_GREP" '2>&1' '2>/dev/null')" s_unread exit2
mutation nobad "$L_BAD" ':' s_unread exit2
hd "M9b audience indexes unmapped (the template path is scanned instead) — P10 must catch it"
mutation audience "$L_AUD" "$(ed "$L_AUD" 'handbooks/audience-index.md)' 'handbooks/audience-index.md-never)')" s_aud clean
hd "M9c the templates/docs listing failure ignored — P16 must catch it"
mutation lsfail "$L_LS" "  || :" s_lsfail exit2
hd "M10 a skill without the explicit . root fails P14's check"
printf 'run bash "${CLAUDE_PLUGIN_ROOT}/scripts/marvin-placeholder-check.sh" from the repo root\n' > "$WORK/skill-mut.md"
calls_dot "$WORK/skill-mut.md" && bad "mutation skill-root survived" || ok "mutation skill-root caught"
if [ "$(id -u)" = 0 ]; then :; else chmod 755 "$WORK/m-lsfail/templates/docs/handbooks/developer" 2>/dev/null; chmod 644 "$P/.marvin/agents/secret.md" 2>/dev/null; fi

printf '\n----\ntest-placeholder-check: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
