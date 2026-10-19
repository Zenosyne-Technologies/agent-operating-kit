#!/usr/bin/env bash
# test-runs-sync.sh — behavioural tests for scripts/marvin-runs-sync.sh (AOS-224).
# Real repos in a temp dir: a Marvin project (main checkout) with a committed briefing.md, a session
# worktree and an isolated agent worktree under .claude/worktrees/. --session-start (SS*): the
# per-session folder, the symlink rule, seeding; --post-tool (PT*): the orchestrator's writes in a
# worktree carried to the project; --subagent-stop (SA*): a sub-agent's named report moved to the
# project; X1 outside Marvin / outside git / bad JSON, X2 a repo path with a space.
# The mutation section reverts one guard at a time in a copy; the guard's fixture must then fail.
# Run from anywhere: bash scripts/test-runs-sync.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SYNC="$SCRIPT_DIR/marvin-runs-sync.sh"
. "$SCRIPT_DIR/lib/marvin-hook-lib.sh"   # mh_get / mh_q decode and encode what the hook prints
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-rstest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
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
assert_rc()    { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1 (got: $(printf '%s' "$OUT" | head -c 200))"; fi; }
assert_empty() { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 300)"; fi; }
assert_only()  { if [ "$OUT" = "$1" ]; then ok "output is exactly the expected line"; else bad "output differs — want: $1 — got: $(printf '%s' "$OUT" | head -c 300)"; fi; }
silent_ok()    { assert_rc 0; assert_empty; }
gone()   { if [ ! -e "$1" ] && [ ! -L "$1" ]; then ok "absent: ${1#"$WORK"/}"; else bad "present: ${1#"$WORK"/}"; fi; }
there()  { if [ -f "$1" ]; then ok "present: ${1#"$WORK"/}"; else bad "missing: ${1#"$WORK"/}"; fi; }
holds()  { if [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]; then ok "${1#"$WORK"/} holds: $2"; else bad "${1#"$WORK"/} holds '$(cat "$1" 2>/dev/null | head -c 100)', want '$2'"; fi; }
same()   { if [ -f "$1" ] && [ -f "$2" ] && cmp -s "$1" "$2"; then ok "same bytes: ${2#"$WORK"/}"; else bad "differ or missing: ${1#"$WORK"/} vs ${2#"$WORK"/}"; fi; }

SID=0123abcd-4567-89ab-cdef-0123456789ab
S="20261019T101500Z-$SID"
AID=a7bf0dd563169ef8d
REP="20261019T101600Z-developer.md"
LIT='.marvin/runs/<session>/'
R="$WORK/repo"

fresh() {  # fresh [nolit] — a Marvin project at $R (committed briefing.md carrying the layout literal unless nolit),
           # a session worktree $W and an isolated agent worktree $A; RUNS = the project's run folder
  rm -rf "$R" "$WORK/plain" "$WORK/elsewhere" "$WORK/lnk" "$WORK/secret"
  git init -q "$R"
  mkdir -p "$R/.marvin/agents"
  if [ "${1:-}" = nolit ]; then echo 'item 11: .marvin/runs/<KEY>/ only' > "$R/.marvin/agents/briefing.md"
  else printf 'item 11: run files live under %s<KEY|adhoc>/\n' "$LIT" > "$R/.marvin/agents/briefing.md"; fi
  git -C "$R" add .marvin && git -C "$R" commit -q -m base
  W="$R/.claude/worktrees/sess"; A="$R/.claude/worktrees/agent-$AID"; RUNS="$R/.marvin/runs"
  git -C "$R" worktree add -q -b sess "$W" main
  git -C "$R" worktree add -q -b "agent-$AID" "$A" main
}
lw() { mkdir -p "$1/.marvin/runs/${2%/*}"; printf "$3" > "$1/.marvin/runs/$2"; }   # lw <checkout> <rel> <printf text>
pw() { lw "$R" "$1" "$2"; }                                                          # pw <rel> <printf text> — a project copy
run() { OUT=$(cd "$WORK" && CLAUDE_PROJECT_DIR="$R" bash "$1" "$2" <<<"$3" 2>&1); RC=$?; }
ss() {  # ss <script> <cwd> [session_id] [source]
  run "$1" --session-start "$(printf '{"session_id":"%s","transcript_path":"/x","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' "${3:-$SID}" "$2" "${4:-startup}")"
}
pt() {  # pt <script> <cwd> <file_path> [agent_id] — a Write's PostToolUse; an agent_id makes it a sub-agent's
  local a=""; [ -n "${4:-}" ] && a="\"agent_id\":\"$4\",\"agent_type\":\"marvin:developer\","
  run "$1" --post-tool "$(printf '{"session_id":"%s","transcript_path":"/x","cwd":"%s",%s"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"x"},"tool_response":{"success":true}}' "$SID" "$2" "$a" "$3")"
}
sa() {  # sa <script> <cwd> <agent transcript> [agent_type]
  run "$1" --subagent-stop "$(printf '{"session_id":"%s","transcript_path":"/x","cwd":"%s","permission_mode":"default","agent_id":"%s","agent_type":"%s","hook_event_name":"SubagentStop","stop_hook_active":false,"agent_transcript_path":"%s","last_assistant_message":"done"}' "$SID" "$2" "$AID" "${4:-marvin:developer}" "$3")"
}
brief() {  # brief <text> — $T, a transcript whose first user message (the brief) is <text>
  T="$WORK/agent.jsonl"
  printf '{"parentUuid":null,"isSidechain":true,"type":"user","message":{"role":"user","content":"%s"}}\n{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n' "$1" > "$T"
}
want_line() { printf 'Marvin run folder: %s/ — write run files under %s/ in your own checkout; hooks carry them to the project.' "$(mh_q "$RUNS/$1")" "$(mh_q ".marvin/runs/$1")"; }
want_clash() {  # want_clash <local> <project> [<sidecar>]
  printf 'Marvin run-state clash: %s differs from %s — both kept; reconcile before the next dispatch.' "$(mh_q "$1")" "$(mh_q "$2")"
  [ -z "${3:-}" ] || printf ' — differing copy saved as %s' "$(mh_q "$3")"
}
want_refusal() { printf 'Marvin run-state sync refused: %s — %s' "$1" "$(mh_q "$2")"; }
nsess() { local n=0 d; for d in "$RUNS"/*-"$SID"; do [ -d "$d" ] && n=$((n+1)); done; echo "$n"; }
pt_clash_ok() {  # pt_clash_ok <local> <project> — the PostToolUse clash JSON: systemMessage and additionalContext
  local want m c e; want=$(want_clash "$1" "$2")
  m=$(printf '%s' "$OUT" | mh_get systemMessage) || m=""
  c=$(printf '%s' "$OUT" | mh_get hookSpecificOutput.additionalContext) || c=""
  e=$(printf '%s' "$OUT" | mh_get hookSpecificOutput.hookEventName) || e=""
  if [ "$m" = "$want" ]; then ok "systemMessage is the clash line"; else bad "systemMessage '$m', want '$want' (raw: $(printf '%s' "$OUT" | head -c 300))"; fi
  if [ "$c" = "$want" ] && [ "$e" = PostToolUse ]; then ok "additionalContext is the clash line"; else bad "additionalContext '$c' / event '$e'"; fi
}
sa_clash_ok() {  # sa_clash_ok <local> <project> [<sidecar>]
  local want m; want=$(want_clash "$1" "$2" "${3:-}")
  m=$(printf '%s' "$OUT" | mh_get systemMessage) || m=""
  if [ "$m" = "$want" ]; then ok "systemMessage is the clash line"; else bad "systemMessage '$m', want '$want' (raw: $(printf '%s' "$OUT" | head -c 300))"; fi
}

# ── fixtures reused by the mutation section: each takes the script and appends a judge token to OUT ──
fx_SS2() { fresh nolit; ss "$1" "$W"; OUT="$OUT runs:$([ -e "$RUNS" ] && echo yes || echo no)"; }
fx_SS3() { fresh; mkdir -p "$RUNS/20261001T000000Z-$SID"; ss "$1" "$W" "$SID" resume; OUT="$OUT count:$(nsess)"; }
fx_SS4() { fresh; pw "$S/AOS-1/ledger.md" 'r1\nr2\n'; pw "$S/AOS-1/build-brief.md" 'brief\n'; ss "$1" "$W" "$SID" resume
           OUT="$OUT seeded:$(cmp -s "$RUNS/$S/AOS-1/ledger.md" "$W/.marvin/runs/$S/AOS-1/ledger.md" && cmp -s "$RUNS/$S/AOS-1/build-brief.md" "$W/.marvin/runs/$S/AOS-1/build-brief.md" && echo yes || echo no)"; }
fx_SS4B() { fresh; pw "$S/AOS-1/ledger.md" 'r1\nr2\n'; lw "$W" "$S/AOS-1/ledger.md" 'mine\n'; ss "$1" "$W" "$SID" resume
            OUT="$OUT local:$(cat "$W/.marvin/runs/$S/AOS-1/ledger.md")"; }
fx_SS5() { fresh; mkdir -p "$WORK/elsewhere"; ln -s "$WORK/elsewhere" "$RUNS"; ss "$1" "$W"
           OUT="$OUT elsewhere:$(ls -A "$WORK/elsewhere" | wc -l | tr -d ' ')"; }
fx_SS7() { fresh; mkdir -p "$RUNS"; : > "$RUNS/.gitignore"; ss "$1" "$W"; OUT="$OUT count:$(nsess)"; }
fx_PT2() { fresh; pw "$S/AOS-1/ledger.md" 'AAA\nBBB\n'; lw "$W" "$S/AOS-1/ledger.md" 'XXX\n'; pt "$1" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"
           OUT="$OUT project:$(tr '\n' ' ' < "$RUNS/$S/AOS-1/ledger.md")"; }
fx_PT3() { fresh; lw "$W" "$S/AOS-1/$REP" 'one\n'; pt "$1" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; lw "$W" "$S/AOS-1/$REP" 'two\n'
           pt "$1" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; OUT="$OUT project:$(cat "$RUNS/$S/AOS-1/$REP" 2>/dev/null)"; }
fx_PT4() { fresh; lw "$W" "$S/AOS-1/$REP" 'one\n'; pt "$1" "$W" "$W/.marvin/runs/$S/AOS-1/$REP" "$AID"
           OUT="$OUT project:$([ -e "$RUNS/$S/AOS-1/$REP" ] && echo yes || echo no)"; }
fx_PT5() { fresh; local n=0 rel
           for rel in "AOS-1/$REP" "$S/AOS-1/sub/$REP" "$S/lower-1/$REP" "$S/AOS-1/notes.md" "20261019T1015Z-$SID/AOS-1/$REP"; do
             lw "$W" "$rel" 'x\n'; pt "$1" "$W" "$W/.marvin/runs/$rel"; [ -e "$RUNS/$rel" ] && n=$((n+1))
           done; OUT="$OUT carried:$n"; }
fx_PT8() { fresh; mkdir -p "$WORK/elsewhere" "$RUNS"; ln -s "$WORK/elsewhere" "$RUNS/$S"; lw "$W" "$S/AOS-1/$REP" 'one\n'
           pt "$1" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; OUT="$OUT elsewhere:$(ls -A "$WORK/elsewhere" | wc -l | tr -d ' ')"; }
fx_SA1() { fresh; lw "$A" "$S/AOS-1/$REP" 'report\n'; brief "Write your run report to .marvin/runs/$S/AOS-1/$REP and stop."; sa "$1" "$A" "$T"
           OUT="$OUT src:$([ -e "$A/.marvin/runs/$S/AOS-1/$REP" ] && echo kept || echo gone) dst:$(cat "$RUNS/$S/AOS-1/$REP" 2>/dev/null)"; }
fx_SA2() { fresh; lw "$A" "$S/AOS-1/$REP" 'report\n'; pw "$S/AOS-1/$REP" 'report\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$1" "$A" "$T"
           OUT="$OUT src:$([ -e "$A/.marvin/runs/$S/AOS-1/$REP" ] && echo kept || echo gone)"; }
SIDE="${REP%.md}.clash-$AID.md"
fx_SA3() { fresh; lw "$A" "$S/AOS-1/$REP" 'mine\n'; pw "$S/AOS-1/$REP" 'theirs\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$1" "$A" "$T"
           OUT="$OUT src:$([ -e "$A/.marvin/runs/$S/AOS-1/$REP" ] && echo kept || echo gone) dst:$(cat "$RUNS/$S/AOS-1/$REP") side:$(cat "$RUNS/$S/AOS-1/$SIDE" 2>/dev/null)"; }
fx_SS1L() { fresh; ss "$1" "$W"; local n; for n in "$RUNS"/*-"$SID"; do n=${n##*/}; done; lw "$W" "$n/AOS-1/ledger.md" 'r1\n'
            OUT="$OUT status:$([ -z "$(git -C "$W" status --porcelain)" ] && echo clean || echo dirty)"; }
