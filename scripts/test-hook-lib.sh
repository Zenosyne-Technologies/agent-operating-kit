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

# ── fleet role marker and settings (fleet-mode) ───────────────────────────────────────────────────
# fleet <root>… → OUT="<printed role>|<MH_FLEET_ROLE>|<MH_FLEET_EPIC>" and RC = mh_fleet_role's OWN status, both of
# the LAST root. The roots are called in ONE shell in order (the globals do not survive a $( ) subshell, and the
# earlier calls let a test see whether a no-marker call resets them). Stderr is collected in $WORK/fleet.err.
fleet() {
  : > "$WORK/fleet.err"
  OUT=$( ( . "$LIBUSE"; for _r in "$@"; do mh_fleet_role "$_r" > "$WORK/fleet.out" 2>> "$WORK/fleet.err"; echo $? > "$WORK/fleet.rc"; done
           printf '%s|%s|%s' "$(cat "$WORK/fleet.out")" "$MH_FLEET_ROLE" "$MH_FLEET_EPIC" ) 2>&1 )
  RC=$(cat "$WORK/fleet.rc")
}
mkrepo() { rm -rf "$1"; mkdir -p "$1"; git -C "$1" init -q; }
gdir()   { ( cd "$1" && cd "$(git rev-parse --git-dir)" && pwd -P ); }

hd "F1 a role=child marker in the private git dir prints child and sets MH_FLEET_EPIC"
mkrepo "$WORK/f1"; printf 'role=child\nepic=ABC-12\n' > "$(gdir "$WORK/f1")/marvin-fleet"
fleet "$WORK/f1"; rc 0; eq "child|child|ABC-12"
printf 'role=master\n' > "$(gdir "$WORK/f1")/marvin-fleet"; fleet "$WORK/f1"; rc 0; eq "master|master|"
printf 'role=child\nepic=bad key\n' > "$(gdir "$WORK/f1")/marvin-fleet"; fleet "$WORK/f1"; eq "child|child|"
printf 'role=child\r\nepic=ABC-12\r\n' > "$(gdir "$WORK/f1")/marvin-fleet"; fleet "$WORK/f1"; eq "child|child|ABC-12"

hd "F1b the marker lives in one worktree's private git dir; the main checkout reads nothing"
mkrepo "$WORK/f1b"; git -C "$WORK/f1b" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
git -C "$WORK/f1b" worktree add -q "$WORK/f1b-wt" -b wt 2>/dev/null
printf 'role=child\nepic=XY-7\n' > "$(gdir "$WORK/f1b-wt")/marvin-fleet"
fleet "$WORK/f1b-wt"; rc 0; eq "child|child|XY-7"
fleet "$WORK/f1b"; rc 0; eq "||"

hd "F2 no marker is empty output, rc 0"
mkrepo "$WORK/f2"; fleet "$WORK/f2"; rc 0; eq "||"
hd "F2b a call that finds no marker resets MH_FLEET_ROLE and MH_FLEET_EPIC set by the call before"
printf 'role=child\nepic=ABC-12\n' > "$(gdir "$WORK/f1")/marvin-fleet"
fleet "$WORK/f1" "$WORK/f2"; rc 0; eq "||"
fleet "$WORK/f1" "$WORK/f5"; rc 0; eq "||"
fleet "$WORK/f2" "$WORK/f1"; rc 0; eq "child|child|ABC-12"

hd "F3 a marker that is a symlink is never followed"
mkrepo "$WORK/f3"; printf 'role=child\nepic=ABC-12\n' > "$WORK/f3-real"; ln -s "$WORK/f3-real" "$(gdir "$WORK/f3")/marvin-fleet"
fleet "$WORK/f3"; rc 0; eq "||"

hd "F4 an unknown role or an empty marker is empty output"
mkrepo "$WORK/f4"; printf 'role=admiral\nepic=ABC-12\n' > "$(gdir "$WORK/f4")/marvin-fleet"
fleet "$WORK/f4"; rc 0; eq "||"
: > "$(gdir "$WORK/f4")/marvin-fleet"; fleet "$WORK/f4"; rc 0; eq "||"

hd "F5 a root that is not a git repo is empty output, rc 0, nothing on stderr"
mkdir -p "$WORK/f5"; fleet "$WORK/f5"; rc 0; eq "||"
fleet "$WORK/f5-missing"; rc 0; eq "||"
if [ ! -s "$WORK/fleet.err" ]; then ok "no stderr"; else bad "stderr: $(head -c 80 "$WORK/fleet.err")"; fi

