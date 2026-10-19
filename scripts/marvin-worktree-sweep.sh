#!/usr/bin/env bash
# marvin-worktree-sweep.sh — remove finished agent worktrees (AOS-196 v0.37.0; scope, mode, G8/G9 AOS-223/224/225).
#
#   marvin-worktree-sweep.sh [--check] [--hook] [<repo-dir>]      repo-dir: $CLAUDE_PROJECT_DIR, else $PWD
#
# Scope: linked worktrees physically under <main checkout>/.claude/worktrees/ — never the main
# checkout, never a worktree elsewhere, never a symlink — that Marvin MARKED as its own: a regular
# file (not a symlink) `marvin-owned` in the worktree's git admin dir whose first line matches the
# marker grammar (MH_MARKER_RE; the one writer is marvin-worktree-mark.sh). An unmarked worktree is
# left to the app: never touched, never named; a hand run counts it in one `skipped:` line. A marker
# is written at the agent's first stop and never means "finished": every guard still applies.
# A candidate is KEPT when any guard holds:
#   G1 locked (Claude Code locks a running agent's worktree)
#   G2 a session stands in it ($PWD, or the hook's stdin "cwd", JSON-decoded by the hook lib)
#   G7 another worktree (any listed path under it, prunable too) or a repository (a .git below its
#      top level — nested clones, submodules) lies inside it: `worktree remove` would delete it,
#      and git status cannot see it when .claude/worktrees/ is git-ignored
#   G6 anything in it or in its git admin dir changed within IDLE_MIN minutes
#   G4 a merge, rebase, cherry-pick, revert or bisect is in progress
#   G3 uncommitted or untracked changes (status runs with --no-optional-locks: no index write,
#      so the sweep never "touches" what G6 measures)
#   G8 a git-ignored `.env` or `.env.*` (any depth) that the main checkout lacks at the same relative
#      path, or holds with other bytes
#   G9 a git-ignored file under its .marvin/runs/ that the project's run folder (mh_runs_root) lacks
#      at the same path, or holds with other bytes — run state a hook did not carry home
#   G5 its HEAD is in no branch other than its own (its own origin copy does not count)
# Otherwise: `git worktree remove` (never --force), then — only when origin has a copy of its
# branch — the local branch is deleted by compare-and-delete on the commit the guards checked,
# and its branch.<name> config section with it. Nothing is backed up.
# Mode: PROJECT-INFO frontmatter `worktree_sweep: on | check | off` (absent or invalid → check)
# governs --hook only: on removes; check removes nothing and prints one summary line when it would
# have removed something (naming an invalid value); off is silent. A hand run always sweeps and
# says when the key is not `on`.
# Rules: .marvin/agents/worktrees.md. Paths print through q() (mh_q, git core.quotePath convention).
# --check reports only. --hook (SessionStart): Marvin projects only, one summary line when
# something was removed (or would be, in check mode), otherwise silent, always exit 0.
# Exit without --hook: 0 ok · 1 refused (symlinked scope) · 2 usage / not a git repository / no lib.
set -u

IDLE_MIN=15
MODE=run; HOOK=0; REPO=""; HOOK_CWD=""; NREM=0; REMOVED=""; NSKIP=0
USAGE="usage: marvin-worktree-sweep.sh [--check] [--hook] [<repo-dir>]"

for a in "$@"; do case "$a" in --hook) HOOK=1 ;; esac; done
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || {
  [ "$HOOK" = 1 ] && exit 0; printf 'marvin-worktree-sweep: hook library lib/marvin-hook-lib.sh not found\n' >&2; exit 2; }

q()    { mh_q "$1"; }
say()  { [ "$HOOK" = 1 ] || printf '%s\n' "$1"; }
keep() { say "kept: $(q "$1") — $2"; }
die()  { [ "$HOOK" = 1 ] && exit 0; printf 'marvin-worktree-sweep: %s\n' "$2" >&2; exit "$1"; }

