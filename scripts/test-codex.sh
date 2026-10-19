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
# count_lines <file> — REAL lines of a captured stdout: "ready\n\n" is 2, "ready" (no newline) is 1, "" is 0
count_lines() { awk 'END { print NR }' "$1"; }
assert_lines() { local n; n=$(count_lines "$WORK/stdout"); if [ "$n" = "$1" ]; then ok "$1 line(s) of stdout"; else bad "$n lines of stdout, want $1: $OUT"; fi; }
assert_prefix() { case "$OUT" in "$1"*) ok "out starts with: $1";; *) bad "out is '$OUT', want prefix '$1'";; esac; }
assert_argv_pair() { if awk -v a="$1" -v b="$2" 'p == a && $0 == b { f = 1 } { p = $0 } END { exit !f }' "$WORK/argv" 2>/dev/null; then ok "companion argv has: $1 $2"; else bad "companion argv lacks '$1 $2' (argv: $(tr '\n' ' ' < "$WORK/argv" 2>/dev/null))"; fi; }
assert_argv_empty() { if [ -s "$WORK/argv" ]; then bad "the companion was called: $(tr '\n' ' ' < "$WORK/argv")"; else ok "the companion was never called"; fi; }
assert_argv_lacks_text() { if grep -Fq -- "$1" "$WORK/argv" 2>/dev/null; then bad "companion argv contains the text '$1'"; else ok "companion argv never contains: $1"; fi; }
assert_argv_has() { if grep -Fxq -- "$1" "$WORK/argv" 2>/dev/null; then ok "companion argv has: $1"; else bad "companion argv lacks '$1' (argv: $(tr '\n' ' ' < "$WORK/argv" 2>/dev/null))"; fi; }
assert_argv_not() { if grep -Fxq -- "$1" "$WORK/argv" 2>/dev/null; then bad "companion argv must not have: $1"; else ok "companion argv free of: $1"; fi; }

# --- tool PATH: symlinks to the basics only, so "no node" is real and the real node is unreachable ---------
TOOLS="$WORK/tools"; BIN="$WORK/bin"; mkdir -p "$TOOLS" "$BIN"
for t in awk sed grep cat head tail tr sort dirname basename ls cut wc mktemp rm git uname expr readlink env sh bash sleep mkdir; do
  p=$(command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -s "$p" "$TOOLS/$t"
done
cat > "$BIN/node" <<'SH'
#!/bin/sh
# fake node: logs argv, answers the companion subcommand ($2) with a fixture — setup: FAKE_SETUP, task:
# FAKE_TASK, status: FAKE_STATUS, result: FAKE_RESULT. Optional siblings: <fx>.err (to stderr), <fx>.rc
# (exit code), <fx>.sleep (hang: exec sleep N, so the watchdog's kill reaches the sleeper itself), <fx>.delay
# (a slow call: sleep N, then answer normally; a TERM also ends the sleeper, so no orphan outlives the kill).
printf '%s\n' "$@" >> "$FAKE_WORK/argv"
case "$2" in
  setup)  fx=${FAKE_SETUP:-ready} ;;
  task)   fx=${FAKE_TASK:-task} ;;
  status) fx=${FAKE_STATUS:-status-completed} ;;
  result) fx=${FAKE_RESULT:-result-ok} ;;
  *)      fx=unknown-subcommand ;;
esac
fx="$FAKE_WORK/fx/$fx"
if [ -f "$fx.stubborn" ]; then trap "" TERM; exec sleep "$(cat "$fx.stubborn")"; fi   # ignores TERM: only KILL ends it
if [ -f "$fx.sleep" ]; then exec sleep "$(cat "$fx.sleep")"; fi
if [ -f "$fx.delay" ]; then
  dp=""; trap '[ -z "$dp" ] || kill "$dp" 2>/dev/null; exit 143' TERM
  sleep "$(cat "$fx.delay")" & dp=$!; wait "$dp"; trap - TERM
fi
cat "$fx"
if [ -f "$fx.err" ]; then cat "$fx.err" >&2; fi
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
mkdir -p "$WORK/fakehome"

plugins_json() {  # plugins_json <file> <codex-entries-json-or-""> [other-plugin-extra]
  { printf '{\n  "version": 2,\n  "plugins": {\n'
    printf '    "other@mkt": [\n      {\n        "scope": "user",\n        "installPath": "%s",\n        "version": "9.9.9"\n      },\n      {\n        "scope": "project",\n        "projectPath": "%s",\n        "installPath": "%s",\n        "version": "9.9.9"\n      }\n    ]' "$WORK/inst/other" "$P" "$WORK/inst/other"
    [ -n "$2" ] && printf ',\n    "codex@openai-codex": %s' "$2"
    printf '\n  }\n}\n'; } > "$1"
}
user_entry()    { printf '{\n        "scope": "user",\n        "installPath": "%s",\n        "version": "1.0.6"\n      }' "$1"; }
project_entry() { printf '{\n        "scope": "project",\n        "projectPath": "%s",\n        "installPath": "%s",\n        "version": "1.0.5"\n      }' "$1" "$2"; }

