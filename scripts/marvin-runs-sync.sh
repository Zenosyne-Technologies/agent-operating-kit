#!/usr/bin/env bash
# marvin-runs-sync.sh — carry run state to the project's per-session run folder (AOS-224).
#
#   --session-start   SessionStart (every source): make or reuse <runs>/<UTC start>-<session_id>/, seed a
#                     non-project checkout's missing ledger.md / build-brief*.md from the project, print one line
#   --post-tool       PostToolUse Write|Edit|MultiEdit, main thread only: an orchestrator write under its own
#                     checkout's .marvin/runs/<session>/<KEY|adhoc>/ is copied to the project
#   --subagent-stop   SubagentStop ^marvin:: each timestamped report the agent's brief names that sits in the
#                     agent's checkout is COPIED to the project; the source is never deleted (the gate may send
#                     the agent back to rewrite it, and Claude Code deletes an isolated worktree itself)
#   --stop            Stop, main thread only: the --post-tool rules for every MUTABLE layout file (ledger.md,
#                     build-brief*.md) under this session's folder in its own checkout, carried only into a
#                     project <session>/<KEY>/ that already exists — the catch-up for writes made through Bash
#                     (`>>`). It never creates a key folder (a prune stays done) and never copies a timestamped
#                     report (SubagentStop carries those, and must record them as its own)
#
# The project run folder is <main checkout>/.marvin/runs (mh_runs_root), the ONLY copy readers use. A file is
# carried only when it is exactly <checkout>/.marvin/runs/<session>/<KEY|adhoc>/<name> (MH_SESSION_RE,
# mh_is_key), the checkout is not the project itself, and <name> is mutable (ledger.md, build-brief*.md) or
# timestamped (MH_STAMP_RE); anything else is left alone, so a flat-layout project is untouched. Every write
# applies the run-state symlink rule: no symlinked component under .marvin/, .marvin/runs/.gitignore = *
# bootstrapped, and refused when git check-ignore says the target is not ignored. ledger.md overwrites the
# project copy only when that copy is a byte prefix of the local one; a timestamped name is copied only when
# absent — except on SubagentStop, where a differing target THIS agent carried before (its per-agent ledger
# <session>/<KEY>/.carried-<agent_id>, one relative path per line, ignored by `*`) is overwritten: the gate's
# send-back makes the agent rewrite its report. Anything else that differs is a clash: both copies are kept
# and one line names them; on SubagentStop the differing source is ALSO saved beside the target as
# <stem>.clash-<agent_id>[-<n>].md (never overwriting), since Claude Code deletes a clean agent worktree right
# after the hook. A layout-shaped path whose <KEY> fails the key rule is refused with a notice, never skipped
# silently. A refused carry that is not a symlink refusal (those stay silent) prints one line:
# `Marvin run-state sync refused: <why> — <path>`, <why> one of key not allowed | not ignored | unreadable |
# copy failed. Carried copies and sidecars get the umask's normal file mode (mktemp's 0600 is undone).
# Only --session-start is gated on the briefing.md literal: it creates the session folder and tells the
# orchestrator to use it. The others need no gate — they act only on exact per-session layout paths, which
# a project still on the flat layout never writes, so such a project is untouched by construction.
#
# Clash channel — probed 2026-10-19 (CLI 2.1.289, claude -p with a sub-agent): on PostToolUse a
# {"systemMessage"} is shown to the user only, plain stdout reaches no one, and hookSpecificOutput.
# additionalContext reaches the model, so --post-tool prints both fields. A SubagentStop {"systemMessage"}
# surfaced nowhere in print mode and the event has no model-facing field, so --subagent-stop prints
# {"systemMessage"} (the fallback); --stop prints {"systemMessage"} too (a Stop "decision" would block the
# stop, which a notice must never do). Hook modes: Marvin projects only, silent on any doubt, always exit 0,
# JSON read only through the hook lib, paths compared through mh_path and printed through mh_q.
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0

