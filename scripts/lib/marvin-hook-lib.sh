#!/usr/bin/env bash
# marvin-hook-lib.sh — shared helpers for the marvin plugin's hook scripts (v0.38.0). Sourced, never run.
# Every helper is read-only and bounded, and fails SILENT: on any doubt it returns 1 with nothing usable
# printed, so the calling hook stays quiet instead of acting on a parse failure. bash 3.2 + POSIX awk
# (mawk-safe), no jq, no python. JSON always arrives on stdin, never through the environment (a 1 MiB
# message would overflow ARG_MAX).

MH_MAX_IN=1048576
MH_DEFAULT_WINDOW_K=1000 # model-profile.md: the orchestrator tier's window (1M) — validate-kit profile-window pins it

# mh_read_stdin — at most MH_MAX_IN bytes of hook stdin into MH_IN; rc 1 when empty or a terminal
mh_read_stdin() {
  MH_IN=""
  [ -t 0 ] && return 1
  MH_IN=$(head -c "$MH_MAX_IN" 2>/dev/null)
  [ -n "$MH_IN" ]
}

# The JSON walker: recursive descent over the whole document. mode=get prints the value at a dotted
# path (object keys and array indexes) — a string decoded to UTF-8, a scalar as its literal; rc 1 when
# the path is absent, holds a container, or the document is malformed. mode=members prints
# "key<TAB>value" per scalar member of the object at the path. A wanted string is decoded by streaming
# runs to stdout, never by growing an awk string, so a 1 MiB message costs one linear pass. The document
# is held in 4 KiB chunks: awk builds that call strlen() per substr() would go quadratic on one long string. Nesting
# deeper than 64 is refused.
IFS= read -r -d '' MH_JSON_AWK <<'AWK' || true
function hx(h,   i, v, d) { v = 0; h = tolower(h)
  for (i = 1; i <= 4; i++) { d = index("0123456789abcdef", substr(h, i, 1)); if (!d) return -1; v = v * 16 + d - 1 }
  return v }
function u8(c) {
  if (c <= 0) return ""
  if (c < 128) return sprintf("%c", c)
  if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
  if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
  return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64) }
function ch(p) { return substr(ck[int((p - 1) / CK) + 1], (p - 1) % CK + 1, 1) }
function sb(p, l,   r, t) { r = ""
  while (l > 0) { t = substr(ck[int((p - 1) / CK) + 1], (p - 1) % CK + 1, l); if (t == "") break; r = r t; p += length(t); l -= length(t) }
  return r }
function emit(p, l,   t) {
  while (l > 0) { t = substr(ck[int((p - 1) / CK) + 1], (p - 1) % CK + 1, l); if (t == "") break; printf "%s", t; p += length(t); l -= length(t) } }
function fail() { exit 1 }
function ws() { while (pos <= n && index(" \t\r\n", ch(pos))) pos++ }
function esc(   c, a, b) {
  c = ch(pos + 1); pos += 2
  if (c == "n") return "\n"
  if (c == "t") return "\t"
  if (c == "r") return "\r"
  if (c == "b") return "\b"
  if (c == "f") return "\f"
  if (c != "u") return c
  a = hx(sb(pos, 4)); if (a < 0) fail(); pos += 4
  if (a >= 55296 && a <= 56319 && sb(pos, 2) == "\\u") {
    b = hx(sb(pos + 2, 4))
    if (b >= 56320 && b <= 57343) { pos += 6; a = 65536 + (a - 55296) * 1024 + (b - 56320) }
  }
  return u8(a) }
function skipstr(   c) { pos++
  while (pos <= n) { c = ch(pos)
    if (c == "\\") { pos += 2; continue }
    pos++; if (c == "\"") return }
  fail() }
function emitstr(   c, st) { pos++; st = pos
  while (pos <= n) { c = ch(pos)
    if (c == "\"") { emit(st, pos - st); pos++; return }
    if (c == "\\") { emit(st, pos - st); printf "%s", esc(); st = pos; continue }
    pos++ }
  fail() }