# sut <cwd> [VAR=val ...] -- <args...> — run the script from <cwd> in a clean env (PATH = fake node + basics).
# Stdout lands in $WORK/stdout (OUT holds it, trailing newlines stripped), stderr in $WORK/stderr, RC the exit.
# Base env: the user-scope plugins file p1.json, an empty cache, poll interval 0.2 s; later VAR=val win (env(1)
# applies them in order), and VAR= (empty) means "unset" to the script's ${VAR:-default} reads.
sut() {
  local cwd="$1"; shift; local envs=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  : > "$WORK/argv"
  ( cd "$cwd" && env -i HOME="$WORK/fakehome" PATH="$BIN:$TOOLS" FAKE_WORK="$WORK" \
      MARVIN_CODEX_PLUGINS_JSON="$WORK/p1.json" MARVIN_CODEX_CACHE="$EMPTY_CACHE" MARVIN_CODEX_POLL=0.2 \
      ${envs[@]+"${envs[@]}"} bash "$SUT" "$@" ) > "$WORK/stdout" 2> "$WORK/stderr"; RC=$?
  OUT=$(cat "$WORK/stdout")
}
# run_check <cwd> <setup-fixture> <plugins-json> <cache-dir> [check args...]
run_check() {
  local cwd="$1" fx="$2" pj="$3" cache="$4"; shift 4
  sut "$cwd" FAKE_SETUP="$fx" MARVIN_CODEX_PLUGINS_JSON="$pj" MARVIN_CODEX_CACHE="$cache" -- check "$@"
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
mkdir -p "$WORK/fakehome/.claude/plugins"; cp "$WORK/p1.json" "$WORK/fakehome/.claude/plugins/installed_plugins.json"
sut "$P" MARVIN_CODEX_PLUGINS_JSON= MARVIN_CODEX_CACHE= -- check
assert_eq ready; assert_rc 0; assert_argv_has "$WORK/inst/user/scripts/codex-companion.mjs"
rm -f "$WORK/fakehome/.claude/plugins/installed_plugins.json"
mkdir -p "$WORK/fakehome/.claude/plugins/cache/openai-codex/codex"; mkcomp "$WORK/fakehome/.claude/plugins/cache/openai-codex/codex/1.2.3"
sut "$P" MARVIN_CODEX_PLUGINS_JSON= MARVIN_CODEX_CACHE= -- check
assert_eq ready; assert_argv_has "$WORK/fakehome/.claude/plugins/cache/openai-codex/codex/1.2.3/scripts/codex-companion.mjs"

hd "check: no-node (node absent from PATH — the companion is never called)"
sut "$P" PATH="$TOOLS" -- check
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
sut "$P" -- check --json; cp "$WORK/stdout" "$WORK/bytes.out"
if cmp -s "$WORK/bytes.out" "$WORK/fx/ready"; then ok "bytes identical"; else bad "bytes differ"; fi

hd "check --json: no companion → status line on stderr only, stdout empty, rc 4"
sut "$P" MARVIN_CODEX_PLUGINS_JSON="$WORK/p2.json" -- check --json; cp "$WORK/stderr" "$WORK/err"
assert_eq ""; assert_rc 4
if grep -Fxq not-installed "$WORK/err"; then ok "stderr says not-installed"; else bad "stderr: $(cat "$WORK/err")"; fi

hd "usage errors exit 2"
sut "$P" -- check --bogus; assert_rc 2
sut "$P" --; assert_rc 2
sut "$P" -- frobnicate; assert_rc 2


# ============================================================================================================
# check hardening (AOS-233 review fold-ins)
hd "check: the real crash shape — stack trace on STDERR, empty stdout, rc 1 → error companion exit 1: <first line>"
: > "$WORK/fx/crash"; echo 1 > "$WORK/fx/crash.rc"
printf 'file:///x/codex-companion.mjs:12\nTypeError: Cannot read properties of undefined\n    at main (file:///x/codex-companion.mjs:1:1)\n' > "$WORK/fx/crash.err"
run_check "$P" crash "$WORK/p1.json" "$EMPTY_CACHE"
assert_rc 4; assert_lines 1; assert_prefix "error companion exit 1: "
if [ "${#OUT}" -le 80 ]; then ok "line is ${#OUT} chars (<= 80)"; else bad "line is ${#OUT} chars: $OUT"; fi
case "$OUT" in *"    at "*) bad "stack text leaked: $OUT";; *) ok "no stack frames";; esac

hd "check: rc 0 with EMPTY stdout → 'error setup output is not JSON (empty output)', no dangling ': '"
: > "$WORK/fx/empty0"
run_check "$P" empty0 "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq "error setup output is not JSON (empty output)"; assert_rc 4; assert_lines 1

hd "check: rc 1 with no output at all → 'error companion exit 1 (no output)'"
: > "$WORK/fx/silent1"; echo 1 > "$WORK/fx/silent1.rc"
run_check "$P" silent1 "$WORK/p1.json" "$EMPTY_CACHE"
assert_eq "error companion exit 1 (no output)"; assert_rc 4

hd "check: a hanging companion is killed by the watchdog → error companion timed out"
: > "$WORK/fx/hang"; echo 97 > "$WORK/fx/hang.sleep"
t0=$SECONDS
sut "$P" FAKE_SETUP=hang MARVIN_CODEX_CALL_TIMEOUT=1 -- check
assert_eq "error companion timed out"; assert_rc 4; assert_lines 1
if [ $((SECONDS - t0)) -le 5 ]; then ok "returned within the watchdog budget"; else bad "took $((SECONDS - t0)) s"; fi

