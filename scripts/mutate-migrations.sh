#!/usr/bin/env bash
# mutate-migrations.sh — mutation harness for scripts/test-migrations.sh.
#
# A green test suite proves nothing about the guards it claims to pin: an assertion that cannot
# fail is indistinguishable from one that passes. This harness reverts ONE mechanic at a time in
# a COPY of the migration script under test, runs that script's suite against the mutant
# (`test-migrations.sh --only <version>`), and requires that the fixture named for that mechanic
# FAILS. A mutation the suite survives is a hole.
#
# The script under test is a parameter: each migration script has its own mutation table below
# (`table_for <version>`), and `--script migrate-v<version>.sh` selects one. Without it, every
# table runs.
#
# Usage:
#   bash scripts/mutate-migrations.sh                                  # every table, 4 at a time
#   bash scripts/mutate-migrations.sh --script migrate-v0.35.0.sh      # one script's table
#   bash scripts/mutate-migrations.sh --script migrate-v0.21.0.sh no-mkdir glob-pathspec
#   bash scripts/mutate-migrations.sh [--script <file>] --list
#   PARALLEL=1 bash scripts/mutate-migrations.sh # serialise (timing fixtures are load-sensitive)
#
# Not wired into CI: a full sweep runs a suite once per mutation. Run it when a migration script
# or its guards change, and quote the result in the change's evidence.
# Exit 0 = every selected mutation was caught by its named fixture.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_SUITE="$SCRIPT_DIR/test-migrations.sh"
PARALLEL=${PARALLEL:-4}
VERSIONS="0.21.0 0.35.0"

