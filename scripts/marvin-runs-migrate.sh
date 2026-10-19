#!/usr/bin/env bash
# marvin-runs-migrate.sh — move a project's run state into the per-session layout (AOS-237). Run by the
# upgrade-agent-os skill's readiness step: `--check` first, the plan shown, then the real run.
#
# SOURCES are the flat run folders `<checkout>/.marvin/runs/<KEY|adhoc>/<file>` of the main checkout and of
# every worktree under `<main>/.claude/worktrees/`. THE TARGET is ONE legacy session folder
# `<main>/.marvin/runs/<UTC of run>-00000000-0000-0000-0000-000000000000/<KEY|adhoc>/<file>` — the nil UUID
# satisfies the session allowlist and the UTC prefix sorts it by time. An existing nil-UUID folder is reused
# (a re-run after a deferral lands in the same folder); more than one refuses. Never sources, never touched:
# `.marvin/runs/.gitignore`, and every folder already named like a session (MH_SESSION_RE). A top-level entry
# whose name is not a key (mh_is_key), and anything in a key folder that is not a regular file, is skipped
# and reported.
#
# MERGE RULES per target name. Mutable (`ledger.md`, `build-brief*.md`): the newest copy by mtime wins the
# target name; every older copy — a displaced existing target included — is kept beside it as
# `<stem>.older-<n>.md`, n = 1, 2, … never overwriting. Immutable (everything else): the first copy lands; a
# later copy identical to what is (or will be) at the target is removed, its bytes being there; a differing
# one stays at its source and is reported `duplicate:` (the sweep's G9 then keeps that worktree).
#
# SHAPE (CLAUDE.md rule 9 discipline, though it moves only ignored files, so no stage and no commit): it MOVES
# and REPORTS, never edits content and never stages. Every move is link-or-copy → cmp → remove the source,
# never overwriting a target, so at every instant each byte is at its source or its target. `--check` prints
# exactly the records a real run would and changes nothing. Guarded — any of these refuses the WHOLE run
# before the first change (exit 1): a symlinked component on a source or target path (`.marvin`,
# `.marvin/runs`, a key folder, a file, the legacy folder), a target git does not ignore, a source file git
# tracks, more than one legacy folder. A deferred worktree (`--defer`) and, with `--defer-flat`, the main
# checkout's flat folders are skipped entirely: `deferred: <path> — open session`. Idempotent: a re-run is
# `result=nothing-to-do`. Every guard has an N* fixture in scripts/test-migrations.sh, mutation-tested by
# scripts/mutate-migrations.sh --script marvin-runs-migrate.sh.
#
# Usage: bash marvin-runs-migrate.sh [--check] [--defer <worktree>]... [--defer-flat] [<repo>]
# Exit: 0 done or nothing to do · 1 refused (nothing moved) or a move failed (nothing lost; re-run resumes) ·
#       2 usage error, not a git work tree, or not a Marvin project.
set -uo pipefail
unset CDPATH

SELF="marvin-runs-migrate"
LIB="$(dirname "$0")/lib/marvin-hook-lib.sh"
if [ ! -f "$LIB" ] || ! . "$LIB" 2>/dev/null; then
  printf '%s: the hook library is missing or unreadable: %s\n' "$SELF" "$LIB" >&2
  exit 2
fi

NIL=00000000-0000-0000-0000-000000000000
NL=$'\n'
NOW=$(date -u +%Y%m%dT%H%M%SZ)
MODE=apply; DEFER_FLAT=0; REPO=""
DEFER_IN=()

