#!/usr/bin/env bash
# test-context-budget.sh — behavioural tests for scripts/marvin-context-budget.sh (AOS-187).
# Pins: Marvin projects only; PostToolUse advises only on the turn a budget is CROSSED; UserPromptSubmit
# advises on every prompt above the soft budget; per-project overrides and their fallbacks; sub-agent
# invocations skipped; escaped tool-result text never read as usage; never writes; always exits 0.
# The mutation section reverts one guard at a time in a throwaway copy; its fixture must fail.
# Run from anywhere: bash scripts/test-context-budget.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/marvin-context-budget.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-cbtest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_CONFIG_DIR="$WORK/cfg"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="" CLAUDE_CODE_DISABLE_1M_CONTEXT="" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=""

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc0()    { if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit $RC, want 0"; fi; }
assert_out()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_empty()  { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 160)"; fi; }
assert_json()   { if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "valid JSON"; else bad "output is not valid JSON"; fi; }

# transcript <file> <ktokens>... — one API message per argument, context = k*1000 split across the three
# counted fields. Like the real host, ONE message is written as SEVERAL assistant lines (thinking, then
# tool_use) sharing one "id":"msg_<n>" and identical usage; a user tool-result line containing escaped
# "usage" text sits between messages.
transcript() {
  local f="$1"; shift; : > "$f"; local n=0 k u
  for k in "$@"; do
    n=$((n+1))
    u=$(printf '"usage":{"input_tokens":2,"cache_creation_input_tokens":998,"cache_read_input_tokens":%d,"output_tokens":50}' $(( k * 1000 - 1000 )))
    printf '{"type":"assistant","message":{"id":"msg_%d","content":[{"type":"thinking","thinking":"hm"}],%s}}\n' "$n" "$u" >> "$f"
    printf '{"type":"assistant","message":{"id":"msg_%d","content":[{"type":"tool_use","id":"toolu_%d","name":"Bash","input":{"command":"ls"}}],%s}}\n' "$n" "$n" "$u" >> "$f"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"{\\"usage\\":{\\"input_tokens\\":999999999}}"}]}}\n' >> "$f"
  done
}
mk_project() {  # mk_project <dir> [soft] [hard] [window]
  rm -rf "$1"; mkdir -p "$1/.marvin"
  { printf -- '---\nkit_version: 0.38.0\n'
    [ -n "${2:-}" ] && printf 'session_soft_ktokens: %s\n' "$2"
    [ -n "${3:-}" ] && printf 'session_hard_ktokens: %s\n' "$3"
    [ -n "${4:-}" ] && printf 'context_window_ktokens: %s\n' "$4"
    printf -- '---\nProject facts.\n'; } > "$1/.marvin/PROJECT-INFO.md"
}
# run <hook> <project_dir> <event> <transcript> [extra_json_fields after cwd] [json_fields before hook_event_name]
run() {
  local hook="$1" p="$2" ev="$3" t="$4" extra="${5:-}" pre="${6:-}"
  OUT=$(printf '{"session_id":"s"%s,"hook_event_name":"%s","transcript_path":"%s","cwd":"%s"%s}' "$pre" "$ev" "$t" "$p" "$extra" \
        | CLAUDE_PROJECT_DIR="$p" bash "$hook" 2>&1); RC=$?
}

P="$WORK/proj"; mk_project "$P"
T="$WORK/t.jsonl"

hd "B1 non-Marvin project gets nothing"
mkdir -p "$WORK/plain"; transcript "$T" 390 410
run "$HOOK" "$WORK/plain" PostToolUse "$T"; assert_rc0; assert_empty

hd "B2 below the soft budget — nothing"
transcript "$T" 100 200
run "$HOOK" "$P" PostToolUse "$T"; assert_rc0; assert_empty
run "$HOOK" "$P" UserPromptSubmit "$T"; assert_rc0; assert_empty

hd "B3 PostToolUse crossing the soft budget — one soft advisory"
transcript "$T" 390 410
run "$HOOK" "$P" PostToolUse "$T"; assert_rc0; assert_json
assert_out '"hookEventName":"PostToolUse"'
assert_out "~410k tokens"
assert_out "past the 400k soft budget"
assert_out "next clean logical break"

hd "B4 PostToolUse already above soft, no new crossing — nothing"
transcript "$T" 410 450
run "$HOOK" "$P" PostToolUse "$T"; assert_rc0; assert_empty

hd "B5 PostToolUse crossing the hard budget — hard advisory"
transcript "$T" 690 705
run "$HOOK" "$P" PostToolUse "$T"; assert_rc0; assert_json
assert_out "past the 700k hard budget"
assert_out "start no new task"

hd "B6 UserPromptSubmit advises on every prompt above soft"
transcript "$T" 410 450
run "$HOOK" "$P" UserPromptSubmit "$T"; assert_rc0; assert_json
assert_out '"hookEventName":"UserPromptSubmit"'
assert_out "past the 400k soft budget"
transcript "$T" 710 720
run "$HOOK" "$P" UserPromptSubmit "$T"; assert_out "past the 700k hard budget"