fx_SA7() { fresh; pw "$S/AOS-1/$REP" 'report\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$1" "$R" "$T"
           OUT="$OUT dst:$([ -e "$RUNS/$S/AOS-1/$REP" ] && echo kept || echo gone)"; }
fx_SA8() { fresh; lw "$W" "$S/AOS-1/ledger.md" 'r1\n'; pw "$S/AOS-1/ledger.md" 'r1\n'; brief "Read .marvin/runs/$S/AOS-1/ledger.md first."; sa "$1" "$W" "$T"
           OUT="$OUT ledger:$([ -e "$W/.marvin/runs/$S/AOS-1/ledger.md" ] && echo kept || echo gone)"; }
fx_SA9() { fresh; printf 'secret\n' > "$WORK/secret"; mkdir -p "$A/.marvin/runs/$S/AOS-1"; ln -s "$WORK/secret" "$A/.marvin/runs/$S/AOS-1/$REP"
           brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$1" "$A" "$T"
           OUT="$OUT dst:$([ -e "$RUNS/$S/AOS-1/$REP" ] && echo yes || echo no) link:$([ -L "$A/.marvin/runs/$S/AOS-1/$REP" ] && echo kept || echo gone)"; }
fx_SA10() { fresh; lw "$A" "$S/AOS-1/$REP" 'report\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$1" "$A" "$T" general-purpose
            OUT="$OUT src:$([ -e "$A/.marvin/runs/$S/AOS-1/$REP" ] && echo kept || echo gone)"; }
