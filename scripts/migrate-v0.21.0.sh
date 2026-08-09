#!/usr/bin/env bash
# migrate-v0.21.0.sh — move Marvin's machinery out of `.docs/` into `.marvin/` in a
# CONSUMER repository. This is the executable form of the v0.21.0 step of the
# `upgrade-agent-os` skill: an agent runs it, reads its report, and reconciles by hand only
# what the script declines to touch.
#
# It performs destructive git operations, unattended, inside a repository the kit does not
# own. Every guard below is a safety control, each one there because its absence was
# reproduced losing consumer data. scripts/test-migrations.sh pins them.
#
# Usage: bash migrate-v0.21.0.sh [--check | --no-commit]
#   --check      dry run: print the exact plan, change nothing at all
#   --no-commit  perform + stage the changes, leave them uncommitted for inspection
#
# Exit codes:
#   0  success (including a clean no-op re-run)
#   2  refused: working tree was not clean
#   3  completed, but destination collisions need reconciling by hand
#   4  usage error / not a git work tree
#   5  a planned change failed to apply
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
# Possibly emptied by the moves above; removal is best effort (see prune_dirs).
PRUNE_DIRS=".docs/agents docs/agents .docs/marvin docs/marvin"

TAB=$'\t'
PLAN_MOVE=""      # src<TAB>dst    real path moves
PLAN_CASE=""      # dir<TAB>from   handbook INDEX.md -> index.md (case only)
DECLINED=""       # path<TAB>reason
COLLISIONS=""     # src<TAB>dst<TAB>reason
FAILURES=""       # src<TAB>dst
MOVED=""          # src<TAB>dst
REWRITTEN=""      # path
STAGE=()
COMMIT_SHA="none"

usage() {
  cat <<EOF
Usage: bash ${SELF}.sh [--check | --no-commit]
  (no flag)    migrate, stage by explicit path, commit as ONE atomic commit
  --check      dry run — print the plan, change nothing
  --no-commit  migrate and stage, but do not commit
EOF
}

say() { printf '%s\n' "$SELF: $*"; }

# Index membership, case-EXACT. `git ls-files --error-unmatch` is the membership test, but on
# its own it is not enough here: with core.ignorecase (the macOS default) a pathspec can match
# an index entry that differs only in case, which would make the handbook rename look already
# done. Re-check that the exact string came back.
tracked_exact() {
  git ls-files --error-unmatch -- "$1" >/dev/null 2>&1 || return 1
  git ls-files -- "$1" | grep -Fxq -- "$1"
}

in_cascade() { printf '%s\n' "$CASCADE_FILES" | grep -Fxq -- "$1"; }

add_move()      { PLAN_MOVE="${PLAN_MOVE}${1}${TAB}${2}"$'\n'; }
add_case()      { PLAN_CASE="${PLAN_CASE}${1}${TAB}${2}"$'\n'; }
add_declined()  { DECLINED="${DECLINED}${1}${TAB}${2}"$'\n'; }
add_collision() { COLLISIONS="${COLLISIONS}${1}${TAB}${2}${TAB}${3}"$'\n'; }
count()         { if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | grep -c . || true; fi; }

# ── destination guards ───────────────────────────────────────────────────────────────────────
# REAL path moves: a destination counts as occupied if it is in the index OR present on disk.
# A consumer who hand-migrated with cp/mv — or whose `.marvin/` is gitignored — leaves an
# untracked destination that an index-only guard walks straight past; `git mv` then either
# aborts the whole run or nests the source into `.marvin/agents/agents/`.
dst_occupied_real() { tracked_exact "$1" || [ -e "$1" ]; }
# CASE-ONLY handbook rename: index ONLY, never the disk test. `INDEX.md` and `index.md` are the
# same inode on a case-insensitive filesystem, so `[ -e … ]` is already true before the rename
# and would skip it silently — shipping `INDEX.md` and breaking case-sensitive checkouts.
dst_occupied_case() { tracked_exact "$1"; }

plan_real_move() {
  local src="$1" dst="$2"
  tracked_exact "$src" || return 0
  if dst_occupied_real "$dst"; then
    add_collision "$src" "$dst" "destination already exists — reconcile by hand"
    return 0
  fi
  add_move "$src" "$dst"
}

build_plan() {
  local d p base s dir from
  # 1. the kit's cascade, file by file against the allowlist
  for d in $CASCADE_SRC_DIRS; do
    while IFS= read -r p; do
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
    done < <(git ls-files -- "$d")
  done
  # 2. PROJECT-INFO + MEMORY
  for s in $PROJECT_INFO_SRCS; do plan_real_move "$s" ".marvin/PROJECT-INFO.md"; done
  for s in $MEMORY_SRCS;       do plan_real_move "$s" ".marvin/MEMORY.md"; done
  # 3. handbook index, per audience: INDEX.md -> index.md, case only.
  #    `__index.tmp` is a RESUME MARKER, not debris: the rename is two `git mv` calls through a
  #    temp name, and a run that died between them leaves only the temp file — the source guard
  #    is off forever, so skipping it loses the handbook index permanently. Check the temp FIRST.
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    from=""
    if tracked_exact "$dir/__index.tmp"; then from="__index.tmp"; fi
    if [ -n "$from" ] && tracked_exact "$dir/INDEX.md"; then
      add_collision "$dir/__index.tmp" "$dir/index.md" \
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
  done < <(git ls-files -- '.docs/handbooks/*/INDEX.md' '.docs/handbooks/*/__index.tmp' \
           | sed 's#/[^/]*$##' | sort -u)
}

