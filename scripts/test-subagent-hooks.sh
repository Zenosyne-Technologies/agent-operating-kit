#!/usr/bin/env bash
# test-subagent-hooks.sh — behavioural tests for marvin-subagent-gate.sh (SubagentStop) and
# marvin-subagent-rules.sh (SubagentStart), v0.38.0. Pins: marvin:* personas only; TRACKER:/GUARDRAILS:
# always; INFORMATION:/WORKTREE:/SURFACES: when the brief reserves them; reserved lines must START a line;
# the 25-line cap with its exempt lines; one block only (stop_hook_active); no echo; never writes; exit 0.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GATE="$SCRIPT_DIR/marvin-subagent-gate.sh"; RULES="$SCRIPT_DIR/marvin-subagent-rules.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-satest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_CONFIG_DIR="$WORK/cfg"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="" CLAUDE_CODE_DISABLE_1M_CONTEXT="" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=""

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc0()   { if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit $RC, want 0"; fi; }
assert_out()   { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_no()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "out must not have: $1"; else ok "out free of: $1"; fi; }
assert_empty() { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 160)"; fi; }
assert_json()  { if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "valid JSON"; else bad "not valid JSON"; fi; }

pyjson() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]), end="")' "$1"; }
P="$WORK/p"; mkdir -p "$P/.marvin"; printf -- '---\nkit_version: 0.38.0\n---\n' > "$P/.marvin/PROJECT-INFO.md"
AT="$WORK/agent.jsonl"
brief() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(pyjson "$1")" > "$AT"; }
stop_in() {  # stop_in <agent_type> <message> [active]
  printf '{"session_id":"s","cwd":"%s","agent_id":"a1","agent_type":"%s","hook_event_name":"SubagentStop","stop_hook_active":%s,"agent_transcript_path":"%s","last_assistant_message":%s}' \
    "$P" "$1" "${3:-false}" "$AT" "$(pyjson "$2")"
}
start_in() { printf '{"session_id":"s","cwd":"%s","agent_id":"a1","agent_type":"%s","hook_event_name":"SubagentStart"}' "$2" "$1"; }
run() { OUT=$(printf '%s' "$3" | CLAUDE_PROJECT_DIR="$2" bash "$1" 2>&1); RC=$?; }

OKMSG='DONE: built it
- TRACKER: none
GUARDRAILS: NONE'
brief "Do X. FINAL MESSAGE: verdict, TRACKER:, GUARDRAILS:. Run report: .marvin/runs/AOS-1/x.md"

hd "S1 a non-marvin agent is ignored"
run "$GATE" "$P" "$(stop_in Explore "no lines at all")"; assert_rc0; assert_empty

hd "S2 a complete message passes"
run "$GATE" "$P" "$(stop_in marvin:ponytail "$OKMSG")"; assert_rc0; assert_empty

hd "S3 missing TRACKER: is sent back, naming it"
run "$GATE" "$P" "$(stop_in marvin:developer "DONE
GUARDRAILS: NONE")"; assert_json; assert_out '"decision":"block"'; assert_out "TRACKER:"; assert_out "briefing.md item 11"; assert_no "Missing reserved line(s): TRACKER: GUARDRAILS:"

hd "S4 WORKTREE: is required only when the brief reserves it"
run "$GATE" "$P" "$(stop_in marvin:developer "$OKMSG")"; assert_empty
brief "FINAL MESSAGE spec: TRACKER:, GUARDRAILS:, WORKTREE: <path>. Report: .marvin/runs/A/r.md"
run "$GATE" "$P" "$(stop_in marvin:developer "$OKMSG")"; assert_out "WORKTREE:"
run "$GATE" "$P" "$(stop_in marvin:developer "$OKMSG
WORKTREE: /x — branch b pushed; safe to delete once merged")"; assert_empty

hd "S5 an array-form brief reserving INFORMATION: is enforced"
printf '{"type":"user","message":{"content":[{"type":"text","text":"INFORMATION: line reserved; TRACKER:"}]}}\n' > "$AT"
run "$GATE" "$P" "$(stop_in marvin:validator-completion "$OKMSG")"; assert_out "INFORMATION:"

hd "S6 the 25-line cap — TRACKER:, UNRELATED: and FAIL lines do not count"
brief "plain brief"
long=$(printf 'line %s\n' $(seq 30)); run "$GATE" "$P" "$(stop_in marvin:developer "$OKMSG
$long")"; assert_out "keep it to 25"
fails=$(printf 'F%s FAIL x.sh:1 broken\n' $(seq 10)); short=$(printf 'line %s\n' $(seq 18))
run "$GATE" "$P" "$(stop_in marvin:validator-completion "$OKMSG
$short
$fails")"; assert_empty