fx_X1M() { fresh; rm -rf "$R/.marvin" "$W/.marvin" "$A/.marvin"; lw "$A" "$S/AOS-1/$REP" 'report\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"
           sa "$1" "$A" "$T"; OUT="$OUT src:$([ -e "$A/.marvin/runs/$S/AOS-1/$REP" ] && echo kept || echo gone)"; }

hd "SS1 briefing literal present: the session folder is created, .gitignore = *, the one line is printed"
fresh; ss "$SYNC" "$W"; assert_rc 0
name=""; for d in "$RUNS"/*-"$SID"; do [ -d "$d" ] && name=${d##*/}; done
if [ "$(nsess)" = 1 ] && printf '%s' "$name" | grep -Eq "$MH_SESSION_RE"; then ok "one session folder: $name"; else bad "session folders: $(nsess) ($name)"; fi
holds "$RUNS/.gitignore" '*'
assert_only "$(want_line "$name")"
if git -C "$R" check-ignore -q "$RUNS/$name/AOS-1/x.md"; then ok "the folder is git-ignored"; else bad "the folder is not ignored"; fi
holds "$W/.marvin/runs/.gitignore" '*'   # the local checkout is bootstrapped too, seeding or not
lw "$W" "$name/AOS-1/ledger.md" 'r1\n'; lw "$W" "$name/AOS-1/$REP" 'rep\n'
if [ -z "$(git -C "$W" status --porcelain)" ]; then ok "local run files leave the session worktree clean"; else bad "worktree dirtied: $(git -C "$W" status --porcelain | head -3)"; fi
fx_SS1L "$SYNC"; assert_only "$(want_line "$(cd "$RUNS" && ls -d *-"$SID")") status:clean"
fresh; mkdir -p "$W/.marvin/runs"; ln -s "$WORK/nowhere" "$W/.marvin/runs/.gitignore"; ss "$SYNC" "$W"; assert_rc 0; gone "$WORK/nowhere"   # local symlink: refused
ss "$SYNC" "$R" "$SID" compact; assert_rc 0; assert_only "$(want_line "$name")"   # from the main checkout, on compact: the same folder