hd "check: project scope matches from a linked worktree (entry's projectPath = the MAIN checkout)"
git -C "$P" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init 2>/dev/null
git -C "$P" worktree add -q --detach "$WORK/wt" 2>/dev/null
if [ -d "$WORK/wt" ]; then
  run_check "$WORK/wt" ready "$WORK/p5.json" "$EMPTY_CACHE"
  assert_eq ready; assert_argv_has "$WORK/inst/proj/scripts/codex-companion.mjs"; assert_argv_not "$WORK/inst/user/scripts/codex-companion.mjs"
  plugins_json "$WORK/pwt.json" "[ $(project_entry "$P" "$WORK/inst/proj"), $(project_entry "$WORK/wt" "$WORK/inst/other") ]"
  run_check "$WORK/wt" ready "$WORK/pwt.json" "$EMPTY_CACHE"
  assert_argv_has "$WORK/inst/other/scripts/codex-companion.mjs"   # an exact worktree entry beats the main-checkout entry
else bad "could not create a linked worktree fixture"; fi

hd "harness: count_lines counts real lines ('ready\\n\\n' is 2, not 1)"
printf 'ready\n\n' > "$WORK/cl"; if [ "$(count_lines "$WORK/cl")" = 2 ]; then ok "2"; else bad "$(count_lines "$WORK/cl")"; fi
printf 'ready' > "$WORK/cl"; if [ "$(count_lines "$WORK/cl")" = 1 ]; then ok "1 (no newline)"; else bad "$(count_lines "$WORK/cl")"; fi

# ============================================================================================================
# run / result — fixtures mirror the live probe (scratchpad codex-probe.md §1): pretty-printed, nested `job`,
# `storedJob.result.rawOutput`; a failed job's summary carries escaped \"status\":400 BEFORE job.status.
J=task-mvb2mu1q-ofobwc
cat > "$WORK/fx/task" <<EOF
{
  "jobId": "$J",
  "status": "queued",
  "title": "Codex Task",
  "summary": "Review the diff",
  "logFile": "/x/state/jobs/$J.log"
}
EOF
gen_status() {  # gen_status <file> <status> <phase> <summary-json-string-body> [<decoy status of an older job>]
  local decoy=""
  [ -n "${5:-}" ] && decoy=$(printf '  "latestFinished": {\n    "id": "task-old-job",\n    "status": "%s"\n  },\n' "$5")
  cat > "$1" <<EOF
{
  "workspaceRoot": "$P",
${decoy}
  "job": {
    "id": "$J",
    "kind": "task",
    "summary": "$4",
    "status": "$2",
    "phase": "$3",
    "write": false,
    "request": {
      "cwd": "$P",
      "model": "m",
      "effort": "high",
      "write": false
    },
    "progressPreview": [],
    "elapsed": "4s"
  }
}
EOF
}
gen_status "$WORK/fx/status-running"   running   running  'decoy: {\"status\":\"completed\"}'   completed
gen_status "$WORK/fx/status-queued"    queued    starting 'Review the diff'    completed
gen_status "$WORK/fx/status-completed" completed done     'Review the diff'
gen_status "$WORK/fx/status-cancelled" cancelled done     'Review the diff'
gen_status "$WORK/fx/status-weird"     exploded  done     'Review the diff'
gen_status "$WORK/fx/status-failed"    failed    failed   '{\"type\":\"error\",\"status\":400,\"error\":{\"type\":\"invalid_request_error\",\"message\":\"The model is not supported when using Codex with a ChatGPT account.\"}}'
printf 'No job found for "%s". Run /codex:status to list known jobs.\n' "$J" > "$WORK/fx/status-nojob"; echo 1 > "$WORK/fx/status-nojob.rc"
: > "$WORK/fx/status-hang"; echo 97 > "$WORK/fx/status-hang.sleep"
gen_result() {  # gen_result <file> <status> <rawOutput-json-string-body> <result.status>
  cat > "$1" <<EOF
{
  "job": {
    "id": "$J",
    "kind": "task",
    "status": "$2",
    "phase": "done"
  },
  "storedJob": {
    "id": "$J",
    "status": "$2",
    "result": {
      "status": $4,
      "threadId": "thr_1",
      "rawOutput": "$3",
      "touchedFiles": [],
      "reasoningSummary": []
    },
    "rendered": "$3\n"
  }
}
EOF
}
gen_result "$WORK/fx/result-ok"     completed 'OK \"quoted\" findings: none' 0
gen_result "$WORK/fx/result-empty"  completed '' 0
gen_result "$WORK/fx/result-blank"  completed '  \n ' 0
gen_result "$WORK/fx/result-failed" failed    '' 1
printf 'Error: something broke\n' > "$WORK/fx/result-garbage"
printf 'Error: spawn failed\n' > "$WORK/fx/task-garbage"; echo 1 > "$WORK/fx/task-garbage.rc"
printf '{\n  "status": "queued",\n  "title": "Codex Task"\n}\n' > "$WORK/fx/task-noid"
printf '{\n  "jobId": "--write",\n  "status": "queued"\n}\n' > "$WORK/fx/task-badid"
: > "$WORK/fx/task-hang"; echo 97 > "$WORK/fx/task-hang.sleep"