# name | fixture that must fail | perl -0 expression reverting one mechanic
MUTATIONS_0_21_0='
no-mkdir|T01|s/^  mkdir_tracked \.marvin\n//m; s/^  mkdir_tracked \.marvin\/agents\n//m; s/^    mkdir_tracked "\$\(dirname "\$dst"\)"\n//m
mkdir-recorded-late|T27|s/^  MUTATED=1\n  CREATED_DIRS\[\$\{#CREATED_DIRS\[\@\]\}\]="\$d"\n  mkdir -p "\$d"/  MUTATED=1\n  mkdir -p "\$d"\n  sleep 0.6\n  CREATED_DIRS[\${#CREATED_DIRS[\@]}]="\$d"/m
disk-guard-on-case|T02S|s/^dst_occupied_case\(\) \{ tracked_exact "\$1"; \}/dst_occupied_case() { tracked_exact "\$1" || [ -e "\$1" ]; }/m
index-only-dst-guard|T02S|s/^dst_occupied_real\(\) \{ tracked_exact "\$1" \|\| \[ -e "\$1" \]; \}/dst_occupied_real() { tracked_exact "\$1"; }/m
no-resume-marker|T03|s/^    if tracked_exact "\$dir\/__index\.tmp"; then from="__index\.tmp"; fi\n//m
resume-ref-is-tmp|T03|s#\$\{CASE_DIR\[\$i\]\}/INDEX\.md#\${CASE_DIR[\$i]}/\${CASE_FROM[\$i]}#
rmdir-not-besteffort|T04|s/if \[ -d "\$d" \]; then rmdir "\$d" 2>\/dev\/null \|\| true; fi/if [ -d "\$d" ]; then rmdir "\$d"; fi/
no-clean-tree-guard|T07|s/^if \[ -n "\$DIRTY" \]; then\n  say "REFUSED/if false; then\n  say "REFUSED/m
no-allowlist|T08|s/^      if in_cascade "\$base"; then/      if true; then/m
jira-file-stranded|T12|s/^convert-milestones-brief\.md\n//m
glob-pathspec|T23|s/^lit\(\) \{ printf .:\(literal\)%s. "\$1"; \}/lit() { printf "%s" "\$1"; }/m
bare-handbook-glob|TM1|s/:\(glob\)\.docs\/handbooks\/\*\/INDEX\.md/.docs\/handbooks\/*\/INDEX.md/
staging-sweep|T09|s/^  git add -f -- "\$\{ADDARGS\[\@\]\}"/  git add -f -A/m
no-symlink-refusal|T24|s/^safety_checks\(\) \{/safety_checks() { return 0;/m
no-rollback-trap|T27|s/^trap rollback EXIT INT TERM HUP\n//m
no-dual-root-detect|T21|s/^  prev=\$\(planned_dst_source "\$dst"\)/  prev=""/m
no-repo-state-check|TP1|s/^repo_state_checks\(\) \{/repo_state_checks() { return 0;/m
state-misses-assume-unchanged|TP1|s#\[abcdefghijklmnopqrstuvwxyz\]\) state_problem "assume-unchanged#[Z]) state_problem "assume-unchanged#
state-misses-merge|TP2|s/for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do/for f in NOTHING_AT_ALL; do/
no-submodule-dirty|TP5|s/    sub=\$\(git status --porcelain --ignore-submodules=none 2>\/dev\/null \|\| true\)/    sub=""/
no-submodule-recurse|TP5|s/\[ "\$\(git config --bool submodule\.recurse 2>\/dev\/null \|\| echo false\)" = "true" \] &&\n      state_problem/[ "false" = "true" ] \&\&\n      state_problem/s
script-commits|T11|s/^say "moved and staged/git commit -q -m "chore: migrate" || true\nsay "moved and staged/m
check-count-lies|TR1|s/^  echo "renamed=\$\(\( \$\{#MOVE_SRC\[\@\]\} \+ \$\{#CASE_DIR\[\@\]\} \)\)"/  if [ "\$MODE" = "check" ]; then echo "renamed=99"; else echo "renamed=\$(( \${#MOVE_SRC[\@]} + \${#CASE_DIR[\@]} ))"; fi/m
check-skips-liveness|TR2|s/^dir_will_empty\(\) \{\n  local d="\$1" e i found\n  \[ -d "\$d" \] \|\| return 1/dir_will_empty() {\n  local d="\$1" e i found\n  [ "\$MODE" = "check" ] \&\& return 0\n  [ -d "\$d" ] || return 1/m
rollback-keeps-map|T27|s/^  clear_move_map\n  report rolled-back/  report rolled-back/m
refusal-keeps-map|TM4|s/^  clear_move_map\n  report dirty-refused/  report dirty-refused/m
symlink-refusal-keeps-map|T24|s/^  clear_move_map\n  report refused-symlink/  report refused-symlink/m
no-encoder|TX1|s/^    \*\[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\._\/\@\+-\]\*\) ;;/    ZZZNOMATCH) ;;/m
locale-dependent-classify|TM3|s/^  local p="\$1" LC_ALL=C LC_COLLATE=C LC_CTYPE=C/  local p="\$1"/m; s/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/A-Za-z0-9/
locale-dependent-tag|TM3|s/\[abcdefghijklmnopqrstuvwxyz\]\) state_problem/[a-z]) state_problem/; s/^  local gitdir f d rec tag path sub hidden LC_ALL=C LC_COLLATE=C LC_CTYPE=C/  local gitdir f d rec tag path sub hidden/m
script-rewrites-content|TC1|s/^prune_dirs\n/prune_dirs\n[ -f CLAUDE.md ] \&\& LC_ALL=C sed -i.bak "s#\.docs\/agents\/#.marvin\/agents\/#g" CLAUDE.md \&\& rm -f CLAUDE.md.bak\n/m
'

# migrate-v0.35.0.sh — every guard it adds or carries over, each against its R* fixture.
MUTATIONS_0_35_0='
no-mkdir|R01|s/^  mkdir_chain "\$DST_ROOT"\n//m; s/^    mkdir_chain "\$\(dirname "\$dst"\)"\n//m
mkdir-recorded-late|R27|s/^  MUTATED=1\n  CREATED_DIRS\[\$\{#CREATED_DIRS\[\@\]\}\]="\$d"\n  mkdir "\$d"/  MUTATED=1\n  mkdir "\$d"\n  sleep 0.6\n  CREATED_DIRS[\${#CREATED_DIRS[\@]}]="\$d"/m
no-prune|R01|s/^  prune_dirs\nfi\n/fi\n/m
rmdir-not-besteffort|R02|s/rmdir "\$d" 2>\/dev\/null \|\| true/rmdir "\$d"/
no-collision-guard|R05|s/^dst_occupied\(\) \{ tracked_exact "\$1" \|\| \[ -e "\$1" \]; \}/dst_occupied() { false; }/m
index-only-dst-guard|R06|s/^dst_occupied\(\) \{ tracked_exact "\$1" \|\| \[ -e "\$1" \]; \}/dst_occupied() { tracked_exact "\$1"; }/m
no-ancestor-guard|R07|s/^  if anc=\$\(dst_ancestor_file "\$dst"\); then/  if false; then/m
no-clean-tree-guard|R08|s/^if tree_dirty; then\n  say "REFUSED/if false; then\n  say "REFUSED/m
refusal-keeps-map|R08|s/^  clear_move_map\n  report dirty-refused/  report dirty-refused/m
untracked-not-dirty|R09|s/^tree_dirty\(\) \{ \[ -n "\$DIRTY" \] \|\| \[ "\$\{#UNTRACKED\[\@\]\}" -gt 0 \]; \}/tree_dirty() { [ -n "\$DIRTY" ]; }/m
untracked-excludes-ignored|R09|s/git ls-files --others -z --/git ls-files --others --exclude-standard -z --/
no-early-nothing-to-do|RN1|s/^if \[ "\$\{#ALL_SRC\[\@\]\}" -eq 0 \] &&/if false \&\& [ "\${#ALL_SRC[\@]}" -eq 0 ] \&\&/m
script-commits|R11|s/^say "moved and staged/git commit -q -m "chore: migrate" || true\nsay "moved and staged/m
check-count-lies|RR1|s/^  echo "renamed=\$\{#MOVE_SRC\[\@\]\}"/  if [ "\$MODE" = "check" ]; then echo "renamed=99"; else echo "renamed=\${#MOVE_SRC[\@]}"; fi/m
check-skips-liveness|RR2|s/^dir_will_empty\(\) \{\n  local e\n  \[ -d "\$SRC_ROOT" \] \|\| return 1/dir_will_empty() {\n  local e\n  [ "\$MODE" = "check" ] \&\& return 0\n  [ -d "\$SRC_ROOT" ] || return 1/m
emptied-ignores-leftovers|RR2|s/^    is_move_src "\$e" \|\| return 1/    true/m
script-rewrites-content|RC1|s/^  prune_dirs\nfi\n/  prune_dirs\nfi\n[ -f CLAUDE.md ] \&\& LC_ALL=C sed -i.bak "s#\\.docs\/reports\/#.marvin\/reports\/#g" CLAUDE.md \&\& rm -f CLAUDE.md.bak\n/m
glob-pathspec|RG1|s/^lit\(\) \{ printf .:\(literal\)%s. "\$1"; \}/lit() { printf "%s" "\$1"; }/m
staging-sweep|RT9|s/^  git add -f -- "\$\{ADDARGS\[\@\]\}"/  git add -f -A/m
no-symlink-refusal|RS1|s/^safety_checks\(\) \{/safety_checks() { return 0;/m
no-fixed-set-check|RS1|s/^  for d in \.docs "\$SRC_ROOT" \.marvin "\$DST_ROOT"; do check_components "\$d"; done\n//m
no-per-file-src-check|RS1|s/^    check_components "\$\{ALL_SRC\[\$i\]\}"; i=\$\(\(i\+1\)\)/    i=\$((i+1))/m
symlink-refusal-keeps-map|RS1|s/^  clear_move_map\n  report refused-symlink/  report refused-symlink/m
no-repo-state-check|RP1|s/^repo_state_checks\(\) \{/repo_state_checks() { return 0;/m
state-misses-assume-unchanged|RP1|s#\[abcdefghijklmnopqrstuvwxyz\]\) state_problem "assume-unchanged#[Z]) state_problem "assume-unchanged#
state-misses-merge|RP2|s/for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do/for f in NOTHING_AT_ALL; do/
state-misses-detached|RP3|s/git symbolic-ref -q HEAD >\/dev\/null 2>&1 \|\|/true ||/
state-misses-unborn|RP3|s/git rev-parse --verify HEAD >\/dev\/null 2>&1 \|\|/true ||/
state-misses-skip-worktree|RP4|s/      S\)     state_problem/      Q)     state_problem/
state-misses-sparse|RP4|s/git config --bool core\.sparseCheckout/git config --bool core.noSuchKey/
no-submodule-dirty|RP5|s/    sub=\$\(git status --porcelain --ignore-submodules=none 2>\/dev\/null \|\| true\)/    sub=""/
no-submodule-recurse|RP5|s/\[ "\$\(git config --bool submodule\.recurse 2>\/dev\/null \|\| echo false\)" = "true" \] &&\n      state_problem/[ "false" = "true" ] \&\&\n      state_problem/s
no-gitlink-refusal|RP6|s/\[ "\$mode" = "160000" \] &&/[ "\$mode" = "nomode" ] \&\&/
no-encoder|RX1|s/^    \*\[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\._\/\@\+-\]\*\) ;;/    ZZZNOMATCH) ;;/m
locale-dependent-classify|RM3|s/^  local p="\$1" LC_ALL=C LC_COLLATE=C LC_CTYPE=C/  local p="\$1"/m; s/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/A-Za-z0-9/
locale-dependent-tag|RM3|s/\[abcdefghijklmnopqrstuvwxyz\]\) state_problem/[a-z]) state_problem/; s/^  local gitdir f d rec tag path sub hidden mode LC_ALL=C LC_COLLATE=C LC_CTYPE=C/  local gitdir f d rec tag path sub hidden mode/m
no-rollback-trap|R27|s/^trap rollback EXIT INT TERM HUP\n//m
rollback-keeps-map|R27|s/^  clear_move_map\n  report rolled-back/  report rolled-back/m
'

table_for() {
  case "$1" in
    0.21.0) printf '%s\n' "$MUTATIONS_0_21_0";;
    0.35.0) printf '%s\n' "$MUTATIONS_0_35_0";;
    *) return 1;;
  esac
}

SELECTED_VERSIONS="$VERSIONS"; LIST=0; NAMES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --script)
      v=${2:-}; v=${v##*/}; v=${v#migrate-v}; v=${v%.sh}
      table_for "$v" >/dev/null 2>&1 || { echo "mutate-migrations: no mutation table for '${2:-}'" >&2; exit 2; }
      [ -f "$SCRIPT_DIR/migrate-v$v.sh" ] || { echo "mutate-migrations: $SCRIPT_DIR/migrate-v$v.sh missing" >&2; exit 2; }
      SELECTED_VERSIONS="$v"; shift 2;;
    --list) LIST=1; shift;;
    *) NAMES="$NAMES $1"; shift;;
  esac
