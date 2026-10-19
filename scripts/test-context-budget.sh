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
export DISABLE_AUTO_COMPACT="" DISABLE_COMPACT=""

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc0()    { if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit $RC, want 0"; fi; }
assert_out()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_empty()  { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 160)"; fi; }
assert_json()   { if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "valid JSON"; else bad "output is not valid JSON"; fi; }
assert_lacks()  { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "out has (unwanted): $1"; else ok "out lacks: $1"; fi; }
assert_is()     { if [ "$OUT" = "$1" ]; then ok "out is exactly the expected text"; else bad "out differs — got: $(printf '%s' "$OUT" | head -c 200)"; fi; }
assert_count()  { local n; n=$(printf '%s\n' "$OUT" | grep -oF -- "$1" | wc -l | tr -d ' ')
  if [ "$n" = "$2" ]; then ok "'$1' occurs $2 time(s)"; else bad "'$1' occurs $n time(s), want $2"; fi; }

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
# tmsg <file> <id> <ktokens> — append one more message (same shape as transcript's) with its own id
tmsg() {
  local u
  u=$(printf '"usage":{"input_tokens":2,"cache_creation_input_tokens":998,"cache_read_input_tokens":%d,"output_tokens":50}' $(( $3 * 1000 - 1000 )))
  printf '{"type":"assistant","message":{"id":"msg_%s","content":[{"type":"tool_use","id":"toolu_%s","name":"Bash","input":{"command":"ls"}}],%s}}\n' "$2" "$2" "$u" >> "$1"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}\n' >> "$1"
}
# tboundary <file> — append one main-thread compaction boundary
tboundary() { printf '{"isSidechain":false,"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":990000}}\n' >> "$1"; }
# tfleet <file> <compactions> <ks after the last boundary...> — a 950k message before each boundary
tfleet() {
  local f="$1" c="$2" i=0 k; shift 2; : > "$f"
  while [ "$i" -lt "$c" ]; do i=$((i+1)); tmsg "$f" "b$i" 950; tboundary "$f"; done
  i=0; for k in "$@"; do i=$((i+1)); tmsg "$f" "a$i" "$k"; done
}
mk_project() {  # mk_project <dir> [soft] [hard] [window] [fleet role: child|master] [extra frontmatter line]
  rm -rf "$1"; mkdir -p "$1/.marvin"; git init -q "$1"
  { printf -- '---\nkit_version: 0.38.0\n'
    [ -n "${2:-}" ] && printf 'session_soft_ktokens: %s\n' "$2"
    [ -n "${3:-}" ] && printf 'session_hard_ktokens: %s\n' "$3"
    [ -n "${4:-}" ] && printf 'context_window_ktokens: %s\n' "$4"
    [ -n "${6:-}" ] && printf '%s\n' "$6"
    printf -- '---\nProject facts.\n'; } > "$1/.marvin/PROJECT-INFO.md"
  case "${5:-}" in
    child)  printf 'role=child\nepic=ABC-12\n' > "$1/.git/marvin-fleet" ;;
    master) printf 'role=master\n' > "$1/.git/marvin-fleet" ;;
  esac
}
# run <hook> <project_dir> <event> <transcript> [extra_json_fields after cwd] [json_fields before hook_event_name]
run() {
  local hook="$1" p="$2" ev="$3" t="$4" extra="${5:-}" pre="${6:-}"
  OUT=$(printf '{"session_id":"s"%s,"hook_event_name":"%s","transcript_path":"%s","cwd":"%s"%s}' "$pre" "$ev" "$t" "$p" "$extra" \
        | CLAUDE_PROJECT_DIR="$p" bash "$hook" 2>&1); RC=$?
}
# runenv <VAR=value> <project_dir> <event> <transcript> [hook] — run with one extra environment variable
runenv() {
  OUT=$(printf '{"session_id":"s","hook_event_name":"%s","transcript_path":"%s","cwd":"%s"}' "$3" "$4" "$2" \
        | env "$1" CLAUDE_PROJECT_DIR="$2" bash "${5:-$HOOK}" 2>&1); RC=$?
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

# ── fleet mode: a role marker in the project's git dir switches the hook to the fleet child / master texts ─
X1="plan only work that can finish before level 2 (the 80% step or the hard budget, whichever comes first) — split or defer anything larger, dispatch no size:l or size:xl task — and at the next clean logical break (all work committed, tracker current, no sub-agent running) tell the user where the session stands."
X2="start no new task: finish the in-flight one to the next clean logical break (all work committed, tracker current, no sub-agent running) and write the handoff now."
X3="STOP at the next clean logical break and lead every reply with the nudge until the user acts: /compact mid-epic, the handoff written first so compaction keeps the thread, or a fresh session with the one-line resume prompt at an epic or release edge."
expect() {  # expect <event> <k> <why> <text> — today's solo output, byte for byte
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"Marvin context: this session is ~%sk tokens, %s — %s Rules: .marvin/agents/session-budget.md"}}' "$1" "$2" "$3" "$4"
}
PC="$WORK/proj-child"; mk_project "$PC" "" "" "" child
PM="$WORK/proj-master"; mk_project "$PM" "" "" "" master

