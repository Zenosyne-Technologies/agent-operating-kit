#!/usr/bin/env bash
# test-worktree-mark.sh — behavioural tests for scripts/marvin-worktree-mark.sh (AOS-223).
# Real repos in a temp dir. Hook mode (--subagent-stop): only the stopping agent's own isolation
# worktree <main>/.claude/worktrees/agent-<agent_id> is marked (K1–K8, K10, K11); by hand (K9) the
# orchestrator marks a worktree it made, refusing its own, the main checkout and anything else.
# The mutation section reverts one guard at a time in a copy; the guard's fixture must then fail.
# Run from anywhere: bash scripts/test-worktree-mark.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MARK="$SCRIPT_DIR/marvin-worktree-mark.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-wmtest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc()     { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1 (got: $(printf '%s' "$OUT" | head -c 200))"; fi; }
assert_out()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1 (got: $(printf '%s' "$OUT" | head -c 200))"; fi; }
assert_empty()  { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 200)"; fi; }

R="$WORK/repo"; WT="$WORK/repo/.claude/worktrees"
ID=a7bf0dd563169ef8d
MARKER_RE='^marvin-owned marvin:developer a7bf0dd563169ef8d [0-9]{8}T[0-9]{6}Z$'
HAND_RE='^marvin-owned orchestrator - [0-9]{8}T[0-9]{6}Z$'

fresh() {  # a Marvin repo at $R (set R before to use another spelling) with .claude/worktrees
  WT="$R/.claude/worktrees"
  rm -rf "$R" "$WORK/outside" "$WORK/lnk" "$WORK/plain" "$WORK/target"
  git init -q "$R"
  echo base > "$R/base.txt"
  git -C "$R" add base.txt && git -C "$R" commit -q -m base
  mkdir -p "$R/.marvin" "$WT"
}
mkwt() { git -C "$R" worktree add -q -b "$1" "$WT/$1" main; }          # mkwt <name>
gdir() { git -C "$1" rev-parse --absolute-git-dir; }
mfile() { printf '%s/marvin-owned' "$(gdir "$1")"; }
state() { if [ -e "$(mfile "$1")" ] || [ -L "$(mfile "$1")" ]; then echo marked; else echo unmarked; fi; }
payload() {  # payload <cwd> <agent_id> <agent_type> <stop_hook_active>
  printf '{"session_id":"s","cwd":"%s","agent_id":"%s","agent_type":"%s","hook_event_name":"SubagentStop","stop_hook_active":%s,"agent_transcript_path":"/x","last_assistant_message":"done"}' "$1" "$2" "$3" "$4"
}
fire() {  # fire <script> <stdin text> — as the host runs it: stdin = payload, CLAUDE_PROJECT_DIR = the project
  OUT=$(cd "$WORK" && CLAUDE_PROJECT_DIR="$R" bash "$1" --subagent-stop <<<"$2" 2>&1); RC=$?
}
hook() { fire "$1" "$(payload "$2" "${3:-$ID}" "${4:-marvin:developer}" "${5:-false}")"; }  # hook <script> <cwd> [id] [type] [active]
silent_ok() { assert_rc 0; assert_empty; }
marker_ok() { # marker_ok <wt> <regex> — one line matching the regex
  local f; f=$(mfile "$1")
  if [ -f "$f" ] && [ ! -L "$f" ] && [ "$(wc -l < "$f" | tr -d ' ')" = 1 ] && grep -Eq "$2" "$f"; then ok "marker is one valid line"; else bad "marker missing or malformed: $(cat "$f" 2>/dev/null | head -c 200)"; fi
}
want_state() { if [ "$(state "$1")" = "$2" ]; then ok "${1#"$WORK"/} $2"; else bad "${1#"$WORK"/} is $(state "$1"), want $2"; fi; }