fprobe() { OUT=$( ( . "$LIBUSE"; mh_fleet_init "$1"; printf '%s %s %s' "$MH_FLEET_MAX_CHILDREN" "$MH_FLEET_MAX_COMPACTIONS" "$MH_FLEET_RESTART_PCT" ) 2>&1 ); RC=$?; }
hd "S1 fleet_max_compactions: 0–9, else 3"
fprobe ""; eq "3 3 33"
for v in abc -1 99 10; do fprobe "fleet_max_compactions: $v"; eq "3 3 33"; done
fprobe "fleet_max_compactions: 0"; eq "3 0 33"
fprobe "fleet_max_compactions: 9   # cap"; eq "3 9 33"

hd "S2 fleet_restart_max_pct: 1–99, else 33"
for v in 0 100 x -5 007x; do fprobe "fleet_restart_max_pct: $v"; eq "3 3 33"; done
fprobe "fleet_restart_max_pct: 50"; eq "3 3 50"
fprobe "fleet_restart_max_pct: 08"; eq "3 3 8"

hd "S3 fleet_max_children: 1–9, else 3"
for v in 0 12 a; do fprobe "fleet_max_children: $v"; eq "3 3 33"; done
fprobe "fleet_max_children: 2"; eq "2 3 33"
fprobe "fleet_max_children: 9
fleet_max_compactions: 1
fleet_restart_max_pct: 99"; eq "9 1 99"

# ── compaction metrics from the transcript (fleet-mode) ───────────────────────────────────────────
# amsg <file> <k> appends one assistant message of context size k (thousands); boundary <file> [sidechain] appends a
# compaction line. mh_compactions / mh_since_compact are read through F (OUT = stdout+stderr, RC = their own status).
CMSG=0
amsg() { CMSG=$((CMSG+1))
  printf '{"type":"assistant","message":{"id":"msg_c%d","content":[{"type":"thinking","thinking":"hm"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":998,"cache_read_input_tokens":%d,"output_tokens":50}}}\n' "$CMSG" $(( $2 * 1000 - 1000 )) >> "$1"; }
boundary() { printf '{"type":"system","subtype":"compact_boundary","isSidechain":%s,"compactMetadata":{"trigger":"auto","preTokens":990000}}\n' "${2:-false}" >> "$1"; }

hd "C1 mh_compactions counts main-thread compaction lines over the whole file"
C="$WORK/c1.jsonl"; : > "$C"; amsg "$C" 900; boundary "$C"; amsg "$C" 120; boundary "$C"; amsg "$C" 130
F mh_compactions "$C"; rc 0; eq 2
: > "$C"; amsg "$C" 100; F mh_compactions "$C"; rc 0; eq 0
: > "$C"; boundary "$C"; for _i in $(seq 450); do amsg "$C" 50; done   # the boundary is far outside any 400-line tail
F mh_compactions "$C"; rc 0; eq 1
F mh_compactions "$WORK/none.jsonl"; rc 1
F mh_compactions ""; rc 1

hd "C2 compaction text quoted in a tool result, or without the system type, is not a compaction"
C="$WORK/c2.jsonl"; : > "$C"
printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"{\\"type\\":\\"system\\",\\"subtype\\":\\"compact_boundary\\"}"}]}}\n' >> "$C"
printf '{"type":"user","subtype":"compact_boundary","message":{"content":"x"}}\n' >> "$C"
F mh_compactions "$C"; rc 0; eq 0
boundary "$C"; F mh_compactions "$C"; rc 0; eq 1

hd "C3 a sub-agent (sidechain) compaction is not the main thread's"
C="$WORK/c3.jsonl"; : > "$C"; boundary "$C" true; F mh_compactions "$C"; rc 0; eq 0
boundary "$C"; F mh_compactions "$C"; rc 0; eq 1

hd "C4 mh_since_compact: messages after the LAST compaction, and the size of the first of them"
C="$WORK/c4.jsonl"; : > "$C"; amsg "$C" 900; boundary "$C"; amsg "$C" 120; amsg "$C" 130
F mh_since_compact "$C"; rc 0; eq "2 120"
: > "$C"; amsg "$C" 900; boundary "$C"; amsg "$C" 700; boundary "$C"; amsg "$C" 150; amsg "$C" 160; amsg "$C" 170
F mh_since_compact "$C"; rc 0; eq "3 150"
: > "$C"; boundary "$C"; amsg "$C" 80; boundary "$C" true; amsg "$C" 90   # a sidechain boundary does not reset the count
F mh_since_compact "$C"; rc 0; eq "2 80"
# one message over several lines is one message, last line's size (as mh_sizes)
: > "$C"; boundary "$C"; amsg "$C" 100; CMSG=$((CMSG-1)); amsg "$C" 110; amsg "$C" 120
F mh_since_compact "$C"; rc 0; eq "2 110"
F mh_since_compact "$WORK/none.jsonl"; rc 1

