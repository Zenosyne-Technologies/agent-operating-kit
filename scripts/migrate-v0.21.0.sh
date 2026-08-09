#!/usr/bin/env bash
# migrate-v0.21.0.sh — relocate Marvin's machinery from `.docs/` to `.marvin/` in a CONSUMER
# repository, stage the renames, and report what moved. Used by the `upgrade-agent-os` skill's
# v0.21.0 step.
#
# WHAT THIS SCRIPT DOES NOT DO: it never reads, writes or stages file CONTENT. It moves files
# and prints a rename map. Updating references to the moved paths is the agent's job, from that
# map, with its own editor — a semantic judgement (a third-party URL that merely contains
# `docs/agents/`, a `.bak` sibling that did not move, a code fence quoting the old layout on
# purpose) that a substring replacer gets wrong silently, and did, repeatedly. The agent then
# commits the staged renames together with its reference edits, so the migration is still one
# atomic, revertible commit.
#
# THE REPORT IS A MACHINE CONTRACT another agent parses while holding edit and commit
# authority, and every path in it comes from a consumer-controlled name. So the report is
# ENCODED, not interpolated: see `q()` and the `encoding=` line it prints. One logical record
# per physical line, always — a path can never forge a record.
#
# It performs destructive git operations, unattended, in a repository the kit does not own,
# whose file names it does not control. Four design rules keep that safe, all mutation-tested
# by scripts/test-migrations.sh:
#
#   1. NO CONSUMER NAME IS EVER INTERPRETED AS A PATTERN. Every git invocation that takes a
#      consumer path passes it as a `:(literal)` pathspec, which cannot glob.
#   2. NO CONSUMER NAME IS EVER EMITTED RAW. Every path printed goes through `q()`.
#   3. SYMLINKS ARE REFUSED, NEVER FOLLOWED. Any symlinked source, destination or destination
#      ancestor aborts before the first change.
#   4. ANY FAILURE AFTER THE FIRST CHANGE ROLLS BACK, and the rolled-back report contains no
#      move records. The repository state is verified exactly clean at entry, so the
#      pre-migration state is HEAD; a trap restores it on error, kill or full disk.
#
# `--check` prints the same report as the real run: they may differ ONLY in `mode=`, `staged=`
# and `result=`. Anything else would make the dry run an unsafe basis for the agent's edits.
#
# Usage: bash migrate-v0.21.0.sh [--check]
#   (no flag)  move the kit's files and stage them by literal pathspec — NO COMMIT
#   --check    dry run: print the same report, change nothing — works on ANY tree
#
# Exit codes:
#   0  success (including a clean no-op re-run)
#   2  dirty working tree: a real run refuses to start; `--check` still printed its plan
#   3  completed, but destination collisions need reconciling by hand
#   4  usage error (unknown flag) / not a git work tree
#   6  refused before changing anything: a symlinked source, destination or ancestor
#   7  a failure occurred after the first change; the repository was rolled back to HEAD
#   9  refused before changing anything: repository state makes this unsafe (an operation in
#      progress, assume-unchanged/skip-worktree bits, sparse checkout, a dirty or recursed
#      submodule, detached or unborn HEAD)
set -euo pipefail

KIT_VERSION="0.21.0"
SELF="migrate-v${KIT_VERSION}"
MODE="stage"

# The kit's OWN cascade files. Moves are file-by-file against this allowlist: `.docs/agents/`
# may also hold consumer-authored files (a runbook, project notes), and moving the whole
# directory silently relocates them. `convert-milestones-brief.md` is Jira-only but is just as
# much kit machinery — leaving it off the list strands it in `.docs/agents/`.
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

MOVE_SRC=(); MOVE_DST=()
CASE_DIR=(); CASE_FROM=()
DECL_PATH=(); DECL_WHY=()
COLL_SRC=(); COLL_DST=(); COLL_WHY=()
FAIL_SRC=(); FAIL_DST=()
STAGE=(); CREATED_DIRS=(); SYMLINK_HITS=(); STATE_PROBLEMS=(); EMPTIED=()
DIRTY=""
HEAD_AT_ENTRY=""
MUTATED=0
COMPLETED=0
STAGED_COUNT=0

usage() {
  cat <<EOF
Usage: bash ${SELF}.sh [--check]
  (no flag)  move the kit's files, stage them by literal pathspec, and print the rename map.
             NOTHING IS COMMITTED and no file content is touched: update the references from
             the map, then commit the renames and your edits together.
  --check    dry run — print the same report, change nothing (valid on a dirty tree too)
EOF
}