# ── fixtures reused by the mutation section: each takes the script, leaves OUT = marked | unmarked ──
fx_K1() { fresh; mkwt "agent-$ID"; hook "$1" "$WT/agent-$ID"; OUT=$(state "$WT/agent-$ID"); }
fx_K3() { fresh; mkwt my-session; hook "$1" "$WT/my-session"; OUT=$(state "$WT/my-session"); }
fx_K4() { fresh; mkwt "agent-$ID"; hook "$1" "$WT/agent-$ID" b7bf0dd563169ef8d; OUT=$(state "$WT/agent-$ID"); }
fx_K7() { fresh; mkwt "agent-$ID"; hook "$1" "$WT/agent-$ID"; printf 'marvin-owned marvin:developer %s 20200101T000000Z\n' "$ID" > "$(mfile "$WT/agent-$ID")"
          hook "$1" "$WT/agent-$ID" "$ID" marvin:developer true; OUT=$(cat "$(mfile "$WT/agent-$ID")"); }
fx_K8M() { fresh; rm -rf "$R/.marvin"; mkwt "agent-$ID"; hook "$1" "$WT/agent-$ID"; OUT=$(state "$WT/agent-$ID"); }
fx_K8T() { fresh; mkwt "agent-$ID"; hook "$1" "$WT/agent-$ID" "$ID" general-purpose; OUT=$(state "$WT/agent-$ID"); }
fx_K11() { fresh; mkwt "agent-$ID"; printf 'marvin-owned marvin:developer %s 20200101T000000Z\n' "$ID" > "$WORK/target"
           ln -s "$WORK/target" "$(mfile "$WT/agent-$ID")"; hook "$1" "$WT/agent-$ID"
           if [ -L "$(mfile "$WT/agent-$ID")" ] && [ "$(cat "$WORK/target")" = "marvin-owned marvin:developer $ID 20200101T000000Z" ]; then OUT=intact; else OUT=damaged; fi; }
fx_K11D() { fresh; mkwt "agent-$ID"; ln -s "$WORK/target" "$(mfile "$WT/agent-$ID")"; hook "$1" "$WT/agent-$ID"   # a dangling link
            if [ -L "$(mfile "$WT/agent-$ID")" ] && [ ! -e "$WORK/target" ]; then OUT=intact; else OUT=damaged; fi; }
by_hand() {  # by_hand <script> <cwd> <args…> — run from <cwd>
  local s="$1" d="$2"; shift 2
  OUT=$(cd "$d" && CLAUDE_PROJECT_DIR="$R" bash "$s" "$@" </dev/null 2>&1); RC=$?
}
fx_OWN() { fresh; mkwt own; by_hand "$1" "$WT/own" "$WT/own"; }
fx_SYM() { fresh; mkwt real; ln -s "$WT/real" "$WT/lnk"; by_hand "$1" "$R" "$WT/lnk"; OUT="$OUT $(state "$WT/real")"; }

hd "K1 an isolated agent's worktree is marked, with a valid one-line marker"
fresh; mkwt "agent-$ID"; hook "$MARK" "$WT/agent-$ID"; silent_ok; marker_ok "$WT/agent-$ID" "$MARKER_RE"
if [ -z "$(git -C "$WT/agent-$ID" status --porcelain)" ]; then ok "worktree stays clean"; else bad "marker leaked into the worktree"; fi

hd "K2 a non-isolated agent in the main checkout marks nothing"
fresh; mkwt other; hook "$MARK" "$R"; silent_ok; want_state "$WT/other" unmarked
if [ ! -e "$R/.git/marvin-owned" ]; then ok "main admin dir unmarked"; else bad "main checkout marked"; fi

hd "K3 a non-isolated agent in a session worktree marks nothing"
fx_K3 "$MARK"; assert_rc 0; if [ "$OUT" = unmarked ]; then ok "unmarked"; else bad "session worktree marked"; fi

hd "K4 cwd named agent-<id> but a different agent_id marks nothing"
fx_K4 "$MARK"; if [ "$OUT" = unmarked ]; then ok "unmarked"; else bad "marked despite id mismatch"; fi

hd "K5 a subdirectory of the agent worktree as cwd resolves to the top level"
fresh; mkwt "agent-$ID"; mkdir -p "$WT/agent-$ID/sub/dir"; hook "$MARK" "$WT/agent-$ID/sub/dir"; silent_ok; marker_ok "$WT/agent-$ID" "$MARKER_RE"

