#!/usr/bin/env bash
# marvin-context-budget.sh — PostToolUse + UserPromptSubmit hook for the marvin plugin (AOS-187, v0.38.0).
#
# Session length is governed by context size, as a SOFT break the orchestrator plans for. The hook reads
# the transcript the host names, takes the context size of the latest assistant message (input +
# cache-read + cache-creation tokens) and maps it to a LEVEL — the stricter of two scales (lib mh_level):
#   absolute budgets  400k soft → 1, 700k hard → 2 (session_soft_ktokens / session_hard_ktokens override)
#   context ladder    70 % → 1, 80 % → 2, 90 % → 3 of the compaction window (mh_budget_init resolves it)
#   PostToolUse      — only on the turn the level RISES (stateless: the last two messages are compared).
#   UserPromptSubmit — on every prompt at level ≥ 1: the user is present, so that is when to tell them.
# Fleet mode (a role marker, lib mh_fleet_role; no marker = the solo texts above, unchanged): level 3 only
# winds down (a child: toward the rest point, never idling below it); the REST point (lib mh_fleet_rest, a
# state above level 3) tells a child or master to write the handoff and keep working until the host
# auto-compacts it. A child is sent a SUCCESSOR instead at the compaction cap, when its first message after a
# compaction is too large, or when compaction is off (DISABLE_COMPACT); DISABLE_AUTO_COMPACT means no rest
# point (today's level-3 text). The compaction history is read only for a fleet child at level ≥ 2, after a
# size drop, or on a prompt (it costs ~0.8 s per 100 MB).
# What each level demands is owned by .marvin/agents/session-budget.md (fleet: fleet.md, fleet-child.md).
# Contract: Marvin projects only; sub-agent invocations skipped; never writes a file; always exits 0; only
# numbers this script computed reach the output; never blocks.
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0
mh_read_stdin || exit 0
mh_is_subagent_call && exit 0

event=$(printf '%s' "$MH_IN" | mh_get hook_event_name) || exit 0
case "$event" in PostToolUse|UserPromptSubmit) ;; *) exit 0 ;; esac
transcript=$(printf '%s' "$MH_IN" | mh_get transcript_path) || exit 0
root=$(mh_root); mh_is_marvin "$root" || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

fm=$(mh_frontmatter "$root") || fm=""
mh_budget_init "$fm"
mh_fleet_role "$root" >/dev/null
sizes=$(mh_sizes "$transcript")
[ -n "$sizes" ] || exit 0
cur=$(printf '%s\n' "$sizes" | tail -n 1)
prev=$(printf '%s\n' "$sizes" | head -n 1); [ "$(printf '%s\n' "$sizes" | wc -l)" -ge 2 ] || prev=0
lc=$(mh_level "$cur"); lp=$(mh_level "$prev")