done

list_names() { table_for "$1" | grep . | cut -d'|' -f1; }
if [ "$LIST" = 1 ]; then
  for v in $SELECTED_VERSIONS; do list_names "$v" | sed "s/^/$v\//"; done
  exit 0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-mutate.XXXXXX") || WORK=""
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "mutate-migrations: FATAL — mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/res"

run_one() {
  local ver="$1" name="$2" fixture="$3" expr="$4" d out rc all hit key mig
  key="v$ver-$name"; d="$WORK/$key"; mkdir -p "$d"
  mig="migrate-v$ver.sh"
  cp "$SCRIPT_DIR"/migrate-v*.sh "$SRC_SUITE" "$d/"
  perl -0pi -e "$expr" "$d/$mig"
  name="v$ver/$name"
  if cmp -s "$d/$mig" "$SCRIPT_DIR/$mig"; then
    printf '%-38s %-6s STALE — the mutation no longer applies; fix this harness\n' "$name" "$fixture" > "$WORK/res/$key"
    return
  fi
  out=$(bash "$d/test-migrations.sh" --only "$ver" 2>&1); rc=$?
  all=$(printf '%s\n' "$out" | grep -c '^   FAIL')
  hit=$(printf '%s\n' "$out" | grep '^   FAIL' | grep -c "\[$fixture")
  { if [ "$rc" != 0 ] && [ "$hit" -gt 0 ]; then
      printf '%-38s %-6s CAUGHT   (%s failing assertion(s) in %s, %s overall)\n' "$name" "$fixture" "$hit" "$fixture" "$all"
    else
      printf '%-38s %-6s *** NOT CAUGHT *** (suite exit %s, %s failing assertion(s), none in %s)\n' \
        "$name" "$fixture" "$rc" "$all" "$fixture"
    fi
    printf '%s\n' "$out" | grep '^   FAIL' | grep "\[$fixture" | head -2 | sed 's/^/     /'
  } > "$WORK/res/$key"
}