hd "K6 a non-physical cwd spelling (a symlinked parent) still marks"
fresh; mkwt "agent-$ID"; ln -s "$WORK" "$WORK/lnk"
hook "$MARK" "$WORK/lnk/repo/.claude/worktrees/agent-$ID"; silent_ok; marker_ok "$WT/agent-$ID" "$MARKER_RE"

hd "K7 a second fire (stop_hook_active) leaves the marker's bytes alone"
fx_K7 "$MARK"; if [ "$OUT" = "marvin-owned marvin:developer $ID 20200101T000000Z" ]; then ok "marker unchanged"; else bad "marker rewritten: $OUT"; fi
hook "$MARK" "$WT/agent-$ID" "$ID" marvin:developer true; silent_ok

hd "K8 outside a Marvin project, outside git, or on bad input: no marker, no output, exit 0"
fx_K8M "$MARK"; assert_rc 0; if [ "$OUT" = unmarked ]; then ok "no .marvin: unmarked"; else bad "marked outside a Marvin project"; fi
fresh; mkwt "agent-$ID"; mkdir -p "$WORK/plain"
hook "$MARK" "$WORK/plain"; silent_ok; want_state "$WT/agent-$ID" unmarked
fx_K8T "$MARK"; if [ "$OUT" = unmarked ]; then ok "agent_type general-purpose: unmarked"; else bad "marked a non-marvin agent"; fi
fresh; mkwt "agent-$ID"
hook "$MARK" "$WT/agent-$ID" "$ID" "marvin:Dev_1"; silent_ok; want_state "$WT/agent-$ID" unmarked
hook "$MARK" "$WT/agent-$ID" "../x"; silent_ok; want_state "$WT/agent-$ID" unmarked
hook "$MARK" "$WT/agent-$ID" "abc"; silent_ok; want_state "$WT/agent-$ID" unmarked
fire "$MARK" ""; silent_ok
fire "$MARK" "not json at all"; silent_ok; want_state "$WT/agent-$ID" unmarked
fire "$MARK" "{\"session_id\":\"s\",\"agent_id\":\"$ID\",\"agent_type\":\"marvin:developer\"}"; silent_ok; want_state "$WT/agent-$ID" unmarked   # no cwd
fire "$MARK" "{\"session_id\":\"s\",\"agent_id\":\"$ID\",\"agent_type\":\"marvin:developer\",\"cwd\":\"$WT/agent-$ID"; silent_ok; want_state "$WT/agent-$ID" unmarked   # cut off mid-string
fire "$MARK" "{\"cwd\":\"$WT/agent-$ID\",\"agent_type\":\"marvin:developer\",\"agent_id\":\"${ID%?????}"; silent_ok; want_state "$WT/agent-$ID" unmarked   # cut off inside agent_id
mkdir -p "$WORK/plain"
OUT=$(cd "$WORK/plain" && env -u CLAUDE_PROJECT_DIR bash "$MARK" --subagent-stop <<<"$(payload "$WT/agent-$ID" "$ID" marvin:developer false)" 2>&1); RC=$?
silent_ok; marker_ok "$WT/agent-$ID" "$MARKER_RE"   # the project comes from cwd, not the caller's directory

