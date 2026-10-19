#!/usr/bin/env bash
# marvin-worktree-mark.sh — mark a worktree as Marvin-owned (AOS-223).
#
#   marvin-worktree-mark.sh --subagent-stop     SubagentStop hook (matcher ^marvin:, stdin = the payload)
#   marvin-worktree-mark.sh <worktree path>     by hand: mark a worktree the orchestrator made itself
#
# The marker is one line in the worktree's git admin dir, `marvin-owned`:
#   marvin-owned <marvin:persona|orchestrator> <agent id|-> <UTC YYYYMMDDTHHMMSSZ>
# The worktree sweep removes only worktrees that carry it. Hook mode marks ONE case: Claude Code's
# isolation worktree of the stopping agent — its physical top level must equal
# <main checkout>/.claude/worktrees/agent-<agent_id>. A non-isolated agent's cwd is the orchestrator's
# own checkout and is never marked. The marker is written once (temp file + mv -n) and never rewritten,
# so the gate's re-fire (stop_hook_active) changes nothing. Hook mode: Marvin projects only, silent,
# always exit 0, JSON read only through the hook lib. By hand: 0 marked or already marked ·
# 1 refused · 2 usage. Paths print through mh_q.
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0

USAGE="usage: marvin-worktree-mark.sh --subagent-stop | <worktree path>"

# is_marked <worktree> — rc 0 when its marker is a regular file (not a symlink) whose first line is valid
is_marked() {
  local gd f
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || return 1
  f="$gd/marvin-owned"
  [ ! -L "$f" ] && [ -f "$f" ] || return 1
  head -n 1 -- "$f" 2>/dev/null | grep -Eq "$MH_MARKER_RE"
}

# write_marker <worktree> <owner> <agent id|-> — only when no file (or symlink) is there yet; rc 0 written
write_marker() {
  local gd f tmp
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) && [ -n "$gd" ] || return 1
  f="$gd/marvin-owned"
  [ -e "$f" ] || [ -L "$f" ] && return 1
  tmp=$(mktemp "$gd/.marvin-owned.XXXXXX" 2>/dev/null) || return 1
  printf 'marvin-owned %s %s %s\n' "$2" "$3" "$(date -u +%Y%m%dT%H%M%SZ)" > "$tmp" 2>/dev/null \
    && mv -n -- "$tmp" "$f" 2>/dev/null
  local rc=$?
  rm -f -- "$tmp" 2>/dev/null
  return "$rc"
}

# main_of <dir> — the physical main checkout of any checkout dir (mh_runs_root minus /.marvin/runs)
main_of() {
  local r; r=$(mh_runs_root "$1") || return 1
  printf '%s' "${r%/.marvin/runs}"
}

# linked_wt <dir> — rc 0 when <dir> is a linked worktree: its admin dir lies under <common dir>/worktrees/
linked_wt() {
  local gd cd_
  gd=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  cd_=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  case "$gd" in "$cd_"/worktrees/?*) return 0 ;; esac
  return 1
}

hook_mode() {
  mh_read_stdin || return 0
  local cwd atype aid main top want
  cwd=$(printf '%s' "$MH_IN" | mh_get cwd) && [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  atype=$(printf '%s' "$MH_IN" | mh_get agent_type) || return 0
  printf '%s' "$atype" | grep -Eq '^marvin:[a-z0-9-]+$' || return 0
  aid=$(printf '%s' "$MH_IN" | mh_get agent_id) || return 0
  printf '%s' "$aid" | grep -Eq '^[0-9a-f]{8,40}$' || return 0
  main=$(main_of "$cwd") && [ -n "$main" ] || return 0
  mh_is_marvin "$main" || return 0
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] || return 0
  top=$(cd "$top" 2>/dev/null && pwd -P) || return 0
  want="$main/.claude/worktrees/agent-$aid"
  [ "$(mh_path "$top")" = "$(mh_path "$want")" ] || return 0
  linked_wt "$top" || return 0
  write_marker "$top" "$atype" "$aid"
  return 0
}

refuse() { printf 'refused: %s — %s\n' "$(mh_q "$1")" "$2"; exit 1; }

hand_mode() {
  local arg="$1" a phys main here
  a=$arg; while [ "${#a}" -gt 1 ] && [ "${a%/}" != "$a" ]; do a=${a%/}; done
  [ -d "$a" ] || refuse "$arg" "not a directory"
  [ -L "$a" ] && refuse "$arg" "a symlink"
  phys=$(cd "$a" 2>/dev/null && pwd -P) || refuse "$arg" "not a directory"
  main=$(main_of "$phys") || refuse "$arg" "not inside a git checkout whose main checkout has a .git directory"
  [ "$(mh_path "$phys")" = "$(mh_path "$main")" ] && refuse "$arg" "the main checkout"
  here=$(pwd -P)
  case "$(mh_path "$here")/" in "$(mh_path "$phys")"/*) refuse "$arg" "the worktree you are standing in" ;; esac
  case "$(mh_path "$phys")" in
    "$(mh_path "$main")/.claude/worktrees/"?*) ;;
    *) refuse "$arg" "not under <main checkout>/.claude/worktrees/" ;;
  esac
  case "${phys#"$main/.claude/worktrees/"}" in */*) refuse "$arg" "not directly under .claude/worktrees/" ;; esac
  [ -L "$main/.claude" ] || [ -L "$main/.claude/worktrees" ] && refuse "$arg" "a symlink under .claude/worktrees"
  linked_wt "$phys" || refuse "$arg" "not a linked worktree"
  gd=$(git -C "$phys" rev-parse --absolute-git-dir 2>/dev/null)
  [ -L "$gd/marvin-owned" ] && refuse "$arg" "its marker file is a symlink"
  if is_marked "$phys"; then printf 'already marked: %s\n' "$(mh_q "$arg")"; exit 0; fi
  [ -e "$gd/marvin-owned" ] && refuse "$arg" "a marker file is there but its first line is not a valid marker"
  write_marker "$phys" orchestrator - || refuse "$arg" "the marker could not be written"
  printf 'marked: %s\n' "$(mh_q "$arg")"
  exit 0
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0   # sourced (the test suite): functions only

case "${1:-}" in
  --subagent-stop) [ "$#" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; hook_mode 2>/dev/null; exit 0 ;;
  ""|-*)           echo "$USAGE" >&2; exit 2 ;;
  *)               [ "$#" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; hand_mode "$1" ;;
esac