mkdir -p "$P/.marvin"
set_handover() {  # set_handover <value> | ABSENT (key missing) | NOFILE (no PROJECT-INFO.md)
  case "$1" in
    NOFILE) rm -f "$P/.marvin/PROJECT-INFO.md" ;;
    ABSENT) printf -- '---\nproject_name: demo\nkit_version: 0.39.0\n---\n\n# Demo\n' > "$P/.marvin/PROJECT-INFO.md" ;;
    *)      printf -- '---\nproject_name: demo\ncodex_handover: %s\nkit_version: 0.39.0\n---\n\n# Demo\ncodex_handover: auto\n' "$1" > "$P/.marvin/PROJECT-INFO.md" ;;
  esac
}
PF="$WORK/prompt.md"
printf -- '--write --model gpt-6-astra\nSECRET-PROMPT-TEXT-42 review this diff\n' > "$PF"
RUN_ENV="FAKE_STATUS=status-completed"

hd "run: profile defaults — review → gpt-5.6-sol high, read-only, payload passed through unchanged"
set_handover auto
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0
if cmp -s "$WORK/stdout" "$WORK/fx/result-ok"; then ok "stdout is the result --json payload, byte for byte"; else bad "stdout differs from the result payload: $OUT"; fi
assert_argv_has task; assert_argv_has --background; assert_argv_has --json
assert_argv_pair --model gpt-5.6-sol; assert_argv_pair --effort high; assert_argv_not --write
assert_argv_pair --prompt-file "$PF"; assert_argv_pair status "$J"; assert_argv_pair result "$J"
if awk -v p="$P" 'prev == "--cwd" && $0 != p { b = 1 } $0 == "--cwd" { n++ } { prev = $0 } END { exit (b || n != 3) }' "$WORK/argv"; then ok "task, status and result all pass --cwd <git toplevel>"; else bad "--cwd not the toplevel on every call: $(tr '\n' ' ' < "$WORK/argv")"; fi

hd "run: review never gets --write, even when the prompt file says --write; the prompt text never reaches argv"
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0; assert_argv_has task; assert_argv_not --write; assert_argv_pair --model gpt-5.6-sol
assert_argv_lacks_text SECRET-PROMPT-TEXT-42; assert_argv_not gpt-6-astra

hd "run: relative prompt path from a subdirectory → absolute --prompt-file, --cwd still the toplevel"
cp "$PF" "$P/sub/p.md"
sut "$P/sub" -- run review --prompt-file p.md
assert_rc 0; assert_argv_pair --prompt-file "$P/sub/p.md"; assert_argv_pair --cwd "$P"

hd "run: build adds --write (gpt-5.6-sol medium)"
sut "$P" -- run build --prompt-file "$PF"
assert_rc 0; assert_argv_has --write; assert_argv_pair --model gpt-5.6-sol; assert_argv_pair --effort medium

hd "run: build-micro → gpt-5.6-luna high, --write"
sut "$P" -- run build-micro --prompt-file "$PF"
assert_rc 0; assert_argv_pair --model gpt-5.6-luna; assert_argv_pair --effort high; assert_argv_has --write

hd "run: the read-only lanes take their profile row and never --write"
for le in plan:high security:high design:medium diagnose:xhigh; do
  sut "$P" -- run "${le%%:*}" --prompt-file "$PF"
  if [ "$RC" = 0 ]; then ok "${le%%:*}: exit 0"; else bad "${le%%:*}: exit $RC ($OUT)"; fi
  assert_argv_pair --model gpt-5.6-sol; assert_argv_pair --effort "${le##*:}"; assert_argv_not --write
done

hd "run: --write-evidence adds --write to the review and security lanes"
sut "$P" -- run review --prompt-file "$PF" --write-evidence
assert_rc 0; assert_argv_has --write
sut "$P" -- run security --prompt-file "$PF" --write-evidence
assert_rc 0; assert_argv_has --write

hd "run: --write-evidence on any other lane is refused — the companion is never called"
for l in plan design diagnose build build-micro astra; do
  sut "$P" -- run "$l" --prompt-file "$PF" --write-evidence --architect
  assert_eq "refused: write-evidence only on review or security"; assert_rc 3; assert_lines 1; assert_argv_empty
done

hd "run: --model / --effort override the profile"
sut "$P" -- run review --prompt-file "$PF" --model gpt-5.6-terra --effort LOW
assert_rc 0; assert_argv_pair --model gpt-5.6-terra; assert_argv_pair --effort low

hd "run: handover off refuses — the companion is never called"
set_handover off
sut "$P" -- run review --prompt-file "$PF"
assert_eq "refused: codex_handover is off"; assert_rc 3; assert_lines 1; assert_argv_empty

hd "run: handover off + --architect runs"
sut "$P" -- run review --prompt-file "$PF" --architect
assert_rc 0; assert_argv_pair --model gpt-5.6-sol

hd "run: handover key missing = off; PROJECT-INFO missing = off; outside git and Marvin = off"
set_handover ABSENT
sut "$P" -- run review --prompt-file "$PF"
assert_eq "refused: codex_handover is off"; assert_rc 3; assert_argv_empty
set_handover NOFILE
sut "$P" -- run review --prompt-file "$PF"
assert_eq "refused: codex_handover is off"; assert_rc 3; assert_argv_empty
sut "$NG" -- run review --prompt-file "$PF"
assert_eq "refused: codex_handover is off"; assert_rc 3; assert_argv_empty

