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

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc0()    { if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit $RC, want 0"; fi; }
assert_out()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_empty()  { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 160)"; fi; }
assert_json()   { if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then ok "valid JSON"; else bad "output is not valid JSON"; fi; }

# transcript <file> <ktokens>... — one assistant line per argument, context = k*1000 split across the
# three counted fields; a user tool-result line containing escaped "usage" text sits in between.
transcript() {
  local f="$1"; shift; : > "$f"
  for k in "$@"; do
    printf '{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":998,"cache_read_input_tokens":%d,"output_tokens":50}}}\n' $(( k * 1000 - 1000 )) >> "$f"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"{\\"usage\\":{\\"input_tokens\\":999999999}}"}]}}\n' >> "$f"
  done
}
mk_project() {  # mk_project <dir> [soft] [hard]
  rm -rf "$1"; mkdir -p "$1/.marvin"
  { printf -- '---\nkit_version: 0.36.0\n'
    [ -n "${2:-}" ] && printf 'session_soft_ktokens: %s\n' "$2"
    [ -n "${3:-}" ] && printf 'session_hard_ktokens: %s\n' "$3"
    printf -- '---\nProject facts.\n'; } > "$1/.marvin/PROJECT-INFO.md"
}
# run <hook> <project_dir> <event> <transcript> [extra_json_fields]
run() {
  local hook="$1" p="$2" ev="$3" t="$4" extra="${5:-}"
  OUT=$(printf '{"session_id":"s","hook_event_name":"%s","transcript_path":"%s","cwd":"%s"%s}' "$ev" "$t" "$p" "$extra" \
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
run "$HOOK" "$P" PostToolUse "$T" ',"agent_id":"a1","agent_type":"marvin:developer"'; assert_rc0; assert_empty

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

# ── mutations: each reverts one guard in a copy; the named fixture must then fail ────────────────
mutation() {  # mutation <name> <exact line in HOOK> <replacement> <event> <transcript-ks> <extra>
  local m="$WORK/mutant-$1.sh"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$HOOK" > "$m"   # ENVIRON: no escape processing, unlike awk -v
  if cmp -s "$m" "$HOOK"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  transcript "$T" $5
  run "$m" "$P" "$4" "$T" "$6"
  if [ -z "$OUT" ]; then bad "mutation $1 survived (no advisory where the mutant should emit one)"; else ok "mutation $1 caught"; fi
}
hd "M1 crossing check removed — B4 (no re-advisory) must catch it"
mutation crossing '    [ "$prev" -lt "$soft" ] && [ "$cur" -ge "$soft" ] && msg="$SOFT_MSG"' '    [ "$cur" -ge "$soft" ] && msg="$SOFT_MSG"' PostToolUse "410 450" ""
hd "M2 sub-agent guard removed — B9 must catch it"
mutation subagent '  *\"agent_id\"*) exit 0 ;;' '  *\"agent_id\"*) : ;;' PostToolUse "390 410" ',"agent_id":"a1"'

printf '\n----\ntest-context-budget: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
