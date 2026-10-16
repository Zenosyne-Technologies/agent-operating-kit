#!/usr/bin/env bash
# test-codex.sh — behavioural tests for scripts/marvin-codex.sh (codex handover, AOS-233).
# Pins `check`: the companion locator (project scope for the cwd's git toplevel, then user scope, then the
# newest cache version by SEMANTIC compare; entries of other plugins ignored; stale installPath falls through),
# the setup-JSON → status-line map by JSON PATH (node.available / codex.available / auth.loggedIn / ready — not
# the first `available` in the text), the failure shapes (no node, rc != 0, garbage stdout, not ready), the
# one-line stdout contract, the exit codes (0 ready, 4 otherwise, 2 usage) and the --json passthrough.
# The real node, the real companion and the real ~/.claude are never touched: a fake `node` on a PATH of
# symlinked basics, env seams for the plugins file and the cache. bash 3.2 + POSIX awk.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUT="$SCRIPT_DIR/marvin-codex.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-codextest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc()  { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1"; fi; }
assert_eq()  { if [ "$OUT" = "$1" ]; then ok "out is: $1"; else bad "out is '$OUT', want '$1'"; fi; }
assert_lines() { local n; n=$(printf '%s\n' "$OUT" | wc -l | tr -d ' '); if [ "$n" = "$1" ]; then ok "$1 line(s) of stdout"; else bad "$n lines of stdout, want $1: $OUT"; fi; }
assert_argv_has() { if grep -Fxq -- "$1" "$WORK/argv" 2>/dev/null; then ok "companion argv has: $1"; else bad "companion argv lacks '$1' (argv: $(tr '\n' ' ' < "$WORK/argv" 2>/dev/null))"; fi; }
assert_argv_not() { if grep -Fxq -- "$1" "$WORK/argv" 2>/dev/null; then bad "companion argv must not have: $1"; else ok "companion argv free of: $1"; fi; }

# --- tool PATH: symlinks to the basics only, so "no node" is real and the real node is unreachable ---------
TOOLS="$WORK/tools"; BIN="$WORK/bin"; mkdir -p "$TOOLS" "$BIN"
for t in awk sed grep cat head tail tr sort dirname basename ls cut wc mktemp rm git uname expr readlink env sh bash; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -s "$p" "$TOOLS/$t"
done
cat > "$BIN/node" <<'SH'
#!/bin/sh
# fake node: logs argv, answers with the fixture named by FAKE_SETUP (and its optional .rc)
printf '%s\n' "$@" >> "$FAKE_WORK/argv"
fx="$FAKE_WORK/fx/$FAKE_SETUP"
cat "$fx"
if [ -f "$fx.rc" ]; then exit "$(cat "$fx.rc")"; fi
exit 0
SH
chmod +x "$BIN/node"

# --- setup-JSON fixtures: the live probe's pretty-printed multi-line shape, `available` under several objects
mkdir -p "$WORK/fx"
gen_setup() {  # gen_setup <file> <node_av> <npm_av> <codex_av> <logged_in> <ready>
  cat > "$1" <<EOF
{
  "ready": $6,
  "node": {
    "available": $2,
    "detail": "v22.5.0"
  },
  "npm": {
    "available": $3,
    "detail": "10.8.2"
  },
  "codex": {
    "available": $4,
    "detail": "codex-cli 0.147.0; advanced runtime available"
  },
  "auth": {
    "available": true,
    "loggedIn": $5,
    "detail": "ChatGPT login active",
    "source": "app-server",
    "authMethod": "chatgpt",
    "verified": true,
    "requiresOpenaiAuth": true,
    "provider": "openai"
  },
  "sessionRuntime": {
    "mode": "direct",
    "label": "direct startup",
    "detail": "no shared runtime",
    "available": false
  },
  "reviewGateEnabled": false,
  "actionsTaken": [],
  "nextSteps": [
    "Run !codex login if needed."
  ]
}
EOF
}
gen_setup "$WORK/fx/ready"          true  true  true  true  true
gen_setup "$WORK/fx/npm-off"        true  false true  true  true     # npm.available false must not matter
gen_setup "$WORK/fx/node-off"       false true  true  true  false
gen_setup "$WORK/fx/codex-off"      true  true  false true  false
gen_setup "$WORK/fx/logged-out"     true  true  true  false false
gen_setup "$WORK/fx/not-ready"      true  true  true  true  false
printf 'TypeError: Cannot read properties of undefined\n    at main (file:///x/codex-companion.mjs:1:1)\n    at async file:///x/codex-companion.mjs:9:3\n' > "$WORK/fx/garbage"
echo 1 > "$WORK/fx/garbage.rc"
printf 'plain words, no json here\n' > "$WORK/fx/prose0"
cp "$WORK/fx/ready" "$WORK/fx/ready-rc2"; echo 2 > "$WORK/fx/ready-rc2.rc"   # rc != 0 beats a parseable body
printf '{"ready": true, "node": {"available": true' > "$WORK/fx/truncated"