say() { printf '%s\n' "$SELF: $*"; }

# ── path encoding: the report is a contract, so every path is encoded, never interpolated ────
# A tracked path may contain a newline, a tab, a `"` or the ` -> ` separator, and it is
# consumer-controlled. Printed raw, one file could forge `renamed:`/`note:`/anything records in
# a report another agent acts on. `q()` follows git's own convention (`core.quotePath`): a path
# made only of the safe set is printed as-is; anything else is C-quoted in double quotes. So a
# record is exactly one line, and an unquoted field can never contain a space — which is what
# makes ` -> ` unambiguous as a separator.
ENCODING_DOC='encoding=paths are printed raw when they match [A-Za-z0-9._/@+-]+, otherwise C-quoted in double quotes with \n \t \r \" \\ and \ooo escapes (git core.quotePath convention); exactly one record per line'
q() {
  local p="$1"
  case "$p" in
    *[!A-Za-z0-9._/@+-]*) ;;
    *) printf '%s' "$p"; return 0;;
  esac
  printf '%s' "$p" | LC_ALL=C od -An -v -tu1 | awk '
    BEGIN{ printf "\"" }
    { for(i=1;i<=NF;i++){ b=$i+0
        if(b==92) printf "\\\\"
        else if(b==34) printf "\\\""
        else if(b==10) printf "\\n"
        else if(b==9)  printf "\\t"
        else if(b==13) printf "\\r"
        else if(b<32 || b>126) printf "\\%03o", b
        else printf "%c", b } }
    END{ printf "\"" }'
}