hd "F1 no marker: today's text, byte for byte, at every level (brief B1)"
transcript "$T" 390 410; run "$HOOK" "$P" PostToolUse "$T"; assert_is "$(expect PostToolUse 410 'past the 400k soft budget' "$X1")"
transcript "$T" 690 705; run "$HOOK" "$P" PostToolUse "$T"; assert_is "$(expect PostToolUse 705 'past the 700k hard budget' "$X2")"
transcript "$T" 895 910; run "$HOOK" "$P" PostToolUse "$T"; assert_is "$(expect PostToolUse 910 'at 91% of the 1000k context window' "$X3")"
run "$HOOK" "$P" UserPromptSubmit "$T"; assert_is "$(expect UserPromptSubmit 910 'at 91% of the 1000k context window' "$X3")"
transcript "$T" 930 950; run "$HOOK" "$P" PostToolUse "$T"; assert_empty

hd "F2 child at the rest point, no compaction yet: rest, keep the turn open (brief B2)"
tfleet "$T" 0 930 950
run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_json
assert_out "~950k tokens, at 95% of the 1000k context window — rest point: dispatch nothing new, write the handoff and reach a clean logical break (all work committed, tracker current, no sub-agent running); then keep to small steps and do NOT end your turn to wait — the host's auto-compact fires shortly (compaction 1 of 3); after it, resume from the handoff. Rules: .marvin/agents/fleet-child.md"
assert_lacks "successor due"; assert_lacks "resting"; assert_lacks "session-budget.md"
run "$HOOK" "$PC" UserPromptSubmit "$T"; assert_out "compaction 1 of 3"; assert_out "do NOT end your turn"
tfleet "$T" 0 950 960; run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_empty
tfleet "$T" 2 930 950; run "$HOOK" "$PC" PostToolUse "$T"; assert_out "compaction 3 of 3"; assert_lacks "successor due"

hd "F3 child at the rest point with the cap reached: successor, not rest (brief B3)"
tfleet "$T" 3 930 950
run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_json
assert_out "— successor due: compaction cap reached (3 of 3) — write the handoff to the epic issue, reach a clean logical break, and end your turn with \\\"FLEET ABC-12 successor: compaction cap reached (3 of 3)\\\". Rules: .marvin/agents/fleet-child.md"
assert_lacks "rest point"; assert_lacks "resting"
PE="$WORK/proj-noepic"; mk_project "$PE"; printf 'role=child\nepic=not a key\n' > "$PE/.git/marvin-fleet"
run "$HOOK" "$PE" PostToolUse "$T"; assert_json; assert_out "FLEET <EPIC-KEY> successor: compaction cap reached (3 of 3)"; assert_lacks "not a key"

hd "F4 child, first message after a compaction too large: successor (brief B4)"
tfleet "$T" 1 400; run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_json
assert_out "successor due: post-compaction context at 40% (limit 33%)"; assert_out "FLEET ABC-12 successor: post-compaction context at 40% (limit 33%)"
tfleet "$T" 1 330; run "$HOOK" "$PC" PostToolUse "$T"; assert_out "post-compaction context at 33% (limit 33%)"
tfleet "$T" 1 320; run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_empty
tfleet "$T" 1 400 405; run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_empty
tfleet "$T" 1 400 850; run "$HOOK" "$PC" PostToolUse "$T"; assert_out "start no new task"; assert_lacks "successor due"
tfleet "$T" 1 400 405 410; run "$HOOK" "$PC" UserPromptSubmit "$T"; assert_out "post-compaction context at 40% (limit 33%)"
tfleet "$T" 1 400 405 410 415; run "$HOOK" "$PC" UserPromptSubmit "$T"; assert_lacks "successor due"; assert_out "past the 400k soft budget"
PR="$WORK/proj-restart"; mk_project "$PR" "" "" "" child "fleet_restart_max_pct: 50"
tfleet "$T" 1 400; run "$HOOK" "$PR" PostToolUse "$T"; assert_rc0; assert_empty