USAGE="usage: marvin-runs-sync.sh --session-start | --post-tool | --subagent-stop | --stop"
LITERAL='.marvin/runs/<session>/'   # the installed briefing.md carries it once the project is on this layout
NL='
'
AID=""     # the stopping sub-agent's id (--subagent-stop), when valid
NOTES=""   # clash and refusal lines, printed once at the end of a hook mode
FMODE=$(printf '%o' $(( 0666 & ~0$(umask) )) 2>/dev/null) || FMODE=644   # a new file's normal mode under this umask

# phys_top <dir> — the physical top level of the checkout holding <dir>
phys_top() {
  local t
  t=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) && [ -n "$t" ] || return 1
  (cd "$t" 2>/dev/null && pwd -P)
}

# project_of <checkout top> — sets RUNS (<main>/.marvin/runs, physical) and MAIN; rc 1 outside a Marvin project
project_of() {
  RUNS=$(mh_runs_root "$1") && [ -n "$RUNS" ] || return 1
  MAIN=${RUNS%/.marvin/runs}
  mh_is_marvin "$MAIN"
}

is_session() { case "$1" in *"$NL"*) return 1 ;; esac; printf '%s' "$1" | grep -Eq "$MH_SESSION_RE"; }
is_key()     { case "$1" in *"$NL"*) return 1 ;; esac; mh_is_key "$1"; }

# kind <name> — prints mutable | stamped; rc 1 for a name this hook never carries
kind() {
  case "$1" in ""|.|..|*/*|*"$NL"*) return 1 ;; esac
  case "$1" in ledger.md|build-brief*.md) echo mutable; return 0 ;; esac
  printf '%s' "$1" | grep -Eq "$MH_STAMP_RE" && { echo stamped; return 0; }
  return 1
}

# layout_rel <checkout top> <file path> — prints <session>/<key>/<name> when the file is exactly
# <top>/.marvin/runs/<session>/<KEY|adhoc>/<name>; rc 4 when it has that shape but <KEY> fails the key rule
# (the caller refuses it with a notice); rc 1 otherwise (deeper, flatter, a bad session or name)
layout_rel() {
  local top p rel s k b
  top=$(mh_path "$1") && p=$(mh_path "$2") || return 1
  case "$p" in *"$NL"*) return 1 ;; "$top"/.marvin/runs/*) ;; *) return 1 ;; esac
  rel=${p#"$top"/.marvin/runs/}
  case "$rel" in */*/*/*) return 1 ;; */*/*) ;; *) return 1 ;; esac
  s=${rel%%/*}; k=${rel#*/}; k=${k%%/*}; b=${rel##*/}
  case "$k" in .|..) return 1 ;; esac
  is_session "$s" && kind "$b" >/dev/null || return 1
  is_key "$k" || return 4
  printf '%s' "$rel"
}

