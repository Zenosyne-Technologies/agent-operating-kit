#!/usr/bin/env bash
# mutate-migrations.sh — mutation harness for scripts/test-migrations.sh.
#
# A green test suite proves nothing about the guards it claims to pin: an assertion that cannot
# fail is indistinguishable from one that passes. This harness reverts ONE mechanic at a time in
# a COPY of scripts/migrate-v0.21.0.sh, runs the whole suite against the mutant, and requires
# that the fixture named for that mechanic FAILS. A mutation the suite survives is a hole.
#
# Usage:
#   bash scripts/mutate-migrations.sh            # every mutation, 4 at a time
#   bash scripts/mutate-migrations.sh no-mkdir glob-pathspec
#   bash scripts/mutate-migrations.sh --list
#   PARALLEL=1 bash scripts/mutate-migrations.sh # serialise (timing fixtures are load-sensitive)
#
# Not wired into CI: a full sweep runs the suite ~25 times. Run it when the migration script or
# its guards change, and quote the result in the change's evidence.
# Exit 0 = every selected mutation was caught by its named fixture.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_MIGRATE="$SCRIPT_DIR/migrate-v0.21.0.sh"
SRC_SUITE="$SCRIPT_DIR/test-migrations.sh"
PARALLEL=${PARALLEL:-4}

# name | fixture that must fail | perl -0 expression reverting one mechanic
MUTATIONS='
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

list_names() { printf '%s\n' "$MUTATIONS" | grep . | cut -d'|' -f1; }
[ "${1:-}" = "--list" ] && { list_names; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-mutate.XXXXXX") || WORK=""
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "mutate-migrations: FATAL — mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/res"

run_one() {
  local name="$1" fixture="$2" expr="$3" d out rc all hit
  d="$WORK/$name"; mkdir -p "$d"
  cp "$SRC_MIGRATE" "$SRC_SUITE" "$d/"
  perl -0pi -e "$expr" "$d/migrate-v0.21.0.sh"
  if cmp -s "$d/migrate-v0.21.0.sh" "$SRC_MIGRATE"; then
    printf '%-30s %-6s STALE — the mutation no longer applies; fix this harness\n' "$name" "$fixture" > "$WORK/res/$name"
    return
  fi
  out=$(bash "$d/test-migrations.sh" 2>&1); rc=$?
  all=$(printf '%s\n' "$out" | grep -c '^   FAIL')
  hit=$(printf '%s\n' "$out" | grep '^   FAIL' | grep -c "\[$fixture")
  { if [ "$rc" != 0 ] && [ "$hit" -gt 0 ]; then
      printf '%-30s %-6s CAUGHT   (%s failing assertion(s) in %s, %s overall)\n' "$name" "$fixture" "$hit" "$fixture" "$all"
    else
      printf '%-30s %-6s *** NOT CAUGHT *** (suite exit %s, %s failing assertion(s), none in %s)\n' \
        "$name" "$fixture" "$rc" "$all" "$fixture"
    fi
    printf '%s\n' "$out" | grep '^   FAIL' | grep "\[$fixture" | head -2 | sed 's/^/     /'
  } > "$WORK/res/$name"
}

SELECTED=$(if [ $# -gt 0 ]; then printf '%s\n' "$@"; else list_names; fi)
n=0; pids=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  line=$(printf '%s\n' "$MUTATIONS" | grep "^${name}|" | head -1)
  if [ -z "$line" ]; then printf '%-30s UNKNOWN mutation name\n' "$name" > "$WORK/res/$name"; continue; fi
  run_one "$name" "$(printf '%s' "$line" | cut -d'|' -f2)" "$(printf '%s' "$line" | cut -d'|' -f3-)" &
  pids="$pids $!"
  n=$((n+1))
  if [ "$((n % PARALLEL))" = 0 ]; then wait $pids 2>/dev/null; pids=""; fi
done < <(printf '%s\n' "$SELECTED")
wait $pids 2>/dev/null

total=0; caught=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -f "$WORK/res/$name" ] || { printf '%-30s NO RESULT\n' "$name"; total=$((total+1)); continue; }
  cat "$WORK/res/$name"
  total=$((total+1))
  grep -q 'CAUGHT   (' "$WORK/res/$name" && caught=$((caught+1))
done < <(printf '%s\n' "$SELECTED")

printf '\n----\nmutate-migrations: %d/%d mutations caught by their named fixture\n' "$caught" "$total"
[ "$caught" -eq "$total" ] || exit 1
exit 0