hd "C5 mh_since_compact prints nothing without a compaction or without a message after it"
C="$WORK/c5.jsonl"; : > "$C"; amsg "$C" 100; amsg "$C" 200
F mh_since_compact "$C"; rc 0; eq ""
boundary "$C"; F mh_since_compact "$C"; rc 0; eq ""
: > "$C"; F mh_since_compact "$C"; rc 0; eq ""

hd "C6 mh_since_compact reads at most 400 lines and 8 MB after the boundary: n saturates, k stays the first message's"
C="$WORK/c6.jsonl"; : > "$C"; amsg "$C" 900; boundary "$C"; amsg "$C" 77; for _i in $(seq 449); do amsg "$C" 50; done
F mh_since_compact "$C"; rc 0; eq "400 77"
C="$WORK/c6b.jsonl"; : > "$C"; boundary "$C"; pad=$(head -c 100000 /dev/zero | tr '\0' x)   # 100 lines of ~100 KB: ~10 MB after the boundary
for _i in $(seq 100); do CMSG=$((CMSG+1))
  printf '{"type":"assistant","message":{"id":"msg_c%d","content":[{"type":"text","text":"%s"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":998,"cache_read_input_tokens":%d}}}\n' "$CMSG" "$pad" $(( (60 + _i) * 1000 - 1000 )) >> "$C"