hd "F5 child, small context after a compaction: no successor (brief B5)"
tfleet "$T" 1 200
run "$HOOK" "$PC" PostToolUse "$T"; assert_rc0; assert_empty
run "$HOOK" "$PC" UserPromptSubmit "$T"; assert_rc0; assert_empty

hd "F6 cap and post-compaction both hold: exactly one successor, the cap reason (brief B6)"
tfleet "$T" 3 950; run "$HOOK" "$PC" PostToolUse "$T"; assert_json
assert_count "successor due" 1; assert_out "compaction cap reached (3 of 3)"; assert_lacks "post-compaction context"
tfleet "$T" 3 400; run "$HOOK" "$PC" PostToolUse "$T"
assert_count "successor due" 1; assert_out "post-compaction context at 40% (limit 33%)"

hd "F7 master at the rest point (brief B7)"
tfleet "$T" 0 930 950; run "$HOOK" "$PM" PostToolUse "$T"; assert_rc0; assert_json
assert_out "~950k tokens, at 95% of the 1000k context window — rest point: write the handoff, then keep to small steps — the host's auto-compact fires shortly; never hand off while a child runs (a fresh master only at a fleet edge). Rules: .marvin/agents/fleet.md"
assert_lacks "successor due"

hd "F8 fleet_max_compactions setting moves the cap (brief B8)"
PK="$WORK/proj-cap"; mk_project "$PK" "" "" "" child "fleet_max_compactions: 1"
tfleet "$T" 1 930 950; run "$HOOK" "$PK" PostToolUse "$T"; assert_json
assert_out "successor due: compaction cap reached (1 of 1)"; assert_lacks "rest point"

hd "F9 the rest point: 92 % winds down, 94 % rests, the override scales both, the disable switches (brief B9)"
S3W94="wind down to the rest point: dispatch only work that can finish before it (94% of the window), nothing size:l or larger; end your turn below it only to wait on the architect or the master (a question, cross-epic or blocked doorbell). Rules: .marvin/agents/fleet-child.md"
transcript "$T" 850 920; run "$HOOK" "$PC" PostToolUse "$T"; assert_json
assert_out "~920k tokens, at 92% of the 1000k context window — $S3W94"; assert_lacks "$X2"; assert_lacks "rest point: dispatch nothing new"
run "$HOOK" "$PC" UserPromptSubmit "$T"; assert_out "$S3W94"; assert_lacks "$X2"
run "$HOOK" "$PM" PostToolUse "$T"; assert_out "at 92% of the 1000k context window — $X2 Rules: .marvin/agents/session-budget.md"; assert_lacks "wind down to the rest point"
run "$HOOK" "$PM" UserPromptSubmit "$T"; assert_out "$X2"; assert_lacks "wind down to the rest point"
transcript "$T" 930 940; run "$HOOK" "$PC" PostToolUse "$T"; assert_out "rest point: dispatch nothing new"
transcript "$T" 920 950; run "$HOOK" "$PC" PostToolUse "$T"; assert_out "rest point: dispatch nothing new"
transcript "$T" 690 730; runenv CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 "$PC" PostToolUse "$T"; assert_out "finish before it (75% of the window)"; assert_lacks "rest point: dispatch nothing new"
transcript "$T" 740 760; runenv CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80 "$PC" PostToolUse "$T"; assert_out "rest point: dispatch nothing new"
transcript "$T" 895 910; runenv DISABLE_AUTO_COMPACT=1 "$PC" PostToolUse "$T"; assert_is "$(expect PostToolUse 910 'at 91% of the 1000k context window' "$X3")"
transcript "$T" 850 950; runenv DISABLE_AUTO_COMPACT=1 "$PC" PostToolUse "$T"; assert_out "$X3"; assert_lacks "rest point"
runenv DISABLE_AUTO_COMPACT=1 "$PM" UserPromptSubmit "$T"; assert_out "$X3"; assert_lacks "rest point"
transcript "$T" 895 910; runenv DISABLE_COMPACT=1 "$PC" PostToolUse "$T"; assert_json
assert_out "successor due: compaction disabled on this host"; assert_out "FLEET ABC-12 successor: compaction disabled on this host"
transcript "$T" 840 850; runenv DISABLE_COMPACT=1 "$PC" UserPromptSubmit "$T"; assert_out "$X2"; assert_lacks "successor due"