# ── reference rewrite ────────────────────────────────────────────────────────────────────────
# `INDEX.md` -> `index.md` is anchored to `.docs/handbooks/…` paths ONLY. A blanket pass
# corrupts a Local-tracker install: its `tracker-config.md` carries `.docs/project-management/
# INDEX.md` references that STAY uppercase — lowercase them and the filing agent finds no
# index, creates one at `next_issue: 1`, and starts overwriting existing issue files.
rewrite_to() {
  LC_ALL=C sed -E \
    -e 's#\.docs/agents/#.marvin/agents/#g' \
    -e 's#(^|[^A-Za-z0-9._-])docs/agents/#\1.marvin/agents/#g' \
    -e 's#\.docs/PROJECT-INFO\.md#.marvin/PROJECT-INFO.md#g' \
    -e 's#(^|[^A-Za-z0-9._-])docs/PROJECT-INFO\.md#\1.marvin/PROJECT-INFO.md#g' \
    -e 's#\.docs/marvin/#.marvin/#g' \
    -e 's#(\.docs/handbooks/[A-Za-z0-9._-]+/)INDEX\.md#\1index.md#g' \
    "$1"
}

needs_rewrite() {
  [ -f "$1" ] || return 1
  ! rewrite_to "$1" | cmp -s - "$1"
}

apply_rewrite() {
  local f="$1" tmpf
  [ -f "$f" ] || return 0
  tmpf=$(mktemp "${TMPDIR:-/tmp}/marvin-migrate.XXXXXX")
  rewrite_to "$f" > "$tmpf"
  if cmp -s "$tmpf" "$f"; then rm -f "$tmpf"; return 0; fi
  cat "$tmpf" > "$f"          # in place: keeps the file's mode and inode
  rm -f "$tmpf"
  REWRITTEN="${REWRITTEN}${f}"$'\n'
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

emit_list() {  # emit_list <label> <tsv-blob> <fmt-fields>
  local label="$1" blob="$2" a b c
  [ -n "$blob" ] || return 0
  printf '%s\n' "$blob" | grep . | while IFS="$TAB" read -r a b c; do
    case "$label" in
      moved|failure) printf '%s: %s -> %s\n' "$label" "$a" "$b";;
      declined)      printf 'declined: %s (%s)\n' "$a" "$b";;
      collision)     printf 'collision: %s -> %s (%s)\n' "$a" "$b" "$c";;
      rewritten)     printf 'rewritten: %s\n' "$a";;
    esac
  done
  return 0
}

report() {
  local result="$1"
  echo "---- ${SELF} report ----"
  echo "version=${KIT_VERSION}"
  echo "mode=${MODE}"
  echo "moved=$(count "$MOVED")"
  echo "declined=$(count "$DECLINED")"
  echo "collisions=$(count "$COLLISIONS")"
  echo "failures=$(count "$FAILURES")"
  echo "rewritten=$(count "$REWRITTEN")"
  echo "commit=${COMMIT_SHA}"
  echo "result=${result}"
  emit_list moved     "$MOVED"
  emit_list declined  "$DECLINED"
  emit_list collision "$COLLISIONS"
  emit_list failure   "$FAILURES"
  emit_list rewritten "$REWRITTEN"
  echo "---- end ${SELF} report ----"
  return 0
}

final_result() {
  if [ -n "$FAILURES" ]; then echo failed
  elif [ -n "$COLLISIONS" ]; then echo collisions
  else echo ok; fi
}

finish() {
  report "$(final_result)"
  if [ -n "$FAILURES" ]; then exit 5; fi
  if [ -n "$COLLISIONS" ]; then exit 3; fi
  exit 0
}

# ── argument parsing ─────────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check";;
    --no-commit) MODE="no-commit";;
    -h|--help)   usage; exit 0;;
    *)           usage >&2; exit 4;;
  esac
  shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { say "not a git work tree — refusing"; exit 4; }
cd "$(git rev-parse --show-toplevel)"

# ── precondition: clean tree ─────────────────────────────────────────────────────────────────
# "git-revertible" — the justification for running this unattended — is FALSE on a dirty tree:
# the consumer's WIP and untracked files land in the migration commit, and the `git revert`
# this step advertises then destroys them. Never stash on their behalf: a stash the script
# creates is a stash the user does not know to pop.
if [ -n "$(git status --porcelain)" ]; then
  say "REFUSED — the working tree is not clean. Commit or stash these yourself, then re-run:"
  git status --short
  report dirty-refused
  exit 2
