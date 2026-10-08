#!/usr/bin/env bash
# marvin-context-budget.sh — PostToolUse + UserPromptSubmit hook for the marvin plugin (AOS-187).
#
# Session length is governed by context size, as a SOFT break. The hook reads the transcript the
# host names, takes the context size of the latest assistant turn (input + cache-read + cache-creation
# tokens) and advises — never blocks:
#   PostToolUse      — only on the turn the size CROSSES a budget (stateless: the last two assistant
#                      turns are compared), so the advisory lands once per crossing, not per tool call.
#   UserPromptSubmit — on every prompt while above the soft budget: the user is present, so that is
#                      when the orchestrator should tell them.
# Budgets: 400k soft / 700k hard; a project overrides them with session_soft_ktokens /
# session_hard_ktokens (integers, thousands of tokens, soft < hard) in .marvin/PROJECT-INFO.md
# frontmatter. Contract: Marvin projects only; sub-agent invocations skipped; never writes a file;
# always exits 0; only numbers this script computed reach the output.
set -u

DEF_SOFT=400; DEF_HARD=700

stdin_json=""
if [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then stdin_json=$(timeout 2 head -c 65536 2>/dev/null || true)
  else IFS= read -r -t 2 stdin_json || true; fi
fi
[ -n "$stdin_json" ] || exit 0

case "$stdin_json" in
  *\"agent_id\"*) exit 0 ;;
esac

field() {  # field <name> — a plain string field from the one-line stdin JSON (no jq needed)
  printf '%s' "$stdin_json" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 \
    | sed -E "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//; s/\"\$//"
}
event=$(field hook_event_name)
case "$event" in PostToolUse|UserPromptSubmit) ;; *) exit 0 ;; esac
transcript=$(field transcript_path)

root="${CLAUDE_PROJECT_DIR:-}"; [ -n "$root" ] || root=$(field cwd); [ -n "$root" ] || root="$PWD"
[ ! -L "$root/.marvin" ] && [ -d "$root/.marvin" ] || exit 0
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Budgets: frontmatter only, bounded read, integers 1..99999 (thousands), soft < hard — else defaults.
soft=$DEF_SOFT; hard=$DEF_HARD
pi="$root/.marvin/PROJECT-INFO.md"
if [ ! -L "$pi" ] && [ -f "$pi" ]; then
  fm=$(head -n 40 -- "$pi" 2>/dev/null | awk '{ sub(/\r$/, "") } NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f')
  s=$(printf '%s\n' "$fm" | sed -nE 's/^session_soft_ktokens:[[:space:]]*([0-9]{1,5})[[:space:]]*$/\1/p' | head -n1)
  h=$(printf '%s\n' "$fm" | sed -nE 's/^session_hard_ktokens:[[:space:]]*([0-9]{1,5})[[:space:]]*$/\1/p' | head -n1)
  s=${s:-$DEF_SOFT}; h=${h:-$DEF_HARD}
  if [ "$((10#$s))" -gt 0 ] && [ "$((10#$s))" -lt "$((10#$h))" ]; then soft=$((10#$s)); hard=$((10#$h)); fi
fi

# Context size (in thousands) of the last two assistant turns. Only lines whose type is assistant
# and that carry an UNESCAPED "usage":{ are read, so usage text quoted inside a tool result never counts.
sizes=$(tail -n 400 -- "$transcript" 2>/dev/null \
  | grep '"type":"assistant"' | grep '"usage":{' | tail -n 2 \
  | awk '{
      n = 0
      if (match($0, /"input_tokens":[0-9]+/))                { n += substr($0, RSTART + 15, RLENGTH - 15) }
      if (match($0, /"cache_read_input_tokens":[0-9]+/))     { n += substr($0, RSTART + 26, RLENGTH - 26) }
      if (match($0, /"cache_creation_input_tokens":[0-9]+/)) { n += substr($0, RSTART + 30, RLENGTH - 30) }
      print int(n / 1000)
    }')
[ -n "$sizes" ] || exit 0
cur=$(printf '%s\n' "$sizes" | tail -n 1)
prev=$(printf '%s\n' "$sizes" | head -n 1); [ "$(printf '%s\n' "$sizes" | wc -l)" -ge 2 ] || prev=0

SOFT_MSG="Marvin context budget: this session's context is ~${cur}k tokens, past the ${soft}k soft budget — the work has grown big. Keep going, and at the next clean logical break (work committed, tracker current, no sub-agent running) write the handoff and tell the user this is a good point to start a fresh session, with the one-line prompt that resumes."
HARD_MSG="Marvin context budget: this session's context is ~${cur}k tokens, past the ${hard}k hard budget — start no new task; finish the current one to a clean logical break (work committed, tracker current, no sub-agent running), write the handoff, and tell the user now that this is the point to start a fresh session, with the one-line prompt that resumes."

msg=""
if [ "$event" = PostToolUse ]; then
  if [ "$prev" -lt "$hard" ] && [ "$cur" -ge "$hard" ]; then
    msg="$HARD_MSG"
  else
    [ "$prev" -lt "$soft" ] && [ "$cur" -ge "$soft" ] && msg="$SOFT_MSG"
  fi
else
  if [ "$cur" -ge "$hard" ]; then msg="$HARD_MSG"; elif [ "$cur" -ge "$soft" ]; then msg="$SOFT_MSG"; fi
fi
[ -n "$msg" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$msg"
exit 0
