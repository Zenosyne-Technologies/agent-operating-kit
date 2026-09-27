#!/usr/bin/env bash
# migrate-v0.35.0.sh — move the project's reports from `.docs/reports/` to `.marvin/reports/` in
# a CONSUMER repository, stage the renames, and report what moved. Used by the `upgrade-agent-os`
# skill's step 3 (and by `install-agent-os` step 1 when a legacy `.docs/reports/` exists).
#
# Reports are Marvin's records, not the project's documentation estate: stats snapshots,
# milestone close-outs, digests, stakeholder pages and the install/upgrade run reports. EVERY
# file under `.docs/reports/` moves to the same relative path under `.marvin/reports/` —
# including ones the consumer wrote by hand. There is no allowlist (unlike v0.21.0's cascade
# move): the whole folder changes owner. A destination that already exists is a COLLISION,
# reported and never overwritten.
#
# WHAT THIS SCRIPT DOES NOT DO: it never reads, writes or stages file CONTENT. It moves files
# and prints a rename map. Updating references to the moved paths is the agent's job, from that
# map, with its own editor — a semantic judgement a substring replacer gets wrong silently. The
# agent then commits the staged renames together with its reference edits, so the migration is
# one atomic, revertible commit.
#
# THE REPORT IS A MACHINE CONTRACT another agent parses while holding edit and commit
# authority, and every path in it comes from a consumer-controlled name. So the report is
# ENCODED, not interpolated: see `q()` and the `encoding=` line it prints. One logical record
# per physical line, always — a path can never forge a record.
#
# Design rules, the same as migrate-v0.21.0.sh's, all mutation-tested by
# scripts/test-migrations.sh (fixtures R*) via scripts/mutate-migrations.sh:
#
#   1. NO CONSUMER NAME IS EVER INTERPRETED AS A PATTERN. Every git invocation that takes a
#      consumer path passes it as a `:(literal)` pathspec, which cannot glob.
#   2. NO CONSUMER NAME IS EVER EMITTED RAW. Every path printed goes through `q()`.
#   3. SYMLINKS ARE REFUSED, NEVER FOLLOWED. A symlinked `.docs`, `.docs/reports`, file or
#      directory under it, `.marvin`, `.marvin/reports` or destination ancestor aborts before
#      the first change.
#   4. ANY FAILURE AFTER THE FIRST CHANGE ROLLS BACK, and the rolled-back report contains no
#      move records. The repository state is verified exactly clean at entry — an UNTRACKED or
#      gitignored file under `.docs/reports/` counts as dirty, so every move is a tracked
#      `git mv` — and the pre-migration state is therefore HEAD; a trap restores it on error,
#      kill or full disk.
#
# `--check` prints the same report as the real run: they may differ ONLY in `mode=`, `staged=`
# and `result=`. Anything else would make the dry run an unsafe basis for the agent's edits.
#
# Usage: bash migrate-v0.35.0.sh [--check]
#   (no flag)  move every report and stage it by literal pathspec — NO COMMIT
#   --check    dry run: print the same report, change nothing — works on ANY tree
#
# Exit codes:
#   0  success, or nothing to do (no `.docs/reports/` content — checked first, on any tree)
#   2  dirty working tree, or untracked/ignored files under `.docs/reports/`: a real run
#      refuses to start (the `untracked:` lines name what to commit or remove); `--check` still
#      printed its plan
#   3  completed, but destination collisions need reconciling by hand
#   4  usage error (unknown flag) / not a git work tree
#   6  refused before changing anything: a symlinked source, destination or ancestor
#   7  a failure occurred after the first change; the repository was rolled back to HEAD
#   9  refused before changing anything: repository state makes this unsafe (an operation in
#      progress, assume-unchanged/skip-worktree bits, sparse checkout, a dirty or recursed
#      submodule, a submodule under `.docs/reports/`, detached or unborn HEAD)
set -euo pipefail

KIT_VERSION="0.35.0"
SELF="migrate-v${KIT_VERSION}"
MODE="stage"
SRC_ROOT=".docs/reports"
DST_ROOT=".marvin/reports"

ALL_SRC=()
MOVE_SRC=(); MOVE_DST=()
COLL_SRC=(); COLL_DST=(); COLL_WHY=()
FAIL_SRC=(); FAIL_DST=()
UNTRACKED=()
STAGE=(); CREATED_DIRS=(); SYMLINK_HITS=(); STATE_PROBLEMS=(); EMPTIED=()
DIRTY=""
HEAD_AT_ENTRY=""
MUTATED=0
COMPLETED=0
STAGED_COUNT=0

