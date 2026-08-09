#!/usr/bin/env bash
# migrate-v0.21.0.sh — move Marvin's machinery out of `.docs/` into `.marvin/` in a
# CONSUMER repository. This is the executable form of the v0.21.0 step of the
# `upgrade-agent-os` skill: an agent runs it, reads its report, and reconciles by hand only
# what the script declines to touch.
#
# It performs destructive git operations, unattended, inside a repository the kit does not
# own, whose file names it does not control. Four design rules keep that safe; each one
# replaced a class of reproduced data loss, and scripts/test-migrations.sh pins all four:
#
#   1. NO REGEX EVER TOUCHES CONSUMER CONTENT. The reference rewrite is literal string
#      replacement over the exact path pairs that actually moved. A file that did not move
#      has no pair, so it can never be retargeted — and a consumer filename containing
#      + ? ( ) { } | * or a space is just text, not a pattern.
#   2. NO CONSUMER NAME IS EVER INTERPRETED AS A PATTERN. Every git invocation that takes a
#      consumer path passes it as a `:(literal)` pathspec, which cannot glob.
#   3. SYMLINKS ARE REFUSED, NEVER FOLLOWED. Any symlinked source, destination, destination
#      ancestor or CLAUDE.md aborts before the first change.
#   4. ANY FAILURE AFTER THE FIRST CHANGE ROLLS BACK. The tree is provably clean at entry, so
#      the pre-migration state is exactly HEAD; a trap restores it on error, kill or disk-full.
#
# Usage: bash migrate-v0.21.0.sh [--check | --no-commit]      (the two flags are exclusive)
#   --check      dry run: print the exact plan, change nothing at all — works on ANY tree
#   --no-commit  perform + stage the changes, leave them uncommitted for inspection
#
# Exit codes:
#   0  success (including a clean no-op re-run)
#   2  dirty working tree: a real run refuses to start; `--check` still printed its plan
#   3  completed, but destination collisions need reconciling by hand
#   4  usage error (unknown or mutually exclusive flags) / not a git work tree
#   6  refused before changing anything: a symlink, or a path resolving outside the repo
#   7  a failure occurred after the first change; the repository was rolled back to HEAD
#   8  refused before changing anything: a file that must be rewritten is not writable
set -euo pipefail

KIT_VERSION="0.21.0"
SELF="migrate-v${KIT_VERSION}"
MODE="apply"

# The kit's OWN cascade files. Moves are file-by-file against this allowlist: `.docs/agents/`
# may also hold consumer-authored files (a runbook, project notes), and moving the whole
# directory silently relocates them. `convert-milestones-brief.md` is Jira-only but is just as
# much kit machinery — leaving it off the list strands it in `.docs/agents/` while every
# reference to it is retargeted at a path that will not exist.
CASCADE_FILES="briefing.md
convert-milestones-brief.md
documentation-agent.md
handbooks.md
label-syntax.md
planning-research.md
ponytail.md
reporting.md
security.md
stats-collection-brief.md
ticket-filing.md
token-economics.md
tracker-config.md
validation-agent.md"

# Source roots. `docs/agents/` is the pre-`.docs/` layout: such an install migrates in one hop.
CASCADE_SRC_DIRS=".docs/agents docs/agents"
PROJECT_INFO_SRCS=".docs/PROJECT-INFO.md docs/PROJECT-INFO.md"
MEMORY_SRCS=".docs/marvin/MEMORY.md docs/marvin/MEMORY.md"
PRUNE_DIRS=".docs/agents docs/agents .docs/marvin docs/marvin"

TAB=$'\t'
MOVE_SRC=(); MOVE_DST=()
CASE_DIR=(); CASE_FROM=()
DECL_PATH=(); DECL_WHY=()
COLL_SRC=(); COLL_DST=(); COLL_WHY=()
FAIL_SRC=(); FAIL_DST=()
MOVED_SRC=(); MOVED_DST=()
PAIR_FROM=(); PAIR_TO=()
KEEP=(); STAGE=(); REWRITTEN=(); NOTES=(); CREATED_DIRS=(); SYMLINK_HITS=(); UNWRITABLE=()
COMMIT_SHA="none"
DIRTY=""
ROOT_PHYS=""
HEAD_AT_ENTRY=""
MUTATED=0
COMPLETED=0