hd "F10 cost rule: the solo path never reads the compaction history"
SH="$WORK/shadow"; rm -rf "$SH"; mkdir -p "$SH/lib"; cp "$HOOK" "$SH/hook.sh"
{ cat "$SCRIPT_DIR/lib/marvin-hook-lib.sh"
  printf '%s\n' 'mh_compactions() { echo SENTINEL-compactions >&2; echo 0; }' 'mh_since_compact() { echo SENTINEL-since >&2; }'; } > "$SH/lib/marvin-hook-lib.sh"
for ev in PostToolUse UserPromptSubmit; do
  transcript "$T" 930 950; run "$SH/hook.sh" "$P" "$ev" "$T"; assert_lacks "SENTINEL"
  tfleet "$T" 1 400; run "$SH/hook.sh" "$P" "$ev" "$T"; assert_lacks "SENTINEL"
done
transcript "$T" 300 310; run "$SH/hook.sh" "$PC" PostToolUse "$T"; assert_lacks "SENTINEL"
run "$SH/hook.sh" "$PC" UserPromptSubmit "$T"; assert_out "SENTINEL"
tfleet "$T" 1 200; run "$SH/hook.sh" "$PC" PostToolUse "$T"; assert_out "SENTINEL"

hd "F11 master: rest text, never a successor"
tfleet "$T" 3 930 950; run "$HOOK" "$PM" PostToolUse "$T"; assert_out "never hand off while a child runs"; assert_lacks "successor due"
tfleet "$T" 1 400; run "$HOOK" "$PM" PostToolUse "$T"; assert_rc0; assert_empty
run "$HOOK" "$PM" UserPromptSubmit "$T"; assert_out "past the 400k soft budget"; assert_lacks "successor due"
transcript "$T" 895 910; runenv DISABLE_COMPACT=1 "$PM" PostToolUse "$T"; assert_is "$(expect PostToolUse 910 'at 91% of the 1000k context window' "$X3")"