usage() {
  cat <<EOF
Usage: bash ${SELF}.sh [--check]
  (no flag)  move every file under ${SRC_ROOT}/ to ${DST_ROOT}/, stage the renames by literal
             pathspec, and print the rename map. NOTHING IS COMMITTED and no file content is
             touched: update the references from the map, then commit the renames and your
             edits together.
  --check    dry run — print the same report, change nothing (valid on a dirty tree too)
EOF
}

say() { printf '%s\n' "$SELF: $*"; }

# ── path encoding: the report is a contract, so every path is encoded, never interpolated ────
# Identical to migrate-v0.21.0.sh's `q()` (git's `core.quotePath` convention): a path made only
# of the safe set is printed as-is; anything else is C-quoted in double quotes. A record is
# exactly one line, and an unquoted field can never contain a space.
ENCODING_DOC='encoding=paths are printed raw when they match [A-Za-z0-9._/@+-]+, otherwise C-quoted in double quotes with \n \t \r \" \\ and \ooo escapes (git core.quotePath convention); exactly one record per line'
q() {
  # LC_ALL=C for the classification too: bash range expressions follow locale collation. The
  # set is enumerated rather than ranged, so collation cannot reorder it either.
  local p="$1" LC_ALL=C LC_COLLATE=C LC_CTYPE=C
  case "$p" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*) ;;
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
# A bare pathspec is a GLOB: a report named `x*.md` plus `git add -f` would force-stage a
# gitignored `.marvin/reports/xsecret.md` beside it. `:(literal)` cannot glob.
lit() { printf ':(literal)%s' "$1"; }

# Index membership, case-EXACT (core.ignorecase can match an entry differing only in case).
tracked_exact() {
  git ls-files --error-unmatch -- "$(lit "$1")" >/dev/null 2>&1 || return 1
  git ls-files -z -- "$(lit "$1")" | tr '\0' '\n' | grep -Fxq -- "$1"
}