# ── git access: every consumer path goes in as a literal pathspec ────────────────────────────
# A bare pathspec is a GLOB. A consumer directory named `x*` plus `git add -f` was reproduced
# force-staging a gitignored `.docs/handbooks/xsecret/index.md` full of credentials into the
# commit. `:(literal)` cannot glob, so a name is only ever itself.
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
add_declined()  { DECL_PATH[${#DECL_PATH[@]}]="$1"; DECL_WHY[${#DECL_WHY[@]}]="$2"; }
add_collision() { COLL_SRC[${#COLL_SRC[@]}]="$1"; COLL_DST[${#COLL_DST[@]}]="$2"
                  COLL_WHY[${#COLL_WHY[@]}]="$3"; }

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

planned_dst_source() {
  local i=0
  while [ "$i" -lt "${#MOVE_DST[@]}" ]; do
    if [ "${MOVE_DST[$i]}" = "$1" ]; then printf '%s' "${MOVE_SRC[$i]}"; return 0; fi
    i=$((i+1))
  done
  return 0
}

drop_planned_dst() {
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
    add_collision "$prev" "$dst" "another source targets the same destination: $(q "$src")"
    add_collision "$src" "$dst" "another source targets the same destination: $(q "$prev")"
    return 0
  fi
  add_move "$src" "$dst"
}

build_plan() {
  local d p base s dir from i seen dirs=()
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
  for s in $PROJECT_INFO_SRCS; do plan_real_move "$s" ".marvin/PROJECT-INFO.md"; done
  for s in $MEMORY_SRCS;       do plan_real_move "$s" ".marvin/MEMORY.md"; done
  # Handbook index, per audience: INDEX.md -> index.md, case only.
  # `__index.tmp` is a RESUME MARKER, not debris: the rename is two `git mv` calls through a
  # temp name, and a run that died between them leaves only the temp file — the source guard is
  # off forever, so skipping it loses the handbook index permanently. Check the temp FIRST.
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

# Which source directories the migration will empty. Predicted from the plan and the disk, at
# plan time, in BOTH modes — a check-mode shortcut here would let the dry run promise something
# the real run withholds, and this line is what licenses the agent to follow bare directory
# references. Reported, never acted on.
dir_will_empty() {
  local d="$1" e i found
  [ -d "$d" ] || return 1
  while IFS= read -r -d '' e; do
    [ -n "$e" ] || continue
    [ -d "$e" ] && return 1                    # a subdirectory survives, so the parent does
    found=0; i=0
    while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
      [ "${MOVE_SRC[$i]}" = "$e" ] && found=1
      i=$((i+1))
    done
    [ "$found" = 1 ] || return 1               # something stays (declined, untracked, ignored)
  done < <(find "$d" -mindepth 1 -print0)
  return 0
}

moved_from() {
  local i=0
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    case "${MOVE_SRC[$i]}" in "$1"/*) return 0;; esac
    i=$((i+1))
  done
  return 1
}

predict_emptied() {
  local d
  EMPTIED=()
  for d in .docs/agents docs/agents .docs/marvin docs/marvin; do
    moved_from "$d" || continue
    dir_will_empty "$d" || continue
    case "$d" in
      *agents) EMPTIED[${#EMPTIED[@]}]="$d/ -> .marvin/agents/";;
      *marvin) EMPTIED[${#EMPTIED[@]}]="$d/ -> .marvin/";;
    esac
  done
  return 0
}

# Best effort ONLY. A consumer may keep their own files in `.docs/marvin/`; `rmdir` then exits
# 1 and, under `set -e`, would abort the run before the handbook renames. Never recursive: this
# script contains no recursive delete of any kind, on either side of a collision or otherwise.
prune_dirs() {
  local d
  for d in $PRUNE_DIRS; do
    if [ -d "$d" ]; then rmdir "$d" 2>/dev/null || true; fi
  done
  return 0
}

# ── symlink refusal ──────────────────────────────────────────────────────────────────────────
# A symlinked `.marvin` was reproduced relocating 15 consumer files out of the repository
# before `git mv` died. Refusing every symlinked component is the containment boundary: with no
# symlinked component and no `..` in any path, everything the script touches is under the root
# by construction, so there is no separate (and untestable) resolved-path check.
check_components() {
  local p="$1" acc="" part oldifs
  oldifs="$IFS"; IFS=/
  set -f
  for part in $p; do
    IFS="$oldifs"
    if [ -n "$part" ]; then
      acc="${acc:+$acc/}$part"
      if [ -L "$acc" ]; then SYMLINK_HITS[${#SYMLINK_HITS[@]}]="$acc"; fi
    fi
    IFS=/
  done
  IFS="$oldifs"; set +f
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
  for d in .marvin .marvin/agents; do check_components "$d"; done
  return 0
}

# ── repository-state refusal ─────────────────────────────────────────────────────────────────
# The clean-tree gate is load-bearing for the rollback, and `git status --porcelain` alone does
# not prove a clean tree.
state_problem() { STATE_PROBLEMS[${#STATE_PROBLEMS[@]}]="$1"; }

submodules_present() {
  [ -f .gitmodules ] && return 0
  [ -n "$(git submodule status 2>/dev/null || true)" ] && return 0
  return 1
}

repo_state_checks() {
  local gitdir f d rec tag path sub hidden
  gitdir=$(git rev-parse --git-dir)
  # An operation in progress: the agent's commit would silently CONCLUDE the consumer's merge,
  # producing a two-parent commit that `git revert HEAD` then refuses.
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    [ -e "$gitdir/$f" ] && state_problem "$f exists — an operation is in progress; finish or abort it first"
  done
  for d in rebase-merge rebase-apply; do
    [ -d "$gitdir/$d" ] && state_problem "$d/ exists — a rebase is in progress; finish or abort it first"
  done
  # assume-unchanged / skip-worktree: `git status --porcelain` does not report modifications to
  # these files, so a "clean" tree can hide uncommitted work that the rollback would destroy.
  while IFS= read -r -d '' rec; do
    [ -n "$rec" ] || continue
    tag=${rec%% *}; path=${rec#* }
    case "$tag" in
      [a-z]) state_problem "assume-unchanged bit set on $(q "$path") — its changes are invisible to git status";;
      S)     state_problem "skip-worktree bit set on $(q "$path") — its changes are invisible to git status";;
    esac
  done < <(git ls-files -v -z)
  [ "$(git config --bool core.sparseCheckout 2>/dev/null || echo false)" = "true" ] &&
    state_problem "core.sparseCheckout is enabled — parts of the tree are not present"
  # Submodules: `git status` hides a dirty submodule when its `ignore` is set (including from a
  # committed .gitmodules), and with submodule.recurse a rollback resets their working trees.
  if submodules_present; then
    [ "$(git config --bool submodule.recurse 2>/dev/null || echo false)" = "true" ] &&
      state_problem "submodule.recurse is enabled and this repository has submodules — a rollback would reset their working trees"
    sub=$(git status --porcelain --ignore-submodules=none 2>/dev/null || true)
    hidden=$(comm -13 <(printf '%s\n' "$DIRTY" | LC_ALL=C sort) \
                      <(printf '%s\n' "$sub"   | LC_ALL=C sort) | grep . || true)
    if [ -n "$hidden" ]; then
      while IFS= read -r rec; do
        [ -n "$rec" ] || continue
        state_problem "a submodule change is hidden from git status: $(q "${rec#???}")"
      done < <(printf '%s\n' "$hidden")
    fi
  fi
  # HEAD must be a real branch tip: rollback resets to it and the agent commits on top of it.
  git rev-parse --verify HEAD >/dev/null 2>&1 ||
    state_problem "HEAD is unborn (no commits yet) — there is nothing to roll back to"
  git symbolic-ref -q HEAD >/dev/null 2>&1 ||
    state_problem "HEAD is detached — commit on a branch before migrating"
  return 0
}

# ── rollback ─────────────────────────────────────────────────────────────────────────────────
# The clean-state precondition is what makes this exact: the pre-migration state IS HEAD.
# Armed as a trap so it also covers a kill or a full disk. The rolled-back report carries NO
# move records: the moves were undone, and an agent that parsed them would edit references for
# files sitting at their original paths.
rollback() {
  local rc=$? i
  trap - EXIT INT TERM HUP
  if [ "$COMPLETED" = 1 ] || [ "$MUTATED" = 0 ]; then exit "$rc"; fi
  say "FAILED after the first change (exit $rc) — restoring the repository to ${HEAD_AT_ENTRY}"
  [ -n "$HEAD_AT_ENTRY" ] && git reset -q --hard "$HEAD_AT_ENTRY" >/dev/null 2>&1 || true
  i="${#CREATED_DIRS[@]}"
  while [ "$i" -gt 0 ]; do
    i=$((i-1))
    [ -d "${CREATED_DIRS[$i]}" ] && rmdir "${CREATED_DIRS[$i]}" 2>/dev/null || true
  done
  MOVE_SRC=(); MOVE_DST=(); CASE_DIR=(); CASE_FROM=(); EMPTIED=(); STAGE=(); STAGED_COUNT=0
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

# ── the report: this is the contract the upgrade skill consumes ──────────────────────────────
# Emitted from the PLAN in both modes. On success the plan is exactly what happened; on failure
# the rollback clears it. That is what makes `--check` and a real run differ only in `mode=`,
# `staged=` and `result=` by construction rather than by coincidence.
report() {
  local result="$1" i
  echo "---- ${SELF} report ----"
  echo "version=${KIT_VERSION}"
  echo "$ENCODING_DOC"
  echo "mode=${MODE}"
  echo "renamed=$(( ${#MOVE_SRC[@]} + ${#CASE_DIR[@]} ))"
  echo "declined=${#DECL_PATH[@]}"
  echo "collisions=${#COLL_SRC[@]}"
  echo "failures=${#FAIL_SRC[@]}"
  echo "staged=${STAGED_COUNT}"
  echo "committed=no"
  echo "result=${result}"
  i=0; while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    printf 'renamed: %s -> %s\n' "$(q "${MOVE_SRC[$i]}")" "$(q "${MOVE_DST[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    printf 'renamed: %s -> %s\n' "$(q "${CASE_DIR[$i]}/${CASE_FROM[$i]}")" \
                                 "$(q "${CASE_DIR[$i]}/index.md")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#DECL_PATH[@]}" ]; do
    printf 'declined: %s (%s)\n' "$(q "${DECL_PATH[$i]}")" "${DECL_WHY[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#COLL_SRC[@]}" ]; do
    printf 'collision: %s -> %s (%s)\n' "$(q "${COLL_SRC[$i]}")" "$(q "${COLL_DST[$i]}")" \
      "${COLL_WHY[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#FAIL_SRC[@]}" ]; do
    printf 'failure: %s -> %s\n' "$(q "${FAIL_SRC[$i]}")" "$(q "${FAIL_DST[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf 'symlink: %s\n' "$(q "${SYMLINK_HITS[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#STATE_PROBLEMS[@]}" ]; do
    printf 'repo-state: %s\n' "${STATE_PROBLEMS[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    printf 'references-to-update: %s\n' "$(q "${MOVE_SRC[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#CASE_DIR[@]}" ]; do
    printf 'references-to-update: %s\n' "$(q "${CASE_DIR[$i]}/${CASE_FROM[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#EMPTIED[@]}" ]; do
    printf 'directory-emptied: %s\n' "${EMPTIED[$i]}"; i=$((i+1)); done
  echo "---- end ${SELF} report ----"
  return 0
}

finish() {
  COMPLETED=1
  if [ "${#COLL_SRC[@]}" -gt 0 ]; then report "$1"; exit 3; fi
  report "$1"
  exit 0
}

# ── argument parsing ─────────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --check)   MODE="check";;
    -h|--help) usage; exit 0;;
    *)         say "unknown option: $1 (this script takes --check, and never commits)"
               usage >&2; exit 4;;
  esac
  shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { say "not a git work tree — refusing"; exit 4; }
cd "$(git rev-parse --show-toplevel)"
HEAD_AT_ENTRY=$(git rev-parse HEAD 2>/dev/null || echo "")
DIRTY=$(git status --porcelain)

build_plan
predict_emptied
repo_state_checks
safety_checks

# ── dry run ──────────────────────────────────────────────────────────────────────────────────
# A dry run changes nothing, so it is available on ANY tree — deciding whether the cleanup is
# worth it is exactly when a preview is useful.
if [ "$MODE" = "check" ]; then
  if [ "${#STATE_PROBLEMS[@]}" -gt 0 ]; then
    say "a real run will REFUSE: the repository state makes this unsafe"
    COMPLETED=1; report plan-only-repo-state; exit 9
  fi
  if [ -n "$DIRTY" ]; then
    say "a real run will REFUSE: the working tree is not clean"
    git status --short
    COMPLETED=1; report plan-only-tree-dirty; exit 2
  fi
  if [ "${#SYMLINK_HITS[@]}" -gt 0 ]; then
    say "a real run will REFUSE: symlinked paths are never followed"
    COMPLETED=1; report plan-only-symlink; exit 6
  fi
  finish plan
fi

# ── preconditions, in the order a real run hits them ─────────────────────────────────────────
if [ "${#STATE_PROBLEMS[@]}" -gt 0 ]; then
  say "REFUSED — the repository state makes an unattended migration unsafe:"
  i=0; while [ "$i" -lt "${#STATE_PROBLEMS[@]}" ]; do
    printf '  %s\n' "${STATE_PROBLEMS[$i]}"; i=$((i+1)); done
  report refused-repo-state
  exit 9
fi
# "git-revertible" — the justification for running this unattended — is FALSE on a dirty tree:
# the consumer's WIP lands in the agent's migration commit and their later `git revert` destroys
# it. Never stash on their behalf: a stash the script creates is a stash they do not know to pop.
if [ -n "$DIRTY" ]; then
  say "REFUSED — the working tree is not clean. Commit or stash these yourself, then re-run:"
  git status --short
  report dirty-refused
  exit 2
fi
if [ "${#SYMLINK_HITS[@]}" -gt 0 ]; then
  say "REFUSED — symlinked paths are never followed:"
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf '  %s\n' "$(q "${SYMLINK_HITS[$i]}")"; i=$((i+1)); done
  report refused-symlink
  exit 6
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
      STAGE[${#STAGE[@]}]="$dst"
    else
      FAIL_SRC[${#FAIL_SRC[@]}]="$src"; FAIL_DST[${#FAIL_DST[@]}]="$dst"
      say "move failed: $(q "$src") -> $(q "$dst")"
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
  STAGE[${#STAGE[@]}]="$dir/index.md"
  i=$((i+1))
done

prune_dirs

# ── stage ────────────────────────────────────────────────────────────────────────────────────
# By explicit literal pathspec, always. A blanket stage-everything sweep drags untracked
# consumer files (a fixture caught `.env.local`) into what the agent then commits. `-f` covers
# one real case: a consumer who gitignored `.marvin/` — `git mv` already put those paths in the
# index, but `git add` still refuses an ignored pathspec and would leave the migration
# half-staged. With `:(literal)` the force flag can only ever apply to paths this run moved.
if [ "${#STAGE[@]}" -gt 0 ]; then
  ADDARGS=()
  i=0
  while [ "$i" -lt "${#STAGE[@]}" ]; do
    ADDARGS[${#ADDARGS[@]}]="$(lit "${STAGE[$i]}")"
    i=$((i+1))
  done
  git add -f -- "${ADDARGS[@]}"
  STAGED_COUNT=${#STAGE[@]}
fi

if git diff --cached --quiet; then
  say "nothing to migrate — already at the v${KIT_VERSION} layout"
  finish nothing-to-do
fi

say "moved and staged ${STAGED_COUNT} path(s) — NOTHING COMMITTED."
say "update the references listed under 'references-to-update:', then commit them together."
finish staged