hd "run: handover 'Auto  # note' = auto; 'ASK' = ask (both run); unknown value 'yes' fails closed"
set_handover 'Auto  # note'
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0
set_handover ASK
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0
set_handover '"auto"'
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0
set_handover yes
sut "$P" -- run review --prompt-file "$PF"
assert_eq "refused: codex_handover is off"; assert_rc 3; assert_argv_empty

set_handover auto
hd "run: astra refused without --astra — via --model, via lane astra, via any case of the name"
sut "$P" -- run review --prompt-file "$PF" --model gpt-6-astra
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_lines 1; assert_argv_empty
sut "$P" -- run astra --prompt-file "$PF"
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty
sut "$P" -- run plan --prompt-file "$PF" --model GPT-6-Astra
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty

hd "run: astra with --astra runs — the astra row's model and effort, still read-only"
sut "$P" -- run review --prompt-file "$PF" --astra
assert_rc 0; assert_argv_pair --model gpt-6-astra; assert_argv_pair --effort high; assert_argv_not --write
sut "$P" -- run astra --prompt-file "$PF" --astra --effort xhigh
assert_rc 0; assert_argv_pair --model gpt-6-astra; assert_argv_pair --effort xhigh; assert_argv_not --write

hd "run: --astra with a different --model is a usage error (never silently pick one)"
sut "$P" -- run review --prompt-file "$PF" --astra --model gpt-5.6-sol
assert_rc 2; assert_argv_empty

hd "run: effort max / ultra refused; unknown effort refused; xhigh allowed"
sut "$P" -- run review --prompt-file "$PF" --effort max
assert_eq "refused: effort above xhigh"; assert_rc 3; assert_lines 1; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --effort ultra
assert_eq "refused: effort above xhigh"; assert_rc 3; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --effort turbo
assert_eq "refused: unknown effort"; assert_rc 3; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --effort --write
assert_eq "refused: unknown effort"; assert_rc 3; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --effort xhigh
assert_rc 0; assert_argv_pair --effort xhigh

hd "run: guard order — handover, then astra, then effort, then the prompt file"
set_handover off
sut "$P" -- run review --prompt-file "$WORK/nope.md" --model gpt-6-astra --effort max
assert_eq "refused: codex_handover is off"; assert_rc 3
set_handover auto
sut "$P" -- run review --prompt-file "$WORK/nope.md" --model gpt-6-astra --effort max
assert_eq "refused: astra needs --astra"; assert_rc 3
sut "$P" -- run review --prompt-file "$WORK/nope.md" --effort max
assert_eq "refused: effort above xhigh"; assert_rc 3

hd "run: prompt file missing / unreadable / not given → exit 2, the companion is never called"
sut "$P" -- run review --prompt-file "$WORK/nope.md"
assert_rc 2; assert_argv_empty
sut "$P" -- run review
assert_rc 2; assert_argv_empty
cp "$PF" "$WORK/locked.md"; chmod 000 "$WORK/locked.md"
if [ -r "$WORK/locked.md" ]; then ok "skipped: running as a user who reads mode-000 files"; else
  sut "$P" -- run review --prompt-file "$WORK/locked.md"; assert_rc 2; assert_argv_empty; fi
chmod 600 "$WORK/locked.md"

hd "run: argv injection through option values is a usage error (a model starting with '-', spaces)"
sut "$P" -- run review --prompt-file "$PF" --model --write
assert_rc 2; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --model 'gpt 5'
assert_rc 2; assert_argv_empty

hd "run: usage errors — unknown lane, unknown option, bad --wait-max, missing values"
sut "$P" -- run frobnicate --prompt-file "$PF"; assert_rc 2; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --bogus; assert_rc 2; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --wait-max soon; assert_rc 2; assert_argv_empty
sut "$P" -- run review --prompt-file; assert_rc 2; assert_argv_empty
sut "$P" -- run; assert_rc 2; assert_argv_empty

hd "run: not ready → exit 4 unavailable: not-logged-in, no task submitted"
sut "$P" FAKE_SETUP=logged-out -- run review --prompt-file "$PF"
assert_eq "unavailable: not-logged-in"; assert_rc 4; assert_lines 1; assert_argv_has setup; assert_argv_not task

hd "run: not installed → exit 4 unavailable: not-installed"
sut "$P" MARVIN_CODEX_PLUGINS_JSON="$WORK/p2.json" -- run review --prompt-file "$PF"
assert_eq "unavailable: not-installed"; assert_rc 4; assert_argv_empty

hd "run: still running at --wait-max → exit 5 pending <id> (status read by path, not the decoy in summary)"
sut "$P" FAKE_STATUS=status-running -- run review --prompt-file "$PF" --wait-max 3
assert_eq "pending $J"; assert_rc 5; assert_lines 1; assert_argv_not result

hd "result <id>: the job finished meanwhile → exit 0 with the payload"
sut "$P" -- result "$J"
assert_rc 0
if cmp -s "$WORK/stdout" "$WORK/fx/result-ok"; then ok "stdout is the result payload"; else bad "stdout: $OUT"; fi
assert_argv_pair status "$J"; assert_argv_pair result "$J"; assert_argv_pair --cwd "$P"; assert_argv_not task; assert_argv_not setup