for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --hook)  ;;
    -*)      die 2 "$USAGE" ;;
    *)       [ -z "$REPO" ] || die 2 "$USAGE"; REPO="$a" ;;
  esac
done

if [ "$HOOK" = 1 ] && mh_read_stdin; then   # the host closes stdin; its hook timeout bounds us
  HOOK_CWD=$(printf '%s' "$MH_IN" | mh_get cwd 2>/dev/null) || HOOK_CWD=""
  HOOK_CWD=$(mh_path "$HOOK_CWD") || HOOK_CWD=""
fi

REPO=${REPO:-${CLAUDE_PROJECT_DIR:-$PWD}}
common=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die 2 "not a git repository: $(q "$REPO")"
case "$common" in */.git) ROOT=${common%/.git} ;; *) die 2 "no main checkout (bare repository or separate git dir)" ;; esac
if [ "$HOOK" = 1 ]; then mh_is_marvin "$ROOT" || exit 0; fi
fm=$(mh_frontmatter "$ROOT" 2>/dev/null) || fm=""
mh_mode "$fm" worktree_sweep "on check off" check >/dev/null; SWEEP_MODE=$MH_MODE; SWEEP_INVALID=$MH_MODE_INVALID
if [ "$HOOK" = 1 ]; then
  [ "$SWEEP_MODE" = off ] && exit 0
  [ "$SWEEP_MODE" = check ] && MODE=check
fi
WT_DIR="$ROOT/.claude/worktrees"
if [ -L "$ROOT/.claude" ] || [ -L "$WT_DIR" ]; then
  say "refused: $(q "$WT_DIR") or its parent is a symlink — never followed"
  [ "$HOOK" = 1 ] && exit 0; exit 1
fi
[ -d "$WT_DIR" ] || exit 0
WT_PHYS=$(cd "$WT_DIR" && pwd -P) || exit 0
RUNS=$(mh_runs_root "$ROOT") || RUNS=""   # the project's run folder, physical (G9)

is_current() {  # is_current <physical worktree path> — a session stands in it
  local c cp
  for c in "$PWD" "$HOOK_CWD"; do
    [ -n "$c" ] || continue
    cp=$(cd "$c" 2>/dev/null && pwd -P) || continue
    case "$(mh_path "$cp")/" in "$(mh_path "$1")"/*) return 0 ;; esac
  done
  return 1
}
recent() {  # recent <worktree> <admin dir> — anything modified inside the idle window
  [ -n "$(find "$1" "$2" -mmin -"$IDLE_MIN" -print -quit 2>/dev/null)" ]
}
nested() {  # nested <worktree> <physical path> — another worktree or a repository lies inside it
  local o op w1 w2
  w1=$(mh_path "$1"); w2=$(mh_path "$2")
  for o in ${ALL[@]+"${ALL[@]}"}; do
    op=$(cd "$o" 2>/dev/null && pwd -P) || op=$o; op=$(mh_path "$op")
    case "$op/" in "$w2"/?*|"$w1"/?*) return 0 ;; esac   # a listed worktree, prunable ones too
  done
  [ -n "$(find "$1" -mindepth 2 -name .git -print -quit 2>/dev/null)" ]   # a clone or submodule
}
in_progress() {  # in_progress <admin dir>
  local f
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
    [ -e "$1/$f" ] && return 0
  done
  return 1
}
is_marked() {  # is_marked <worktree> — a regular-file (not symlink) marker whose FIRST line is valid (marvin-worktree-mark.sh's rule)
  local gd f
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || return 1
  f="$gd/marvin-owned"
  [ ! -L "$f" ] && [ -f "$f" ] || return 1
  head -n 1 -- "$f" 2>/dev/null | grep -Eq "$MH_MARKER_RE"
}
# g8 / g9 <worktree> — rc 0 when safe; rc 1 with the keep reason (naming the first offending file) on
# stdout. git lists the ignored files (NUL-separated, pathspec-limited); a listing git could not
# produce keeps the worktree too.
g8() {
  local f s0 s1
  git -C "$1" ls-files -z --others --ignored --exclude-standard -- ':(glob)**/.env' ':(glob)**/.env.*' 2>/dev/null | {
    while IFS= read -r -d '' f; do
      case "${f##*/}" in .env|.env.*) ;; *) continue ;; esac
      if [ ! -e "$ROOT/$f" ] && [ ! -L "$ROOT/$f" ]; then printf 'G8 ignored %s absent from the main checkout' "$(q "$f")"; exit 1; fi
      cmp -s "$1/$f" "$ROOT/$f" || { printf 'G8 ignored %s differs from the main checkout' "$(q "$f")"; exit 1; }
    done; exit 0; }
  s0=${PIPESTATUS[0]} s1=${PIPESTATUS[1]}
  [ "$s1" = 0 ] || return 1
  [ "$s0" = 0 ] || { printf 'G8 ignored files unreadable'; return 1; }
}
g9() {
  local f s0 s1
  git -C "$1" ls-files -z --others --ignored --exclude-standard -- .marvin/runs/ 2>/dev/null | {
    while IFS= read -r -d '' f; do
      case "$f" in .marvin/runs/?*) ;; *) continue ;; esac
      [ -n "$RUNS" ] && cmp -s "$1/$f" "$RUNS/${f#.marvin/runs/}" || { printf 'G9 run state not in the project: %s' "$(q "$f")"; exit 1; }
    done; exit 0; }
  s0=${PIPESTATUS[0]} s1=${PIPESTATUS[1]}
  [ "$s1" = 0 ] || return 1
  [ "$s0" = 0 ] || { printf 'G9 ignored files unreadable'; return 1; }
}
tally() { NREM=$((NREM + 1)); REMOVED="$REMOVED${REMOVED:+,} $(q "$(basename "$p")")"; }   # removed, or would be

