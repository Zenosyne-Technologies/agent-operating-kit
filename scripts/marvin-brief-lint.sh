#!/usr/bin/env bash
# marvin-brief-lint.sh — PreToolUse hook (matcher Agent|Task) for the marvin plugin (v0.38.0).
# On a dispatch to a marvin:* persona, advises the ORCHESTRATOR — its additionalContext arrives with the
# Agent tool result (spec H7), so it shapes the NEXT briefs — when the brief lacks what
# .marvin/agents/briefing.md makes mandatory: a run-report path under .marvin/runs/ (item 11), a FINAL
# MESSAGE spec naming TRACKER: (item 11), a DoD (item 3); and, at context level ≥ 2, that nothing new may
# start (.marvin/agents/session-budget.md). Never denies, allows or rewrites (spec H8).
# Contract: Marvin projects only; sub-agent invocations skipped; never writes; always exits 0; nothing
# from the brief is echoed — not even the subagent_type.
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0
mh_read_stdin || exit 0
mh_is_subagent_call && exit 0
case "$(printf '%s' "$MH_IN" | mh_get tool_name)" in Agent|Task) ;; *) exit 0 ;; esac
st=$(printf '%s' "$MH_IN" | mh_get tool_input.subagent_type) || exit 0
case "$st" in marvin:*) ;; *) exit 0 ;; esac
root=$(mh_root); mh_is_marvin "$root" || exit 0
brief=$(printf '%s' "$MH_IN" | mh_get tool_input.prompt) || brief=""

miss=""
case "$brief" in *.marvin/runs/*) ;; *) miss="$miss; no run-report path under .marvin/runs/ (item 11)" ;; esac
case "$brief" in
  *"FINAL MESSAGE"*) case "$brief" in *TRACKER:*) ;; *) miss="$miss; a FINAL MESSAGE spec without the TRACKER: line (item 11)" ;; esac ;;
  *) miss="$miss; no FINAL MESSAGE spec (item 11)" ;;
esac
printf '%s\n' "$brief" | grep -Eiq 'DoD|definition of done' || miss="$miss; no DoD (item 3)"

ctx=""
tp=$(printf '%s' "$MH_IN" | mh_get transcript_path) || tp=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  fm=$(mh_frontmatter "$root") || fm=""
  mh_budget_init "$fm"
  k=$(mh_sizes "$tp" | tail -n 1)
  if [ -n "$k" ] && [ "$(mh_level "$k")" -ge 2 ]; then
    ctx=" Context is at or past the wind-down step (~${k}k tokens): start nothing new — finish the in-flight task and write the handoff (.marvin/agents/session-budget.md)."
  fi
fi
[ -n "$miss$ctx" ] || exit 0
out="Marvin brief lint (.marvin/agents/briefing.md):"
[ -n "$miss" ] && out="$out the brief you just dispatched lacked — ${miss#; }; fix it in your next briefs."
out="$out$ctx"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$out"
exit 0