hd "result <id> --wait-max 1 while queued → exit 5 pending <id>"
sut "$P" FAKE_STATUS=status-queued -- result "$J" --wait-max 1
assert_eq "pending $J"; assert_rc 5

hd "result: a bad or missing job id is a usage error (never reaches the companion)"
sut "$P" -- result --write; assert_rc 2; assert_argv_empty
sut "$P" -- result; assert_rc 2; assert_argv_empty
sut "$P" -- result "$J" --wait-max x; assert_rc 2; assert_argv_empty

hd "run: completed with an empty rawOutput → exit 4 unavailable: empty"
sut "$P" FAKE_RESULT=result-empty -- run review --prompt-file "$PF"
assert_eq "unavailable: empty"; assert_rc 4; assert_lines 1
sut "$P" FAKE_RESULT=result-blank -- run review --prompt-file "$PF"
assert_eq "unavailable: empty"; assert_rc 4

hd "run: non-JSON result → exit 4 unavailable: error"
sut "$P" FAKE_RESULT=result-garbage -- run review --prompt-file "$PF"
assert_prefix "unavailable: error"; assert_rc 4; assert_lines 1

hd "run: result payload says failed although status said completed → exit 4 unavailable: error"
sut "$P" FAKE_RESULT=result-failed -- run review --prompt-file "$PF"
assert_prefix "unavailable: error"; assert_rc 4

hd "run: failed job (the probe's model-unsupported shape) → exit 4 unavailable: error, short reason"
sut "$P" FAKE_STATUS=status-failed -- run review --prompt-file "$PF"
assert_prefix "unavailable: error"; assert_rc 4; assert_lines 1; assert_argv_not result
if [ "${#OUT}" -le 93 ]; then ok "line is ${#OUT} chars"; else bad "line is ${#OUT} chars: $OUT"; fi
case "$OUT" in *"not supported"*) ok "reason names the companion's message";; *) bad "reason lacks the message: $OUT";; esac

hd "run: cancelled job, unknown job status, 'No job found' → exit 4 unavailable: error"
sut "$P" FAKE_STATUS=status-cancelled -- run review --prompt-file "$PF"
assert_prefix "unavailable: error"; assert_rc 4
sut "$P" FAKE_STATUS=status-weird -- run review --prompt-file "$PF"
assert_prefix "unavailable: error"; assert_rc 4
sut "$P" FAKE_STATUS=status-nojob -- result "$J"
assert_prefix "unavailable: error"; assert_rc 4; assert_lines 1

hd "run: task submission fails (rc 1 / no jobId / malformed jobId) → exit 4 unavailable: error, no status poll"
for t in task-garbage task-noid task-badid; do
  sut "$P" FAKE_TASK="$t" -- run review --prompt-file "$PF"
  assert_prefix "unavailable: error"; assert_rc 4; assert_argv_not status
done

hd "run: a hanging task call (no job id yet) → exit 4 unavailable: timeout (job may be queued…)"
sut "$P" FAKE_TASK=task-hang MARVIN_CODEX_CALL_TIMEOUT=2 -- run review --prompt-file "$PF"
assert_eq "unavailable: timeout (job may be queued; check status)"; assert_rc 4; assert_lines 1

hd "a status or result call past the per-call timeout with the job id known → exit 5 pending <id>, never unavailable"
sut "$P" FAKE_STATUS=status-hang MARVIN_CODEX_CALL_TIMEOUT=1 -- result "$J"
assert_eq "pending $J"; assert_rc 5; assert_lines 1
if grep -qi terminated "$WORK/stderr"; then bad "job-control noise: $(cat "$WORK/stderr")"; else ok "no Terminated noise"; fi
sut "$P" FAKE_STATUS=status-hang MARVIN_CODEX_CALL_TIMEOUT=1 -- run build --prompt-file "$PF"
assert_eq "pending $J"; assert_rc 5; assert_lines 1
if grep -qx "submitted $J" "$WORK/stderr"; then ok "stderr announced submitted $J"; else bad "stderr lacks submitted $J: $(cat "$WORK/stderr")"; fi
: > "$WORK/fx/result-hang"; echo 97 > "$WORK/fx/result-hang.sleep"
sut "$P" FAKE_RESULT=result-hang MARVIN_CODEX_CALL_TIMEOUT=1 -- run review --prompt-file "$PF"
assert_eq "pending $J"; assert_rc 5; assert_lines 1; assert_argv_pair result "$J"

hd "watchdog: a companion that ignores TERM is KILLed after the grace period"
: > "$WORK/fx/stubborn"; echo 89 > "$WORK/fx/stubborn.stubborn"
t0=$SECONDS
sut "$P" FAKE_SETUP=stubborn MARVIN_CODEX_CALL_TIMEOUT=1 -- check
assert_eq "error companion timed out"; assert_rc 4
if [ $((SECONDS - t0)) -le 6 ]; then ok "returned after TERM + grace + KILL"; else bad "took $((SECONDS - t0)) s"; fi

