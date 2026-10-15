#!/usr/bin/env bash
# marvin-subagent-gate.sh — SubagentStop hook (matcher ^marvin:) for the marvin plugin (v0.38.0).
# Holds a marvin:* persona's final message to .marvin/agents/briefing.md item 11: TRACKER: and GUARDRAILS:
# always; INFORMATION:, WORKTREE: and SURFACES: when the brief reserves them (the literal token appears in
# the brief — the agent transcript's first user message, first 256 KiB); reserved lines must START a line;
# at most 25 lines, not counting TRACKER:, UNRELATED: and FAIL-grade finding lines. A miss sends the
# message back ONCE (decision: block — the user never sees it); on the re-fire (stop_hook_active) it
# passes as is, and parsing it stays the orchestrator's duty.
# Contract: Marvin projects only; marvin:* personas only; never writes; always exits 0; the reason is
# constant text plus the names of missing lines and a line count — nothing from the message or brief.
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0
mh_read_stdin || exit 0
root=$(mh_root); mh_is_marvin "$root" || exit 0
atype=$(printf '%s' "$MH_IN" | mh_get agent_type) || exit 0
case "$atype" in marvin:*) ;; *) exit 0 ;; esac
[ "$(printf '%s' "$MH_IN" | mh_get stop_hook_active)" = true ] && exit 0
msg=$(printf '%s' "$MH_IN" | mh_get last_assistant_message) || exit 0
atp=$(printf '%s' "$MH_IN" | mh_get agent_transcript_path) || atp=""
brief=$(mh_first_user_text "$atp") || brief=""

has() { printf '%s\n' "$msg" | grep -Eq '^[[:space:]>*`-]*'"$1"':'; }
missing=""
for t in TRACKER GUARDRAILS; do has "$t" || missing="$missing $t:"; done
for t in INFORMATION WORKTREE SURFACES; do
  case "$brief" in *"$t:"*) has "$t" || missing="$missing $t:" ;; esac
done
lines=$(printf '%s\n' "$msg" | awk 'NF && !/^[ \t>*`-]*(TRACKER|UNRELATED):/ && !/(^|[^A-Za-z])FAIL([^A-Za-z]|$)/' | wc -l | tr -d ' ')
[ -n "$missing" ] || [ "$lines" -gt 25 ] || exit 0
reason="Marvin FINAL MESSAGE contract (.marvin/agents/briefing.md item 11): re-send your final message with the same content, fixed."
[ -n "$missing" ] && reason="$reason Missing reserved line(s):$missing — write each as your brief's FINAL MESSAGE spec reserves it (TRACKER: none when you made no tracker write; GUARDRAILS: NONE when no DO NOT row was hit)."
[ "$lines" -gt 25 ] && reason="$reason It runs to $lines lines; keep it to 25 (TRACKER:, UNRELATED: and FAIL-grade finding lines do not count) and move the rest to your run report."
printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