# --- filesystem fixtures -----------------------------------------------------------------------------------
mkcomp() { mkdir -p "$1/scripts"; : > "$1/scripts/codex-companion.mjs"; }
for v in 1.0.4 1.0.5 1.0.6 1.0.9 1.0.10; do mkcomp "$WORK/cachefull/$v"; done
mkcomp "$WORK/inst/user"; mkcomp "$WORK/inst/proj"; mkcomp "$WORK/inst/other"
P="$WORK/repo"; mkdir -p "$P/sub"; git -C "$P" init -q 2>/dev/null
ln -s "$P" "$WORK/repo-link"
NG="$WORK/notgit"; mkdir -p "$NG"
mkdir -p "$WORK/home"

plugins_json() {  # plugins_json <file> <codex-entries-json-or-""> [other-plugin-extra]
  { printf '{\n  "version": 2,\n  "plugins": {\n'
    printf '    "other@mkt": [\n      {\n        "scope": "user",\n        "installPath": "%s",\n        "version": "9.9.9"\n      },\n      {\n        "scope": "project",\n        "projectPath": "%s",\n        "installPath": "%s",\n        "version": "9.9.9"\n      }\n    ]' "$WORK/inst/other" "$P" "$WORK/inst/other"
    [ -n "$2" ] && printf ',\n    "codex@openai-codex": %s' "$2"
    printf '\n  }\n}\n'; } > "$1"
}
user_entry()    { printf '{\n        "scope": "user",\n        "installPath": "%s",\n        "version": "1.0.6"\n      }' "$1"; }
project_entry() { printf '{\n        "scope": "project",\n        "projectPath": "%s",\n        "installPath": "%s",\n        "version": "1.0.5"\n      }' "$1" "$2"; }