hd "watchdog: no stray sleepers or companions left behind"
sut "$P" MARVIN_CODEX_CALL_TIMEOUT=473 -- run review --prompt-file "$PF"
assert_rc 0
if command -v ps >/dev/null 2>&1; then
  sleep 0.5
  if ps -A -o args= 2>/dev/null | grep -Eq '(^|/)sleep (473|97|89)$'; then bad "stray sleeper: $(ps -A -o args= | grep -E '(^|/)sleep (473|97|89)$' | tr '\n' ' ')"; else ok "no 'sleep 473' watchdog or '97'/'89' fake companion survives"; fi
else ok "skipped: no ps here"; fi
if grep -v "^submitted task-" "$WORK/stderr" | grep -q .; then bad "stderr noise: $(head -c 200 "$WORK/stderr")"; else ok "no job-control noise on stderr (only the submitted line)"; fi

hd "run: the project's model-profile.md wins over the kit template (only the Codex profile section is read)"
mkdir -p "$P/.marvin/agents"
cat > "$P/.marvin/agents/model-profile.md" <<'EOF'
# Model profile

| Lane | Tier | Model | Effort | Why |
|---|---|---|---|---|
| review | decoy | decoy-before | low | a table above the section must not be read |

## Codex profile

| Lane | Tier | Model | Effort | Why |
|---|---|---|---|---|
| `review` | codex workhorse | `gpt-5.6-terra` | `medium` | project override |
| astra | codex frontier | gpt-6-astra | high | x |

### a sub-heading does not end the section

## Something else

| review | decoy | decoy-after | low | |
EOF
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0; assert_argv_pair --model gpt-5.6-terra; assert_argv_pair --effort medium

hd "run: a lane missing from the project copy falls back to the kit template"
sut "$P" -- run diagnose --prompt-file "$PF"
assert_rc 0; assert_argv_pair --model gpt-5.6-sol; assert_argv_pair --effort xhigh

hd "run: the project copy routes a lane to the astra model → still refused without --astra"
sed 's/`gpt-5.6-terra`/gpt-6-astra/' "$P/.marvin/agents/model-profile.md" > "$WORK/mp" && cp "$WORK/mp" "$P/.marvin/agents/model-profile.md"
sut "$P" -- run review --prompt-file "$PF"
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty
rm -rf "$P/.marvin/agents"


# ============================================================================================================
# fix round 1 — the --wait-max wall-clock budget (Review Focus 4), the job id on submission, the astra guard
cp "$WORK/fx/status-running" "$WORK/fx/status-slow"; echo 37 > "$WORK/fx/status-slow.delay"
cp "$WORK/fx/task" "$WORK/fx/task-slow"; echo 37 > "$WORK/fx/task-slow.delay"
cp "$WORK/fx/result-ok" "$WORK/fx/result-slow"; echo 37 > "$WORK/fx/result-slow.delay"
cp "$WORK/fx/task" "$WORK/fx/task-rc1"; echo 1 > "$WORK/fx/task-rc1.rc"
# Timing: every "slow" fake call takes 37 s, far past each budget (2-3 s; a run's fast path — setup, task,
# one status — needs slack under load, so no run case budgets below 3 s), so the asserted outcome cannot be
# reached by a call finishing on its own, and an uncapped call would take 37 s. Outcome (stdout, exit) is
# asserted first; elapsed second, with a load margin (budget + 3 s) that still sits far below the 37 s.
# Sleep durations here (37, 97, 89, the 473 s watchdog limit, below the 540 s default budget that would otherwise cap it)
# are deliberately odd: the stray-process checks
# scan the whole host, where another session's `sleep 30` loop is common.
within() {  # within <t0> <budget> — the run returned within budget + 3 s ($SECONDS rounding, scheduler load)
  local took=$((SECONDS - $1))
  if [ "$took" -le $(($2 + 3)) ]; then ok "returned in ${took} s (budget $2 s + 3)"; else bad "took ${took} s, budget $2 s + 3"; fi
}

hd "budget: a status call slower than --wait-max is capped by the budget → exit 5 pending <id> in time"
t0=$SECONDS
sut "$P" FAKE_STATUS=status-slow -- run review --prompt-file "$PF" --wait-max 3
assert_eq "pending $J"; assert_rc 5; assert_lines 1; within "$t0" 3

hd "budget: the 60 s per-call timeout never outlasts the budget (a 37 s task, --wait-max 3)"
t0=$SECONDS
sut "$P" FAKE_TASK=task-slow -- run review --prompt-file "$PF" --wait-max 3
assert_eq "unavailable: timeout (job may be queued; check status)"; assert_rc 4; within "$t0" 3

hd "budget: completed, but the result fetch would cross the budget → exit 5 pending <id> (resume with result)"
t0=$SECONDS
sut "$P" FAKE_RESULT=result-slow -- run review --prompt-file "$PF" --wait-max 3
assert_eq "pending $J"; assert_rc 5; within "$t0" 3
sut "$P" -- result "$J"
assert_rc 0

hd "budget: a poll interval longer than the budget left → pending at once, no sleep past the budget"
t0=$SECONDS
sut "$P" FAKE_STATUS=status-running MARVIN_CODEX_POLL=30 -- run review --prompt-file "$PF" --wait-max 3
assert_eq "pending $J"; assert_rc 5; within "$t0" 3

hd "budget: result <id> obeys the same budget"
t0=$SECONDS
sut "$P" FAKE_STATUS=status-slow -- result "$J" --wait-max 2
assert_eq "pending $J"; assert_rc 5; within "$t0" 2