hd "SS2 briefing literal absent: nothing created, silent"
fx_SS2 "$SYNC"; assert_rc 0; assert_only " runs:no"

hd "SS3 resume: a folder ending in -<session_id> is reused, never duplicated"
fx_SS3 "$SYNC"; assert_rc 0; assert_only "$(want_line "20261001T000000Z-$SID") count:1"
ss "$SYNC" "$W" "$SID" clear; assert_rc 0; if [ "$(nsess)" = 1 ]; then ok "still one folder"; else bad "duplicated: $(nsess)"; fi

hd "SS4 seeding: the project's ledger and build brief are copied into a checkout that lacks them"
fx_SS4 "$SYNC"; assert_rc 0; assert_only "$(want_line "$S") seeded:yes"
holds "$W/.marvin/runs/.gitignore" '*'
if [ -z "$(git -C "$W" status --porcelain)" ]; then ok "seeded copies are ignored in the worktree"; else bad "worktree dirtied"; fi
fx_SS4B "$SYNC"; assert_only "$(want_line "$S") local:mine"   # an existing local copy is never overwritten
fresh; pw "$S/AOS-1/ledger.md" 'r1\n'; pw "$S/AOS-1/$REP" 'rep\n'; pw "$S/AOS-1/notes.md" 'n\n'; ss "$SYNC" "$W" "$SID" resume
gone "$W/.marvin/runs/$S/AOS-1/$REP"; gone "$W/.marvin/runs/$S/AOS-1/notes.md"; there "$W/.marvin/runs/$S/AOS-1/ledger.md"   # mutable files only
fresh; pw "$S/AOS-1/ledger.md" 'r1\n'; ss "$SYNC" "$R" "$SID" resume; assert_only "$(want_line "$S")"   # main checkout: nothing to seed

hd "SS5 a symlinked .marvin/runs: refused, nothing written, silent exit 0"
fx_SS5 "$SYNC"; assert_rc 0; assert_only " elsewhere:0"
fresh; mkdir -p "$RUNS"; ln -s "$WORK/nowhere" "$RUNS/.gitignore"; ss "$SYNC" "$W"; silent_ok; gone "$WORK/nowhere"
if [ "$(nsess)" = 0 ]; then ok "no folder behind a symlinked .gitignore"; else bad "folder created"; fi

hd "SS6 a session_id that is not 36 hex-and-dash characters: nothing"
for bid in "0123abcd" "0123ABCD-4567-89AB-CDEF-0123456789AB" "../../../../../../../../../../../x/yy"; do
  fresh; ss "$SYNC" "$W" "$bid"; silent_ok; gone "$RUNS"
done

hd "SS7 an existing .gitignore that does not ignore the folder: refused (check-ignore)"
fx_SS7 "$SYNC"; assert_rc 0; assert_only " count:0"

hd "PT1 an orchestrator ledger write in a worktree: the project copy equals the local one, appends follow"
fresh; lw "$W" "$S/AOS-1/ledger.md" '| 1 |\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok; same "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"
holds "$RUNS/.gitignore" '*'
printf 'F1 new FAIL\n' >> "$W/.marvin/runs/$S/AOS-1/ledger.md"; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok; same "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"
pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok; same "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"   # a second fire
lw "$W" "$S/adhoc/build-brief-2.md" 'v1\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/adhoc/build-brief-2.md"; silent_ok
lw "$W" "$S/adhoc/build-brief-2.md" 'rewritten\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/adhoc/build-brief-2.md"; silent_ok
holds "$RUNS/$S/adhoc/build-brief-2.md" 'rewritten'   # a build brief overwrites, no prefix rule
if [ -z "$(ls -A "$RUNS/$S/AOS-1" | grep -v '^ledger.md$')" ]; then ok "no temp file left behind"; else bad "left: $(ls -A "$RUNS/$S/AOS-1")"; fi