usage() {
  cat <<EOF
Usage: bash ${SELF}.sh [--check] [--defer <worktree>]... [--defer-flat] [<repo>]
  Move flat .marvin/runs/<KEY|adhoc>/ run state (main checkout and worktrees under .claude/worktrees/)
  into ONE legacy session folder .marvin/runs/<UTC>-${NIL}/. Moves and reports only.
  --check        print exactly the records a real run would; change nothing
  --defer <wt>   skip a worktree with an open session (repeatable; must be under .claude/worktrees/)
  --defer-flat   skip the main checkout's flat folders (a session is open there)
  <repo>         any directory of the project (default: the current directory)
EOF
}
usage_err() { printf '%s: %s\n' "$SELF" "$1" >&2; usage >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check)      MODE=check ;;
    --defer)      [ $# -ge 2 ] || usage_err "--defer needs a worktree path"
                  DEFER_IN[${#DEFER_IN[@]}]="$2"; shift ;;
    --defer-flat) DEFER_FLAT=1 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           usage_err "unknown option: $1" ;;
    *)            [ -z "$REPO" ] || usage_err "more than one repository path"; REPO="$1" ;;
  esac
  shift
done
[ -n "$REPO" ] || REPO=.
[ -d "$REPO" ] || usage_err "not a directory: $(mh_q "$REPO")"
RUNS=$(mh_runs_root "$REPO") && [ -n "$RUNS" ] || { printf '%s: not a git work tree with a main checkout: %s\n' "$SELF" "$(mh_q "$REPO")" >&2; exit 2; }
MAIN=${RUNS%/.marvin/runs}
if [ ! -L "$MAIN/.marvin" ] && [ ! -d "$MAIN/.marvin" ]; then
  printf '%s: not a Marvin project (no .marvin/ in the main checkout): %s\n' "$SELF" "$(mh_q "$MAIN")" >&2; exit 2
fi

# ── state ────────────────────────────────────────────────────────────────────────────────────
OP_T=(); OP_S=(); OP_D=()        # planned operations: move | dedup | older | displace, in apply order
DUP_S=(); DUP_D=()               # differing immutable copies left at their source
DEFERRED=(); SKIP_P=(); SKIP_WHY=(); HITS=(); REFUSED=()
WT=(); DEFER=()                  # physical worktree paths under .claude/worktrees/; the deferred ones

rel()  { case "$1" in "$MAIN"/*) printf '%s' "${1#"$MAIN"/}" ;; *) printf '%s' "$1" ;; esac; }
hit()  { local i=0; while [ "$i" -lt "${#HITS[@]}" ]; do [ "${HITS[$i]}" = "$1" ] && return 0; i=$((i+1)); done
         HITS[${#HITS[@]}]="$1"; }
skip() { SKIP_P[${#SKIP_P[@]}]="$1"; SKIP_WHY[${#SKIP_WHY[@]}]="$2"; }
refuse() { REFUSED[${#REFUSED[@]}]="$1"; }
op()   { OP_T[${#OP_T[@]}]="$1"; OP_S[${#OP_S[@]}]="$2"; OP_D[${#OP_D[@]}]="$3"; }
has()  { [ -e "$1" ] || [ -L "$1" ]; }   # present on disk, a dangling link included
no_nl() { case "$1" in *"$NL"*) return 1 ;; esac; return 0; }
is_session() { no_nl "$1" && printf '%s' "$1" | grep -Eq "$MH_SESSION_RE"; }
is_key()     { no_nl "$1" && mh_is_key "$1"; }
is_mutable() { case "$1" in ledger.md|build-brief*.md) return 0 ;; esac; return 1; }
in_list() {  # in_list <value> <array name>
  local v="$1" n i=0 x
  eval "n=\${#$2[@]}"
  while [ "$i" -lt "$n" ]; do eval "x=\${$2[$i]}"; [ "$x" = "$v" ] && return 0; i=$((i+1)); done
  return 1
}
phys() { (cd "$1" 2>/dev/null && pwd -P); }

# ── the worktrees, and the deferred ones ─────────────────────────────────────────────────────
# Listed through a temp file so git's exit status is seen: a failed listing is never "no worktrees" —
# it would silently leave every worktree's run state behind and call the run done.
WT_RAW=()
WTL=$(mktemp "${TMPDIR:-/tmp}/${SELF}.XXXXXX") || { printf '%s: refused: cannot create a temp file\n' "$SELF" >&2; exit 2; }
if ! git -C "$MAIN" worktree list --porcelain -z > "$WTL" 2>/dev/null; then
  rm -f -- "$WTL"
  printf '%s: refused: cannot list worktrees (git worktree list failed) — nothing moved\n' "$SELF" >&2
  exit 2
fi
while IFS= read -r -d '' p; do
  case "$p" in "worktree "*) WT_RAW[${#WT_RAW[@]}]=${p#worktree } ;; esac
done < "$WTL"
rm -f -- "$WTL"
if [ "${#WT_RAW[@]}" -gt 0 ]; then
  while IFS= read -r -d '' p; do
    pp=$(phys "$p") || continue
    case "$pp" in "$MAIN/.claude/worktrees/"*) in_list "$pp" WT || WT[${#WT[@]}]="$pp" ;; esac
  done < <(printf '%s\0' "${WT_RAW[@]}" | LC_ALL=C sort -z)
fi
i=0
while [ "$i" -lt "${#DEFER_IN[@]}" ]; do
  d=${DEFER_IN[$i]}; i=$((i+1))
  pd=$(phys "$d") || usage_err "--defer: not a directory: $(mh_q "$d")"
  in_list "$pd" WT || usage_err "--defer: not a worktree under .claude/worktrees/: $(mh_q "$d")"
  in_list "$pd" DEFER || DEFER[${#DEFER[@]}]="$pd"
done

# ── the scan: per checkout, its flat key folders ─────────────────────────────────────────────
CHK=()                           # checkouts whose flat folders are sources, main first
if [ "$DEFER_FLAT" = 1 ]; then DEFERRED[${#DEFERRED[@]}]="$MAIN/.marvin/runs"; else CHK[0]="$MAIN"; fi
i=0
while [ "$i" -lt "${#WT[@]}" ]; do
  if in_list "${WT[$i]}" DEFER; then DEFERRED[${#DEFERRED[@]}]="${WT[$i]}"; else CHK[${#CHK[@]}]="${WT[$i]}"; fi
  i=$((i+1))
done

KC_C=(); KC_K=()                 # (checkout, key) pairs with a real key folder
KEYS=()                          # the distinct keys, in first-seen order
TRK=()                           # tracked paths under the scanned checkout's .marvin/runs
scan_checkout() {
  local c="$1" r="$1/.marvin/runs" e n
  if [ -L "$c/.marvin" ]; then hit "$c/.marvin"; return 0; fi
  [ -d "$c/.marvin" ] || return 0
  if [ -L "$r" ]; then hit "$r"; return 0; fi
  [ -d "$r" ] || return 0
  while IFS= read -r -d '' e; do
    n=${e##*/}
    [ "$n" = .gitignore ] && continue                  # the ignore file stays where it is
    is_session "$n" && continue                        # already the per-session layout
    if ! is_key "$n"; then skip "$e" "not a key folder"; continue; fi
    if [ -L "$e" ]; then hit "$e"; continue; fi
    if [ ! -d "$e" ]; then skip "$e" "not a key folder"; continue; fi
    KC_C[${#KC_C[@]}]="$c"; KC_K[${#KC_K[@]}]="$n"
    in_list "$n" KEYS || KEYS[${#KEYS[@]}]="$n"
  done < <(find "$r" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | LC_ALL=C sort -z)
}
i=0
while [ "$i" -lt "${#CHK[@]}" ]; do scan_checkout "${CHK[$i]}"; i=$((i+1)); done

# ── the target: the project's runs folder and its ONE legacy folder ──────────────────────────
L=""
if [ -L "$MAIN/.marvin" ]; then hit "$MAIN/.marvin"
elif [ -L "$RUNS" ]; then hit "$RUNS"
else
  LEG=()
  if [ -d "$RUNS" ]; then
    while IFS= read -r -d '' e; do
      n=${e##*/}
      is_session "$n" || continue
      case "$n" in *-"$NIL") ;; *) continue ;; esac
      if [ -L "$e" ]; then hit "$e"; elif [ -d "$e" ]; then LEG[${#LEG[@]}]="$n"; else refuse "a legacy name that is not a folder: $(mh_q "$(rel "$e")")"; fi
    done < <(find "$RUNS" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | LC_ALL=C sort -z)
  fi
  if [ "${#LEG[@]}" -gt 1 ]; then
    refuse "more than one legacy folder: $(i=0; while [ "$i" -lt "${#LEG[@]}" ]; do printf '%s ' "$(mh_q ".marvin/runs/${LEG[$i]}")"; i=$((i+1)); done)— merge them by hand, then re-run"
  elif [ "${#LEG[@]}" -eq 1 ]; then L=${LEG[0]}
  else L="$NOW-$NIL"; fi
fi
LEGACY_EXISTED=0; [ -n "$L" ] && [ -d "$RUNS/$L" ] && LEGACY_EXISTED=1

# ── the plan, key by key, name by name ───────────────────────────────────────────────────────
tracked_in() {  # tracked_in <checkout> — fill TRK with its tracked paths under .marvin/runs/ (absolute)
  local c="$1" t
  TRK=()
  while IFS= read -r -d '' t; do [ -n "$t" ] && TRK[${#TRK[@]}]="$c/$t"; done \
    < <(git -C "$c" ls-files -z -- ':(literal).marvin/runs' 2>/dev/null)
}

# alloc_older <dir> <stem> — the first <stem>.older-<n>.md present neither on disk, in the plan, nor as
# another source name of this key
alloc_older() {
  local n=1 p
  while :; do
    p="$1/$2.older-$n.md"
    if ! has "$p" && ! in_list "$p" OP_D && ! in_list "${p##*/}" GB; then printf '%s' "$p"; return 0; fi
    n=$((n+1))
  done
}

# plan_group <target> <source>... — every copy of one name of one key
KEPT=()
kept_match() {  # kept_match <file> — the planned destination of a kept copy byte-identical to <file>
  local i=0
  while [ "$i" -lt "${#KEPT[@]}" ]; do
    cmp -s -- "$1" "${KEPT[$i]}" && { printf '%s' "${KEPT_D[$i]}"; return 0; }
    i=$((i+1))
  done
  return 1
}
plan_group() {
  local t="$1" s w i stem dir m o
  shift
  dir=${t%/*}; KEPT=(); KEPT_D=()
  if [ -L "$t" ]; then hit "$t"; return 0; fi
  if has "$t" && [ ! -f "$t" ]; then refuse "a target that is not a regular file: $(mh_q "$(rel "$t")")"; return 0; fi
  if ! is_mutable "${t##*/}"; then
    if has "$t"; then KEPT[0]="$t"; else op move "$1" "$t"; KEPT[0]="$1"; shift; fi
    KEPT_D[0]="$t"
    for s in "$@"; do
      if cmp -s -- "$s" "${KEPT[0]}"; then op dedup "$s" "$t"; else DUP_S[${#DUP_S[@]}]="$s"; DUP_D[${#DUP_D[@]}]="$t"; fi
    done
    return 0
  fi
  stem=${t##*/}; stem=${stem%.md}
  w=""; has "$t" && w="$t"
  for s in "$@"; do if [ -z "$w" ] || [ "$s" -nt "$w" ]; then w="$s"; fi; done
  if [ "$w" != "$t" ]; then
    if has "$t" && cmp -s -- "$w" "$t"; then op dedup "$w" "$t"
    else
      if has "$t"; then o=$(alloc_older "$dir" "$stem"); op displace "$t" "$o"; KEPT[${#KEPT[@]}]="$t"; KEPT_D[${#KEPT_D[@]}]="$o"; fi
      op move "$w" "$t"
    fi
  fi
  KEPT[${#KEPT[@]}]="$w"; KEPT_D[${#KEPT_D[@]}]="$t"
  for s in "$@"; do
    [ "$s" = "$w" ] && continue
    if m=$(kept_match "$s"); then op dedup "$s" "$m"; continue; fi
    o=$(alloc_older "$dir" "$stem"); op older "$s" "$o"
    KEPT[${#KEPT[@]}]="$s"; KEPT_D[${#KEPT_D[@]}]="$o"
  done
}

plan_key() {  # plan_key <key>
  local k="$1" j=0 c kd f n g b
  GS=(); GB=()                                         # this key's source paths and names, scan order
  while [ "$j" -lt "${#KC_K[@]}" ]; do
    if [ "${KC_K[$j]}" = "$k" ]; then
      c=${KC_C[$j]}; kd="$c/.marvin/runs/$k"
      tracked_in "$c"
      while IFS= read -r -d '' f; do
        n=${f##*/}
        if [ -L "$f" ]; then hit "$f"; continue; fi
        if [ ! -f "$f" ]; then skip "$f" "not a run file"; continue; fi
        if in_list "$f" TRK; then refuse "tracked by git: $(mh_q "$(rel "$f")")"; continue; fi
        GS[${#GS[@]}]="$f"; GB[${#GB[@]}]="$n"
      done < <(find "$kd" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | LC_ALL=C sort -z)
    fi
    j=$((j+1))
  done
  [ "${#GS[@]}" -gt 0 ] || return 0
  if [ -L "$RUNS/$L/$k" ]; then hit "$RUNS/$L/$k"; return 0; fi
  DONE=()
  g=0
  while [ "$g" -lt "${#GS[@]}" ]; do
    b=${GB[$g]}
    if ! in_list "$b" DONE; then
      DONE[${#DONE[@]}]="$b"
      MEM=(); j=$g
      while [ "$j" -lt "${#GS[@]}" ]; do [ "${GB[$j]}" = "$b" ] && MEM[${#MEM[@]}]="${GS[$j]}"; j=$((j+1)); done
      plan_group "$RUNS/$L/$k/$b" "${MEM[@]}"
    fi
    g=$((g+1))
  done
}
if [ -n "$L" ] && [ "${#HITS[@]}" -eq 0 ]; then
  i=0; while [ "$i" -lt "${#KEYS[@]}" ]; do plan_key "${KEYS[$i]}"; i=$((i+1)); done
fi

# ── every path this run would create must be ignored by git ──────────────────────────────────
if [ "${#HITS[@]}" -eq 0 ]; then
  i=0
  while [ "$i" -lt "${#OP_T[@]}" ]; do
    case "${OP_T[$i]}" in
      move|older|displace)
        git -C "$MAIN" check-ignore -q -- "${OP_D[$i]}" 2>/dev/null ||
          refuse "not ignored by git: $(mh_q "$(rel "${OP_D[$i]}")") — ignore .marvin/runs/, then re-run" ;;
    esac
    i=$((i+1))
  done
fi

# ── the report: the contract the upgrade skill reads ─────────────────────────────────────────
ENCODING_DOC='encoding=paths are relative to the main checkout, printed raw when they match [A-Za-z0-9._/@+-]+, otherwise C-quoted in double quotes with \n \t \r \" \\ and \ooo escapes (git core.quotePath convention); exactly one record per line'
count_t() { local n=0 i=0; while [ "$i" -lt "${#OP_T[@]}" ]; do case " $* " in *" ${OP_T[$i]} "*) n=$((n+1)) ;; esac; i=$((i+1)); done; echo "$n"; }
report() {
  local result="$1" i tgt=none
  [ -n "$L" ] && { [ "${#OP_T[@]}" -gt 0 ] || [ "$LEGACY_EXISTED" = 1 ]; } && tgt=".marvin/runs/$L"
  echo "---- ${SELF} report ----"
  echo "$ENCODING_DOC"
  echo "mode=${MODE}"
  echo "target=${tgt}"
  echo "moved=$(count_t move dedup)"
  echo "kept-older=$(count_t older displace)"
  echo "duplicates=${#DUP_S[@]}"
  echo "deferred=${#DEFERRED[@]}"
  echo "skipped=${#SKIP_P[@]}"
  echo "result=${result}"
  i=0; while [ "$i" -lt "${#OP_T[@]}" ]; do
    case "${OP_T[$i]}" in move|dedup) printf 'moved: %s -> %s\n' "$(mh_q "$(rel "${OP_S[$i]}")")" "$(mh_q "$(rel "${OP_D[$i]}")")" ;; esac
    i=$((i+1)); done
  i=0; while [ "$i" -lt "${#OP_T[@]}" ]; do
    case "${OP_T[$i]}" in older|displace) printf 'kept-older: %s -> %s\n' "$(mh_q "$(rel "${OP_S[$i]}")")" "$(mh_q "$(rel "${OP_D[$i]}")")" ;; esac
    i=$((i+1)); done
  i=0; while [ "$i" -lt "${#DUP_S[@]}" ]; do
    printf 'duplicate: %s (differs from %s)\n' "$(mh_q "$(rel "${DUP_S[$i]}")")" "$(mh_q "$(rel "${DUP_D[$i]}")")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#DEFERRED[@]}" ]; do
    printf 'deferred: %s — open session\n' "$(mh_q "$(rel "${DEFERRED[$i]}")")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#SKIP_P[@]}" ]; do
    printf 'skipped: %s (%s)\n' "$(mh_q "$(rel "${SKIP_P[$i]}")")" "${SKIP_WHY[$i]}"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#HITS[@]}" ]; do
    printf 'symlink: %s\n' "$(mh_q "$(rel "${HITS[$i]}")")"; i=$((i+1)); done
  i=0; while [ "$i" -lt "${#REFUSED[@]}" ]; do
    printf 'refused: %s\n' "${REFUSED[$i]}"; i=$((i+1)); done
  echo "---- end ${SELF} report ----"
}

# A refusal moves nothing, so its report carries no move records.
if [ "${#HITS[@]}" -gt 0 ]; then
  refuse "a symlinked component is never followed — replace it with a real folder or file, then re-run"
fi
if [ "${#REFUSED[@]}" -gt 0 ]; then
  OP_T=(); OP_S=(); OP_D=(); DUP_S=(); DUP_D=()
  printf '%s: REFUSED — nothing moved; the refused: lines say why\n' "$SELF"
  report refused
  exit 1
fi
if [ "${#OP_T[@]}" -eq 0 ]; then
  printf '%s: nothing to move\n' "$SELF"
  report nothing-to-do
  exit 0
fi
if [ "$MODE" = check ]; then
  printf '%s: --check — the real run would make these moves; nothing changed\n' "$SELF"
  report done
  exit 0
fi

# ── apply ────────────────────────────────────────────────────────────────────────────────────
# place <src> <dst> — a hard link (same filesystem) or a verified copy beside <dst>, linked in; either way
# never over an existing <dst>. Only once <dst> compares equal is <src> removed.
place() {
  local s="$1" d="$2" dir=${2%/*} tmp
  has "$d" && return 1
  mkdir -p -- "$dir" 2>/dev/null || return 1
  [ -L "$dir" ] || [ -L "${dir%/*}" ] && return 1
  if ! ln -- "$s" "$d" 2>/dev/null; then
    has "$d" && return 1
    tmp=$(mktemp "$dir/.${SELF}.XXXXXX" 2>/dev/null) || return 1
    if ! cp -p -- "$s" "$tmp" 2>/dev/null || ! ln -- "$tmp" "$d" 2>/dev/null; then rm -f -- "$tmp"; return 1; fi
    rm -f -- "$tmp"
  fi
  cmp -s -- "$s" "$d" || { rm -f -- "$d"; return 1; }
  rm -f -- "$s"
}
i=0
while [ "$i" -lt "${#OP_T[@]}" ]; do
  s=${OP_S[$i]}; d=${OP_D[$i]}
  case "${OP_T[$i]}" in
    dedup) cmp -s -- "$s" "$d" && rm -f -- "$s"; okk=$? ;;
    *)     place "$s" "$d"; okk=$? ;;
  esac
  if [ "$okk" != 0 ]; then
    OP_T=("${OP_T[@]:0:$i}"); OP_S=("${OP_S[@]:0:$i}"); OP_D=("${OP_D[@]:0:$i}")
    refuse "move failed: $(mh_q "$(rel "$s")") -> $(mh_q "$(rel "$d")") — nothing lost; fix the cause and re-run to resume"
    printf '%s: FAILED mid-run — every byte is at its source or its target; re-run resumes\n' "$SELF"
    report refused
    exit 1
  fi
  i=$((i+1))
done
# Best effort: a source key folder left empty is removed; one still holding a skipped entry stays.
i=0
while [ "$i" -lt "${#KC_C[@]}" ]; do rmdir -- "${KC_C[$i]}/.marvin/runs/${KC_K[$i]}" 2>/dev/null || true; i=$((i+1)); done
printf '%s: moved run state into .marvin/runs/%s/ — nothing staged, nothing committed\n' "$SELF" "$L"
report done
exit 0
