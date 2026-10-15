#!/usr/bin/env bash
# test-brief-lint.sh — behavioural tests for scripts/marvin-brief-lint.sh (PreToolUse, v0.38.0).
# Pins: marvin:* dispatches only; run-report path, FINAL MESSAGE spec with TRACKER:, DoD; the ≥ level-2
# context line; never a decision or a rewrite; no echo; sub-agent calls skipped; never writes; exit 0.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/marvin-brief-lint.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-bltest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
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
T="$WORK/t.jsonl"
transcript() {  # transcript <k>… — one assistant message per argument at k thousand tokens of context
  local k n=0; : > "$T"
  for k in "$@"; do n=$((n+1))
    printf '{"type":"assistant","message":{"id":"msg_%d","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%d,"output_tokens":5}}}\n' "$n" $((k * 1000)) >> "$T"
  done
}
pre_in() {  # pre_in <tool> <subagent_type> <prompt> [prefix-fields]
  printf '{"session_id":"s"%s,"transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"description":"d","prompt":%s,"subagent_type":"%s"}}' \
    "${4:-}" "$T" "$P" "$1" "$(pyjson "$3")" "$2"
}
run() { OUT=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1); RC=$?; }

GOOD='DoD: the cache keys are stable. Branch: feature/AOS-1-x. FINAL MESSAGE: verdict line, TRACKER:, GUARDRAILS:. Run report: .marvin/runs/AOS-1/20261014T000000Z-developer.md'
transcript 100 120

hd "B1 a complete brief passes"
run "$P" "$(pre_in Agent marvin:developer "$GOOD")"; assert_rc0; assert_empty
run "$P" "$(pre_in Task marvin:developer "$GOOD")"; assert_empty

hd "B2 no run-report path"
run "$P" "$(pre_in Agent marvin:developer "${GOOD%%Run report*}")"; assert_json; assert_out ".marvin/runs/"; assert_out '"hookEventName":"PreToolUse"'

hd "B3 no FINAL MESSAGE spec"
run "$P" "$(pre_in Agent marvin:developer 'DoD: x. Report: .marvin/runs/A/r.md')"; assert_out "no FINAL MESSAGE spec"

hd "B4 a FINAL MESSAGE spec without TRACKER:"
run "$P" "$(pre_in Agent marvin:developer 'DoD: x. FINAL MESSAGE: verdict. Report: .marvin/runs/A/r.md')"; assert_out "without the TRACKER: line"

hd "B5 no DoD"
run "$P" "$(pre_in Agent marvin:developer 'FINAL MESSAGE: v, TRACKER:. Report: .marvin/runs/A/r.md')"; assert_out "no DoD"

hd "B6 other agents, other tools, non-Marvin projects — nothing"
run "$P" "$(pre_in Agent Explore "bad brief")"; assert_empty
run "$P" "$(pre_in Bash marvin:developer "bad brief")"; assert_empty
mkdir -p "$WORK/plain"; run "$WORK/plain" "$(pre_in Agent marvin:developer "bad brief")"; assert_empty

hd "B7 at the wind-down step a complete brief still gets the context line"
transcript 690 705
run "$P" "$(pre_in Agent marvin:developer "$GOOD")"; assert_json; assert_out "start nothing new"; assert_out "session-budget.md"
transcript 100 120

hd "B8 never a decision, never a rewrite, never an echo"
run "$P" "$(pre_in Agent marvin:developer "ZQX-MARK no spec \" \\")"; assert_json
assert_no "permissionDecision"; assert_no "updatedInput"; assert_no "ZQX-MARK"

hd "B9 a sub-agent's own dispatch is skipped; malformed stdin is silent"
run "$P" "$(pre_in Agent marvin:developer "bad" ',"agent_id":"a1"')"; assert_empty
run "$P" '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"prompt":"unterminated'; assert_rc0; assert_empty

hd "B10 never writes"
before=$(ls -R "$WORK" | cksum); run "$P" "$(pre_in Agent marvin:developer "bad")"
after=$(ls -R "$WORK" | cksum); if [ "$before" = "$after" ]; then ok "nothing written"; else bad "the hook wrote something"; fi

mutation() {  # mutation <name> <exact line> <replacement> <stdin>
  local d="$WORK/m-$1" orig rc1
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$LIB" "$d/lib/"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$HOOK" > "$d/hook.sh"
  if [ ! -f "$HOOK" ] || cmp -s "$d/hook.sh" "$HOOK"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  run "$P" "$4"; orig=$OUT; rc1=$RC
  OUT=$(printf '%s' "$4" | CLAUDE_PROJECT_DIR="$P" bash "$d/hook.sh" 2>&1); RC=$?
  if [ "$rc1" != 0 ] || [ "$RC" != 0 ]; then bad "mutation $1: run failed (exit $rc1 / $RC)"; return; fi
  if [ "$OUT" = "$orig" ]; then bad "mutation $1 survived"; else ok "mutation $1 caught"; fi
}
hd "M1 DoD check removed — B5 must catch it"
mutation dod "printf '%s\n' \"\$brief\" | grep -Eiq 'DoD|definition of done' || miss=\"\$miss; no DoD (item 3)\"" ':' "$(pre_in Agent marvin:developer 'FINAL MESSAGE: v, TRACKER:. Report: .marvin/runs/A/r.md')"
hd "M2 context level ignored — B7 must catch it"
transcript 690 705
mutation level '  if [ -n "$k" ] && [ "$(mh_level "$k")" -ge 2 ]; then' '  if false; then' "$(pre_in Agent marvin:developer "$GOOD")"

printf '\n----\ntest-brief-lint: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