hd "PT2 a local ledger that does not extend the project copy: clash, the project copy is kept"
fx_PT2 "$SYNC"; assert_rc 0
OUT=${OUT% project:*}; pt_clash_ok "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"
holds "$RUNS/$S/AOS-1/ledger.md" "$(printf 'AAA\nBBB')"; holds "$W/.marvin/runs/$S/AOS-1/ledger.md" 'XXX'

hd "PT3 a timestamped file: copied when absent; present and differing → clash, project kept"
fresh; lw "$W" "$S/AOS-1/$REP" 'one\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; silent_ok; holds "$RUNS/$S/AOS-1/$REP" one
pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; silent_ok   # identical: no-op
lw "$W" "$S/AOS-1/$REP" 'two\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; assert_rc 0
pt_clash_ok "$W/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$REP"; holds "$RUNS/$S/AOS-1/$REP" one; holds "$W/.marvin/runs/$S/AOS-1/$REP" two

hd "PT4 a sub-agent's write (agent_id in the payload prefix): ignored"
fx_PT4 "$SYNC"; assert_rc 0; assert_only " project:no"

hd "PT5 paths outside the layout (flat, deeper, bad key, unknown name, bad session): ignored"
fx_PT5 "$SYNC"; assert_rc 0; assert_only " carried:0"

hd "PT6 checkout = the project root: no-op"
fresh; lw "$R" "$S/AOS-1/ledger.md" 'r1\n'; pt "$SYNC" "$R" "$RUNS/$S/AOS-1/ledger.md"; silent_ok; holds "$RUNS/$S/AOS-1/ledger.md" r1
gone "$RUNS/.gitignore"

hd "PT7 a non-physical spelling of the file path (a symlinked parent) is still carried"
fresh; ln -s "$WORK" "$WORK/lnk"; lw "$W" "$S/AOS-1/ledger.md" 'r1\n'
pt "$SYNC" "$WORK/lnk/repo/.claude/worktrees/sess" "$WORK/lnk/repo/.claude/worktrees/sess/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok
same "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"

hd "PT8 a symlinked component in the project path (the session folder): nothing written through it"
fx_PT8 "$SYNC"; assert_rc 0; assert_only " elsewhere:0"
fresh; mkdir -p "$WORK/elsewhere" "$W/.marvin/runs/$S"; ln -s "$WORK/elsewhere" "$W/.marvin/runs/$S/AOS-1"
printf 'z\n' > "$WORK/elsewhere/$REP"; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; silent_ok; gone "$RUNS/$S/AOS-1/$REP"   # a symlinked LOCAL key dir

hd "SA1 an isolated agent's report: moved to the project, the source is gone"
fx_SA1 "$SYNC"; assert_rc 0; assert_only " src:gone dst:report"
if [ -z "$(git -C "$A" status --porcelain)" ]; then ok "agent worktree clean"; else bad "agent worktree dirty"; fi
fresh; lw "$A" "$S/AOS-1/$REP" 'abs\n'; brief "Write the report to $A/.marvin/runs/$S/AOS-1/$REP (absolute)."; sa "$SYNC" "$A" "$T"; silent_ok
holds "$RUNS/$S/AOS-1/$REP" abs; gone "$A/.marvin/runs/$S/AOS-1/$REP"
fresh; mkdir -p "$A/sub"; lw "$A" "$S/adhoc/$REP" 'sub\n'; brief "Report \`.marvin/runs/$S/adhoc/$REP\`."; sa "$SYNC" "$A/sub" "$T"; silent_ok
holds "$RUNS/$S/adhoc/$REP" sub; gone "$A/.marvin/runs/$S/adhoc/$REP"   # cwd a subdirectory; a back-quoted path

hd "SA2 a report already identical in the project: the source is deleted"
fx_SA2 "$SYNC"; assert_rc 0; assert_only " src:gone"

hd "SA3 a differing project copy: clash, both kept"
fx_SA3 "$SYNC"; assert_rc 0
OUT=${OUT% src:*}; sa_clash_ok "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$SIDE"
holds "$A/.marvin/runs/$S/AOS-1/$REP" mine; holds "$RUNS/$S/AOS-1/$REP" theirs
same "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$SIDE"   # the differing source survives the worktree's removal
sa "$SYNC" "$A" "$T"; sa_clash_ok "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$SIDE"   # re-fire: the identical sidecar is reused
gone "$RUNS/$S/AOS-1/${SIDE%.md}-2.md"
lw "$A" "$S/AOS-1/$REP" 'third\n'; sa "$SYNC" "$A" "$T"; sa_clash_ok "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/${SIDE%.md}-2.md"
holds "$RUNS/$S/AOS-1/${SIDE%.md}-2.md" third; holds "$RUNS/$S/AOS-1/$SIDE" mine   # a differing sidecar is never overwritten
fresh; lw "$A" "$S/AOS-1/$REP" 'mine\n'; pw "$S/AOS-1/$REP" 'theirs\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"
run "$SYNC" --subagent-stop "$(printf '{"cwd":"%s","agent_type":"marvin:developer","hook_event_name":"SubagentStop","agent_transcript_path":"%s"}' "$A" "$T")"
nside=$(ls "$RUNS/$S/AOS-1" | grep -cE '^20261019T101600Z-developer\.clash-[0-9]{8}T[0-9]{6}Z\.md$')
if [ "$nside" = 1 ]; then ok "no agent_id: the sidecar is tagged with the UTC time"; else bad "UTC-tagged sidecars: $nside ($(ls "$RUNS/$S/AOS-1"))"; fi

