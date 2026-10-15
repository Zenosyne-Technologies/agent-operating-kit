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
# What each level demands is owned by .marvin/agents/session-budget.md. Contract: Marvin projects only;
# sub-agent invocations skipped; never writes a file; always exits 0; only numbers this script computed
# reach the output; never blocks.
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
say() {
  local s
  case "$1" in 1) s=$S1 ;; 2) s=$S2 ;; *) s=$S3 ;; esac
  printf 'Marvin context: this session is ~%sk tokens, %s — %s Rules: .marvin/agents/session-budget.md' "$cur" "$(why "$1")" "$s"
}

msg=""
if [ "$event" = PostToolUse ]; then
  [ "$lp" -lt "$lc" ] && msg=$(say "$lc")
else
  [ "$lc" -ge 1 ] && msg=$(say "$lc")
fi
[ -n "$msg" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$msg"
exit 0