function keystr(   c, k) { pos++; k = ""
  while (pos <= n) { c = ch(pos)
    if (c == "\"") { pos++; return k }
    if (c == "\\") { k = k esc(); continue }
    k = k c; pos++; if (length(k) > 1024) fail() }
  fail() }
function scalar(   st) { st = pos
  while (pos <= n && !index(",}] \t\r\n", ch(pos))) pos++
  if (pos == st) fail()
  return sb(st, pos - st) }
function value(d, m,   c, v) {
  if (d > 64) fail()
  ws(); c = ch(pos)
  if (c == "{") { obj(d, m); return }
  if (c == "[") { arr(d, m); return }
  if (c == "\"") { if (m && d == np && mode == "get") { emitstr(); exit 0 } skipstr(); return }
  v = scalar(); if (m && d == np && mode == "get") { printf "%s", v; exit 0 } }
function member(k,   c) { ws(); c = ch(pos)
  if (c == "{" || c == "[") { value(np + 1, 0); return }
  printf "%s\t", k
  if (c == "\"") emitstr(); else printf "%s", scalar()
  printf "\n" }
function obj(d, m,   k, hit, c) { pos++; ws()
  if (ch(pos) == "}") { pos++; if (m && d == np) exit (mode == "members" ? 0 : 1); return }
  while (1) { ws(); if (ch(pos) != "\"") fail()
    k = keystr(); ws(); if (ch(pos) != ":") fail(); pos++
    hit = m && d < np && seg[d + 1] == k
    if (m && d == np && mode == "members") member(k); else value(d + 1, hit)
    ws(); c = ch(pos); pos++
    if (c == "}") { if (m && d == np) exit (mode == "members" ? 0 : 1); return }
    if (c != ",") fail() } }
function arr(d, m,   i, c) { pos++; ws()
  if (ch(pos) == "]") { pos++; if (m && d == np) exit 1; return }
  i = 0
  while (1) { value(d + 1, m && d < np && seg[d + 1] == i ""); i++
    ws(); c = ch(pos); pos++
    if (c == "]") { if (m && d == np) exit 1; return }
    if (c != ",") fail() } }
BEGIN { CK = 4096 }
{ buf = buf $0 "\n"
  while (length(buf) >= CK) { ck[++nck] = substr(buf, 1, CK); buf = substr(buf, CK + 1) } }
END { if (buf != "") ck[++nck] = buf
  n = nck ? (nck - 1) * CK + length(ck[nck]) : 0; pos = 1; np = split(path, seg, "."); value(0, 1); exit 1 }
AWK

mh_json() { LC_ALL=C awk -v mode="$1" -v path="$2" "$MH_JSON_AWK"; }
mh_get()  { mh_json get "$1"; }

# agent_id marks a sub-agent call; the host emits it before hook_event_name, so only that prefix is
# searched — an agent_id key inside a later tool_input/tool_response must not silence the main thread.
mh_is_subagent_call() {
  local pre=${MH_IN%%\"hook_event_name\"*}
  case "$pre" in
    *\"agent_id\"*) return 0 ;;
  esac
  return 1
}

mh_root() {
  local r="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$r" ] || r=$(printf '%s' "$MH_IN" | mh_get cwd) || r=""
  [ -n "$r" ] || r="$PWD"
  printf '%s' "$r"
}
mh_is_marvin() { [ ! -L "$1/.marvin" ] && [ -d "$1/.marvin" ]; }

mh_frontmatter() {
  local pi="$1/.marvin/PROJECT-INFO.md"
  [ ! -L "$pi" ] && [ -f "$pi" ] || return 1
  head -n 40 -- "$pi" 2>/dev/null | awk '{ sub(/\r$/, "") } NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f'
}
mh_fm_value() {
  printf '%s\n' "$1" | sed -nE "s/^$2:[[:space:]]*//p" | head -n 1 \
    | sed -E 's/(^|[[:space:]]+)#.*$//' \
    | sed -E 's/^[[:space:]"'"'"']+//; s/[[:space:]"'"'"']+$//'
}