hd "K9 by hand: <path> marks it as orchestrator-owned; a repeat is 'already marked'"
fresh; mkwt hand; by_hand "$MARK" "$R" "$WT/hand"; assert_rc 0; assert_out "marked: $WT/hand"; marker_ok "$WT/hand" "$HAND_RE"
cp "$(mfile "$WT/hand")" "$WORK/before"; printf 'marvin-owned orchestrator - 20200101T000000Z\n' > "$(mfile "$WT/hand")"
by_hand "$MARK" "$R" "$WT/hand/"; assert_rc 0; assert_out "already marked: $WT/hand"
if [ "$(cat "$(mfile "$WT/hand")")" = "marvin-owned orchestrator - 20200101T000000Z" ]; then ok "bytes unchanged"; else bad "marker rewritten"; fi
mkwt viadot; by_hand "$MARK" "$WT" "viadot"; assert_rc 0; assert_out "marked: viadot"; marker_ok "$WT/viadot" "$HAND_RE"   # relative path
mkwt viasym; ln -s "$WORK" "$WORK/lnk"; by_hand "$MARK" "$R" "$WORK/lnk/repo/.claude/worktrees/viasym"; assert_rc 0; marker_ok "$WT/viasym" "$HAND_RE"
fx_OWN "$MARK"; assert_rc 1; assert_out "refused: $WT/own — "; assert_out "standing in"; want_state "$WT/own" unmarked
fresh; mkwt own; mkdir -p "$WT/own/deep"; by_hand "$MARK" "$WT/own/deep" "$WT/own"; assert_rc 1; assert_out "standing in"; want_state "$WT/own" unmarked
fresh; mkwt own; mkwt peer; by_hand "$MARK" "$WT/own" "$WT/peer"; assert_rc 0; want_state "$WT/peer" marked   # another worktree is fine
fresh; by_hand "$MARK" "$R" "$R"; assert_rc 1; assert_out "refused: $R — "; assert_out "main checkout"
if [ ! -e "$R/.git/marvin-owned" ]; then ok "main admin dir unmarked"; else bad "main checkout marked"; fi
fresh; git -C "$R" worktree add -q -b outside "$WORK/outside" main; by_hand "$MARK" "$R" "$WORK/outside"; assert_rc 1; assert_out "refused:"; assert_out ".claude/worktrees"; want_state "$WORK/outside" unmarked
fresh; mkdir -p "$WT/plain"; by_hand "$MARK" "$R" "$WT/plain"; assert_rc 1; assert_out "not a linked worktree"
fresh; mkwt nest; mkdir -p "$WT/nest/sub"; by_hand "$MARK" "$R" "$WT/nest/sub"; assert_rc 1; assert_out "refused:"; want_state "$WT/nest" unmarked
fresh; by_hand "$MARK" "$R" "$WT/missing"; assert_rc 1; assert_out "not a directory"
fx_SYM "$MARK"; assert_rc 1; assert_out "a symlink"; assert_out "unmarked"
fresh; mkwt real; ln -s "$WORK/target" "$(mfile "$WT/real")"; by_hand "$MARK" "$R" "$WT/real"; assert_rc 1; assert_out "marker file is a symlink"
if [ ! -e "$WORK/target" ]; then ok "nothing written through the symlink"; else bad "wrote through the symlink"; fi
fresh; mkwt real; echo junk > "$(mfile "$WT/real")"; by_hand "$MARK" "$R" "$WT/real"; assert_rc 1; assert_out "not a valid marker"
if [ "$(cat "$(mfile "$WT/real")")" = junk ]; then ok "junk left alone"; else bad "junk file replaced"; fi
by_hand "$MARK" "$R"; assert_rc 2; assert_out "usage"
by_hand "$MARK" "$R" --bogus; assert_rc 2; assert_out "usage"
by_hand "$MARK" "$R" a b; assert_rc 2; assert_out "usage"
by_hand "$MARK" "$R" --subagent-stop x; assert_rc 2

hd "K10 a repo path with a space: hook and by-hand both work, output is encoded"
R="$WORK/my repo"; fresh; mkwt "agent-$ID"; mkwt hand
hook "$MARK" "$WT/agent-$ID"; silent_ok; marker_ok "$WT/agent-$ID" "$MARKER_RE"
by_hand "$MARK" "$R" "$WT/hand"; assert_rc 0; assert_out "marked: \"$WT/hand\""; marker_ok "$WT/hand" "$HAND_RE"
by_hand "$MARK" "$WT/hand" "$R"; assert_rc 1; assert_out "refused: \"$R\" — "
R="$WORK/repo"

