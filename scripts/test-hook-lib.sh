#!/usr/bin/env bash
# test-hook-lib.sh — unit tests for scripts/lib/marvin-hook-lib.sh (v0.38.0).
# Pins the JSON walker (escapes, \u and surrogate pairs, paths into objects and arrays, scalars,
# containers, keys hidden inside strings, malformed and deep input, a 1 MiB string in one pass), the
# transcript readers, window/budget resolution and the level ladder. The mutation section reverts one
# line of the lib at a time in a throwaway copy; the named fixture's result must then change.
# Run from anywhere: bash scripts/test-hook-lib.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"; LIBUSE="$LIB"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-libtest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_CONFIG_DIR="$WORK/cfg"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="" CLAUDE_CODE_DISABLE_1M_CONTEXT="" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=""

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
eq()  { if [ "$OUT" = "$1" ]; then ok "= $(printf '%s' "$1" | head -c 60)"; else bad "got '$(printf '%s' "$OUT" | head -c 120)', want '$(printf '%s' "$1" | head -c 120)'"; fi; }
rc()  { if [ "$RC" = "$1" ]; then ok "rc $1"; else bad "rc $RC, want $1"; fi; }

J()  { OUT=$(printf '%s' "$1" | ( . "$LIBUSE"; mh_json "$2" "$3" ) 2>&1); RC=$?; }   # J <json> <mode> <path>
F()  { OUT=$( ( . "$LIBUSE"; "$@" ) 2>&1); RC=$?; }                                   # F <lib fn> <args…>

hd "J1 top-level string with the simple escapes"
J '{"a":"x\ny\t\"q\" back\\slash \/"}' get a; rc 0; eq "x
y	\"q\" back\\slash /"

hd "J2 \\u escapes: BMP and a surrogate pair decode to UTF-8; raw UTF-8 passes through"
J '{"a":"\u00e9 \u2705 \ud83d\ude80"}' get a; rc 0; eq "é ✅ 🚀"
J '{"a":"é ✅ 🚀"}' get a; rc 0; eq "é ✅ 🚀"

hd "J3 paths into nested objects and arrays"
J '{"tool_input":{"description":"d","prompt":"brief text"}}' get tool_input.prompt; rc 0; eq "brief text"
J '{"background_tasks":[{"status":"done"},{"status":"running"}]}' get background_tasks.1.status; rc 0; eq "running"
J '{"background_tasks":[]}' get background_tasks.0.status; rc 1

hd "J4 scalars print their literal; containers and absent paths are rc 1"
J '{"stop_hook_active":true,"n":12,"z":null}' get stop_hook_active; rc 0; eq "true"
J '{"stop_hook_active":true,"n":12,"z":null}' get n; rc 0; eq "12"
J '{"o":{"k":"v"}}' get o; rc 1
J '{"o":{"k":"v"}}' get nope; rc 1

hd "J5 a key-looking text inside a string value is never a key"
J '{"last_assistant_message":"see \"agent_type\":\"marvin:fake\" here","k":"v"}' get agent_type; rc 1
J '{"t":"a\"b","k":"v"}' get k; rc 0; eq "v"

hd "J6 malformed or truncated JSON is rc 1"
J '{"a":"unterminated' get a; rc 1
J '{"a" "missing colon"}' get a; rc 1
J 'not json' get a; rc 1

hd "J7 nesting deeper than 64 is refused"
deep="$(printf '%.0s[' $(seq 70))1$(printf '%.0s]' $(seq 70))"
dpath=$(printf '0.%.0s' $(seq 70)); dpath=${dpath%.}
J "$deep" get "$dpath"; rc 1

hd "J8 members lists the scalar members of an object"
J '{"enabledPlugins":{"a@m":true,"b@m":false,"c@m":{"x":1}},"other":1}' members enabledPlugins; rc 0
eq "$(printf 'a@m\ttrue\nb@m\tfalse')"

hd "J9 a 1 MiB string decodes in one pass, in under 10 s"
big=$(python3 -c 'import json; print(json.dumps({"m": "ab\n" * 350000}))')
SECONDS=0; J "$big" get m; t=$SECONDS; rc 0
if [ "${#OUT}" -ge 1049990 ]; then ok "length ${#OUT}"; else bad "decoded length ${#OUT}"; fi
if [ "$t" -lt 10 ]; then ok "took ${t}s"; else bad "took ${t}s"; fi