fi

build_plan

if [ "$MODE" = "check" ]; then
  say "plan (dry run — nothing will be changed):"
  if [ -n "$PLAN_MOVE" ]; then
    printf '%s\n' "$PLAN_MOVE" | grep . | while IFS="$TAB" read -r a b; do
      printf '  move:    %s -> %s\n' "$a" "$b"; done
  fi
  if [ -n "$PLAN_CASE" ]; then
    printf '%s\n' "$PLAN_CASE" | grep . | while IFS="$TAB" read -r a b; do
      printf '  rename:  %s/%s -> %s/index.md (case only, via __index.tmp)\n' "$a" "$b" "$a"; done
  fi
  # Reference rewrite, previewed against the paths as they stand today.
  targets="CLAUDE.md"
  if [ -n "$PLAN_MOVE" ]; then
    targets="$targets $(printf '%s\n' "$PLAN_MOVE" | grep . | cut -f1 | tr '\n' ' ')"
  fi
  if [ -n "$PLAN_CASE" ]; then
    targets="$targets $(printf '%s\n' "$PLAN_CASE" | grep . | awk -F"$TAB" '{print $1"/"$2}' | tr '\n' ' ')"
  fi
  for t in $targets; do
    if needs_rewrite "$t"; then
      printf '  rewrite: %s\n' "$t"
      REWRITTEN="${REWRITTEN}${t}"$'\n'
    fi
  done
  if [ -z "$PLAN_MOVE$PLAN_CASE$REWRITTEN" ]; then echo "  (nothing to do)"; fi
  finish
fi

# ── apply: real path moves ───────────────────────────────────────────────────────────────────
if [ -n "$PLAN_MOVE" ]; then
  # `git mv` creates no parent directory, and `mkdir -p .marvin` alone is not enough for the
  # per-file cascade moves — every one of those dies "fatal: … No such file or directory".
  mkdir -p .marvin .marvin/agents
  while IFS="$TAB" read -r src dst; do
    [ -n "$src" ] || continue
    mkdir -p "$(dirname "$dst")"
    if git mv -- "$src" "$dst"; then
      MOVED="${MOVED}${src}${TAB}${dst}"$'\n'
      stage_path "$dst"
    else
      FAILURES="${FAILURES}${src}${TAB}${dst}"$'\n'
    fi
  done < <(printf '%s\n' "$PLAN_MOVE" | grep .)
fi

# ── apply: case-only handbook renames, through the resume marker ─────────────────────────────
if [ -n "$PLAN_CASE" ]; then
  while IFS="$TAB" read -r dir from; do
    [ -n "$dir" ] || continue
    ok=1
    if [ "$from" = "INDEX.md" ]; then
      git mv -- "$dir/INDEX.md" "$dir/__index.tmp" || ok=0
    fi
    if [ "$ok" = 1 ]; then git mv -- "$dir/__index.tmp" "$dir/index.md" || ok=0; fi
    if [ "$ok" = 1 ]; then
      MOVED="${MOVED}${dir}/${from}${TAB}${dir}/index.md"$'\n'
      stage_path "$dir/index.md"
    else
      FAILURES="${FAILURES}${dir}/${from}${TAB}${dir}/index.md"$'\n'
    fi
  done < <(printf '%s\n' "$PLAN_CASE" | grep .)
fi

prune_dirs

# ── apply: reference rewrite ─────────────────────────────────────────────────────────────────
# CLAUDE.md plus the migrated files at their NEW paths. Nothing else is touched: the script's
# entire blast radius is those four locations and CLAUDE.md.
i=0
while [ "$i" -lt "${#STAGE[@]}" ]; do
  apply_rewrite "${STAGE[$i]}"
  i=$((i+1))
done
apply_rewrite "CLAUDE.md"
if printf '%s\n' "$REWRITTEN" | grep -Fxq "CLAUDE.md"; then stage_path "CLAUDE.md"; fi

# ── stage + commit ───────────────────────────────────────────────────────────────────────────
# Staging is by explicit path, always. A blanket stage-everything sweep drags untracked
# consumer files (a fixture caught `.env.local`) into the migration commit, and the `git
# revert` escape hatch this step advertises then destroys them.
# The renames AND the CLAUDE.md rewrite land in ONE commit: a revert that restored the file
# locations but not the references — or the other way round — leaves an inconsistent repo.
# `-f` covers one real case only: a consumer who gitignored `.marvin/`. `git mv` has already put
# those paths in the index, but `git add` still refuses an ignored pathspec and would leave the
# migration half-staged. The pathspec is an explicit, kit-owned list either way — never a sweep.
if [ ${#STAGE[@]} -gt 0 ]; then
  git add -f -- "${STAGE[@]}"
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