hd "budget: the capped slow calls leave no 37 s sleeper behind"
if command -v ps >/dev/null 2>&1; then
  sleep 0.5
  if ps -A -o args= 2>/dev/null | grep -Eq '(^|/)sleep 37$'; then bad "stray sleeper: $(ps -A -o args= | grep -E '(^|/)sleep 37$' | tr '\n' ' ')"; else ok "no 'sleep 37' survives a capped call"; fi
else ok "skipped: no ps here"; fi

hd "budget: --wait-max 0 or absurdly large is a usage error"
sut "$P" -- run review --prompt-file "$PF" --wait-max 0; assert_rc 2; assert_argv_empty
sut "$P" -- result "$J" --wait-max 0; assert_rc 2; assert_argv_empty
sut "$P" -- result "$J" --wait-max 99999999999999999999; assert_rc 2; assert_argv_empty

hd "job id: announced on stderr as soon as it is known (stdout keeps its contract)"
sut "$P" -- run review --prompt-file "$PF"
assert_rc 0
if grep -Fxq "submitted $J" "$WORK/stderr"; then ok "stderr has: submitted $J"; else bad "stderr: $(cat "$WORK/stderr")"; fi
if cmp -s "$WORK/stdout" "$WORK/fx/result-ok"; then ok "stdout is still only the payload"; else bad "stdout changed: $OUT"; fi

hd "job id: task rc != 0 but its output carries a job id → the job exists, it is polled to the end"
sut "$P" FAKE_TASK=task-rc1 -- run review --prompt-file "$PF"
assert_rc 0; assert_argv_pair status "$J"
if grep -Fxq "submitted $J" "$WORK/stderr"; then ok "stderr has: submitted $J"; else bad "stderr: $(cat "$WORK/stderr")"; fi

hd "astra: a project copy that renames its astra row does not launder the template's astra model"
mkdir -p "$P/.marvin/agents"
cat > "$P/.marvin/agents/model-profile.md" <<'EOF'
## Codex profile

| Lane | Tier | Model | Effort | Why |
|---|---|---|---|---|
| review | codex workhorse | gpt-5.6-sol | high | x |
| astra | codex frontier | gpt-7-zenith | high | renamed in the project copy |
EOF
sut "$P" -- run review --prompt-file "$PF" --model gpt-6-astra
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty
sut "$P" -- run review --prompt-file "$PF" --model gpt-7-zenith
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty
rm -rf "$P/.marvin/agents"

hd "astra: any model naming astra is refused without --astra (dated alias, odd case)"
sut "$P" -- run review --prompt-file "$PF" --model gpt-6-astra-2026-10
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty
sut "$P" -- run plan --prompt-file "$PF" --model my-ASTRA-preview
assert_eq "refused: astra needs --astra"; assert_rc 3; assert_argv_empty

hd "mc_is_astra: the TEMPLATE's astra row counts even when it does not say astra and the project copy renames it"
mkdir -p "$WORK/kit/scripts" "$WORK/kit/templates/marvin/agents" "$P/.marvin/agents"
printf '## Codex profile\n\n| Lane | Tier | Model | Effort | Why |\n|---|---|---|---|---|\n| astra | codex frontier | gpt-9-zenith | high | x |\n' > "$WORK/kit/templates/marvin/agents/model-profile.md"
printf '## Codex profile\n\n| Lane | Tier | Model | Effort | Why |\n|---|---|---|---|---|\n| astra | codex frontier | gpt-9-nadir | high | x |\n' > "$P/.marvin/agents/model-profile.md"
ia() { ( cd "$P" && env -i HOME="$WORK/fakehome" PATH="$TOOLS" bash -c '. "$1"; MC_HERE="$2"; mc_is_astra "$3" "$4"' _ "$SUT" "$WORK/kit/scripts" "$1" "$P" ); }
if ia gpt-9-zenith; then ok "template astra row (gpt-9-zenith) is astra"; else bad "template astra row not recognised"; fi
if ia GPT-9-NADIR; then ok "project astra row (gpt-9-nadir) is astra"; else bad "project astra row not recognised"; fi
if ia gpt-5.6-sol; then bad "gpt-5.6-sol taken for astra"; else ok "gpt-5.6-sol is not astra"; fi
rm -rf "$P/.marvin/agents"

hd "mc_profile: sourced, reads lane model/effort from the template; unknown lane → rc 1; bad field → rc 2"
mp() { ( cd "$P" && env -i HOME="$WORK/fakehome" PATH="$TOOLS" bash -c '. "$1"; shift; mc_profile "$@"' _ "$SUT" "$@" ); }
OUT=$(mp review model); RC=$?; assert_eq gpt-5.6-sol; assert_rc 0
OUT=$(mp build-micro effort); RC=$?; assert_eq high; assert_rc 0
OUT=$(mp astra model); RC=$?; assert_eq gpt-6-astra
OUT=$(mp nosuchlane model); RC=$?; assert_eq ""; assert_rc 1
OUT=$(mp review tier 2>/dev/null); RC=$?; assert_rc 2

hd "the script is executable and parses under bash -n"
if [ -x "$SUT" ]; then ok "executable"; else bad "not executable"; fi
if bash -n "$SUT" 2>/dev/null; then ok "bash -n clean"; else bad "bash -n fails"; fi

printf '\n----\ntest-codex: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