hd "K11 a symlinked marker file is unmarked (is_marked) and nothing is written through it"
fresh; mkwt "agent-$ID"; printf 'marvin-owned marvin:developer %s 20200101T000000Z\n' "$ID" > "$WORK/target"; ln -s "$WORK/target" "$(mfile "$WT/agent-$ID")"
if (. "$MARK"; is_marked "$WT/agent-$ID"); then bad "is_marked trusted a symlinked marker"; else ok "is_marked: unmarked"; fi
rm -f "$(mfile "$WT/agent-$ID")"; printf 'marvin-owned marvin:developer %s 20200101T000000Z\n' "$ID" > "$(mfile "$WT/agent-$ID")"
if (. "$MARK"; is_marked "$WT/agent-$ID"); then ok "is_marked: a regular file is marked"; else bad "is_marked rejected a valid regular marker"; fi
printf 'marvin-owned nobody 20200101T000000Z\n' > "$(mfile "$WT/agent-$ID")"
if (. "$MARK"; is_marked "$WT/agent-$ID"); then bad "is_marked accepted a malformed line"; else ok "is_marked: a malformed line is unmarked"; fi
fx_K11 "$MARK"; if [ "$OUT" = intact ]; then ok "hook wrote nothing through the symlink"; else bad "hook touched the symlinked marker"; fi
fx_K11D "$MARK"; if [ "$OUT" = intact ]; then ok "hook wrote nothing through a dangling symlink"; else bad "hook touched the dangling symlinked marker"; fi

# ── mutations: each reverts one guard in a copy (with the hook lib beside it); its fixture must then fail ──
MUT="$WORK/mut"; mkdir -p "$MUT/lib"; cp "$SCRIPT_DIR/lib/marvin-hook-lib.sh" "$MUT/lib/"
mutation() {  # mutation <name> <fixture-fn> <exact script line> <replacement> <what the real script leaves in OUT> [<line2> <replacement2>]
  local m="$MUT/mutant-$1.sh"
  A="$3" B="$4" A2="${6:-}" B2="${7:-}" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } ENVIRON["A2"] != "" && $0 == ENVIRON["A2"] { print ENVIRON["B2"]; next } { print }' "$MARK" > "$m"
  if cmp -s "$m" "$MARK"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  if [ -n "${6:-}" ] && ! grep -qxF -- "$7" "$m"; then bad "mutation $1: second target line not found — harness is stale"; return; fi
  "$2" "$m"
  if printf '%s\n' "$OUT" | grep -Fq -- "$5"; then bad "mutation $1 survived ($2 still left: $5)"; else ok "mutation $1 caught"; fi
}
hd "M mutations"
EQ='  [ "$(mh_path "$top")" = "$(mh_path "$want")" ] || return 0'
mutation EQ-SESSION fx_K3 "$EQ" '  :' unmarked
mutation EQ-ID fx_K4 "$EQ" '  :' unmarked
mutation AGENTTYPE fx_K8T "  printf '%s' \"\$atype\" | grep -Eq '^marvin:[a-z0-9-]+\$' || return 0" '  :' unmarked
mutation MARVIN fx_K8M '  mh_is_marvin "$main" || return 0' '  :' unmarked
mutation IDEM fx_K7 '  [ -e "$f" ] || [ -L "$f" ] && return 1' '  :' "marvin-owned marvin:developer $ID 20200101T000000Z" \
                    '    && mv -n -- "$tmp" "$f" 2>/dev/null' '    && mv -f -- "$tmp" "$f" 2>/dev/null'
mutation SYMMARK fx_K11D '  [ -e "$f" ] || [ -L "$f" ] && return 1' '  [ -e "$f" ] && return 1' intact \
                      '    && mv -n -- "$tmp" "$f" 2>/dev/null' '    && mv -f -- "$tmp" "$f" 2>/dev/null'
mutation OWN fx_OWN '  case "$(mh_path "$here")/" in "$(mh_path "$phys")"/*) refuse "$arg" "the worktree you are standing in" ;; esac' '  :' "standing in"
mutation SYMARG fx_SYM '  [ -L "$a" ] && refuse "$arg" "a symlink"' '  :' "unmarked"

printf '\n----\ntest-worktree-mark: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