hd "SA4 a brief naming no layout path: nothing"
fresh; lw "$A" "$S/AOS-1/$REP" 'report\n'; lw "$A" "AOS-1/$REP" 'flat\n'; brief "Report: .marvin/runs/AOS-1/$REP (flat layout)."; sa "$SYNC" "$A" "$T"; silent_ok
there "$A/.marvin/runs/$S/AOS-1/$REP"; there "$A/.marvin/runs/AOS-1/$REP"; gone "$RUNS"

hd "SA5 a second fire (stop_hook_active): no change"
fx_SA1 "$SYNC"; sa "$SYNC" "$A" "$T"; silent_ok; holds "$RUNS/$S/AOS-1/$REP" report

hd "SA6 a non-isolated agent (cwd = the orchestrator's worktree): its named report is moved from there"
fresh; lw "$W" "$S/AOS-1/$REP" 'from-w\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$SYNC" "$W" "$T"; silent_ok
holds "$RUNS/$S/AOS-1/$REP" from-w; gone "$W/.marvin/runs/$S/AOS-1/$REP"

hd "SA7 a non-isolated agent in the main checkout: the report stays where it is"
fx_SA7 "$SYNC"; assert_rc 0; assert_only " dst:kept"

hd "SA8 a mutable file the brief names (the ledger) is never moved off the orchestrator's checkout"
fx_SA8 "$SYNC"; assert_rc 0; assert_only " ledger:kept"

hd "SA9 a symlinked source report: not moved, nothing read through it"
fx_SA9 "$SYNC"; assert_rc 0; assert_only " dst:no link:kept"; holds "$WORK/secret" secret

hd "SA10 a non-marvin agent type: nothing"
fx_SA10 "$SYNC"; assert_rc 0; assert_only " src:kept"

hd "SA11 a changed re-fire (stop_hook_active) after a first fire moved a version: the second lands as a sidecar"
fx_SA1 "$SYNC"; lw "$A" "$S/AOS-1/$REP" 'report v2\n'
run "$SYNC" --subagent-stop "$(printf '{"session_id":"%s","cwd":"%s","agent_id":"%s","agent_type":"marvin:developer","hook_event_name":"SubagentStop","stop_hook_active":true,"agent_transcript_path":"%s"}' "$SID" "$A" "$AID" "$T")"
assert_rc 0; sa_clash_ok "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$SIDE"
holds "$RUNS/$S/AOS-1/$REP" report; holds "$RUNS/$S/AOS-1/$SIDE" 'report v2'; holds "$A/.marvin/runs/$S/AOS-1/$REP" 'report v2'

hd "R1 a non-symlink refusal prints one notice (not ignored, unreadable); a symlink refusal stays silent"
fresh; mkdir -p "$RUNS"; : > "$RUNS/.gitignore"; lw "$W" "$S/AOS-1/ledger.md" 'r1\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; assert_rc 0
m=$(printf '%s' "$OUT" | mh_get systemMessage) || m=""; c=$(printf '%s' "$OUT" | mh_get hookSpecificOutput.additionalContext) || c=""
w=$(want_refusal "not ignored" "$RUNS/$S/AOS-1/ledger.md")
if [ "$m" = "$w" ] && [ "$c" = "$w" ]; then ok "post-tool: not ignored notice"; else bad "post-tool notice '$m' / '$c', want '$w'"; fi
gone "$RUNS/$S/AOS-1/ledger.md"
lw "$A" "$S/AOS-1/$REP" 'r\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$SYNC" "$A" "$T"; assert_rc 0
m=$(printf '%s' "$OUT" | mh_get systemMessage) || m=""; w=$(want_refusal "not ignored" "$RUNS/$S/AOS-1/$REP")
if [ "$m" = "$w" ]; then ok "subagent-stop: not ignored notice"; else bad "subagent-stop notice '$m', want '$w'"; fi
there "$A/.marvin/runs/$S/AOS-1/$REP"
fresh; lw "$W" "$S/AOS-1/$REP" 'r\n'; chmod 000 "$W/.marvin/runs/$S/AOS-1/$REP"
if [ -r "$W/.marvin/runs/$S/AOS-1/$REP" ]; then ok "running as root: the unreadable case cannot be built (skipped)"
else
  pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/$REP"; m=$(printf '%s' "$OUT" | mh_get systemMessage) || m=""
  w=$(want_refusal unreadable "$W/.marvin/runs/$S/AOS-1/$REP")
  if [ "$m" = "$w" ]; then ok "post-tool: unreadable notice"; else bad "unreadable notice '$m', want '$w'"; fi
fi
chmod 644 "$W/.marvin/runs/$S/AOS-1/$REP"; gone "$RUNS/$S/AOS-1/$REP"