landed() {  # landed <sha> <own branch or ""> — the commit is in a branch other than its own
  git -C "$ROOT" for-each-ref --contains "$1" --format='%(refname)' refs/heads refs/remotes 2>/dev/null \
    | B="$2" REMOTES="$(git -C "$ROOT" remote)" awk '
        BEGIN { n = split(ENVIRON["REMOTES"], r, "\n"); b = ENVIRON["B"]; found = 0 }
        b != "" && $0 == "refs/heads/" b { next }
        /^refs\/remotes\/.*\/HEAD$/ { next }
        { own = 0; for (i = 1; i <= n; i++) if (b != "" && $0 == "refs/remotes/" r[i] "/" b) own = 1
          if (!own) found = 1 }
        END { exit found ? 0 : 1 }'
}

consider() {  # one linked worktree: globals p sha b locked prunable
  local p_phys gd st note why
  [ -n "$p" ] || return 0
  if [ -L "$p" ]; then
    case "$p/" in "$WT_DIR"/?*|"$WT_PHYS"/?*) keep "$p" "symlink — never followed" ;; esac; return 0
  fi
  p_phys=$(cd "$p" 2>/dev/null && pwd -P) || {
    case "$p/" in "$WT_DIR"/?*|"$WT_PHYS"/?*) keep "$p" "missing — run git worktree prune" ;; esac; return 0; }
  case "$p_phys/" in "$WT_PHYS"/?*) ;; *) return 0 ;; esac
  [ -n "$prunable" ] && { keep "$p" "prunable — run git worktree prune"; return; }
  is_marked "$p" || { NSKIP=$((NSKIP + 1)); return 0; }   # not Marvin's: left to the app
  [ -n "$locked" ] && { keep "$p" "G1 locked"; return; }
  is_current "$p_phys" && { keep "$p" "G2 current checkout"; return; }
  nested "$p" "$p_phys" && { keep "$p" "G7 another worktree or repository inside it"; return; }
  gd=$(git -C "$p" rev-parse --absolute-git-dir 2>/dev/null) || { keep "$p" "git metadata unreadable"; return; }
  recent "$p" "$gd" && { keep "$p" "G6 active in the last $IDLE_MIN min"; return; }
  in_progress "$gd" && { keep "$p" "G4 merge, rebase, cherry-pick, revert or bisect in progress"; return; }
  st=$(git -C "$p" --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null) || { keep "$p" "G3 status unreadable"; return; }
  [ -n "$st" ] && { keep "$p" "G3 uncommitted or untracked changes"; return; }
  why=$(g8 "$p") || { keep "$p" "$why"; return; }
  why=$(g9 "$p") || { keep "$p" "$why"; return; }
  landed "$sha" "$b" || { keep "$p" "G5 commits not in any other branch"; return; }
  if [ "$MODE" = check ]; then say "would remove: $(q "$p")"; tally; return 0; fi
  git -C "$ROOT" worktree remove "$p" >/dev/null 2>&1 || { keep "$p" "git refused the removal"; return; }
  note=""
  if [ -n "$b" ]; then
    if git -C "$ROOT" show-ref --verify --quiet "refs/remotes/origin/$b"; then
      if ! git -C "$ROOT" merge-base --is-ancestor "$sha" "refs/remotes/origin/$b" 2>/dev/null; then note=" (branch $(q "$b") kept: origin copy is behind)"
      elif git -C "$ROOT" update-ref -d "refs/heads/$b" "$sha" 2>/dev/null; then note=" (branch $(q "$b") deleted)"
        git -C "$ROOT" config --remove-section "branch.$b" 2>/dev/null || true   # its stale push -u tracking
      else note=" (branch $(q "$b") kept: it moved)"; fi
    else note=" (branch $(q "$b") kept: no origin copy)"; fi
  fi
  say "removed: $(q "$p")$note"
  tally
}