usage() {
  cat <<EOF
Usage: bash ${SELF}.sh [--check | --no-commit]
  (no flag)    migrate, stage by explicit literal pathspec, commit as ONE atomic commit
  --check      dry run — print the plan, change nothing (valid on a dirty tree too)
  --no-commit  migrate and stage, but do not commit
The two flags are mutually exclusive: anything containing --check must not modify the repo.
EOF
}

say()  { printf '%s\n' "$SELF: $*"; }
note() { NOTES[${#NOTES[@]}]="$*"; }

# ── git access: every consumer path goes in as a literal pathspec ────────────────────────────
# A bare pathspec is a GLOB. A consumer directory named `x*` plus `git add -f` was reproduced
# force-staging a gitignored `.docs/handbooks/xsecret/index.md` full of credentials into the
# migration commit. `:(literal)` cannot glob, so a name is only ever itself.
lit() { printf ':(literal)%s' "$1"; }

# Index membership, case-EXACT. `git ls-files --error-unmatch` is the membership test, but on
# its own it is not enough here: with core.ignorecase (the macOS default) a pathspec can match
# an index entry that differs only in case, which would make the handbook rename look already
# done. Re-check that the exact string came back.
tracked_exact() {
  git ls-files --error-unmatch -- "$(lit "$1")" >/dev/null 2>&1 || return 1
  git ls-files -z -- "$(lit "$1")" | tr '\0' '\n' | grep -Fxq -- "$1"
}

in_cascade() { printf '%s\n' "$CASCADE_FILES" | grep -Fxq -- "$1"; }

add_move()      { MOVE_SRC[${#MOVE_SRC[@]}]="$1"; MOVE_DST[${#MOVE_DST[@]}]="$2"; }
add_case()      { CASE_DIR[${#CASE_DIR[@]}]="$1"; CASE_FROM[${#CASE_FROM[@]}]="$2"; }
add_declined()  { DECL_PATH[${#DECL_PATH[@]}]="$1"; DECL_WHY[${#DECL_WHY[@]}]="$2"
                  KEEP[${#KEEP[@]}]="$1"; }
add_collision() { COLL_SRC[${#COLL_SRC[@]}]="$1"; COLL_DST[${#COLL_DST[@]}]="$2"
                  COLL_WHY[${#COLL_WHY[@]}]="$3"; KEEP[${#KEEP[@]}]="$1"; }

# ── destination guards ───────────────────────────────────────────────────────────────────────
# REAL path moves: a destination counts as occupied if it is in the index OR present on disk.
# A consumer who hand-migrated with cp/mv — or whose `.marvin/` is gitignored — leaves an
# untracked destination that an index-only guard walks straight past; `git mv` then either
# aborts the whole run or nests the source into `.marvin/agents/agents/`.
dst_occupied_real() { tracked_exact "$1" || [ -e "$1" ]; }
# CASE-ONLY handbook rename: index ONLY. This guard must contain NO filesystem-existence test.
# `INDEX.md` and `index.md` are the same inode on a case-insensitive filesystem, so `[ -e … ]`
# is already true before the rename and would skip it silently — shipping `INDEX.md` and
# breaking case-sensitive checkouts. On a case-sensitive filesystem that mistake is invisible
# at runtime, so test-migrations.sh pins this line's exact text as well as its behaviour.
dst_occupied_case() { tracked_exact "$1"; }

planned_dst_source() {   # first source already planning a move to $1, if any
  local i=0
  while [ "$i" -lt "${#MOVE_DST[@]}" ]; do
    if [ "${MOVE_DST[$i]}" = "$1" ]; then printf '%s' "${MOVE_SRC[$i]}"; return 0; fi
    i=$((i+1))
  done
  return 0
}

drop_planned_dst() {     # remove every planned move targeting $1
  local i=0 s=() d=()
  while [ "$i" -lt "${#MOVE_DST[@]}" ]; do
    if [ "${MOVE_DST[$i]}" != "$1" ]; then
      s[${#s[@]}]="${MOVE_SRC[$i]}"; d[${#d[@]}]="${MOVE_DST[$i]}"
    fi
    i=$((i+1))
  done
  MOVE_SRC=(${s[@]+"${s[@]}"}); MOVE_DST=(${d[@]+"${d[@]}"})
}

plan_real_move() {
  local src="$1" dst="$2" prev
  tracked_exact "$src" || return 0
  case "$src" in *"$TAB"*|*"
"*) add_declined "$src" "unsupported: the path contains a tab or newline"; return 0;; esac
  if dst_occupied_real "$dst"; then
    add_collision "$src" "$dst" "destination already exists — reconcile by hand"
    return 0
  fi
  # Two source roots can target one destination (a repo carrying both `docs/agents/` and
  # `.docs/agents/`). Neither is authoritative, and letting the plan promise both moves means
  # the second `git mv` fails mid-run. Detect it here and decline BOTH.
  prev=$(planned_dst_source "$dst")
  if [ -n "$prev" ]; then
    drop_planned_dst "$dst"
    add_collision "$prev" "$dst" "another source targets the same destination: $src"
    add_collision "$src" "$dst" "another source targets the same destination: $prev"
    return 0
  fi
  add_move "$src" "$dst"
}

build_plan() {
  local d p base s dir from i seen
  # 1. the kit's cascade, file by file against the allowlist
  for d in $CASCADE_SRC_DIRS; do
    while IFS= read -r -d '' p; do
      [ -n "$p" ] || continue
      base=${p#"$d"/}
      case "$base" in
        */*) add_declined "$p" "consumer-owned (not a kit cascade file)"; continue;;
      esac
      if in_cascade "$base"; then
        plan_real_move "$p" ".marvin/agents/$base"
      else
        add_declined "$p" "consumer-owned (not a kit cascade file)"
      fi
    done < <(git ls-files -z -- "$(lit "$d")")
  done
  # 2. PROJECT-INFO + MEMORY
  for s in $PROJECT_INFO_SRCS; do plan_real_move "$s" ".marvin/PROJECT-INFO.md"; done
  for s in $MEMORY_SRCS;       do plan_real_move "$s" ".marvin/MEMORY.md"; done
  # 3. handbook index, per audience: INDEX.md -> index.md, case only.
  #    `__index.tmp` is a RESUME MARKER, not debris: the rename is two `git mv` calls through a
  #    temp name, and a run that died between them leaves only the temp file — the source guard
  #    is off forever, so skipping it loses the handbook index permanently. Check the temp FIRST.
  local dirs=()
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    dir=${p%/*}
    seen=0; i=0
    while [ "$i" -lt "${#dirs[@]}" ]; do
      [ "${dirs[$i]}" = "$dir" ] && seen=1
      i=$((i+1))
    done
    [ "$seen" = 0 ] && dirs[${#dirs[@]}]="$dir"
  done < <(git ls-files -z -- '.docs/handbooks/*/INDEX.md' '.docs/handbooks/*/__index.tmp')
  i=0
  while [ "$i" -lt "${#dirs[@]}" ]; do
    dir="${dirs[$i]}"; i=$((i+1))
    from=""
    if tracked_exact "$dir/__index.tmp"; then from="__index.tmp"; fi
    if [ -n "$from" ] && tracked_exact "$dir/INDEX.md"; then
      add_collision "$dir/INDEX.md" "$dir/index.md" \
        "both INDEX.md and __index.tmp are tracked — reconcile by hand"
      continue
    fi
    [ -n "$from" ] || from="INDEX.md"
    tracked_exact "$dir/$from" || continue
    if dst_occupied_case "$dir/index.md"; then
      add_collision "$dir/$from" "$dir/index.md" "destination already tracked — reconcile by hand"
      continue
    fi
    add_case "$dir" "$from"
  done
}

# ── reference rewrite: literal pairs only ────────────────────────────────────────────────────
# Every pair is an exact path that actually moved. There is no pattern, no escaping and no
# protection mechanism, because a path that did not move never enters the list.
keep_extends() {          # does some kept path continue past $1?
  local k
  for k in ${KEEP[@]+"${KEEP[@]}"}; do
    case "$k" in "$1"?*) return 0;; esac
  done
  return 1
}
keep_matches_here() {     # does the text in $2 continue into a kept path that starts with $1?
  local k tail
  for k in ${KEEP[@]+"${KEEP[@]}"}; do
    case "$k" in "$1"?*) tail=${k#"$1"};; *) continue;; esac
    case "$2" in "$tail"*) return 0;; esac
  done
  return 1
}

REPL_OUT=""
replace_literal() {       # $1 content, $2 from, $3 to → REPL_OUT
  local c="$1" from="$2" to="$3" out pre rest
  if ! keep_extends "$from"; then
    REPL_OUT=${c//"$from"/"$to"}      # quoted pattern = literal; no metacharacters exist here
    return 0
  fi
  # A kept path extends this one (`…/notes.md` vs a declined `…/notes.md.bak`), so replace
  # occurrence by occurrence and leave the ones that are really the longer, unmoved path.
  out=""; rest="$c"
  while :; do
    case "$rest" in *"$from"*) ;; *) break;; esac
    pre=${rest%%"$from"*}
    rest=${rest#"$pre$from"}
    if keep_matches_here "$from" "$rest"; then out="$out$pre$from"; else out="$out$pre$to"; fi
  done
  REPL_OUT="$out$rest"
}

add_pair() { PAIR_FROM[${#PAIR_FROM[@]}]="$1"; PAIR_TO[${#PAIR_TO[@]}]="$2"; }

keep_under() {            # is any kept path inside directory $1?
  local k
  for k in ${KEEP[@]+"${KEEP[@]}"}; do
    case "$k" in "$1"/*) return 0;; esac
  done
  return 1
}
moved_from() {            # did anything move out of directory $1?
  local i=0
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    case "${MOVE_SRC[$i]}" in "$1"/*) return 0;; esac
    i=$((i+1))
  done
  return 1
}

build_pairs() {
  local i=0 d
  PAIR_FROM=(); PAIR_TO=()
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    add_pair "${MOVE_SRC[$i]}" "${MOVE_DST[$i]}"
    i=$((i+1))
  done
  i=0
  while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    add_pair "${CASE_DIR[$i]}/INDEX.md" "${CASE_DIR[$i]}/index.md"
    i=$((i+1))
  done
  # A bare directory reference is one explicit final pair, and only when the directory was
  # emptied — anything declined or collided keeps it alive and keeps its references valid.
  for d in .docs/agents docs/agents .docs/marvin docs/marvin; do
    moved_from "$d" || continue
    if keep_under "$d" || { [ "$MODE" != "check" ] && [ -e "$d" ]; }; then
      note "dir-ref-kept: $d/ (files remain there — bare directory references left as they are)"
      continue
    fi
    case "$d" in
      *agents) add_pair "$d/" ".marvin/agents/";;
      *marvin) add_pair "$d/" ".marvin/";;
    esac
  done
  sort_pairs_longest_first
}

sort_pairs_longest_first() {
  local i=0 blob="" n f t
  while [ "$i" -lt "${#PAIR_FROM[@]}" ]; do
    blob="${blob}${#PAIR_FROM[$i]}${TAB}${PAIR_FROM[$i]}${TAB}${PAIR_TO[$i]}"$'\n'
    i=$((i+1))
  done
  PAIR_FROM=(); PAIR_TO=()
  [ -n "$blob" ] || return 0
  while IFS="$TAB" read -r n f t; do
    [ -n "$f" ] || continue
    add_pair "$f" "$t"
  done < <(printf '%s' "$blob" | sort -t"$TAB" -k1,1nr)
}

NEW_CONTENT=""
compute_rewrite() {       # $1 file → 0 if the content would change, NEW_CONTENT set
  local f="$1" orig new i bytes_file bytes_mem
  [ -f "$f" ] || return 1
  IFS= read -r -d '' orig < "$f" || true
  bytes_file=$(wc -c < "$f" | tr -d ' ')
  bytes_mem=$(printf '%s' "$orig" | wc -c | tr -d ' ')
  if [ "$bytes_file" != "$bytes_mem" ]; then
    note "rewrite-skipped: $f (NUL bytes — left untouched)"
    return 1
  fi
  new="$orig"; i=0
  while [ "$i" -lt "${#PAIR_FROM[@]}" ]; do
    replace_literal "$new" "${PAIR_FROM[$i]}" "${PAIR_TO[$i]}"
    new="$REPL_OUT"
    i=$((i+1))
  done
  [ "$new" = "$orig" ] && return 1
  NEW_CONTENT="$new"
  return 0
}

apply_rewrite() {
  local f="$1"
  compute_rewrite "$f" || return 0
  printf '%s' "$NEW_CONTENT" > "$f"
  REWRITTEN[${#REWRITTEN[@]}]="$f"
}

stage_path() { STAGE[${#STAGE[@]}]="$1"; }

# Best effort ONLY. A consumer may keep their own files in `.docs/marvin/`; `rmdir` then exits
# 1 and, under `set -e`, would abort the run before the handbook renames. Never recursive:
# this script contains no recursive delete of any kind, on either side of a collision or
# otherwise — reconciling one is the user's call on their own data.
prune_dirs() {
  local d
  for d in $PRUNE_DIRS; do
    if [ -d "$d" ]; then rmdir "$d" 2>/dev/null || true; fi
  done
  return 0
}

# ── symlink and containment refusal ──────────────────────────────────────────────────────────
# A symlinked `.marvin` was reproduced relocating 15 consumer files out of the repository
# before `git mv` died; a symlinked CLAUDE.md was reproduced rewriting a file outside the repo
# while the commit stayed empty of it. Neither is worth following "safely".
check_components() {      # record every symlinked component of a repo-relative path
  local p="$1" acc="" part oldifs
  oldifs="$IFS"; IFS=/
  set -f
  for part in $p; do
    IFS="$oldifs"
    if [ -n "$part" ]; then
      acc="${acc:+$acc/}$part"
      if [ -L "$acc" ]; then SYMLINK_HITS[${#SYMLINK_HITS[@]}]="$acc (symlink)"; fi
    fi
    IFS=/
  done
  IFS="$oldifs"; set +f
  return 0
}

check_contained() {       # an existing directory must resolve inside the repository root
  local d="$1" phys
  [ -d "$d" ] || return 0
  phys=$(cd "$d" 2>/dev/null && pwd -P) || return 0
  case "$phys" in
    "$ROOT_PHYS"|"$ROOT_PHYS"/*) return 0;;
    *) SYMLINK_HITS[${#SYMLINK_HITS[@]}]="$d (resolves outside the repository: $phys)";;
  esac
  return 0
}

safety_checks() {
  local i=0 d
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    check_components "${MOVE_SRC[$i]}"; check_components "${MOVE_DST[$i]}"
    i=$((i+1))
  done
  i=0
  while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    check_components "${CASE_DIR[$i]}/${CASE_FROM[$i]}"
    check_components "${CASE_DIR[$i]}/index.md"
    i=$((i+1))
  done
  check_components "CLAUDE.md"
  for d in .marvin .marvin/agents; do check_components "$d"; check_contained "$d"; done
  i=0
  while [ "$i" -lt "${#CASE_DIR[@]}" ]; do check_contained "${CASE_DIR[$i]}"; i=$((i+1)); done
}

writability_checks() {    # fail cleanly BEFORE the first move, not after
  local i=0 f
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    f="${MOVE_SRC[$i]}"
    [ -f "$f" ] && [ ! -w "$f" ] && UNWRITABLE[${#UNWRITABLE[@]}]="$f"
    i=$((i+1))
  done
  i=0
  while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    f="${CASE_DIR[$i]}/${CASE_FROM[$i]}"
    [ -f "$f" ] && [ ! -w "$f" ] && UNWRITABLE[${#UNWRITABLE[@]}]="$f"
    i=$((i+1))
  done
  [ -f CLAUDE.md ] && [ ! -w CLAUDE.md ] && UNWRITABLE[${#UNWRITABLE[@]}]="CLAUDE.md"
  return 0
}

# ── rollback ─────────────────────────────────────────────────────────────────────────────────
# The clean-tree precondition is what makes this trivial: the pre-migration state IS HEAD.
# Armed as a trap so it also covers a kill, a full disk or an unwritable file.
rollback() {
  local rc=$?
  trap - EXIT INT TERM HUP
  if [ "$COMPLETED" = 1 ] || [ "$MUTATED" = 0 ]; then exit "$rc"; fi
  say "FAILED after the first change (exit $rc) — restoring the repository to ${HEAD_AT_ENTRY}"
  [ -n "$HEAD_AT_ENTRY" ] && git reset -q --hard "$HEAD_AT_ENTRY" >/dev/null 2>&1 || true
  local i="${#CREATED_DIRS[@]}"
  while [ "$i" -gt 0 ]; do                       # deepest first; empty ones only
    i=$((i-1))
    [ -d "${CREATED_DIRS[$i]}" ] && rmdir "${CREATED_DIRS[$i]}" 2>/dev/null || true
  done
  COMMIT_SHA="none"
  report rolled-back
  exit 7
}

mkdir_tracked() {
  local d="$1"
  [ -d "$d" ] && return 0
  MUTATED=1
  mkdir -p "$d"
  CREATED_DIRS[${#CREATED_DIRS[@]}]="$d"
  return 0
}

# ── reporting ────────────────────────────────────────────────────────────────────────────────
report() {
  local result="$1" i
  echo "---- ${SELF} report ----"
  echo "version=${KIT_VERSION}"
  echo "mode=${MODE}"
  echo "moved=${#MOVED_SRC[@]}"
  echo "declined=${#DECL_PATH[@]}"
  echo "collisions=${#COLL_SRC[@]}"
  echo "failures=${#FAIL_SRC[@]}"
  echo "rewritten=${#REWRITTEN[@]}"
  echo "commit=${COMMIT_SHA}"
  echo "result=${result}"
  i=0; while [ "$i" -lt "${#MOVED_SRC[@]}" ]; do
    printf 'moved: %s -> %s\n' "${MOVED_SRC[$i]}" "${MOVED_DST[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#DECL_PATH[@]}" ]; do
    printf 'declined: %s (%s)\n' "${DECL_PATH[$i]}" "${DECL_WHY[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#COLL_SRC[@]}" ]; do
    printf 'collision: %s -> %s (%s)\n' "${COLL_SRC[$i]}" "${COLL_DST[$i]}" "${COLL_WHY[$i]}"
    i=$((i+1)); done
  i=0; while [ "$i" -lt "${#FAIL_SRC[@]}" ]; do
    printf 'failure: %s -> %s\n' "${FAIL_SRC[$i]}" "${FAIL_DST[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#REWRITTEN[@]}" ]; do
    printf 'rewritten: %s\n' "${REWRITTEN[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf 'symlink: %s\n' "${SYMLINK_HITS[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#UNWRITABLE[@]}" ]; do
    printf 'unwritable: %s\n' "${UNWRITABLE[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#NOTES[@]}" ]; do
    printf 'note: %s\n' "${NOTES[$i]}"; i=$((i+1)); done
  echo "---- end ${SELF} report ----"
  return 0
}

finish() {
  COMPLETED=1
  if [ "${#COLL_SRC[@]}" -gt 0 ]; then report collisions; exit 3; fi
  report ok
  exit 0
}

# ── argument parsing ─────────────────────────────────────────────────────────────────────────
# The flags are mutually exclusive and "last one wins" is not an option: an invocation
# containing --check must never modify the repository, whatever else is on the line.
saw_check=0; saw_nocommit=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     saw_check=1;;
    --no-commit) saw_nocommit=1;;
    -h|--help)   usage; exit 0;;
    *)           say "unknown option: $1"; usage >&2; exit 4;;
  esac
  shift
done
if [ "$saw_check" = 1 ] && [ "$saw_nocommit" = 1 ]; then
  say "--check and --no-commit are mutually exclusive — refusing (nothing was changed)"
  usage >&2
  exit 4
fi
[ "$saw_check" = 1 ] && MODE="check"
[ "$saw_nocommit" = 1 ] && MODE="no-commit"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { say "not a git work tree — refusing"; exit 4; }
cd "$(git rev-parse --show-toplevel)"
ROOT_PHYS=$(pwd -P)
HEAD_AT_ENTRY=$(git rev-parse HEAD 2>/dev/null || echo "")
DIRTY=$(git status --porcelain)

build_plan
build_pairs

# ── dry run ──────────────────────────────────────────────────────────────────────────────────
# A dry run changes nothing, so it is available on ANY tree — deciding whether the cleanup is
# worth it is exactly when a preview is useful. It reports the dirty state as part of the plan.
if [ "$MODE" = "check" ]; then
  say "plan (dry run — nothing will be changed):"
  i=0; while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    printf '  move:    %s -> %s\n' "${MOVE_SRC[$i]}" "${MOVE_DST[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    printf '  rename:  %s/%s -> %s/index.md (case only, via __index.tmp)\n' \
      "${CASE_DIR[$i]}" "${CASE_FROM[$i]}" "${CASE_DIR[$i]}"; i=$((i+1)); done
  TARGETS=("CLAUDE.md")
  i=0; while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    TARGETS[${#TARGETS[@]}]="${MOVE_SRC[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    TARGETS[${#TARGETS[@]}]="${CASE_DIR[$i]}/${CASE_FROM[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#TARGETS[@]}" ]; do
    if compute_rewrite "${TARGETS[$i]}"; then
      printf '  rewrite: %s\n' "${TARGETS[$i]}"
      REWRITTEN[${#REWRITTEN[@]}]="${TARGETS[$i]}"
    fi
    i=$((i+1))
  done
  safety_checks
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf '  refuse:  %s\n' "${SYMLINK_HITS[$i]}"; i=$((i+1)); done
  if [ "${#MOVE_SRC[@]}" = 0 ] && [ "${#CASE_DIR[@]}" = 0 ] && [ "${#REWRITTEN[@]}" = 0 ]; then
    echo "  (nothing to do)"
  fi
  if [ -n "$DIRTY" ]; then
    say "the working tree is NOT clean — a real run will refuse to start until you clear it:"
    git status --short
    COMPLETED=1
    report plan-only-tree-dirty
    exit 2
  fi
  if [ "${#SYMLINK_HITS[@]}" -gt 0 ]; then COMPLETED=1; report would-refuse-symlink; exit 6; fi
  finish
fi

# ── precondition: clean tree ─────────────────────────────────────────────────────────────────
# "git-revertible" — the justification for running this unattended — is FALSE on a dirty tree:
# the consumer's WIP and untracked files land in the migration commit, and the `git revert`
# this step advertises then destroys them. Never stash on their behalf: a stash the script
# creates is a stash the user does not know to pop. It is also what makes rollback exact.
if [ -n "$DIRTY" ]; then
  say "REFUSED — the working tree is not clean. Commit or stash these yourself, then re-run:"
  git status --short
  report dirty-refused
  exit 2
fi

# ── preconditions that must hold before the FIRST change ─────────────────────────────────────
safety_checks
if [ "${#SYMLINK_HITS[@]}" -gt 0 ]; then
  say "REFUSED — symlinked or out-of-repository paths are never followed:"
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf '  %s\n' "${SYMLINK_HITS[$i]}"; i=$((i+1)); done
  report refused-symlink
  exit 6
fi
writability_checks
if [ "${#UNWRITABLE[@]}" -gt 0 ]; then
  say "REFUSED — these files must be rewritten but are not writable:"
  i=0; while [ "$i" -lt "${#UNWRITABLE[@]}" ]; do
    printf '  %s\n' "${UNWRITABLE[$i]}"; i=$((i+1)); done
  report refused-unwritable
  exit 8
fi

trap rollback EXIT INT TERM HUP

# ── apply: real path moves ───────────────────────────────────────────────────────────────────
if [ "${#MOVE_SRC[@]}" -gt 0 ]; then
  # `git mv` creates no parent directory, and `mkdir -p .marvin` alone is not enough for the
  # per-file cascade moves — every one of those dies "fatal: … No such file or directory".
  mkdir_tracked .marvin
  mkdir_tracked .marvin/agents
  i=0
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    src="${MOVE_SRC[$i]}"; dst="${MOVE_DST[$i]}"
    mkdir_tracked "$(dirname "$dst")"
    MUTATED=1
    if git mv -- "$src" "$dst"; then
      MOVED_SRC[${#MOVED_SRC[@]}]="$src"; MOVED_DST[${#MOVED_DST[@]}]="$dst"
      stage_path "$dst"
    else
      FAIL_SRC[${#FAIL_SRC[@]}]="$src"; FAIL_DST[${#FAIL_DST[@]}]="$dst"
      say "move failed: $src -> $dst"
      exit 1                                     # the trap rolls the whole run back
    fi
    i=$((i+1))
  done
fi

# ── apply: case-only handbook renames, through the resume marker ─────────────────────────────
i=0
while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
  dir="${CASE_DIR[$i]}"; from="${CASE_FROM[$i]}"
  MUTATED=1
  if [ "$from" = "INDEX.md" ]; then
    if ! git mv -- "$dir/INDEX.md" "$dir/__index.tmp"; then
      FAIL_SRC[${#FAIL_SRC[@]}]="$dir/INDEX.md"; FAIL_DST[${#FAIL_DST[@]}]="$dir/index.md"
      exit 1
    fi
  fi
  if ! git mv -- "$dir/__index.tmp" "$dir/index.md"; then
    FAIL_SRC[${#FAIL_SRC[@]}]="$dir/$from"; FAIL_DST[${#FAIL_DST[@]}]="$dir/index.md"
    exit 1
  fi
  MOVED_SRC[${#MOVED_SRC[@]}]="$dir/$from"; MOVED_DST[${#MOVED_DST[@]}]="$dir/index.md"
  stage_path "$dir/index.md"
  i=$((i+1))
done

prune_dirs
build_pairs                                      # bare-directory pairs need the post-prune state

# ── apply: reference rewrite ─────────────────────────────────────────────────────────────────
# CLAUDE.md plus the migrated files at their NEW paths. Nothing else is touched: the script's
# entire blast radius is those four locations and CLAUDE.md.
i=0
while [ "$i" -lt "${#STAGE[@]}" ]; do
  apply_rewrite "${STAGE[$i]}"
  i=$((i+1))
done
apply_rewrite "CLAUDE.md"
i=0
while [ "$i" -lt "${#REWRITTEN[@]}" ]; do
  [ "${REWRITTEN[$i]}" = "CLAUDE.md" ] && stage_path "CLAUDE.md"
  i=$((i+1))
done

# ── stage + commit ───────────────────────────────────────────────────────────────────────────
# Staging is by explicit literal pathspec, always. A blanket stage-everything sweep drags
# untracked consumer files (a fixture caught `.env.local`) into the migration commit, and the
# `git revert` escape hatch this step advertises then destroys them. `-f` covers one real case:
# a consumer who gitignored `.marvin/` — `git mv` already put those paths in the index, but
# `git add` still refuses an ignored pathspec and would leave the migration half-staged. With
# `:(literal)` the force flag can only ever apply to the exact paths this run moved.
# The renames AND the CLAUDE.md rewrite land in ONE commit: a revert that restored the file
# locations but not the references — or the other way round — leaves an inconsistent repo.
if [ "${#STAGE[@]}" -gt 0 ]; then
  ADDARGS=()
  i=0
  while [ "$i" -lt "${#STAGE[@]}" ]; do
    ADDARGS[${#ADDARGS[@]}]="$(lit "${STAGE[$i]}")"
    i=$((i+1))
  done
  git add -f -- "${ADDARGS[@]}"
fi

if git diff --cached --quiet; then
  say "nothing to migrate — already at the v${KIT_VERSION} layout"
  finish
fi

if [ "$MODE" = "no-commit" ]; then
  say "staged, not committed (--no-commit)"
else
  git commit -q -m "chore: move Marvin machinery from .docs/ to .marvin/ (kit v${KIT_VERSION})"
  COMMIT_SHA=$(git rev-parse HEAD)
  say "committed ${COMMIT_SHA}"
fi

finish