# Context size (in thousands) per MESSAGE, last two messages. Only lines whose type is assistant and that
# carry an UNESCAPED "usage":{ are read (usage text quoted inside a tool result is escaped, so never
# counts); the counters are matched only in the text from the LAST "usage":{ on, so a tool_use input
# holding an input_tokens key earlier on the line is ignored. One size per "id":"msg_…" (last line wins);
# a line without a message id is its own message.
mh_sizes() {
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  tail -c 8000000 -- "$1" 2>/dev/null | tail -n 400 \
  | grep '"type":"assistant"' | grep '"usage":{' \
  | awk '{
      key = "L" NR
      if (match($0, /"id":"msg_[^"]*"/)) key = substr($0, RSTART, RLENGTH)
      rest = $0; pos = 0
      while ((i = index(rest, "\"usage\":{")) > 0) { pos += i; rest = substr(rest, i + 1) }
      u = substr($0, pos)
      n = 0
      if (match(u, /"input_tokens":[0-9]+/))                { n += substr(u, RSTART + 15, RLENGTH - 15) }
      if (match(u, /"cache_read_input_tokens":[0-9]+/))     { n += substr(u, RSTART + 26, RLENGTH - 26) }
      if (match(u, /"cache_creation_input_tokens":[0-9]+/)) { n += substr(u, RSTART + 30, RLENGTH - 30) }
      if (!(key in val)) order[++cnt] = key
      val[key] = int(n / 1000)
    }
    END { for (j = 1; j <= cnt; j++) print val[order[j]] }' | tail -n 2
}

# mh_last_text <transcript> — the last main-thread assistant text block, decoded. Up to five candidate
# lines are tried from the end, since a tool_use input may itself hold an unescaped "type":"text".
mh_last_text() {
  [ -n "${1:-}" ] && [ ! -L "$1" ] && [ -f "$1" ] || return 1
  local cands j line i t out
  cands=$(tail -c 8000000 -- "$1" 2>/dev/null | tail -n 400 | grep '"type":"assistant"' \
    | grep -v '"isSidechain":true' | grep '"type":"text"' | tail -n 5)
  [ -n "$cands" ] || return 1
  j=$(printf '%s\n' "$cands" | wc -l | tr -d ' ')
  while [ "$j" -ge 1 ]; do
    line=$(printf '%s\n' "$cands" | sed -n "${j}p"); out=""; i=0
    if [ "$(printf '%s' "$line" | mh_get type)" = assistant ]; then
      while [ "$i" -lt 16 ]; do
        t=$(printf '%s' "$line" | mh_get "message.content.$i.type") || break
        [ "$t" = text ] && { out=$(printf '%s' "$line" | mh_get "message.content.$i.text") || out=""; }
        i=$((i + 1))
      done
    fi
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    j=$((j - 1))
  done
  return 1
}

# mh_first_user_text <transcript> — the first user message (a sub-agent's brief), first 256 KiB only
mh_first_user_text() {
  [ -n "${1:-}" ] && [ ! -L "$1" ] && [ -f "$1" ] || return 1
  local line
  line=$(head -c 262144 -- "$1" 2>/dev/null | grep -m 1 '"type":"user"') || return 1
  printf '%s' "$line" | mh_get message.content && return 0
  printf '%s' "$line" | mh_get message.content.0.text
}