hd "B7 project override moves the budgets"
P2="$WORK/proj-override"; mk_project "$P2" 100 200
transcript "$T" 90 110
run "$HOOK" "$P2" PostToolUse "$T"; assert_out "past the 100k soft budget"

hd "B8 invalid overrides fall back to the defaults"
for pair in "abc 200" "0 200" "300 300" "500 400" "1234567 9999999"; do
  set -- $pair; P3="$WORK/proj-bad"; mk_project "$P3" "$1" "$2"
  transcript "$T" 390 410
  run "$HOOK" "$P3" PostToolUse "$T"; assert_out "past the 400k soft budget"
done

hd "B9 a sub-agent invocation is skipped"
transcript "$T" 390 410
run "$HOOK" "$P" PostToolUse "$T" "" ',"agent_id":"a1","agent_type":"marvin:developer"'; assert_rc0; assert_empty

hd "B10 missing transcript, symlinked .marvin, empty stdin — nothing, exit 0"
run "$HOOK" "$P" PostToolUse "$WORK/none.jsonl"; assert_rc0; assert_empty
L="$WORK/proj-link"; mkdir -p "$L"; ln -s "$P/.marvin" "$L/.marvin"; transcript "$T" 390 410
run "$HOOK" "$L" PostToolUse "$T"; assert_rc0; assert_empty
OUT=$(printf '' | CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>&1); RC=$?; assert_rc0; assert_empty

hd "B11 escaped usage text inside a tool result is never read"
transcript "$T" 100 200   # each tool-result line embeds a 999999999-token fake usage
run "$HOOK" "$P" UserPromptSubmit "$T"; assert_empty

hd "B12 never writes"
transcript "$T" 390 410; before=$(ls -R "$WORK" | cksum)
run "$HOOK" "$P" PostToolUse "$T"
after=$(ls -R "$WORK" | cksum)
if [ "$before" = "$after" ]; then ok "nothing written"; else bad "the hook wrote something"; fi

hd "B13 a tool_use input with an unescaped input_tokens key is never read as usage"
transcript "$T" 100 100
printf '{"type":"assistant","message":{"id":"msg_z","content":[{"type":"tool_use","id":"toolu_z","name":"X","input":{"input_tokens":999999999,"cache_read_input_tokens":999999999}}],"usage":{"input_tokens":2,"cache_creation_input_tokens":998,"cache_read_input_tokens":149000,"output_tokens":5}}}\n' >> "$T"
run "$HOOK" "$P" UserPromptSubmit "$T"; assert_rc0; assert_empty
run "$HOOK" "$P" PostToolUse "$T"; assert_rc0; assert_empty

hd "B14 agent_id inside a tool_input AFTER hook_event_name is not a sub-agent marker"
transcript "$T" 390 410
run "$HOOK" "$P" PostToolUse "$T" ',"tool_input":{"agent_id":"x","note":"agent_id"}'; assert_rc0; assert_json
assert_out "past the 400k soft budget"

hd "B15 one message spread over several assistant lines counts once (crossing seen on the last message pair)"
transcript "$T" 300 410
run "$HOOK" "$P" PostToolUse "$T"; assert_rc0; assert_out "past the 400k soft budget"

hd "C1 the ladder speaks where the budgets are raised: 70 % plan, 80 % wind down, 90 % stop"
PL="$WORK/proj-ladder"; mk_project "$PL" 950 990
transcript "$T" 690 705
run "$HOOK" "$PL" PostToolUse "$T"; assert_rc0; assert_json
assert_out "at 70% of the 1000k context window"; assert_out "next clean logical break"; assert_out "the 80% step or the hard budget"
transcript "$T" 795 805
run "$HOOK" "$PL" PostToolUse "$T"; assert_out "at 80% of the 1000k context window"; assert_out "start no new task"
transcript "$T" 895 905
run "$HOOK" "$PL" PostToolUse "$T"; assert_out "at 90% of the 1000k context window"; assert_out "/compact"
run "$HOOK" "$PL" UserPromptSubmit "$T"; assert_out "/compact"; assert_out "session-budget.md"
transcript "$T" 895 905
run "$HOOK" "$P" PostToolUse "$T"; assert_out "at 90% of the 1000k context window"; assert_out "/compact"

hd "C2 PostToolUse stays quiet inside a step"
transcript "$T" 905 910
run "$HOOK" "$PL" PostToolUse "$T"; assert_rc0; assert_empty

hd "C3 CLAUDE_CODE_AUTO_COMPACT_WINDOW sets the window"
transcript "$T" 205 215
OUT=$(printf '{"session_id":"s","hook_event_name":"PostToolUse","transcript_path":"%s","cwd":"%s"}' "$T" "$P" \
  | CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>&1); RC=$?
assert_rc0; assert_out "at 71% of the 300k context window"