S1="plan only work that can finish before level 2 (the 80% step or the hard budget, whichever comes first) — split or defer anything larger, dispatch no size:l or size:xl task — and at the next clean logical break (all work committed, tracker current, no sub-agent running) tell the user where the session stands."
S2="start no new task: finish the in-flight one to the next clean logical break (all work committed, tracker current, no sub-agent running) and write the handoff now."
S3="STOP at the next clean logical break and lead every reply with the nudge until the user acts: /compact mid-epic, the handoff written first so compaction keeps the thread, or a fresh session with the one-line resume prompt at an epic or release edge."
why() {  # why <level> — the budget that triggered it, else the ladder step
  if [ "$1" -eq 2 ] && [ "$cur" -ge "$MH_HARD" ]; then echo "past the ${MH_HARD}k hard budget"
  elif [ "$1" -eq 1 ] && [ "$cur" -ge "$MH_SOFT" ]; then echo "past the ${MH_SOFT}k soft budget"
  else echo "at $(mh_pct "$cur")% of the $(mh_win_for "$cur")k context window"; fi
}
say() {  # say <level> [text] [rules] — the text defaults to the level's, the rules to session-budget.md
  local s=${2:-}
  [ -n "$s" ] || case "$1" in 1) s=$S1 ;; 2) s=$S2 ;; *) s=$S3 ;; esac
  printf 'Marvin context: this session is ~%sk tokens, %s — %s Rules: %s' "$cur" "$(why "$1")" "$s" "${3:-.marvin/agents/session-budget.md}"
}
st() {  # st <k> <level> — the fleet state: the level, or 4 at the rest point (there is none while compaction is off)
  if [ "$2" -ge 3 ] && [ -z "$off" ] && [ "$(mh_fleet_rest "$1")" = 1 ]; then echo 4; else echo "$2"; fi
}
fsay() {  # fsay <state> — the fleet role's advisory: successor, rest, level 3 winds down, else the solo text
  if [ -n "$reason" ]; then
    say "$lc" "successor due: $reason — write the handoff to the epic issue, reach a clean logical break, and end your turn with \"FLEET ${MH_FLEET_EPIC:-<EPIC-KEY>} successor: $reason\"." .marvin/agents/fleet-child.md
  elif [ "$1" = 4 ] && [ "$MH_FLEET_ROLE" = child ]; then
    say 3 "rest point: dispatch nothing new, write the handoff and reach a clean logical break (all work committed, tracker current, no sub-agent running); then keep to small steps and do NOT end your turn to wait — the host's auto-compact fires shortly (compaction $((c + 1)) of $MH_FLEET_MAX_COMPACTIONS); after it, resume from the handoff." .marvin/agents/fleet-child.md
  elif [ "$1" = 4 ]; then
    say 3 "rest point: write the handoff, then keep to small steps — the host's auto-compact fires shortly; never hand off while a child runs (a fresh master only at a fleet edge)." .marvin/agents/fleet.md
  elif [ "$1" = 3 ] && [ -z "$off" ] && [ "$MH_FLEET_ROLE" = child ]; then
    say 3 "wind down to the rest point: dispatch only work that can finish before it ($((MH_FLEET_REST_PCT * MH_SCALE / 100))% of the window), nothing size:l or larger; end your turn below it only to wait on the architect or the master (a question, cross-epic or blocked doorbell)." .marvin/agents/fleet-child.md
  elif [ "$1" = 3 ] && [ -z "$off" ]; then say 3 "$S2"
  else say "$1"; fi
}

msg=""
if [ -z "$MH_FLEET_ROLE" ]; then
  if [ "$event" = PostToolUse ]; then
    [ "$lp" -lt "$lc" ] && msg=$(say "$lc")
  else
    [ "$lc" -ge 1 ] && msg=$(say "$lc")
  fi
else
  mh_fleet_init "$fm"
  off=""; [ "${DISABLE_AUTO_COMPACT:-}" = 1 ] && off=auto; [ "${DISABLE_COMPACT:-}" = 1 ] && off=all
  sc=$(st "$cur" "$lc"); sp=$(st "$prev" "$lp")
  reason=""; post=0; c=0
  if [ "$MH_FLEET_ROLE" = child ] && { [ "$lc" -ge 2 ] || [ "$cur" -lt "$prev" ] || [ "$event" = UserPromptSubmit ]; }; then
    if [ "$sc" = 4 ]; then
      c=$(mh_compactions "$transcript") || c=0
      case "$c" in ''|*[!0-9]*) c=0 ;; esac
      [ "$c" -ge "$MH_FLEET_MAX_COMPACTIONS" ] && reason="compaction cap reached ($c of $MH_FLEET_MAX_COMPACTIONS)"
    fi
    set -- $(mh_since_compact "$transcript")
    n=${1:-0}; k0=${2:-0}; case "$n$k0" in *[!0-9]*) n=0; k0=0 ;; esac
    lim=1; [ "$event" = UserPromptSubmit ] && lim=3
    if [ "$n" -ge 1 ] && [ "$n" -le "$lim" ] && [ "$(mh_pct "$k0")" -ge "$MH_FLEET_RESTART_PCT" ]; then
      post=1
      [ -n "$reason" ] || reason="post-compaction context at $(mh_pct "$k0")% (limit $MH_FLEET_RESTART_PCT%)"
    fi
  fi
  if [ "$MH_FLEET_ROLE" = child ] && [ "$off" = all ] && [ "$lc" -ge 3 ] && [ -z "$reason" ]; then reason="compaction disabled on this host"; fi
  if [ "$event" = PostToolUse ]; then
    { [ "$sp" -lt "$sc" ] || [ "$post" = 1 ]; } && msg=$(fsay "$sc")
  else
    { [ "$lc" -ge 1 ] || [ -n "$reason" ]; } && msg=$(fsay "$sc")
  fi
  msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
fi
[ -n "$msg" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$msg"
exit 0
