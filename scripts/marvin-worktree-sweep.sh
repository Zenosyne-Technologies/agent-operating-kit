#!/usr/bin/env bash
# marvin-worktree-sweep.sh — remove finished agent worktrees (AOS-196, v0.37.0).
#
#   marvin-worktree-sweep.sh [--check] [--hook] [<repo-dir>]      repo-dir: $CLAUDE_PROJECT_DIR, else $PWD
#
# Scope: linked worktrees physically under <main checkout>/.claude/worktrees/ — never the main
# checkout, never a worktree elsewhere, never a symlink. A candidate is KEPT when any guard holds:
#   G1 locked (Claude Code locks a running agent's worktree)
#   G2 a session stands in it ($PWD, or the hook's stdin "cwd")
#   G7 another worktree (any listed path under it, prunable too) or a repository (a .git below its
#      top level — nested clones, submodules) lies inside it: `worktree remove` would delete it,
#      and git status cannot see it when .claude/worktrees/ is git-ignored
#   G6 anything in it or in its git admin dir changed within IDLE_MIN minutes
#   G4 a merge, rebase, cherry-pick, revert or bisect is in progress
#   G3 uncommitted or untracked changes (status runs with --no-optional-locks: no index write,
#      so the sweep never "touches" what G6 measures)
#   G5 its HEAD is in no branch other than its own (its own origin copy does not count)
# Otherwise: `git worktree remove` (never --force), then — only when origin has a copy of its
# branch — the local branch is deleted by compare-and-delete on the commit the guards checked,
# and its branch.<name> config section with it.
# Rules: .marvin/agents/worktrees.md. Paths print through q() (git core.quotePath convention).
# --check reports only. --hook (SessionStart): Marvin projects only, one summary line when
# something was removed, otherwise silent, always exit 0.
# Exit without --hook: 0 ok · 1 refused (symlinked scope) · 2 usage / not a git repository.
set -u

IDLE_MIN=15
MODE=run; HOOK=0; REPO=""; HOOK_CWD=""; NREM=0; REMOVED=""
USAGE="usage: marvin-worktree-sweep.sh [--check] [--hook] [<repo-dir>]"

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
say()  { [ "$HOOK" = 1 ] || printf '%s\n' "$1"; }
keep() { say "kept: $(q "$1") — $2"; }
die()  { [ "$HOOK" = 1 ] && exit 0; printf 'marvin-worktree-sweep: %s\n' "$2" >&2; exit "$1"; }

for a in "$@"; do case "$a" in --hook) HOOK=1 ;; esac; done
for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --hook)  ;;
    -*)      die 2 "$USAGE" ;;
    *)       [ -z "$REPO" ] || die 2 "$USAGE"; REPO="$a" ;;
  esac
done

if [ "$HOOK" = 1 ] && [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then stdin_json=$(timeout 2 head -c 65536 2>/dev/null || true)
  else stdin_json=$(head -c 65536 2>/dev/null || true); fi   # the host closes stdin; its hook timeout bounds us
  HOOK_CWD=$(printf '%s' "$stdin_json" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 \
             | sed -E 's/^"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//')
fi

REPO=${REPO:-${CLAUDE_PROJECT_DIR:-$PWD}}
common=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
  || die 2 "not a git repository: $(q "$REPO")"
case "$common" in */.git) ROOT=${common%/.git} ;; *) die 2 "no main checkout (bare repository or separate git dir)" ;; esac
if [ "$HOOK" = 1 ]; then [ -d "$ROOT/.marvin" ] && [ ! -L "$ROOT/.marvin" ] || exit 0; fi
WT_DIR="$ROOT/.claude/worktrees"
if [ -L "$ROOT/.claude" ] || [ -L "$WT_DIR" ]; then
  say "refused: $(q "$WT_DIR") or its parent is a symlink — never followed"
  [ "$HOOK" = 1 ] && exit 0; exit 1
fi
[ -d "$WT_DIR" ] || exit 0
WT_PHYS=$(cd "$WT_DIR" && pwd -P) || exit 0

is_current() {  # is_current <physical worktree path> — a session stands in it
  local c cp
  for c in "$PWD" "$HOOK_CWD"; do
    [ -n "$c" ] || continue
    cp=$(cd "$c" 2>/dev/null && pwd -P) || continue
    case "$cp/" in "$1"/*) return 0 ;; esac
  done
  return 1
}
recent() {  # recent <worktree> <admin dir> — anything modified inside the idle window
  [ -n "$(find "$1" "$2" -mmin -"$IDLE_MIN" -print -quit 2>/dev/null)" ]
}
nested() {  # nested <worktree> <physical path> — another worktree or a repository lies inside it
  local o op
  for o in ${ALL[@]+"${ALL[@]}"}; do
    op=$(cd "$o" 2>/dev/null && pwd -P) || op=$o
    case "$op/" in "$2"/?*|"$1"/?*) return 0 ;; esac   # a listed worktree, prunable ones too
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
  local p_phys gd st note
  [ -n "$p" ] || return 0
  if [ -L "$p" ]; then
    case "$p/" in "$WT_DIR"/?*|"$WT_PHYS"/?*) keep "$p" "symlink — never followed" ;; esac; return 0
  fi
  p_phys=$(cd "$p" 2>/dev/null && pwd -P) || {
    case "$p/" in "$WT_DIR"/?*|"$WT_PHYS"/?*) keep "$p" "missing — run git worktree prune" ;; esac; return 0; }
  case "$p_phys/" in "$WT_PHYS"/?*) ;; *) return 0 ;; esac
  [ -n "$prunable" ] && { keep "$p" "prunable — run git worktree prune"; return; }
  [ -n "$locked" ] && { keep "$p" "G1 locked"; return; }
  is_current "$p_phys" && { keep "$p" "G2 current checkout"; return; }
  nested "$p" "$p_phys" && { keep "$p" "G7 another worktree or repository inside it"; return; }
  gd=$(git -C "$p" rev-parse --absolute-git-dir 2>/dev/null) || { keep "$p" "git metadata unreadable"; return; }
  recent "$p" "$gd" && { keep "$p" "G6 active in the last $IDLE_MIN min"; return; }
  in_progress "$gd" && { keep "$p" "G4 merge, rebase, cherry-pick, revert or bisect in progress"; return; }
  st=$(git -C "$p" --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null) || { keep "$p" "G3 status unreadable"; return; }
  [ -n "$st" ] && { keep "$p" "G3 uncommitted or untracked changes"; return; }
  landed "$sha" "$b" || { keep "$p" "G5 commits not in any other branch"; return; }
  if [ "$MODE" = check ]; then say "would remove: $(q "$p")"; return 0; fi
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
  NREM=$((NREM + 1)); REMOVED="$REMOVED${REMOVED:+,} $(q "$(basename "$p")")"
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

if [ "$HOOK" = 1 ] && [ "$NREM" -gt 0 ]; then
  printf 'Marvin: removed %d finished agent worktree(s) under .claude/worktrees/:%s\n' "$NREM" "$REMOVED"
fi
exit 0