# no_links <top> <rel under .marvin/runs> — rc 0 when <top>/.marvin, <top>/.marvin/runs and every component of
# <rel> below it is not a symlink (test -L, so a dangling link refuses too)
no_links() {
  local d="$1/.marvin" r="$2" seg
  [ -L "$d" ] && return 1; d="$d/runs"; [ -L "$d" ] && return 1
  while [ -n "$r" ]; do
    seg=${r%%/*}; d="$d/$seg"; [ -L "$d" ] && return 1
    case "$r" in */*) r=${r#*/} ;; *) r="" ;; esac
  done
  return 0
}

# bootstrap <top> — <top>/.marvin/runs exists and holds .gitignore = * (written once, never through a link).
# rc 0 ready · 1 refused (not Marvin, or a symlink: silent) · 3 a write failed
bootstrap() {
  local runs="$1/.marvin/runs"
  mh_is_marvin "$1" && no_links "$1" "" || return 1
  [ -L "$runs/.gitignore" ] && return 1
  mkdir -p -- "$runs" 2>/dev/null || return 3
  [ -L "$runs" ] && return 1
  [ -e "$runs/.gitignore" ] || (set -C; printf '*\n' > "$runs/.gitignore") 2>/dev/null || return 3
  return 0
}

# ready <top> <dir rel under .marvin/runs> [<name>] — the run-state symlink rule before a write under
# <top>/.marvin/runs: refuse a symlinked component, bootstrap .gitignore = *, refuse when the target is not
# ignored, then make the directory. rc 0 ready · 1 symlink or not Marvin · 2 not ignored · 3 a write failed
ready() {
  local top="$1" runs="$1/.marvin/runs" rel="$2${3:+/$3}"
  no_links "$top" "$rel" || return 1
  bootstrap "$top" || return $?
  git -C "$top" check-ignore -q -- "$runs/$rel" 2>/dev/null || return 2
  mkdir -p -- "$runs/$2" 2>/dev/null || return 3
  no_links "$top" "$rel" || return 1
}

# refuse <why> <path> — note a non-symlink refusal; gate <rc> <path> — rc 0 only when ready said 0
refuse() { NOTES="${NOTES:+$NOTES$NL}Marvin run-state sync refused: $1 — $(mh_q "$2")"; }
gate() {
  case "$1" in 0) return 0 ;; 2) refuse "not ignored" "$2" ;; 3) refuse "copy failed" "$2" ;; esac
  return 1
}

# put <src> <dst> <overwrite: yes|no> — atomic: a temp file beside <dst>, then one rename
put() {
  local tmp rc=1
  tmp=$(mktemp "${2%/*}/.marvin-sync.XXXXXX" 2>/dev/null) || return 1
  if cp -- "$1" "$tmp" 2>/dev/null; then
    chmod "$FMODE" "$tmp" 2>/dev/null   # mktemp made it 0600; a carried copy gets the normal mode
    if [ "$3" = yes ]; then mv -f -- "$tmp" "$2" 2>/dev/null; else mv -n -- "$tmp" "$2" 2>/dev/null; fi
    rc=$?
  fi
  rm -f -- "$tmp" 2>/dev/null
  [ "$rc" -eq 0 ] && [ -f "$2" ]
}

# is_prefix <short> <long> — rc 0 when <short>'s bytes are a prefix of <long>'s
is_prefix() {
  local n m
  n=$(wc -c < "$1" | tr -d ' ') && m=$(wc -c < "$2" | tr -d ' ') || return 1
  [ "$n" -le "$m" ] || return 1
  head -c "$n" -- "$2" | cmp -s - "$1"
}

clash() {  # clash <local> <project> [<sidecar>]
  local side=""; [ -n "${3:-}" ] && side=" — differing copy saved as $(mh_q "$3")"
  NOTES="${NOTES:+$NOTES$NL}Marvin run-state clash: $(mh_q "$1") differs from $(mh_q "$2") — both kept; reconcile before the next dispatch.$side"
}

# sidecar <src> <dst> <tag> — save the differing <src> beside <dst> as <stem>.clash-<tag>.md, else -<n> for
# n = 2..50: an identical one already there is reused, a differing or symlinked one is never overwritten.
# Prints the sidecar path; rc 1 when none could be written.
sidecar() {
  local stem=${2%.md} n=1 p
  while [ "$n" -le 50 ]; do
    p="$stem.clash-$3.md"; [ "$n" -gt 1 ] && p="$stem.clash-$3-$n.md"
    if [ -e "$p" ] || [ -L "$p" ]; then
      [ ! -L "$p" ] && cmp -s "$1" "$p" && { printf '%s' "$p"; return 0; }
    else
      git -C "$MAIN" check-ignore -q -- "$p" 2>/dev/null && put "$1" "$p" no && cmp -s "$1" "$p" || return 1
      printf '%s' "$p"; return 0
    fi
    n=$((n + 1))
  done
  return 1
}
jstr() {  # jstr <text> — a JSON string literal (the text is mh_q-encoded paths plus fixed words)
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')"
}