# ── mutations: revert one line of the hook or the lib in a copy; the fixture's output must then change ─
LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
mutation() {  # mutation <name> <hook|lib> <exact line> <replacement> <project> <event> <transcript-ks | - = keep $T> [env]
  local d="$WORK/m-$1" tgt orig
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$HOOK" "$d/hook.sh"; cp "$LIB" "$d/lib/marvin-hook-lib.sh"
  if [ "$2" = lib ]; then tgt="$d/lib/marvin-hook-lib.sh"; else tgt="$d/hook.sh"; fi
  A="$3" B="$4" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$tgt" > "$tgt.m" && mv "$tgt.m" "$tgt"
  if [ "$2" = lib ]; then cmp -s "$tgt" "$LIB"; else cmp -s "$tgt" "$HOOK"; fi && { bad "mutation $1: target line not found — harness is stale"; return; }
  [ "$7" = - ] || transcript "$T" $7
  OUT=$(printf '{"session_id":"s","hook_event_name":"%s","transcript_path":"%s","cwd":"%s"}' "$6" "$T" "$5" | env ${8:-} CLAUDE_PROJECT_DIR="$5" bash "$HOOK" 2>&1); orig=$OUT
  OUT=$(printf '{"session_id":"s","hook_event_name":"%s","transcript_path":"%s","cwd":"%s"}' "$6" "$T" "$5" | env ${8:-} CLAUDE_PROJECT_DIR="$5" bash "$d/hook.sh" 2>&1)
  if [ "$OUT" = "$orig" ]; then bad "mutation $1 survived"; else ok "mutation $1 caught"; fi
}
hd "M1 crossing check removed — B4 (no re-advisory) must catch it"
mutation crossing hook '    [ "$lp" -lt "$lc" ] && msg=$(say "$lc")' '    [ "$lc" -ge 1 ] && msg=$(say "$lc")' "$P" PostToolUse "410 450"
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
hd "M5 the fleet role check removed — F1 (solo byte-identity) must catch it"
mutation role hook 'if [ -z "$MH_FLEET_ROLE" ]; then' 'if false; then' "$P" PostToolUse "895 910"
hd "M6 cap comparison loosened — F3 (3 of 3) must catch it"
tfleet "$T" 3 930 950
mutation cap hook '      [ "$c" -ge "$MH_FLEET_MAX_COMPACTIONS" ] && reason="compaction cap reached ($c of $MH_FLEET_MAX_COMPACTIONS)"' '      [ "$c" -gt "$MH_FLEET_MAX_COMPACTIONS" ] && reason="compaction cap reached ($c of $MH_FLEET_MAX_COMPACTIONS)"' "$PC" PostToolUse -
hd "M7 restart threshold loosened — F4 (exactly 33 %) must catch it"
tfleet "$T" 1 330
mutation restart hook '    if [ "$n" -ge 1 ] && [ "$n" -le "$lim" ] && [ "$(mh_pct "$k0")" -ge "$MH_FLEET_RESTART_PCT" ]; then' '    if [ "$n" -ge 1 ] && [ "$n" -le "$lim" ] && [ "$(mh_pct "$k0")" -gt "$MH_FLEET_RESTART_PCT" ]; then' "$PC" PostToolUse -
hd "M8 single-successor guard removed — F6 (the cap reason wins) must catch it"
tfleet "$T" 3 950
mutation onesucc hook '      [ -n "$reason" ] || reason="post-compaction context at $(mh_pct "$k0")% (limit $MH_FLEET_RESTART_PCT%)"' '      reason="post-compaction context at $(mh_pct "$k0")% (limit $MH_FLEET_RESTART_PCT%)"' "$PC" PostToolUse -
hd "M9 cost-rule gate removed — F10 (no history read below level 2 without a drop) must catch it"
dg="$WORK/m-gate"; rm -rf "$dg"; mkdir -p "$dg/lib"; cp "$SH/lib/marvin-hook-lib.sh" "$dg/lib/"
A='  if [ "$MH_FLEET_ROLE" = child ] && { [ "$lc" -ge 2 ] || [ "$cur" -lt "$prev" ] || [ "$event" = UserPromptSubmit ]; }; then' B='  if [ "$MH_FLEET_ROLE" = child ]; then' awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$HOOK" > "$dg/hook.sh"
if cmp -s "$dg/hook.sh" "$HOOK"; then bad "mutation gate: target line not found — harness is stale"; else
  transcript "$T" 300 310; run "$dg/hook.sh" "$PC" PostToolUse "$T"
  if printf '%s' "$OUT" | grep -q SENTINEL; then ok "mutation gate caught"; else bad "mutation gate survived"; fi; fi
hd "M10 rest threshold loosened — F9 (exactly 94 %) must catch it"
REST='  if [ "$1" -gt 0 ] && [ "$(mh_pct "$1")" -ge $((MH_FLEET_REST_PCT * MH_SCALE / 100)) ]; then echo 1; else echo 0; fi'
mutation rest lib "$REST" '  if [ "$1" -gt 0 ] && [ "$(mh_pct "$1")" -gt $((MH_FLEET_REST_PCT * MH_SCALE / 100)) ]; then echo 1; else echo 0; fi' "$PC" PostToolUse "930 940"
hd "M11 rest point unscaled — F9 (the override at 80) must catch it"
mutation restscale lib "$REST" '  if [ "$1" -gt 0 ] && [ "$(mh_pct "$1")" -ge "$MH_FLEET_REST_PCT" ]; then echo 1; else echo 0; fi' "$PC" PostToolUse "740 760" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80
hd "M12 the child's wind-down branch dropped — F9 (child at 92 % gets S3W) must catch it"
mutation s3w hook '  elif [ "$1" = 3 ] && [ -z "$off" ] && [ "$MH_FLEET_ROLE" = child ]; then' '  elif false; then' "$PC" PostToolUse "850 920"
hd "M13 PostToolUse post-compaction window widened to n ≤ 3 — F4 (400k → 850k) must catch it"
tfleet "$T" 1 400 850
mutation lim hook '    lim=1; [ "$event" = UserPromptSubmit ] && lim=3' '    lim=3' "$PC" PostToolUse -

printf '\n----\ntest-context-budget: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