# run_check <cwd> <setup-fixture> <plugins-json> <cache-dir> [check args...]  — PATH = fake node + basics
run_check() {
  local cwd="$1" fx="$2" pj="$3" cache="$4"; shift 4
  : > "$WORK/argv"
  OUT=$(cd "$cwd" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" FAKE_WORK="$WORK" FAKE_SETUP="$fx" \
        MARVIN_CODEX_PLUGINS_JSON="$pj" MARVIN_CODEX_CACHE="$cache" bash "$SUT" check "$@" 2>/dev/null); RC=$?
}
EMPTY_CACHE="$WORK/emptycache"; mkdir -p "$EMPTY_CACHE"

if [ ! -f "$SUT" ]; then bad "scripts/marvin-codex.sh is missing"; printf '\n----\ntest-codex: %d passed, %d failed\n' "$PASSED" "$FAILED"; exit 1; fi

# ============================================================================================================
hd "check: ready (user scope entry)"
plugins_json "$WORK/p1.json" "[ $(user_entry "$WORK/inst/user") ]"
run_check "$P" ready "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq ready; assert_rc 0; assert_lines 1
assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"; assert_argv_has setup; assert_argv_has --json

hd "check: not-installed (no codex@ key; another plugin's entries must not be borrowed)"
plugins_json "$WORK/p2.json" ""
run_check "$P" ready "$WORK/p2.json" "$EMPTY_CACHE"
assert_eq not-installed; assert_rc 4; assert_lines 1; assert_argv_not "$WORK/inst/other/scripts/codex-companion.mjs"

hd "check: not-installed (plugins file absent, cache empty)"
run_check "$P" ready "$WORK/nope.json" "$EMPTY_CACHE"
assert_eq not-installed; assert_rc 4

hd "check: not-installed (plugins file is garbage)"
printf 'not json at all' > "$WORK/p-garbage.json"
run_check "$P" ready "$WORK/p-garbage.json" "$EMPTY_CACHE"
assert_eq not-installed; assert_rc 4

hd "check: stale installPath falls back to the newest cache version"
plugins_json "$WORK/p3.json" "[ $(user_entry "$WORK/gone/1.0.6") ]"
mkdir -p "$WORK/cache3"; mkcomp "$WORK/cache3/1.0.4"; mkcomp "$WORK/cache3/1.0.6"
run_check "$P" ready "$WORK/p3.json" "$WORK/cache3"
assert_eq ready; assert_rc 0; assert_argv_has "$WORK/cache3/1.0.6/scripts/codex-companion.mjs"; assert_argv_not "$WORK/cache3/1.0.4/scripts/codex-companion.mjs"

hd "check: cache fallback compares versions semantically (1.0.10 > 1.0.9, not lexically)"
run_check "$P" ready "$WORK/nope.json" "$WORK/cachefull"
assert_eq ready; assert_argv_has "$WORK/cachefull/1.0.10/scripts/codex-companion.mjs"

hd "check: cache entry without a companion file is skipped; non-version folders ignored"
mkdir -p "$WORK/cache4/9.9.9" "$WORK/cache4/latest/scripts"; : > "$WORK/cache4/latest/scripts/codex-companion.mjs"; mkcomp "$WORK/cache4/1.0.2"
run_check "$P" ready "$WORK/nope.json" "$WORK/cache4"
assert_eq ready; assert_argv_has "$WORK/cache4/1.0.2/scripts/codex-companion.mjs"

hd "check: project scope for this repo wins over user scope"
plugins_json "$WORK/p5.json" "[ $(user_entry "$WORK/inst/user"), $(project_entry "$P" "$WORK/inst/proj") ]"
run_check "$P" ready "$WORK/p5.json" "$EMPTY_CACHE"
assert_eq ready; assert_argv_has "$WORK/inst/proj/scripts/codex-companion.mjs"; assert_argv_not "$WORK/inst/user/scripts/codex-companion.mjs"

hd "check: project scope matches from a subdirectory (git toplevel)"
run_check "$P/sub" ready "$WORK/p5.json" "$EMPTY_CACHE"
assert_argv_has "$WORK/inst/proj/scripts/codex-companion.mjs"

hd "check: project scope matches through a symlinked projectPath (physical paths compared)"
plugins_json "$WORK/p5l.json" "[ $(user_entry "$WORK/inst/user"), $(project_entry "$WORK/repo-link" "$WORK/inst/proj") ]"
run_check "$P" ready "$WORK/p5l.json" "$EMPTY_CACHE"
assert_argv_has "$WORK/inst/proj/scripts/codex-companion.mjs"
run_check "$WORK/repo-link" ready "$WORK/p5.json" "$EMPTY_CACHE"
assert_argv_has "$WORK/inst/proj/scripts/codex-companion.mjs"

hd "check: project entry for ANOTHER repo is not used (user scope is)"
plugins_json "$WORK/p6.json" "[ $(project_entry "$WORK/elsewhere" "$WORK/inst/proj"), $(user_entry "$WORK/inst/user") ]"
run_check "$P" ready "$WORK/p6.json" "$EMPTY_CACHE"
assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"; assert_argv_not "$WORK/inst/proj/scripts/codex-companion.mjs"

hd "check: project entry whose companion is missing falls through to user scope"
plugins_json "$WORK/p7.json" "[ $(project_entry "$P" "$WORK/gone/proj"), $(user_entry "$WORK/inst/user") ]"
run_check "$P" ready "$WORK/p7.json" "$EMPTY_CACHE"
assert_eq ready; assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"

hd "check: outside a git repo the project entry is not matched"
run_check "$NG" ready "$WORK/p5.json" "$EMPTY_CACHE"
assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"

hd "check: a minified plugins file reads the same"
printf '{"version":2,"plugins":{"x@y":[{"scope":"user","installPath":"%s"}],"codex@openai-codex":[{"scope":"user","installPath":"%s"}]}}' "$WORK/inst/other" "$WORK/inst/user" > "$WORK/p8.json"
run_check "$P" ready "$WORK/p8.json" "$EMPTY_CACHE"
assert_eq ready; assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"

hd "check: default seams read \$HOME/.claude/plugins/... (no env seam set)"
mkdir -p "$WORK/home/.claude/plugins"; cp "$WORK/p1.json" "$WORK/home/.claude/plugins/installed_plugins.json"
: > "$WORK/argv"
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" FAKE_WORK="$WORK" FAKE_SETUP=ready bash "$SUT" check 2>/dev/null); RC=$?
assert_eq ready; assert_rc 0; assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"
rm -f "$WORK/home/.claude/plugins/installed_plugins.json"
mkdir -p "$WORK/home/.claude/plugins/cache/openai-codex/codex"; mkcomp "$WORK/home/.claude/plugins/cache/openai-codex/codex/1.2.3"
: > "$WORK/argv"
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" FAKE_WORK="$WORK" FAKE_SETUP=ready bash "$SUT" check 2>/dev/null); RC=$?
assert_eq ready; assert_argv_has "$WORK/home/.claude/plugins/cache/openai-codex/codex/1.2.3/scripts/codex-companion.mjs"

hd "check: no-node (node absent from PATH — the companion is never called)"
: > "$WORK/argv"
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$TOOLS" FAKE_WORK="$WORK" FAKE_SETUP=ready MARVIN_CODEX_PLUGINS_JSON="$WORK/p1.json" MARVIN_CODEX_CACHE="$EMPTY_CACHE" bash "$SUT" check 2>/dev/null); RC=$?
assert_eq no-node; assert_rc 4; assert_lines 1

hd "check: no-node when setup reports node.available false"
run_check "$P" node-off "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq no-node; assert_rc 4

hd "check: no-codex-cli (codex.available false)"
run_check "$P" codex-off "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq no-codex-cli; assert_rc 4; assert_lines 1

hd "check: not-logged-in (auth.loggedIn false)"
run_check "$P" logged-out "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq not-logged-in; assert_rc 4; assert_lines 1

hd "check: fields are read by path — npm.available false (and sessionRuntime.available false) do not matter"
run_check "$P" npm-off "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq ready; assert_rc 0

hd "check: parseable but not ready, no named cause → error <reason>"
run_check "$P" not-ready "$WORK/p1.json" "$EMPTY_CACHE"
case "$OUT" in error\ *) ok "starts with 'error '";; *) bad "out is '$OUT'";; esac
assert_rc 4; assert_lines 1