# carry_rel <checkout top> <rel> — the post-tool / stop carry of one local layout file to the project
carry_rel() {
  local src="$1/.marvin/runs/$2" dst="$RUNS/$2"
  no_links "$1" "$2" && [ -f "$src" ] || return 0
  [ -r "$src" ] || { refuse unreadable "$src"; return 0; }
  ready "$MAIN" "${2%/*}" "${2##*/}"; gate $? "$dst" || return 0
  [ "$src" -ef "$dst" ] && return 0
  carry "$src" "$dst" "$(kind "${2##*/}")"
}

# carried <rel> / was_carried <rel> — the per-agent ledger <RUNS>/<session>/<KEY>/.carried-<agent_id>: record
# a target this agent carried, ask whether it did. Never through a symlink; no agent id → no ledger.
ledger_of() { [ -n "$AID" ] && printf '%s' "${1%/*}/.carried-$AID"; }
was_carried() {
  local l; l=$(ledger_of "$1") || return 1
  no_links "$MAIN" "$l" && [ -f "$RUNS/$l" ] && grep -Fxq -- "$1" "$RUNS/$l" 2>/dev/null
}
carried() {
  local l; l=$(ledger_of "$1") || return 0
  was_carried "$1" && return 0
  no_links "$MAIN" "$l" && git -C "$MAIN" check-ignore -q -- "$RUNS/$l" 2>/dev/null || return 0
  printf '%s\n' "$1" >> "$RUNS/$l" 2>/dev/null
  chmod "$FMODE" "$RUNS/$l" 2>/dev/null
  return 0
}

# carry <src> <dst> <kind> — the post-tool copy rules
carry() {
  local src="$1" dst="$2"
  case "$3" in
    stamped) if [ -e "$dst" ] || [ -L "$dst" ]; then cmp -s "$src" "$dst" || clash "$src" "$dst"; return 0; fi
             put "$src" "$dst" no || { refuse "copy failed" "$dst"; return 0; }
             cmp -s "$src" "$dst" || clash "$src" "$dst" ;;
    mutable) cmp -s "$src" "$dst" && return 0
             if [ "${dst##*/}" = ledger.md ] && [ -e "$dst" ]; then
               is_prefix "$dst" "$src" || { clash "$src" "$dst"; return 0; }
             fi
             put "$src" "$dst" yes || refuse "copy failed" "$dst" ;;
  esac
}

session_start() {
  mh_read_stdin || return 0
  local sid cwd top b d name=""
  sid=$(printf '%s' "$MH_IN" | mh_get session_id) || return 0
  case "$sid" in *"$NL"*) return 0 ;; esac
  printf '%s' "$sid" | grep -Eq '^[0-9a-f-]{36}$' || return 0
  cwd=$(printf '%s' "$MH_IN" | mh_get cwd) && [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  top=$(phys_top "$cwd") || return 0
  project_of "$top" || return 0
  b="$top/.marvin/agents/briefing.md"                     # the rules this session reads; else the project's
  [ -e "$b" ] || [ -L "$b" ] || b="$MAIN/.marvin/agents/briefing.md"
  [ ! -L "$b" ] && [ -f "$b" ] && grep -Fq -- "$LITERAL" "$b" 2>/dev/null || return 0
  for d in "$RUNS"/*-"$sid"; do
    [ -d "$d" ] && [ ! -L "$d" ] && is_session "${d##*/}" && { name=${d##*/}; break; }
  done
  [ -n "$name" ] || name="$(date -u +%Y%m%dT%H%M%SZ)-$sid"
  is_session "$name" || return 0
  ready "$MAIN" "$name" || return 0
  if [ "$(mh_path "$top")" != "$(mh_path "$MAIN")" ]; then   # the local checkout: its run files stay ignored
    bootstrap "$top"
    seed "$top" "$name"
  fi
  printf 'Marvin run folder: %s/ — write run files under %s/ in your own checkout; hooks carry them to the project.\n' \
    "$(mh_q "$RUNS/$name")" "$(mh_q ".marvin/runs/$name")"
  [ -z "$NOTES" ] || printf '%s\n' "$NOTES"
}