hd "L1 mh_last_text: the last main-thread assistant text block, decoded"
T="$WORK/t.jsonl"
{ printf '{"type":"assistant","message":{"id":"msg_1","content":[{"type":"text","text":"first"}]}}\n'
  printf '{"type":"user","message":{"content":"plain \\"type\\":\\"text\\" talk"}}\n'
  printf '{"type":"assistant","message":{"id":"msg_2","content":[{"type":"thinking","thinking":"x"}]}}\n'
  printf '{"type":"assistant","message":{"id":"msg_2","content":[{"type":"text","text":"last \\u2705\\nline2"}]}}\n'
  printf '{"type":"assistant","message":{"id":"msg_2","content":[{"type":"tool_use","id":"t","name":"X","input":{"type":"text"}}]}}\n'
  printf '{"type":"assistant","isSidechain":true,"message":{"id":"msg_3","content":[{"type":"text","text":"side"}]}}\n'
} > "$T"
F mh_last_text "$T"; rc 0; eq "last ✅
line2"
F mh_last_text "$WORK/none.jsonl"; rc 1
ln -s "$T" "$WORK/link.jsonl"; F mh_last_text "$WORK/link.jsonl"; rc 1

hd "L2 mh_first_user_text: string form and text-block form"
printf '{"type":"user","message":{"role":"user","content":"brief with WORKTREE: line"}}\n{"type":"user","message":{"content":"second"}}\n' > "$WORK/a1.jsonl"
F mh_first_user_text "$WORK/a1.jsonl"; rc 0; eq "brief with WORKTREE: line"
printf '{"type":"user","message":{"content":[{"type":"text","text":"array brief INFORMATION:"}]}}\n' > "$WORK/a2.jsonl"
F mh_first_user_text "$WORK/a2.jsonl"; rc 0; eq "array brief INFORMATION:"