hd "check: garbage stdout with rc 1 (stack trace) → one short error line, no stack text"
run_check "$P" garbage "$WORK/p1.json" "$EMPTY_CACHE"
case "$OUT" in error\ *) ok "starts with 'error '";; *) bad "out is '$OUT'";; esac
assert_rc 4; assert_lines 1
if [ "${#OUT}" -le 80 ]; then ok "line is ${#OUT} chars (<= 80)"; else bad "line is ${#OUT} chars: $OUT"; fi
case "$OUT" in *"    at "*|*codex-companion.mjs:*) bad "stack text leaked: $OUT";; *) ok "no stack text";; esac

hd "check: rc 0 with non-JSON stdout → error"
run_check "$P" prose0 "$WORK/p1.json" "$EMPTY_CACHE"
case "$OUT" in error\ *) ok "starts with 'error '";; *) bad "out is '$OUT'";; esac
assert_rc 4; assert_lines 1

hd "check: truncated JSON → error"
run_check "$P" truncated "$WORK/p1.json" "$EMPTY_CACHE"
case "$OUT" in error\ *) ok "starts with 'error '";; *) bad "out is '$OUT'";; esac
assert_rc 4

hd "check: rc != 0 is an error even when stdout parses"
run_check "$P" ready-rc2 "$WORK/p1.json" "$EMPTY_CACHE"
case "$OUT" in error\ *) ok "starts with 'error '";; *) bad "out is '$OUT'";; esac
assert_rc 4