# The work list: `<version> <name>` per line. A name given on the command line runs in every
# selected table that has it; one no selected table has is reported UNKNOWN.
SELECTED=$(
  for v in $SELECTED_VERSIONS; do
    if [ -n "$NAMES" ]; then
      for nm in $NAMES; do table_for "$v" | grep -q "^${nm}|" && printf '%s %s\n' "$v" "$nm"; done
    else
      list_names "$v" | sed "s/^/$v /"
    fi
  done
  for nm in $NAMES; do
    hit=0
    for v in $SELECTED_VERSIONS; do table_for "$v" | grep -q "^${nm}|" && hit=1; done
    [ "$hit" = 1 ] || printf 'unknown %s\n' "$nm"
  done
)
n=0; pids=""
while IFS=' ' read -r ver name; do
  [ -n "$name" ] || continue
  if [ "$ver" = unknown ]; then printf '%-38s UNKNOWN mutation name\n' "$name" > "$WORK/res/unknown-$name"; continue; fi
  line=$(table_for "$ver" | grep "^${name}|" | head -1)
  run_one "$ver" "$name" "$(printf '%s' "$line" | cut -d'|' -f2)" "$(printf '%s' "$line" | cut -d'|' -f3-)" &
  pids="$pids $!"
  n=$((n+1))
  if [ "$((n % PARALLEL))" = 0 ]; then wait $pids 2>/dev/null; pids=""; fi
done < <(printf '%s\n' "$SELECTED")
wait $pids 2>/dev/null

total=0; caught=0
while IFS=' ' read -r ver name; do
  [ -n "$name" ] || continue
  if [ "$ver" = unknown ]; then key="unknown-$name"; else key="v$ver-$name"; fi
  [ -f "$WORK/res/$key" ] || { printf '%-38s NO RESULT\n' "v$ver/$name"; total=$((total+1)); continue; }
  cat "$WORK/res/$key"
  total=$((total+1))
  grep -q 'CAUGHT   (' "$WORK/res/$key" && caught=$((caught+1))
done < <(printf '%s\n' "$SELECTED")

printf '\n----\nmutate-migrations: %d/%d mutations caught by their named fixture\n' "$caught" "$total"
[ "$caught" -eq "$total" ] || exit 1
exit 0