# mh_budget_init <frontmatter> — the absolute budgets (AOS-187) and the context ladder's window and scale.
# Window precedence: context_window_ktokens > CLAUDE_CODE_AUTO_COMPACT_WINDOW (100000–1000000) >
# CLAUDE_CODE_DISABLE_1M_CONTEXT=1 (200k) > MH_DEFAULT_WINDOW_K. CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (1–100)
# scales every ladder step. Hooks inherit both the shell environment and settings env (spec H16).
mh_budget_init() {
  local fm="$1" s h w e
  MH_SOFT=400; MH_HARD=700
  s=$(printf '%s\n' "$fm" | sed -nE 's/^session_soft_ktokens:[[:space:]]*([0-9]{1,5})[[:space:]]*$/\1/p' | head -n 1)
  h=$(printf '%s\n' "$fm" | sed -nE 's/^session_hard_ktokens:[[:space:]]*([0-9]{1,5})[[:space:]]*$/\1/p' | head -n 1)
  s=${s:-400}; h=${h:-700}
  if [ "$((10#$s))" -gt 0 ] && [ "$((10#$s))" -lt "$((10#$h))" ]; then MH_SOFT=$((10#$s)); MH_HARD=$((10#$h)); fi
  MH_WIN=$MH_DEFAULT_WINDOW_K
  w=$(printf '%s\n' "$fm" | sed -nE 's/^context_window_ktokens:[[:space:]]*([0-9]{1,5})[[:space:]]*$/\1/p' | head -n 1)
  e="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
  if [ -n "$w" ] && [ "$((10#$w))" -gt 0 ]; then MH_WIN=$((10#$w))
  elif printf '%s' "$e" | grep -Eq '^[0-9]{6,7}$' && [ "$e" -ge 100000 ] && [ "$e" -le 1000000 ]; then MH_WIN=$((e / 1000))
  elif [ "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}" = 1 ]; then MH_WIN=200
  fi
  MH_SCALE=100
  e="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}"
  if printf '%s' "$e" | grep -Eq '^[0-9]{1,3}$' && [ "$e" -ge 1 ] && [ "$e" -le 100 ]; then MH_SCALE=$e; fi
}
# mh_win_for <k> — the resolved window, stepped up (→ 200k → 1M → k) when usage exceeds it
mh_win_for() {
  local k=$1 w=$MH_WIN
  if [ "$k" -gt "$w" ]; then
    if [ "$k" -le 200 ]; then w=200; elif [ "$k" -le 1000 ]; then w=1000; else w=$k; fi
  fi
  echo "$w"
}
mh_pct() { local w; w=$(mh_win_for "$1"); echo $(( $1 * 100 / w )); }
# mh_level <k> — 0 none · 1 plan (70 % or soft) · 2 wind down (80 % or hard) · 3 stop (90 %); the owner
# of what each level means is .marvin/agents/session-budget.md
mh_level() {
  local k=$1 p l=0
  [ "$k" -gt 0 ] || { echo 0; return; }
  p=$(mh_pct "$k")
  if [ "$p" -ge $((70 * MH_SCALE / 100)) ] || [ "$k" -ge "$MH_SOFT" ]; then l=1; fi
  if [ "$p" -ge $((80 * MH_SCALE / 100)) ] || [ "$k" -ge "$MH_HARD" ]; then l=2; fi
  if [ "$p" -ge $((90 * MH_SCALE / 100)) ]; then l=3; fi
  echo "$l"
}

# mh_q — git core.quotePath-style encoding for anything an agent will parse (the sweep's q())
mh_q() {
  local p="$1" LC_ALL=C LC_COLLATE=C LC_CTYPE=C
  case "$p" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*) ;;
    *) printf '%s' "$p"; return 0;;
  esac
  printf '%s' "$p" | LC_ALL=C od -An -v -tu1 | awk '
    BEGIN{ printf "\"" }
    { for(i=1;i<=NF;i++){ b=$i+0
        if(b==92) printf "\\\\"
        else if(b==34) printf "\\\""
        else if(b==10) printf "\\n"
        else if(b==9)  printf "\\t"
        else if(b==13) printf "\\r"
        else if(b<32 || b>126) printf "\\%03o", b
        else printf "%c", b } }
    END{ printf "\"" }'
}