hd "X1 outside Marvin, outside git, malformed JSON: silent, exit 0, nothing written (each mode)"
fx_X1M "$SYNC"; assert_rc 0; assert_only " src:kept"
fresh; rm -rf "$R/.marvin" "$W/.marvin"; ss "$SYNC" "$W"; silent_ok; gone "$RUNS"
lw "$W" "$S/AOS-1/ledger.md" 'r\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok; gone "$RUNS"
mkdir -p "$WORK/plain/.marvin/agents"; printf '%s\n' "$LIT" > "$WORK/plain/.marvin/agents/briefing.md"   # a Marvin tree outside git
lw "$WORK/plain" "$S/AOS-1/ledger.md" 'r\n'; lw "$WORK/plain" "$S/AOS-1/$REP" 'r\n'
ss "$SYNC" "$WORK/plain"; silent_ok; gone "$WORK/plain/.marvin/runs/.gitignore"
pt "$SYNC" "$WORK/plain" "$WORK/plain/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok
brief "Report: .marvin/runs/$S/AOS-1/$REP"; sa "$SYNC" "$WORK/plain" "$T"; silent_ok; there "$WORK/plain/.marvin/runs/$S/AOS-1/$REP"
fresh; lw "$W" "$S/AOS-1/ledger.md" 'r\n'; lw "$A" "$S/AOS-1/$REP" 'r\n'; brief "Report: .marvin/runs/$S/AOS-1/$REP"
for m in --session-start --post-tool --subagent-stop; do
  run "$SYNC" "$m" ""; silent_ok
  run "$SYNC" "$m" "not json at all"; silent_ok
  run "$SYNC" "$m" "{\"session_id\":\"$SID\",\"hook_event_name\":\"x\",\"agent_type\":\"marvin:developer\",\"agent_transcript_path\":\"$T\",\"tool_input\":{\"file_path\":\"$W/.marvin/runs/$S/AOS-1/ledger.md\"}}"; silent_ok   # no cwd
  run "$SYNC" "$m" "{\"session_id\":\"$SID\",\"cwd\":\"$W"; silent_ok   # cut off mid-string
  run "$SYNC" "$m" "{\"session_id\":\"${SID%?????}"; silent_ok          # cut off inside session_id
done
run "$SYNC" --post-tool "{\"cwd\":\"$W\",\"hook_event_name\":\"PostToolUse\",\"tool_input\":{\"file_path\":\"$W/.marvin/runs/$S/AOS-1/led"; silent_ok   # cut inside file_path
gone "$RUNS"; there "$A/.marvin/runs/$S/AOS-1/$REP"
run "$SYNC" --bogus "{}"; assert_rc 2
run "$SYNC" "" "{}"; assert_rc 2

hd "X2 a repo path with a space: SS1, PT1, SA1 and the clash line hold, paths quoted"
R="$WORK/my repo"; fresh
ss "$SYNC" "$W"; assert_rc 0; name=""; for d in "$RUNS"/*-"$SID"; do [ -d "$d" ] && name=${d##*/}; done; assert_only "$(want_line "$name")"
case "$OUT" in "Marvin run folder: \"$RUNS/"*) ok "project folder printed quoted" ;; *) bad "not quoted: $OUT" ;; esac
lw "$W" "$S/AOS-1/ledger.md" 'r1\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; silent_ok; same "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"
lw "$W" "$S/AOS-1/ledger.md" 'other\n'; pt "$SYNC" "$W" "$W/.marvin/runs/$S/AOS-1/ledger.md"; pt_clash_ok "$W/.marvin/runs/$S/AOS-1/ledger.md" "$RUNS/$S/AOS-1/ledger.md"
fx_SA1 "$SYNC"; assert_rc 0; assert_only " src:gone dst:report"
fx_SA3 "$SYNC"; OUT=${OUT% src:*}; sa_clash_ok "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$SIDE"
same "$A/.marvin/runs/$S/AOS-1/$REP" "$RUNS/$S/AOS-1/$SIDE"
R="$WORK/repo"

# ── mutations: each reverts one guard in a copy (with the hook lib beside it); its fixture must then fail ──
MUT="$WORK/mut"; mkdir -p "$MUT/lib"; cp "$SCRIPT_DIR/lib/marvin-hook-lib.sh" "$MUT/lib/"
mutation() {  # mutation <name> <fixture-fn> <exact script line> <replacement> <judge token the real script leaves in OUT> [<line2> <replacement2>]
  local m="$MUT/mutant-$1.sh"
  A1="$3" B1="$4" A2="${6:-}" B2="${7:-}" awk '$0 == ENVIRON["A1"] { print ENVIRON["B1"]; next } ENVIRON["A2"] != "" && $0 == ENVIRON["A2"] { print ENVIRON["B2"]; next } { print }' "$SYNC" > "$m"
  if cmp -s "$m" "$SYNC"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  if [ -n "${6:-}" ] && ! grep -qxF -- "$7" "$m"; then bad "mutation $1: second target line not found — harness is stale"; return; fi
  "$2" "$m"
  if printf '%s\n' "$OUT" | grep -Fq -- "$5"; then bad "mutation $1 survived ($2 still left: $5)"; else ok "mutation $1 caught"; fi
}
hd "M mutations"
mutation LITERAL fx_SS2 '  [ ! -L "$b" ] && [ -f "$b" ] && grep -Fq -- "$LITERAL" "$b" 2>/dev/null || return 0' '  :' "runs:no"
mutation REUSE fx_SS3 '    [ -d "$d" ] && [ ! -L "$d" ] && is_session "${d##*/}" && { name=${d##*/}; break; }' '    :' "count:1"
mutation SEED fx_SS4 '    seed "$top" "$name"' '    :' "seeded:yes"
mutation LOCALIGNORE fx_SS1L '    bootstrap "$top"' '    :' "status:clean"
mutation SEEDKEEP fx_SS4B '      [ -e "$dst" ] || [ -L "$dst" ] && continue' '      :' "local:mine" \
                          '    if [ "$3" = yes ]; then mv -f -- "$tmp" "$2" 2>/dev/null; else mv -n -- "$tmp" "$2" 2>/dev/null; fi' '    mv -f -- "$tmp" "$2" 2>/dev/null'