# seed <checkout top> <session> — copy this session's project ledger.md / build-brief*.md into a checkout
# that lacks them (resume, or a recycle into a new worktree), so a short fresh local ledger never stands in
seed() {
  local top="$1" s="$2" kd k f dst
  for kd in "$RUNS/$s"/*; do
    [ -d "$kd" ] && [ ! -L "$kd" ] || continue
    is_key "${kd##*/}" || { refuse "key not allowed" "$kd"; continue; }
    k=${kd##*/}
    for f in "$kd"/ledger.md "$kd"/build-brief*.md; do
      [ -f "$f" ] && [ ! -L "$f" ] && [ "$(kind "${f##*/}")" = mutable ] || continue
      dst="$top/.marvin/runs/$s/$k/${f##*/}"
      [ -e "$dst" ] || [ -L "$dst" ] && continue
      ready "$top" "$s/$k" "${f##*/}" || continue
      put "$f" "$dst" no
    done
  done
}

post_tool() {
  mh_read_stdin || return 0
  pt_carry
  [ -n "$NOTES" ] || return 0
  printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$(jstr "$NOTES")" "$(jstr "$NOTES")"
}

pt_carry() {
  local fp cwd pdir top rel rc
  fp=$(printf '%s' "$MH_IN" | mh_get tool_input.file_path) && [ -n "$fp" ] || return 0
  fp=$(mh_path "$fp") || return 0
  case "$fp" in */.marvin/runs/*) ;; *) return 0 ;; esac   # the cheap exit for every other write
  mh_is_subagent_call && return 0
  cwd=$(printf '%s' "$MH_IN" | mh_get cwd) && [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  top=$(phys_top "$cwd") || return 0
  project_of "$top" || return 0
  [ "$(mh_path "$top")" = "$(mh_path "$MAIN")" ] && return 0
  pdir=$(cd "${fp%/*}" 2>/dev/null && pwd -P) || return 0
  rel=$(layout_rel "$top" "$pdir/${fp##*/}"); rc=$?
  [ "$rc" -eq 4 ] && { refuse "key not allowed" "$pdir/${fp##*/}"; return 0; }
  [ "$rc" -eq 0 ] || return 0
  carry_rel "$top" "$rel"
}

stop_mode() {
  mh_read_stdin || return 0
  mh_is_subagent_call && return 0                          # main thread only
  local sid cwd top d kd f rel rc
  sid=$(printf '%s' "$MH_IN" | mh_get session_id) || return 0
  case "$sid" in *"$NL"*) return 0 ;; esac
  printf '%s' "$sid" | grep -Eq '^[0-9a-f-]{36}$' || return 0
  cwd=$(printf '%s' "$MH_IN" | mh_get cwd) && [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  top=$(phys_top "$cwd") || return 0
  project_of "$top" || return 0
  [ "$(mh_path "$top")" = "$(mh_path "$MAIN")" ] && return 0
  no_links "$top" "" || return 0
  for d in "$top/.marvin/runs"/*-"$sid"; do                # this session's folder(s) in its own checkout
    [ -d "$d" ] && [ ! -L "$d" ] && is_session "${d##*/}" || continue
    for kd in "$d"/*; do
      [ -d "$kd" ] && [ ! -L "$kd" ] || continue
      for f in "$kd"/*; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        [ "$(kind "${f##*/}")" = mutable ] || continue   # timestamped reports are SubagentStop's
        rel=$(layout_rel "$top" "$f"); rc=$?
        if [ "$rc" -eq 4 ]; then refuse "key not allowed" "$f"; continue; fi
        [ "$rc" -eq 0 ] || continue
        [ -d "$RUNS/${rel%/*}" ] && [ ! -L "$RUNS/${rel%/*}" ] || continue   # never (re)create a key folder: a prune stays done
        carry_rel "$top" "$rel"
      done
    done
  done
  [ -n "$NOTES" ] || return 0
  printf '{"systemMessage":%s}\n' "$(jstr "$NOTES")"
}