hd "L3 mh_budget_init: frontmatter > AUTO_COMPACT_WINDOW > DISABLE_1M > profile default; invalid ignored"
probe() { ( . "$LIBUSE"; mh_budget_init "$1"; echo "$MH_SOFT $MH_HARD $MH_WIN $MH_SCALE" ); }
OUT=$(probe ""); eq "400 700 1000 100"
OUT=$(CLAUDE_CODE_DISABLE_1M_CONTEXT=1 probe ""); eq "400 700 200 100"
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=300000 CLAUDE_CODE_DISABLE_1M_CONTEXT=1 probe ""); eq "400 700 300 100"
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 probe "context_window_ktokens: 300"); eq "400 700 300 100"
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=99999 probe ""); eq "400 700 1000 100"
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=abc probe "context_window_ktokens: 0"); eq "400 700 1000 100"
OUT=$(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50 probe "session_soft_ktokens: 100
session_hard_ktokens: 200"); eq "100 200 1000 50"
OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 probe "context_window_ktokens: 300   # note"); eq "400 700 300 100"
OUT=$(probe "session_soft_ktokens: 100 # x
session_hard_ktokens: 200"); eq "100 200 1000 100"
OUT=$(probe "context_window_ktokens: 12x"); eq "400 700 1000 100"
OUT=$(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=500 probe "session_soft_ktokens: 300
session_hard_ktokens: 200"); eq "400 700 1000 100"

hd "L4 mh_pct steps the window up and never passes 100; mh_level takes the stricter scale"
lvl() { ( . "$LIBUSE"; mh_budget_init "$1"; shift; for k in "$@"; do printf '%s:%s:%s ' "$k" "$(mh_pct "$k")" "$(mh_level "$k")"; done ); }
OUT=$(lvl "context_window_ktokens: 100" 50 150 900 1500); eq "50:50:0 150:75:1 900:90:3 1500:100:3 "
OUT=$(lvl "session_soft_ktokens: 900
session_hard_ktokens: 990" 0 690 705 805 905); eq "0:0:0 690:69:0 705:70:1 805:80:2 905:90:3 "
OUT=$(lvl "" 405 705); eq "405:40:1 705:70:2 "
OUT=$(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50 lvl "session_soft_ktokens: 900
session_hard_ktokens: 990" 340 355 405 455); eq "340:34:0 355:35:1 405:40:2 455:45:3 "

hd "L5 mh_q encodes anything outside the safe set"
F mh_q "explanatory-output-style@claude-plugins-official"; eq "explanatory-output-style@claude-plugins-official"
F mh_q "a b\"c\\"; eq '"a b\"c\\"'

hd "L6 mh_is_subagent_call looks only before hook_event_name"
OUT=$( ( . "$LIBUSE"; MH_IN='{"agent_id":"a","hook_event_name":"PostToolUse"}'; mh_is_subagent_call && echo yes || echo no ) ); eq yes
OUT=$( ( . "$LIBUSE"; MH_IN='{"hook_event_name":"PostToolUse","tool_input":{"agent_id":"a"}}'; mh_is_subagent_call && echo yes || echo no ) ); eq no

hd "L7 mh_fm_value: quotes trimmed, a trailing # comment dropped, a # inside a word kept"
FM=$'a: block   # strict\nb: "q" #c\nc: x#y\nd: # only a comment\ne: plain'
F mh_fm_value "$FM" a; eq "block"
F mh_fm_value "$FM" b; eq "q"
F mh_fm_value "$FM" c; eq "x#y"
F mh_fm_value "$FM" d; eq ""
F mh_fm_value "$FM" e; eq "plain"

hd "L8 mh_path: one comparable form for Windows spellings; POSIX paths pass through"
F mh_path 'C:\Work\a b\r'; rc 0; eq "/c/Work/a b/r"
F mh_path 'C:/Work/x'; rc 0; eq "/c/Work/x"
F mh_path '/c/Work/x'; rc 0; eq "/c/Work/x"
F mh_path '/private/tmp/x'; rc 0; eq "/private/tmp/x"
F mh_path 'c:\x\y'; rc 0; eq "/c/x/y"
F mh_path 'C:\Work\\a b'; rc 0; eq "/c/Work/a b"
F mh_path 'C://Work//x'; rc 0; eq "/c/Work/x"
F mh_path ''; rc 1

hd "L9 mh_mode: lower-cased when allowed; absent/empty -> default; invalid -> default + MH_MODE_INVALID"
mode() { OUT=$( ( . "$LIBUSE"; mh_mode "$1" worktree_sweep "off on dry-run" "$2" >/dev/null; echo "$MH_MODE|inv=${MH_MODE_INVALID:-}" ) 2>&1); RC=$?; }   # mode <fm> <default>
mode $'worktree_sweep: OFF' on; rc 0; eq "off|inv="
mode $'other: 1' on; rc 0; eq "on|inv="
mode $'worktree_sweep:' on; rc 0; eq "on|inv="
mode $'worktree_sweep: on # c' off; rc 0; eq "on|inv="
mode $'worktree_sweep: "Dry-Run"' on; rc 0; eq "dry-run|inv="
mode $'worktree_sweep: Bogus' on; rc 0; eq "on|inv=Bogus"
mode $'worktree_sweep: bogus' off; rc 0; eq "off|inv=bogus"
mode $'worktree_sweep: on off' off; rc 0; eq "off|inv=on off"
# the printed value matches MH_MODE; both globals are reset on the next call
OUT=$( ( . "$LIBUSE"; mh_mode $'worktree_sweep: bogus' worktree_sweep "off on" on >/dev/null; a=$MH_MODE_INVALID
         v=$(mh_mode $'worktree_sweep: off' worktree_sweep "off on" on); mh_mode $'worktree_sweep: off' worktree_sweep "off on" on >/dev/null
         echo "$v|$MH_MODE|a=$a|after=${MH_MODE_INVALID:-}" ) 2>&1); RC=$?; rc 0; eq "off|off|a=bogus|after="

hd "L9b mh_is_key: a ticket key or exactly adhoc"
isk() { OUT=$( ( . "$LIBUSE"; mh_is_key "$1" && echo yes || echo no ) 2>&1); RC=$?; }
isk adhoc; eq yes
isk AOS-1; eq yes
isk aos-1; eq no
isk adhoc2; eq no
isk ""; eq no

hd "L10 mh_runs_root: the main checkout's physical .marvin/runs, from any linked worktree"
RR="$WORK/rr main"; mkdir -p "$RR" && git -C "$RR" init -q -b main . && git -C "$RR" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i \
  && git -C "$RR" worktree add -q "$WORK/rr wt" -b side 2>/dev/null
PHYS=$(cd "$RR" && pwd -P)
F mh_runs_root "$RR"; rc 0; eq "$PHYS/.marvin/runs"
F mh_runs_root "$WORK/rr wt"; rc 0; eq "$PHYS/.marvin/runs"
mkdir -p "$RR/sub dir"; F mh_runs_root "$RR/sub dir"; rc 0; eq "$PHYS/.marvin/runs"
git init -q --bare "$WORK/rr.git"; F mh_runs_root "$WORK/rr.git"; rc 1; eq ""
mkdir -p "$WORK/notrepo"; F mh_runs_root "$WORK/notrepo"; rc 1; eq ""
F mh_runs_root ""; rc 1
# a separate-git-dir checkout (common dir is not <main>/.git) has no run state
git init -q --separate-git-dir "$WORK/rr sep.gitdir" "$WORK/rr sep" >/dev/null 2>&1; F mh_runs_root "$WORK/rr sep"; rc 1; eq ""

hd "L11 layout regexes: session folder, key, stamp, marker"
re() { OUT=$( ( . "$LIBUSE"; printf '%s' "$2" | grep -Eq "${!1}" && echo match || echo no ) 2>&1); RC=$?; }   # re <CONST> <value>
re MH_SESSION_RE 20261019T101500Z-0b1f6c1e-aaaa-4bbb-8ccc-0123456789ab; eq match
re MH_SESSION_RE 20261019T101500Z-short; eq no
re MH_KEY_RE AOS-222; eq match
re MH_KEY_RE adhoc; eq no
re MH_KEY_RE aos-222; eq no
re MH_KEY_RE A-1; eq no
re MH_STAMP_RE 20261019T101500Z-note.md; eq match
re MH_STAMP_RE note.md; eq no
re MH_MARKER_RE 'marvin-owned marvin:developer-small 0123abcd 20261019T101500Z'; eq match
re MH_MARKER_RE 'marvin-owned orchestrator - 20261019T101500Z'; eq match
re MH_MARKER_RE 'marvin-owned marvin:Dev 0123abcd 20261019T101500Z'; eq no
re MH_MARKER_RE 'marvin-owned orchestrator abc 20261019T101500Z'; eq no

# ── mutations: revert one lib line in a copy; the fixture's OUT|RC must then change ────────────────
mutlib() {  # mutlib <name> <exact line> <replacement> <fixture-fn>
  local m="$WORK/lib-$1.sh" orig
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$LIB" > "$m"   # ENVIRON: no escape processing
  if cmp -s "$m" "$LIB"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  LIBUSE="$LIB"; "$4"; orig="$OUT|$RC"
  LIBUSE="$m"; "$4"; LIBUSE="$LIB"
  if [ "$OUT|$RC" = "$orig" ]; then bad "mutation $1 survived"; else ok "mutation $1 caught"; fi
}
f_sur()   { J '{"a":"\ud83d\ude80"}' get a; }
f_skip()  { J '{"t":"a\"b","k":"v"}' get k; }
f_win()   { OUT=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 probe "context_window_ktokens: 300"); RC=0; }
f_deep()  { J "$deep" get "$dpath"; }
f_cmt()   { F mh_fm_value "update_gate: block   # strict" update_gate; }
hd "ML1 surrogate-pair combining removed — J2 must catch it"
mutlib sur '    if (b >= 56320 && b <= 57343) { pos += 6; a = 65536 + (a - 55296) * 1024 + (b - 56320) }' '    b = b' f_sur
hd "ML2 escape skipping in skipped strings broken — J5 must catch it"
mutlib skip '    if (c == "\\") { pos += 2; continue }' '    if (c == "\\") { pos += 1; continue }' f_skip
hd "ML3 frontmatter window no longer first — L3 must catch it"
mutlib win '  if [ -n "$w" ] && [ "$((10#$w))" -gt 0 ]; then MH_WIN=$((10#$w))' '  if false; then :' f_win
f_cwin()  { OUT=$(probe "context_window_ktokens: 300   # note"); RC=0; }
hd "ML6 window read bypasses the comment-stripping reader — L3 must catch it"
mutlib cwin "  w=\$(mh_fm_value \"\$fm\" context_window_ktokens)" "  w=\$(printf '%s\\n' \"\$fm\" | sed -nE 's/^context_window_ktokens:[[:space:]]*([0-9]{1,5})[[:space:]]*\$/\\1/p' | head -n 1)" f_cwin
hd "ML4 depth guard removed — J7 must catch it"
mutlib deep '  if (d > 64) fail()' '  if (d > 100000) fail()' f_deep
hd "ML5 trailing-comment strip removed — L7 must catch it"
mutlib cmt "    | sed -E 's/(^|[[:space:]]+)#.*\$//' \\" '    | cat \' f_cmt

printf '\n----\ntest-hook-lib: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
