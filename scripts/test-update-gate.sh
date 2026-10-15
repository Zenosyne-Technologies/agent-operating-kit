#!/usr/bin/env bash
# test-update-gate.sh — behavioural tests for scripts/marvin-update-gate.sh (v0.38.0).
# Pins U1–U4 (pass and fail), code stripping, advise on UserPromptSubmit from the PREVIOUS transcript text,
# block mode at Stop (once: never under stop_hook_active, never while a background task runs; U4 never
# blocks), off, non-Marvin and sub-agent silence, no echo of message content, never writes, exit 0.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HOOK="$SCRIPT_DIR/marvin-update-gate.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-ugtest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
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

pyjson() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1], ensure_ascii=(sys.argv[2]=="ascii")), end="")' "$1" "${2:-raw}"; }
mk_project() {  # mk_project <dir> [update_gate]
  rm -rf "$1"; mkdir -p "$1/.marvin"
  { printf -- '---\nkit_version: 0.38.0\n'; [ -n "${2:-}" ] && printf 'update_gate: %s\n' "$2"; printf -- '---\nFacts.\n'; } > "$1/.marvin/PROJECT-INFO.md"
}
mk_t() {  # mk_t <text> [ascii] — transcript whose last main-thread assistant text is <text>
  local q; q=$(pyjson "$1" "${2:-raw}")
  { printf '{"type":"user","message":{"role":"user","content":"go"}}\n'
    printf '{"type":"assistant","message":{"id":"msg_1","content":[{"type":"thinking","thinking":"hm"}]}}\n'
    printf '{"type":"assistant","message":{"id":"msg_1","content":[{"type":"text","text":%s}]}}\n' "$q"
    printf '{"type":"assistant","isSidechain":true,"message":{"id":"msg_9","content":[{"type":"text","text":"<details> side 🚀"}]}}\n'
  } > "$T"
}
ups_in()  { printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"next"}' "$T" "$1"; }
stop_in() {  # stop_in <project> <text> [active] [bg-status]
  local q bg=""; q=$(pyjson "$2")
  [ -n "${4:-}" ] && bg=$(printf '{"id":"a1","type":"subagent","status":"%s","description":"x ] y","agent_type":"marvin:ponytail"}' "$4")
  printf '{"session_id":"s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":%s,"background_tasks":[%s]}' "$T" "$1" "${3:-false}" "$q" "$bg"
}
run() { OUT=$(printf '%s' "$3" | CLAUDE_PROJECT_DIR="$2" bash "$1" 2>&1); RC=$?; }   # run <hook> <project> <stdin>

P="$WORK/p"; mk_project "$P"; PB="$WORK/pb"; mk_project "$PB" block; PO="$WORK/po"; mk_project "$PO" off
PC="$WORK/pc"; mk_project "$PC" "block   # strict"
T="$WORK/t.jsonl"
GOOD_TABLE='| item | result | where |
|---|---|---|
| AOS-12 | ✅ merged | AOS-12 |

**Next**

- merge AOS-13'
GOOD_CALLOUT='> **❌ AOS-13 blocked: validator failed**
> - **What**: rows drop.
> - **Impact**: AOS-13 cannot close.
> - **Cause**: unknown
> - **Fix**: rebuild.
> - **Needs you?**: no.

**Open questions**

- ship it?'

hd "G1 non-Marvin project — nothing"
mkdir -p "$WORK/plain"; mk_t "<details>x</details>"; run "$HOOK" "$WORK/plain" "$(ups_in "$WORK/plain")"; assert_rc0; assert_empty

hd "G2 U1: a <details> fold is advised on the next prompt"
mk_t "Done.
<details><summary>log</summary>x</details>"
run "$HOOK" "$P" "$(ups_in "$P")"; assert_rc0; assert_json
assert_out '"hookEventName":"UserPromptSubmit"'; assert_out "Marvin update check"; assert_out "U1"; assert_out "user-updates.md"

hd "G3 U2: a status emoji outside the legend — raw and \\u-escaped; the legend alone passes"
mk_t "🚀 shipped"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U2"
mk_t "🚀 shipped" ascii; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U2"
mk_t "✅ AOS-12 merged. ❌ x ⚠️ y ⏳ z ⏭️ w"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty
mk_t "✅ AOS-12 merged." ascii; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty

hd "G4 U3: a callout missing a point, or out of order; the full callout passes"
mk_t "$GOOD_CALLOUT"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty
mk_t "$(printf '%s\n' "$GOOD_CALLOUT" | grep -v Cause)"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U3"
mk_t "> **⚠️ x**
> - **Impact**: a
> - **What**: b
> - **Cause**: c
> - **Fix**: d
> - **Needs you?**: no."; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U3"
mk_t '> **⚠️ AOS-13 slow**
> | point | detail |
> |---|---|
> | What | export is slow. |
> | Impact | AOS-13 waits. |
> | Cause | unknown |
> | Fix | add an index. |
> | Needs you? | no |

**Next**

- fix it'; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty
mk_t '> **❌ AOS-13 blocked**

| point | detail |
|---|---|
| **What** | rows drop. |
| **Impact** | AOS-13 waits. |
| **Cause** | unknown |
| **Fix** | rebuild. |
| **Needs you?:** | no |

**Open questions**

- ship it?'; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty
mk_t '> **❌ AOS-13 blocked**

| point | detail |
|---|---|
| Impact | AOS-13 waits. |
| What | rows drop. |
| Cause | unknown |
| Fix | rebuild. |
| Needs you? | no |

**Next**

- fix it'; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U3"
mk_t '> **❌ AOS-13 blocked**

| point | detail |
|---|---|
| What | rows drop. |
| Impact | AOS-13 waits. |
| Fix | rebuild. |
| Needs you? | no |

**Next**

- fix it'; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U3"

hd "G5 U4: a legend table without the tail is advised; with it, or a plain one-liner, passes"
mk_t "$GOOD_TABLE"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty
mk_t "$(printf '%s\n' "$GOOD_TABLE" | sed '/Next/,$d')"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U4"
mk_t "✅ AOS-12 merged to develop."; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty

hd "G6 fenced and inline code is ignored"
mk_t 'Example:
```
<details>x</details> 🚀
```
and `🚀` inline.'; run "$HOOK" "$P" "$(ups_in "$P")"; assert_empty

hd "G7 advise mode: Stop is silent even on a violation"
run "$HOOK" "$P" "$(stop_in "$P" "<details>x</details>")"; assert_rc0; assert_empty

hd "G8 block mode: Stop blocks U1–U3 once; never under stop_hook_active or a running background task; U4 never blocks"
run "$HOOK" "$PB" "$(stop_in "$PB" "<details>x</details>")"; assert_json; assert_out '"decision":"block"'; assert_out "U1"
run "$HOOK" "$PB" "$(stop_in "$PB" "<details>x</details>" true)"; assert_empty
run "$HOOK" "$PB" "$(stop_in "$PB" "<details>x</details>" false running)"; assert_empty
run "$HOOK" "$PB" "$(stop_in "$PB" "<details>x</details>" false completed)"; assert_out '"decision":"block"'
run "$HOOK" "$PB" "$(stop_in "$PB" "$(printf '%s\n' "$GOOD_TABLE" | sed '/Next/,$d')")"; assert_empty
mk_t "<details>x</details>"; run "$HOOK" "$PB" "$(ups_in "$PB")"; assert_empty
mk_t "$(printf '%s\n' "$GOOD_TABLE" | sed '/Next/,$d')"; run "$HOOK" "$PB" "$(ups_in "$PB")"; assert_out "U4"

hd "G8b an inline YAML comment after the mode still selects it"
run "$HOOK" "$PC" "$(stop_in "$PC" "<details>x</details>")"; assert_out '"decision":"block"'

hd "G9 off: nothing anywhere"
mk_t "<details>x</details>"; run "$HOOK" "$PO" "$(ups_in "$PO")"; assert_empty
run "$HOOK" "$PO" "$(stop_in "$PO" "<details>x</details>")"; assert_empty

hd "G10 a sub-agent invocation is skipped"
run "$HOOK" "$PB" "{\"agent_id\":\"a\",$(stop_in "$PB" "<details>x</details>" | cut -c2-)"; assert_empty