hd "check: very long first line of garbage is cut to the 80-char budget"
{ printf 'E'; i=0; while [ "$i" -lt 400 ]; do printf 'xxxxxxxxxx'; i=$((i+10)); done; printf '\n'; } > "$WORK/fx/longline"; echo 1 > "$WORK/fx/longline.rc"
run_check "$P" longline "$WORK/p1.json" "$EMPTY_CACHE"
if [ "${#OUT}" -le 80 ]; then ok "line is ${#OUT} chars (<= 80)"; else bad "line is ${#OUT} chars"; fi
case "$OUT" in error\ *) ok "starts with 'error '";; *) bad "out is '$OUT'";; esac

hd "check --json: setup JSON passes through unchanged, exit code kept (ready)"
run_check "$P" ready "$WORK/p1.json" "$EMPTY_CACHE" --json
printf '%s' "$OUT" > "$WORK/got"; if [ "$OUT" = "$(cat "$WORK/fx/ready")" ]; then ok "stdout equals the fixture"; else bad "stdout differs from the fixture"; fi
assert_rc 0

hd "check --json: passthrough with exit 4 when not ready (not-logged-in)"
run_check "$P" logged-out "$WORK/p1.json" "$EMPTY_CACHE" --json
if [ "$OUT" = "$(cat "$WORK/fx/logged-out")" ]; then ok "stdout equals the fixture"; else bad "stdout differs from the fixture"; fi
assert_rc 4

hd "check --json: byte-exact (trailing newline kept)"
: > "$WORK/argv"
( cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" FAKE_WORK="$WORK" FAKE_SETUP=ready MARVIN_CODEX_PLUGINS_JSON="$WORK/p1.json" MARVIN_CODEX_CACHE="$EMPTY_CACHE" bash "$SUT" check --json > "$WORK/bytes.out" 2>/dev/null )
if cmp -s "$WORK/bytes.out" "$WORK/fx/ready"; then ok "bytes identical"; else bad "bytes differ"; fi

hd "check --json: no companion → status line on stderr only, stdout empty, rc 4"
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" FAKE_WORK="$WORK" FAKE_SETUP=ready MARVIN_CODEX_PLUGINS_JSON="$WORK/p2.json" MARVIN_CODEX_CACHE="$EMPTY_CACHE" bash "$SUT" check --json 2>"$WORK/err"); RC=$?
assert_eq ""; assert_rc 4
if grep -Fxq not-installed "$WORK/err"; then ok "stderr says not-installed"; else bad "stderr: $(cat "$WORK/err")"; fi

hd "usage errors exit 2"
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" bash "$SUT" check --bogus 2>/dev/null); RC=$?; assert_rc 2
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" bash "$SUT" 2>/dev/null); RC=$?; assert_rc 2
OUT=$(cd "$P" && env -i HOME="$WORK/home" PATH="$BIN:$TOOLS" bash "$SUT" frobnicate 2>/dev/null); RC=$?; assert_rc 2

hd "the script is executable and parses under bash -n"
if [ -x "$SUT" ]; then ok "executable"; else bad "not executable"; fi
if bash -n "$SUT" 2>/dev/null; then ok "bash -n clean"; else bad "bash -n fails"; fi

printf '\n----\ntest-codex: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