ALL=()   # every listed worktree path, for G7
while IFS= read -r -d '' line; do
  case "$line" in "worktree "*) ALL[${#ALL[@]}]=${line#worktree } ;; esac
done < <(git -C "$ROOT" worktree list --porcelain -z 2>/dev/null)

n=0; p=""; sha=""; ref=""; b=""; locked=""; prunable=""
flush() {
  n=$((n + 1)); b=${ref#refs/heads/}; [ -n "$ref" ] || b=""
  [ "$n" -gt 1 ] && consider   # the first record is always the main checkout
  p=""; sha=""; ref=""; b=""; locked=""; prunable=""
}
while IFS= read -r -d '' line; do
  case "$line" in
    "")             flush ;;
    "worktree "*)   p=${line#worktree } ;;
    "HEAD "*)       sha=${line#HEAD } ;;
    "branch "*)     ref=${line#branch } ;;
    locked|"locked "*) locked=1 ;;
    prunable|"prunable "*) prunable=1 ;;
  esac
done < <(git -C "$ROOT" worktree list --porcelain -z 2>/dev/null)
[ -z "$p" ] || flush

if [ "$HOOK" = 1 ]; then
  if [ "$NREM" -gt 0 ] && [ "$MODE" = check ]; then
    printf 'Marvin: worktree sweep in check mode — would remove %d:%s%s\n' "$NREM" "$REMOVED" \
      "${SWEEP_INVALID:+ (invalid worktree_sweep: $(q "$SWEEP_INVALID"))}"
  elif [ "$NREM" -gt 0 ]; then
    printf 'Marvin: removed %d finished agent worktree(s) under .claude/worktrees/:%s\n' "$NREM" "$REMOVED"
  fi
else
  [ "$NSKIP" -eq 0 ] || say "skipped: $NSKIP worktree(s) not created by Marvin — left to the app"
  if mh_is_marvin "$ROOT" && [ "$SWEEP_MODE" != on ]; then
    say "Marvin: worktree sweep is $SWEEP_MODE (worktree_sweep in .marvin/PROJECT-INFO.md)"
  fi
fi
exit 0