hd "G11 nothing from the message is echoed back"
mk_t "ZQX-ECHO-MARK <details>x</details> \" \\ %s"; run "$HOOK" "$P" "$(ups_in "$P")"; assert_json; assert_no "ZQX-ECHO-MARK"
run "$HOOK" "$PB" "$(stop_in "$PB" "ZQX-ECHO-MARK <details>")"; assert_json; assert_no "ZQX-ECHO-MARK"

hd "G12 missing transcript, malformed stdin, empty stdin — nothing, exit 0"
run "$HOOK" "$P" "$(printf '{"hook_event_name":"UserPromptSubmit","transcript_path":"%s","cwd":"%s"}' "$WORK/none" "$P")"; assert_rc0; assert_empty
run "$HOOK" "$P" '{"hook_event_name":"Stop","last_assistant_message":"unterminated'; assert_rc0; assert_empty
run "$HOOK" "$P" ''; assert_rc0; assert_empty

hd "G13 never writes"
mk_t "<details>x</details>"; before=$(ls -R "$WORK" | cksum)
run "$HOOK" "$P" "$(ups_in "$P")"; run "$HOOK" "$PB" "$(stop_in "$PB" "<details>")"
after=$(ls -R "$WORK" | cksum); if [ "$before" = "$after" ]; then ok "nothing written"; else bad "the hook wrote something"; fi

hd "G14 the last text block is read, past later tool_use-only lines"
mk_t "<details>x</details>"
printf '{"type":"assistant","message":{"id":"msg_2","content":[{"type":"tool_use","id":"t","name":"X","input":{"type":"text"}}]}}\n' >> "$T"
run "$HOOK" "$P" "$(ups_in "$P")"; assert_out "U1"

# ── mutations ──────────────────────────────────────────────────────────────────────────────────────
mutation() {  # mutation <name> <exact line> <replacement> <project> <stdin> — a mutant must change the output
  local d="$WORK/m-$1" orig rc1
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$LIB" "$d/lib/"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$HOOK" > "$d/hook.sh"
  if [ ! -f "$HOOK" ] || cmp -s "$d/hook.sh" "$HOOK"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  run "$HOOK" "$4" "$5"; orig=$OUT; rc1=$RC
  run "$d/hook.sh" "$4" "$5"
  if [ "$rc1" != 0 ] || [ "$RC" != 0 ]; then bad "mutation $1: run failed (exit $rc1 / $RC)"; return; fi
  if [ "$OUT" = "$orig" ]; then bad "mutation $1 survived"; else ok "mutation $1 caught"; fi
}
hd "M1 fence skipping removed — G6 must catch it"
mk_t 'x
```
<details>
```'
mutation fence '  if (fence) next' '  fence = fence' "$P" "$(ups_in "$P")"
hd "M2 stop_hook_active guard removed — G8 must catch it"
mutation active '  [ "$(printf '"'"'%s'"'"' "$MH_IN" | mh_get stop_hook_active)" = true ] && exit 0' '  :' "$PB" "$(stop_in "$PB" "<details>" true)"
hd "M3 background-task guard removed — G8 must catch it"
mutation bg '    [ "$st" = running ] && exit 0' '    :' "$PB" "$(stop_in "$PB" "<details>" false running)"
hd "M4 legend not stripped before the emoji test — G3 must catch it"
mk_t "✅ AOS-12 merged."
mutation legend '    t = l; gsub(ck, "", t); gsub(cx, "", t); gsub(wn, "", t)' '    t = l' "$P" "$(ups_in "$P")"
hd "M5 table-below-the-callout not read — G4 must catch it"
mk_t '> **❌ AOS-13 blocked**

| point | detail |
|---|---|
| What | a |
| Impact | b |
| Cause | c |
| Fix | d |
| Needs you? | no |

**Next**

- x'
mutation tablebelow '      if (!haspoint(c)) { while (j <= n && L[j] ~ /^[ \t]*$/) j++' '      if (0) { while (j <= n && L[j] ~ /^[ \t]*$/) j++' "$P" "$(ups_in "$P")"

printf '\n----\ntest-update-gate: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