subagent_stop() {
  mh_read_stdin || return 0
  local cwd atype tp tag top brief cands sre p rel rc src dst side
  cwd=$(printf '%s' "$MH_IN" | mh_get cwd) && [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  atype=$(printf '%s' "$MH_IN" | mh_get agent_type) || return 0
  printf '%s' "$atype" | grep -Eq '^marvin:[a-z0-9-]+$' || return 0
  tp=$(printf '%s' "$MH_IN" | mh_get agent_transcript_path) && [ -n "$tp" ] || return 0
  AID=$(printf '%s' "$MH_IN" | mh_get agent_id) || AID=""
  case "$AID" in *"$NL"*) AID="" ;; esac
  printf '%s' "$AID" | grep -Eq '^[0-9a-f]{8,40}$' || AID=""   # no valid id: no carried ledger, never an overwrite
  tag=${AID:-$(date -u +%Y%m%dT%H%M%SZ)}
  top=$(phys_top "$cwd") || return 0
  project_of "$top" || return 0
  [ "$(mh_path "$top")" = "$(mh_path "$MAIN")" ] && return 0   # the project itself: nothing to carry
  brief=$(mh_first_user_text "$(mh_path "$tp")") && [ -n "$brief" ] || return 0
  sre=${MH_SESSION_RE#^}; sre=${sre%\$}
  cands=$(printf '%s\n' "$brief" | grep -oE "\.marvin/runs/$sre/[A-Za-z0-9._-]+/${MH_STAMP_RE#^}[A-Za-z0-9._-]*\.md" | sort -u)
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    rel=$(layout_rel "$top" "$top/$p"); rc=$?
    if [ "$rc" -eq 4 ]; then [ -f "$top/$p" ] && refuse "key not allowed" "$top/$p"; continue; fi
    [ "$rc" -eq 0 ] || continue
    [ "$(kind "${rel##*/}")" = stamped ] || continue   # mutable files are the orchestrator's own
    src="$top/.marvin/runs/$rel"; dst="$RUNS/$rel"
    no_links "$top" "$rel" && [ -f "$src" ] || continue
    [ -r "$src" ] || { refuse unreadable "$src"; continue; }
    ready "$MAIN" "${rel%/*}" "${rel##*/}"; gate $? "$dst" || continue
    [ "$src" -ef "$dst" ] && continue
    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
      put "$src" "$dst" no || { refuse "copy failed" "$dst"; continue; }
      cmp -s "$src" "$dst" && { carried "$rel"; continue; }
    fi
    cmp -s "$src" "$dst" && continue                    # already there: the source stays, nothing to record
    if was_carried "$rel"; then put "$src" "$dst" yes && cmp -s "$src" "$dst" || refuse "copy failed" "$dst"; continue; fi
    side=$(sidecar "$src" "$dst" "$tag") || side=""
    clash "$src" "$dst" "$side"
  done <<EOF
$cands
EOF
  [ -n "$NOTES" ] || return 0
  printf '{"systemMessage":%s}\n' "$(jstr "$NOTES")"
}

case "${1:-}" in
  --session-start) [ "$#" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; session_start 2>/dev/null; exit 0 ;;
  --post-tool)     [ "$#" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; post_tool 2>/dev/null; exit 0 ;;
  --subagent-stop) [ "$#" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; subagent_stop 2>/dev/null; exit 0 ;;
  --stop)          [ "$#" -eq 1 ] || { echo "$USAGE" >&2; exit 2; }; stop_mode 2>/dev/null; exit 0 ;;
  *)               echo "$USAGE" >&2; exit 2 ;;
esac