done
F mh_since_compact "$C"; rc 0
if printf '%s' "$OUT" | grep -Eq '^([1-9]|[1-9][0-9]) 61$'; then ok "n < 100 (capped at 8 MB), k = first message ($OUT)"; else bad "got '$OUT', want '<n<100> 61'"; fi

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
f_fsym()  { fleet "$WORK/f3"; }
f_frole() { printf 'role=admiral\nepic=ABC-12\n' > "$(gdir "$WORK/f4")/marvin-fleet"; fleet "$WORK/f4"; }
f_fepic() { printf 'role=child\nepic=bad key\n' > "$(gdir "$WORK/f1")/marvin-fleet"; fleet "$WORK/f1"; }
f_fpct()  { fprobe "fleet_restart_max_pct: 100"; }
hd "ML7 symlink guard on the fleet marker removed — F3 must catch it"
mutlib fsym '  [ ! -L "$mk" ] && [ -f "$mk" ] || return 0' '  [ -f "$mk" ] || return 0' f_fsym
hd "ML8 role allow-list opened to any value — F4 must catch it"
mutlib frole '    master) MH_FLEET_ROLE=master; echo master ;;' '    ?*) MH_FLEET_ROLE=$role; echo "$role" ;;' f_frole
f_fnogit() { fleet "$WORK/f5"; }
f_fnomk()  { fleet "$WORK/f2"; }
f_fvar()   { printf 'role=child\nepic=ABC-12\n' > "$(gdir "$WORK/f1")/marvin-fleet"; fleet "$WORK/f1"; }
f_freset() { printf 'role=child\nepic=ABC-12\n' > "$(gdir "$WORK/f1")/marvin-fleet"; fleet "$WORK/f1" "$WORK/f2"; }
hd "ML11 not-a-repo guard returns 1 — F5 rc must catch it"
mutlib fnogit '  gd=$(git -C "$root" rev-parse --git-dir 2>/dev/null) || return 0' '  gd=$(git -C "$root" rev-parse --git-dir 2>/dev/null) || return 1' f_fnogit
hd "ML12 no-marker guard returns 1 — F2 rc must catch it"
mutlib fnomk '  [ ! -L "$mk" ] && [ -f "$mk" ] || return 0' '  [ ! -L "$mk" ] && [ -f "$mk" ] || return 1' f_fnomk
hd "ML13 MH_FLEET_ROLE no longer set for a child — F1 must catch it"
mutlib fvar '      MH_FLEET_ROLE=child; echo child ;;' '      echo child ;;' f_fvar
hd "ML14 globals no longer reset per call — F2b must catch it"
mutlib freset '  MH_FLEET_ROLE=; MH_FLEET_EPIC=' '  :' f_freset
hd "ML9 epic key shape check removed — F1 must catch it"
mutlib fepic "      if printf '%s' \"\$epic\" | grep -Eq '^[A-Za-z][A-Za-z0-9]*-[0-9]+\$'; then MH_FLEET_EPIC=\$epic; fi" '      MH_FLEET_EPIC=$epic' f_fepic
hd "ML10 restart-percentage upper bound removed — S2 must catch it"
mutlib fpct '  if [ -n "$p" ] && [ "$((10#$p))" -ge 1 ] && [ "$((10#$p))" -le 99 ]; then MH_FLEET_RESTART_PCT=$((10#$p)); fi' '  if [ -n "$p" ] && [ "$((10#$p))" -ge 1 ]; then MH_FLEET_RESTART_PCT=$((10#$p)); fi' f_fpct
f_cpat()  { F mh_compactions "$WORK/c2.jsonl"; }
f_cside() { F mh_compactions "$WORK/c3.jsonl"; }
f_ctail() { F mh_compactions "$WORK/c1.jsonl"; }
f_cm()    { local f="$WORK/cm.jsonl"; : > "$f"; amsg "$f" 900; boundary "$f"; amsg "$f" 700; boundary "$f"; amsg "$f" 150; amsg "$f" 160; F mh_since_compact "$f"; }
f_clast() { f_cm; }
f_cfirst() { f_cm; }
f_crc()   { F mh_compactions "$WORK/none.jsonl"; }
hd "ML15 compaction match loses the system type — C2 must catch it"
mutlib cpat "MH_COMPACT_PAT='\"type\":\"system\",\"subtype\":\"compact_boundary\"'" "MH_COMPACT_PAT='\"subtype\":\"compact_boundary\"'" f_cpat
hd "ML16 sidechain compactions counted — C3 must catch it"
mutlib cside "  LC_ALL=C grep -F -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | LC_ALL=C grep -vc '\"isSidechain\":true'" "  LC_ALL=C grep -F -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | LC_ALL=C grep -c ''" f_cside
hd "ML17 compactions read only the 400-line tail — C1 must catch it"
mutlib ctail "  LC_ALL=C grep -F -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | LC_ALL=C grep -vc '\"isSidechain\":true'" "  tail -n 400 -- \"\$1\" | LC_ALL=C grep -F -- \"\$MH_COMPACT_PAT\" 2>/dev/null | LC_ALL=C grep -vc '\"isSidechain\":true'" f_ctail
hd "ML18 since_compact anchors on the FIRST compaction — C4 must catch it"
mutlib clast "  ln=\$(LC_ALL=C grep -nF -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | LC_ALL=C grep -v '\"isSidechain\":true' | tail -n 1 | cut -d: -f1)" "  ln=\$(LC_ALL=C grep -nF -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | LC_ALL=C grep -v '\"isSidechain\":true' | head -n 1 | cut -d: -f1)" f_clast
f_cside2() { local f="$WORK/cs2.jsonl"; : > "$f"; boundary "$f"; amsg "$f" 80; boundary "$f" true; amsg "$f" 90; F mh_since_compact "$f"; }
hd "ML21 since_compact's boundary search counts a sidechain boundary — C4 must catch it"
mutlib csb2 "  ln=\$(LC_ALL=C grep -nF -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | LC_ALL=C grep -v '\"isSidechain\":true' | tail -n 1 | cut -d: -f1)" "  ln=\$(LC_ALL=C grep -nF -- \"\$MH_COMPACT_PAT\" \"\$1\" 2>/dev/null | cat | tail -n 1 | cut -d: -f1)" f_cside2
f_ccap()  { F mh_since_compact "$WORK/c6.jsonl"; }
f_ccapb() { F mh_since_compact "$WORK/c6b.jsonl"; }
hd "ML22 since_compact reads past 400 lines after the boundary — C6 must catch it"
mutlib ccap '  tail -n "+$((ln + 1))" -- "$1" 2>/dev/null | head -n 400 | head -c 8000000 \' '  tail -n "+$((ln + 1))" -- "$1" 2>/dev/null | head -c 8000000 \' f_ccap
hd "ML23 since_compact reads past 8 MB after the boundary — C6 must catch it"
mutlib ccapb '  tail -n "+$((ln + 1))" -- "$1" 2>/dev/null | head -n 400 | head -c 8000000 \' '  tail -n "+$((ln + 1))" -- "$1" 2>/dev/null | head -n 400 \' f_ccapb
hd "ML19 since_compact reports the LAST message's size, not the first's — C4 must catch it"
mutlib cfirst "  | awk \"\$MH_SIZES_AWK\" | awk 'NR == 1 { f = \$0 } END { if (NR) print NR, f }'" "  | awk \"\$MH_SIZES_AWK\" | awk '{ f = \$0 } END { if (NR) print NR, f }'" f_cfirst
hd "ML20 unreadable file no longer rc 1 — C1 rc must catch it"
mutlib crc '  [ -n "${1:-}" ] && [ -f "$1" ] && [ -r "$1" ] || return 1' '  [ -n "${1:-}" ] && [ -f "$1" ] && [ -r "$1" ] || return 0' f_crc

printf '\n----\ntest-hook-lib: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