hd "C4 CLAUDE_CODE_DISABLE_1M_CONTEXT=1 means a 200k window"
transcript "$T" 135 145
OUT=$(printf '{"session_id":"s","hook_event_name":"PostToolUse","transcript_path":"%s","cwd":"%s"}' "$T" "$P" \
  | CLAUDE_CODE_DISABLE_1M_CONTEXT=1 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>&1); RC=$?
assert_out "at 72% of the 200k context window"

hd "C5 context_window_ktokens beats the environment, and steps up past it"
PW="$WORK/proj-window"; mk_project "$PW" "" "" 100
transcript "$T" 100 150
OUT=$(printf '{"session_id":"s","hook_event_name":"UserPromptSubmit","transcript_path":"%s","cwd":"%s"}' "$T" "$PW" \
  | CLAUDE_CODE_AUTO_COMPACT_WINDOW=900000 CLAUDE_PROJECT_DIR="$PW" bash "$HOOK" 2>&1); RC=$?
assert_out "at 75% of the 200k context window"

hd "C6 CLAUDE_AUTOCOMPACT_PCT_OVERRIDE scales the steps"
transcript "$T" 440 455
OUT=$(printf '{"session_id":"s","hook_event_name":"PostToolUse","transcript_path":"%s","cwd":"%s"}' "$T" "$PL" \
  | CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50 CLAUDE_PROJECT_DIR="$PL" bash "$HOOK" 2>&1); RC=$?
assert_out "/compact"

hd "C7 the stricter scale names the trigger: hard budget before the 70 % step on a 1M window"
transcript "$T" 690 705
run "$HOOK" "$P" PostToolUse "$T"; assert_out "past the 700k hard budget"

# ── mutations: revert one line of the hook or the lib in a copy; the fixture's output must then change ─
LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
mutation() {  # mutation <name> <hook|lib> <exact line> <replacement> <project> <event> <transcript-ks> [env]
  local d="$WORK/m-$1" tgt orig
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$HOOK" "$d/hook.sh"; cp "$LIB" "$d/lib/marvin-hook-lib.sh"
  if [ "$2" = lib ]; then tgt="$d/lib/marvin-hook-lib.sh"; else tgt="$d/hook.sh"; fi
  A="$3" B="$4" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$tgt" > "$tgt.m" && mv "$tgt.m" "$tgt"
  if [ "$2" = lib ]; then cmp -s "$tgt" "$LIB"; else cmp -s "$tgt" "$HOOK"; fi && { bad "mutation $1: target line not found — harness is stale"; return; }
  transcript "$T" $7
  OUT=$(printf '{"session_id":"s","hook_event_name":"%s","transcript_path":"%s","cwd":"%s"}' "$6" "$T" "$5" | env ${8:-} CLAUDE_PROJECT_DIR="$5" bash "$HOOK" 2>&1); orig=$OUT
  OUT=$(printf '{"session_id":"s","hook_event_name":"%s","transcript_path":"%s","cwd":"%s"}' "$6" "$T" "$5" | env ${8:-} CLAUDE_PROJECT_DIR="$5" bash "$d/hook.sh" 2>&1)
  if [ "$OUT" = "$orig" ]; then bad "mutation $1 survived"; else ok "mutation $1 caught"; fi
}
hd "M1 crossing check removed — B4 (no re-advisory) must catch it"
mutation crossing hook '  [ "$lp" -lt "$lc" ] && msg=$(say "$lc")' '  [ "$lc" -ge 1 ] && msg=$(say "$lc")' "$P" PostToolUse "410 450"
hd "M2 sub-agent guard removed — B9 must catch it"
d9="$WORK/m9"; rm -rf "$d9"; mkdir -p "$d9/lib"; cp "$HOOK" "$d9/hook.sh"
A='    *\"agent_id\"*) return 0 ;;' B='    *\"agent_id\"*) : ;;' awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$LIB" > "$d9/lib/marvin-hook-lib.sh"
if cmp -s "$d9/lib/marvin-hook-lib.sh" "$LIB"; then bad "mutation subagent: target line not found — harness is stale"; else
  transcript "$T" 390 410; run "$d9/hook.sh" "$P" PostToolUse "$T" "" ',"agent_id":"a1"'
  if [ -n "$OUT" ]; then ok "mutation subagent caught"; else bad "mutation subagent survived"; fi; fi
hd "M3 the 90 % step removed — C1 must catch it"
mutation stop lib '  if [ "$p" -ge $((90 * MH_SCALE / 100)) ]; then l=3; fi' '  :' "$PL" PostToolUse "895 905"
hd "M4 percentage scaling removed — C6 must catch it"
mutation scale lib '  if printf '"'"'%s'"'"' "$e" | grep -Eq '"'"'^[0-9]{1,3}$'"'"' && [ "$e" -ge 1 ] && [ "$e" -le 100 ]; then MH_SCALE=$e; fi' '  :' "$PL" PostToolUse "440 455" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50

printf '\n----\ntest-context-budget: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