hd "S7 the re-fire (stop_hook_active) passes as is"
run "$GATE" "$P" "$(stop_in marvin:developer "nothing" true)"; assert_empty

hd "S8 non-Marvin project, missing agent transcript, empty stdin"
mkdir -p "$WORK/plain"; run "$GATE" "$WORK/plain" "$(stop_in marvin:developer "x")"; assert_empty
rm -f "$AT"; run "$GATE" "$P" "$(stop_in marvin:developer "$OKMSG")"; assert_rc0; assert_empty
run "$GATE" "$P" ''; assert_rc0; assert_empty

hd "S9 a reserved token mid-sentence does not count — it must start a line"
brief "plain brief"
run "$GATE" "$P" "$(stop_in marvin:developer "I made no TRACKER: writes
GUARDRAILS: NONE")"; assert_out "TRACKER:"

hd "S10 nothing from the message or brief is echoed"
brief "ZQX-BRIEF-MARK WORKTREE:"
run "$GATE" "$P" "$(stop_in marvin:developer "ZQX-MSG-MARK \" \\")"; assert_json; assert_no "ZQX-MSG-MARK"; assert_no "ZQX-BRIEF-MARK"

hd "R1 SubagentStart injects the rules for a marvin persona"
run "$RULES" "$P" "$(start_in marvin:developer-small "$P")"; assert_rc0; assert_json
assert_out '"hookEventName":"SubagentStart"'; assert_out "Marvin sub-agent rules"; assert_out "TRACKER:"; assert_out "never create, move or delete a git tag"

hd "R2 not for other agents or non-Marvin projects"
run "$RULES" "$P" "$(start_in Explore "$P")"; assert_empty
run "$RULES" "$WORK/plain" "$(start_in marvin:developer "$WORK/plain")"; assert_empty

hd "R3 never writes (both hooks)"
brief "x"; before=$(ls -R "$WORK" | cksum)
run "$GATE" "$P" "$(stop_in marvin:developer "x")"; run "$RULES" "$P" "$(start_in marvin:developer "$P")"
after=$(ls -R "$WORK" | cksum); if [ "$before" = "$after" ]; then ok "nothing written"; else bad "a hook wrote something"; fi

# ── mutations on the gate ──────────────────────────────────────────────────────────────────────────
mutation() {  # mutation <name> <exact line> <replacement> <stdin>
  local d="$WORK/m-$1" orig rc1
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$LIB" "$d/lib/"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$GATE" > "$d/hook.sh"
  if [ ! -f "$GATE" ] || cmp -s "$d/hook.sh" "$GATE"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  run "$GATE" "$P" "$4"; orig=$OUT; rc1=$RC
  run "$d/hook.sh" "$P" "$4"
  if [ "$rc1" != 0 ] || [ "$RC" != 0 ]; then bad "mutation $1: run failed (exit $rc1 / $RC)"; return; fi
  if [ "$OUT" = "$orig" ]; then bad "mutation $1 survived"; else ok "mutation $1 caught"; fi
}
hd "M1 stop_hook_active guard removed — S7 must catch it"
mutation active '[ "$(printf '"'"'%s'"'"' "$MH_IN" | mh_get stop_hook_active)" = true ] && exit 0' ':' "$(stop_in marvin:developer "nothing" true)"
hd "M2 brief-reserved lines ignored — S4 must catch it"
brief "FINAL MESSAGE spec: TRACKER:, GUARDRAILS:, WORKTREE: <path>."
mutation brief '  case "$brief" in *"$t:"*) has "$t" || missing="$missing $t:" ;; esac' '  :' "$(stop_in marvin:developer "$OKMSG")"
hd "M3 line-start anchor dropped — S9 must catch it"
brief "plain brief"
mutation anchor 'has() { printf '"'"'%s\n'"'"' "$msg" | grep -Eq '"'"'^[[:space:]>*`-]*'"'"'"$1"'"'"':'"'"'; }' 'has() { printf '"'"'%s\n'"'"' "$msg" | grep -Eq "$1:"; }' "$(stop_in marvin:developer "I made no TRACKER: writes
GUARDRAILS: NONE")"

printf '\n----\ntest-subagent-hooks: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