add_move()      { MOVE_SRC[${#MOVE_SRC[@]}]="$1"; MOVE_DST[${#MOVE_DST[@]}]="$2"; }
add_collision() { COLL_SRC[${#COLL_SRC[@]}]="$1"; COLL_DST[${#COLL_DST[@]}]="$2"
                  COLL_WHY[${#COLL_WHY[@]}]="$3"; }

# ── destination guard ────────────────────────────────────────────────────────────────────────
# Occupied = in the index OR present on disk. A consumer who hand-copied reports — or whose
# `.marvin/` is gitignored — leaves an untracked destination that an index-only guard walks
# straight past, and `git mv` then aborts the run or nests the source inside it.
dst_occupied() { tracked_exact "$1" || [ -e "$1" ]; }

# A destination ANCESTOR that is a file (on disk or in the index) blocks the move just as
# surely: `mkdir` fails mid-run. Found at plan time, it is a collision, not a rollback.
# Directories already found clear are cached: a report tree shares a handful of ancestors, and
# each test costs a git process.
ANC_CLEAR=""
dst_ancestor_file() {
  local a="${1%/*}"
  while [ -n "$a" ] && [ "$a" != "$1" ]; do
    case "$ANC_CLEAR" in *"/$a/"*) return 1;; esac
    if { [ -e "$a" ] && [ ! -d "$a" ]; } || tracked_exact "$a"; then printf '%s' "$a"; return 0; fi
    case "$a" in */*) a="${a%/*}";; *) a="";; esac
  done
  ANC_CLEAR="$ANC_CLEAR/${1%/*}/"
  return 1
}

plan_move() {
  local src="$1" dst="$2" anc
  if dst_occupied "$dst"; then
    add_collision "$src" "$dst" "destination already exists — reconcile by hand"
    return 0
  fi
  if anc=$(dst_ancestor_file "$dst"); then
    add_collision "$src" "$dst" "a destination ancestor is a file: $(q "$anc") — reconcile by hand"
    return 0
  fi
  add_move "$src" "$dst"
}

build_plan() {
  local p rel
  # Tracked files: every one moves (or collides). The case pattern also drops a tracked entry
  # that IS `.docs/reports` (a committed symlink) — the symlink refusal names that one.
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    case "$p" in "$SRC_ROOT"/*) ;; *) continue;; esac
    ALL_SRC[${#ALL_SRC[@]}]="$p"
    rel=${p#"$SRC_ROOT"/}
    plan_move "$p" "$DST_ROOT/$rel"
  done < <(git ls-files -z -- "$(lit "$SRC_ROOT")")
  # Untracked files — gitignored ones INCLUDED (no --exclude-standard): `git mv` cannot move
  # them and the rollback cannot restore them, so they make the tree dirty for this script.
  # An untracked `.docs/reports` that is ITSELF a file (a symlink) is not under it: the symlink
  # refusal names that one.
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    case "$p" in "$SRC_ROOT"/*) ;; *) continue;; esac
    UNTRACKED[${#UNTRACKED[@]}]="$p"
  done < <(git ls-files --others -z -- "$(lit "$SRC_ROOT")")
  return 0
}

is_move_src() {
  local i=0
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    [ "${MOVE_SRC[$i]}" = "$1" ] && return 0
    i=$((i+1))
  done
  return 1
}

# Will the migration empty `.docs/reports/`? Predicted from the plan and the disk, at plan time,
# in BOTH modes — this line licenses the agent to follow bare directory references, so the dry
# run must never promise what the real run withholds. Directories do not keep it alive (they
# are pruned when empty); any other entry that does not move does.
dir_will_empty() {
  local e
  [ -d "$SRC_ROOT" ] || return 1
  while IFS= read -r -d '' e; do
    [ -n "$e" ] || continue
    if [ -d "$e" ] && [ ! -L "$e" ]; then continue; fi
    is_move_src "$e" || return 1
  done < <(find "$SRC_ROOT" -mindepth 1 -print0)
  return 0
}

predict_emptied() {
  EMPTIED=()
  [ "${#MOVE_SRC[@]}" -gt 0 ] || return 0
  if dir_will_empty; then EMPTIED[0]="$SRC_ROOT/ -> $DST_ROOT/"; fi
  return 0
}

# Best effort ONLY, deepest first, never recursive: a directory that still holds something (a
# collided report) makes `rmdir` exit 1, which under `set -e` would abort a finished run.
prune_dirs() {
  local d
  [ -d "$SRC_ROOT" ] || return 0
  while IFS= read -r -d '' d; do
    rmdir "$d" 2>/dev/null || true
  done < <(find "$SRC_ROOT" -depth -type d -print0)
  return 0
}

# ── symlink refusal ──────────────────────────────────────────────────────────────────────────
# Refusing every symlinked component is the containment boundary: with no symlinked component
# and no `..` in any path, everything the script touches is under the root by construction.
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

# De-duplicated: every source shares the `.docs/reports` prefix, and one hit is one record.
add_symlink_hit_unique() {
  local i=0
  while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    [ "${SYMLINK_HITS[$i]}" = "$1" ] && return 0
    i=$((i+1))
  done
  SYMLINK_HITS[${#SYMLINK_HITS[@]}]="$1"
}

safety_checks() {
  local i=0 d hits=() h
  SYMLINK_HITS=()
  # The fixed set FIRST: a symlinked `.docs/reports` hides its files from `git ls-files`, so
  # the per-file checks below would find nothing and the run would call itself a no-op.
  for d in .docs "$SRC_ROOT" .marvin "$DST_ROOT"; do check_components "$d"; done
  while [ "$i" -lt "${#ALL_SRC[@]}" ]; do
    check_components "${ALL_SRC[$i]}"; i=$((i+1))
  done
  i=0
  while [ "$i" -lt "${#MOVE_DST[@]}" ]; do
    check_components "${MOVE_DST[$i]}"; i=$((i+1))
  done
  hits=(${SYMLINK_HITS[@]+"${SYMLINK_HITS[@]}"}); SYMLINK_HITS=()
  for h in ${hits[@]+"${hits[@]}"}; do add_symlink_hit_unique "$h"; done
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
  # LC_ALL=C: the `git ls-files -v` tag test is a bracket match, and under a UTF-8 locale
  # collation puts `H` inside `[a-z]`. Enumerated, not ranged.
  local gitdir f d rec tag path sub hidden mode LC_ALL=C LC_COLLATE=C LC_CTYPE=C
  gitdir=$(git rev-parse --git-dir)
  # An operation in progress: the agent's commit would silently CONCLUDE the consumer's merge.
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
    [ -e "$gitdir/$f" ] && state_problem "$f exists — an operation is in progress; finish or abort it first"
  done
  for d in rebase-merge rebase-apply; do
    [ -d "$gitdir/$d" ] && state_problem "$d/ exists — a rebase is in progress; finish or abort it first"
  done
  # assume-unchanged / skip-worktree hide modifications from `git status --porcelain`, so a
  # "clean" tree can hide uncommitted work that the rollback would destroy.
  while IFS= read -r -d '' rec; do
    [ -n "$rec" ] || continue
    tag=${rec%% *}; path=${rec#* }
    case "$tag" in
      [abcdefghijklmnopqrstuvwxyz]) state_problem "assume-unchanged bit set on $(q "$path") — its changes are invisible to git status";;
      S)     state_problem "skip-worktree bit set on $(q "$path") — its changes are invisible to git status";;
    esac
  done < <(git ls-files -v -z)
  [ "$(git config --bool core.sparseCheckout 2>/dev/null || echo false)" = "true" ] &&
    state_problem "core.sparseCheckout is enabled — parts of the tree are not present"
  # A submodule UNDER `.docs/reports/`: `git mv` would rewrite `.gitmodules`, and this script
  # never edits content. Move it by hand.
  while IFS= read -r -d '' rec; do
    [ -n "$rec" ] || continue
    mode=${rec%% *}; path=${rec#*$'\t'}
    [ "$mode" = "160000" ] &&
      state_problem "a submodule lives under ${SRC_ROOT}/: $(q "$path") — move it by hand"
  done < <(git ls-files -s -z -- "$(lit "$SRC_ROOT")")
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
# The clean-state precondition (untracked reports included) is what makes this exact: the
# pre-migration state IS HEAD. Armed as a trap so it also covers a kill or a full disk.
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
  clear_move_map
  report rolled-back
  exit 7
}

# Nothing moved, so the report must carry no move records. Used by the rollback and by every
# real-run refusal. `--check` keeps its plan: `mode=check` says it is one.
clear_move_map() {
  MOVE_SRC=(); MOVE_DST=(); EMPTIED=(); STAGE=(); STAGED_COUNT=0
  return 0
}

# A symlink refusal reports the symlink, nothing else. Collisions computed through a link are
# artefacts of the link (a `.marvin` pointing at a file makes every destination "blocked by a
# file"), so printing them would send the user reconciling paths that are not the problem.
clear_collisions() {
  COLL_SRC=(); COLL_DST=(); COLL_WHY=()
  return 0
}

mkdir_tracked() {
  local d="$1"
  [ -d "$d" ] && return 0
  # Record BEFORE creating: a signal between `mkdir` and the bookkeeping would otherwise leave
  # a directory the rollback never hears about.
  MUTATED=1
  CREATED_DIRS[${#CREATED_DIRS[@]}]="$d"
  mkdir "$d"
  return 0
}

# Every level on its own, top down, so each created directory is recorded for the rollback.
mkdir_chain() {
  local p="$1" acc="" part oldifs
  oldifs="$IFS"; IFS=/
  set -f
  for part in $p; do
    IFS="$oldifs"
    if [ -n "$part" ]; then acc="${acc:+$acc/}$part"; mkdir_tracked "$acc"; fi
    IFS=/
  done
  IFS="$oldifs"; set +f
  return 0
}

# ── the report: this is the contract the upgrade and install skills consume ─────────────────
# Emitted from the PLAN in both modes; on failure the rollback clears it. That is what makes
# `--check` and a real run differ only in `mode=`, `staged=` and `result=` by construction.
# `declined=` is always 0 — nothing under `.docs/reports/` is declined — and is kept so the
# record set matches migrate-v0.21.0.sh's.
report() {
  local result="$1" i
  echo "---- ${SELF} report ----"
  echo "version=${KIT_VERSION}"
  echo "$ENCODING_DOC"
  echo "mode=${MODE}"
  echo "renamed=${#MOVE_SRC[@]}"
  echo "declined=0"
  echo "collisions=${#COLL_SRC[@]}"
  echo "failures=${#FAIL_SRC[@]}"
  echo "untracked=${#UNTRACKED[@]}"
  echo "staged=${STAGED_COUNT}"
  echo "committed=no"
  echo "result=${result}"
  i=0; while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    printf 'renamed: %s -> %s\n' "$(q "${MOVE_SRC[$i]}")" "$(q "${MOVE_DST[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#COLL_SRC[@]}" ]; do
    printf 'collision: %s -> %s (%s)\n' "$(q "${COLL_SRC[$i]}")" "$(q "${COLL_DST[$i]}")" \
      "${COLL_WHY[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#FAIL_SRC[@]}" ]; do
    printf 'failure: %s -> %s\n' "$(q "${FAIL_SRC[$i]}")" "$(q "${FAIL_DST[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#UNTRACKED[@]}" ]; do
    printf 'untracked: %s\n' "$(q "${UNTRACKED[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf 'symlink: %s\n' "$(q "${SYMLINK_HITS[$i]}")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#STATE_PROBLEMS[@]}" ]; do
    printf 'repo-state: %s\n' "${STATE_PROBLEMS[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    printf 'references-to-update: %s\n' "$(q "${MOVE_SRC[$i]}")"; i=$((i+1)); done
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

tree_dirty() { [ -n "$DIRTY" ] || [ "${#UNTRACKED[@]}" -gt 0 ]; }

show_dirty() {
  local i=0
  [ -n "$DIRTY" ] && git status --short
  while [ "$i" -lt "${#UNTRACKED[@]}" ]; do
    printf '  untracked under %s/: %s\n' "$SRC_ROOT" "$(q "${UNTRACKED[$i]}")"; i=$((i+1)); done
  return 0
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
safety_checks

# ── nothing to do: checked FIRST, on any tree, in both modes ─────────────────────────────────
# No tracked or untracked file under `.docs/reports/`, and no symlinked `.docs` or
# `.docs/reports` that could be hiding some from git: this run can change nothing, so a dirty
# tree, an unusual repository state or a symlinked `.marvin` elsewhere is not its business. The
# upgrade skill runs this script on every upgrade across v0.35.0; a refusal here would stop an
# upgrade over reports that do not exist.
src_root_linked() { [ -L .docs ] || [ -L "$SRC_ROOT" ]; }
if [ "${#ALL_SRC[@]}" -eq 0 ] && [ "${#UNTRACKED[@]}" -eq 0 ] && ! src_root_linked; then
  say "nothing to migrate — no ${SRC_ROOT}/ content, already at the v${KIT_VERSION} layout"
  finish nothing-to-do
fi

predict_emptied
repo_state_checks

# ── dry run ──────────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
  if [ "${#STATE_PROBLEMS[@]}" -gt 0 ]; then
    say "a real run will REFUSE: the repository state makes this unsafe"
    COMPLETED=1; report plan-only-repo-state; exit 9
  fi
  if tree_dirty; then
    say "a real run will REFUSE: the working tree is not clean"
    show_dirty
    COMPLETED=1; report plan-only-tree-dirty; exit 2
  fi
  if [ "${#SYMLINK_HITS[@]}" -gt 0 ]; then
    say "a real run will REFUSE: symlinked paths are never followed"
    clear_collisions
    COMPLETED=1; report plan-only-symlink; exit 6
  fi
  finish plan
fi

# ── preconditions, in the order a real run hits them ─────────────────────────────────────────
if [ "${#STATE_PROBLEMS[@]}" -gt 0 ]; then
  say "REFUSED — the repository state makes an unattended migration unsafe:"
  i=0; while [ "$i" -lt "${#STATE_PROBLEMS[@]}" ]; do
    printf '  %s\n' "${STATE_PROBLEMS[$i]}"; i=$((i+1)); done
  clear_move_map
  report refused-repo-state
  exit 9
fi
# "git-revertible" is FALSE on a dirty tree, and an untracked report cannot be moved by `git mv`
# or restored by the rollback. Never stash, never delete on the consumer's behalf.
if tree_dirty; then
  say "REFUSED — the working tree is not clean. Commit or remove these yourself, then re-run:"
  show_dirty
  clear_move_map
  report dirty-refused
  exit 2
fi
if [ "${#SYMLINK_HITS[@]}" -gt 0 ]; then
  say "REFUSED — symlinked paths are never followed:"
  i=0; while [ "$i" -lt "${#SYMLINK_HITS[@]}" ]; do
    printf '  %s\n' "$(q "${SYMLINK_HITS[$i]}")"; i=$((i+1)); done
  clear_move_map
  clear_collisions
  report refused-symlink
  exit 6
fi

trap rollback EXIT INT TERM HUP

# ── apply ────────────────────────────────────────────────────────────────────────────────────
if [ "${#MOVE_SRC[@]}" -gt 0 ]; then
  # `git mv` creates no parent directory. Each level is created on its own and recorded.
  mkdir_chain "$DST_ROOT"
  i=0
  while [ "$i" -lt "${#MOVE_SRC[@]}" ]; do
    src="${MOVE_SRC[$i]}"; dst="${MOVE_DST[$i]}"
    mkdir_chain "$(dirname "$dst")"
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
  prune_dirs
fi

# ── stage ────────────────────────────────────────────────────────────────────────────────────
# By explicit literal pathspec, always — a blanket sweep drags untracked consumer files into
# what the agent then commits. `-f` covers a gitignored `.marvin/`: with `:(literal)` the force
# flag can only ever apply to paths this run moved.
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

if [ "${#MOVE_SRC[@]}" -eq 0 ]; then
  say "nothing moved — every report collides with an existing destination"
  finish nothing-to-do
fi

say "moved and staged ${STAGED_COUNT} path(s) — NOTHING COMMITTED."
say "update the references listed under 'references-to-update:', then commit them together."
finish staged