mutation RUNSLINK fx_SS5 '  [ -L "$d" ] && return 1; d="$d/runs"; [ -L "$d" ] && return 1' '  [ -L "$d" ] && return 1; d="$d/runs"' "elsewhere:0" \
                         '  [ -L "$runs" ] && return 1' '  :'
mutation IGNORED fx_SS7 '  git -C "$top" check-ignore -q -- "$runs/$rel" 2>/dev/null || return 2' '  :' "count:0"
mutation PREFIX fx_PT2 '               is_prefix "$dst" "$src" || { clash "$src" "$dst"; return 0; }' '    :' "project:AAA BBB"
mutation STAMPED fx_PT3 '    stamped) if [ -e "$dst" ] || [ -L "$dst" ]; then cmp -s "$src" "$dst" || clash "$src" "$dst"; return 0; fi' '    stamped) :' "project:one" \
                        '    if [ "$3" = yes ]; then mv -f -- "$tmp" "$2" 2>/dev/null; else mv -n -- "$tmp" "$2" 2>/dev/null; fi' '    mv -f -- "$tmp" "$2" 2>/dev/null'
mutation SUBAGENT fx_PT4 '  mh_is_subagent_call && return 0' '  :' "project:no"
mutation LAYOUT fx_PT5 '  case "$rel" in */*/*/*) return 1 ;; */*/*) ;; *) return 1 ;; esac' '  :' "carried:0"
mutation LAYOUTSEG fx_PT5 '  is_session "$s" && is_key "$k" && kind "$b" >/dev/null || return 1' '  :' "carried:0"
mutation COMPLINK fx_PT8 '    seg=${r%%/*}; d="$d/$seg"; [ -L "$d" ] && return 1' '    seg=${r%%/*}; d="$d/$seg"' "elsewhere:0" \
                        '  git -C "$top" check-ignore -q -- "$runs/$rel" 2>/dev/null || return 2' '  :'   # git refuses a path beyond a symlink: the second layer
mutation MOVE fx_SA1 '    if cmp -s "$src" "$dst"; then rm -f -- "$src"; continue; fi' '    if cmp -s "$src" "$dst"; then continue; fi' "src:gone"
mutation COPY fx_SA1 '    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then put "$src" "$dst" no || { refuse "copy failed" "$dst"; continue; }; fi' '    :' "dst:report"
mutation IDENTICAL fx_SA2 '    if cmp -s "$src" "$dst"; then rm -f -- "$src"; continue; fi' '    :' "src:gone"
mutation CLASHKEEP fx_SA3 '    clash "$src" "$dst" "$side"' '    rm -f -- "$src"' "src:kept"
mutation SIDECAR fx_SA3 '    side=$(sidecar "$src" "$dst" "$tag") || side=""' '    side=""' "side:mine"
mutation ROOT fx_SA7 '  [ "$(mh_path "$top")" = "$(mh_path "$MAIN")" ] && return 0   # the project itself: nothing to carry' '  :' "dst:kept" \
                     '    [ "$src" -ef "$dst" ] && continue' '    :'
IFS= read -r CAND_LINE <<'L' || true
  cands=$(printf '%s\n' "$brief" | grep -oE "\.marvin/runs/$sre/(adhoc|$kre)/${MH_STAMP_RE#^}[A-Za-z0-9._-]*\.md" | sort -u)
L
IFS= read -r CAND_ANY <<'L' || true
  cands=$(printf '%s\n' "$brief" | grep -oE "\.marvin/runs/$sre/(adhoc|$kre)/[A-Za-z0-9._-]*\.md" | sort -u)
L
mutation STAMPONLY fx_SA8 '    [ "$(kind "${rel##*/}")" = stamped ] || continue   # mutable files are the orchestrator'"'"'s own' '    :' "ledger:kept" \
                        "$CAND_LINE" "$CAND_ANY"   # the candidate pattern is the first layer
mutation SRCLINK fx_SA9 '    no_links "$top" "$rel" && [ -f "$src" ] || continue' '    [ -e "$src" ] || continue' "dst:no"
mutation AGENTTYPE fx_SA10 "  printf '%s' \"\$atype\" | grep -Eq '^marvin:[a-z0-9-]+\$' || return 0" '  :' "src:kept"
mutation MARVIN fx_X1M '  mh_is_marvin "$MAIN"' '  :' "src:kept" \
                       '  mh_is_marvin "$1" && no_links "$1" "" || return 1' '  :'

printf '\n----\ntest-runs-sync: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
