#!/usr/bin/env bash
# test-worktree-sweep.sh — behavioural tests for scripts/marvin-worktree-sweep.sh (AOS-196, AOS-223).
# Real repos in a temp dir: a bare origin, a clone carrying .marvin/ (PROJECT-INFO worktree_sweep: on),
# and agent worktrees under .claude/worktrees/, each MARKED as Marvin's unless the fixture says
# otherwise. One fixture per keep-guard (G1–G9) asserting its NAMED reason (git's own refusal must not
# mask a missing guard), removal fixtures, scope (marked only), the worktree_sweep mode, --check, --hook,
# and the report-only --at-risk mode (AR*: G8/G9 conditions on EVERY worktree under .claude/worktrees/).
# A fixture whose real output is silent appends a `state: kept|gone` line, so a mutation can be judged.
# The mutation section reverts each guard line in a copy; the guard's fixture must then fail.
# Run from anywhere: bash scripts/test-worktree-sweep.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SWEEP="$SCRIPT_DIR/marvin-worktree-sweep.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-wstest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT

# Isolate git from the user's config (commit signing, hooks, default branch name).
export HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc()     { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1"; fi; }
assert_out()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1 (got: $(printf '%s' "$OUT" | head -c 200))"; fi; }
assert_no_out() { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "out must not have: $1"; else ok "out free of: $1"; fi; }
assert_empty()  { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 200)"; fi; }
assert_only()   { if [ "$OUT" = "$1" ]; then ok "output is exactly: $1"; else bad "output is not exactly: $1 (got: $(printf '%s' "$OUT" | head -c 200))"; fi; }
assert_gone()   { if [ ! -e "$1" ]; then ok "removed: ${1#"$WORK"/}"; else bad "still there: ${1#"$WORK"/}"; fi; }
assert_there()  { if [ -d "$1" ]; then ok "still there: ${1#"$WORK"/}"; else bad "wrongly removed: ${1#"$WORK"/}"; fi; }
assert_branch()    { if git -C "$R" show-ref --verify --quiet "refs/heads/$1"; then ok "branch $1 kept"; else bad "branch $1 missing"; fi; }
assert_no_branch() { if git -C "$R" show-ref --verify --quiet "refs/heads/$1"; then bad "branch $1 still exists"; else ok "branch $1 deleted"; fi; }

R="$WORK/repo"; O="$WORK/origin.git"; WT="$WORK/repo/.claude/worktrees"

fresh() {  # a bare origin + a Marvin clone with main, develop (both pushed) and a local feature branch
  rm -rf "$R" "$O" "$WORK/outside" "$WORK/real"
  git init -q --bare "$O"
  git init -q "$R"
  echo base > "$R/base.txt"
  git -C "$R" add base.txt && git -C "$R" commit -q -m base
  git -C "$R" remote add origin "$O"
  git -C "$R" branch develop && git -C "$R" branch feat
  git -C "$R" push -q origin main develop 2>/dev/null
  mkdir -p "$R/.marvin" "$WT"
  setmode on
}
setmode() {  # setmode <on|check|off|any value|-> — PROJECT-INFO frontmatter worktree_sweep; - = key absent
  if [ "$1" = - ]; then printf -- '---\nproject: t\n---\n' > "$R/.marvin/PROJECT-INFO.md"
  else printf -- '---\nproject: t\nworktree_sweep: %s\n---\n' "$1" > "$R/.marvin/PROJECT-INFO.md"; fi
}
MARKLINE='marvin-owned marvin:developer a7bf0dd563169ef8d 20261019T120000Z'
mark()  { printf '%s\n' "$MARKLINE" > "$(git -C "$1" rev-parse --absolute-git-dir)/marvin-owned"; }   # mark <worktree>
mkwt()  { git -C "$R" worktree add -q -b "$1" "$WT/$1" "$2" && mark "$WT/$1"; }  # mkwt <name> <base> — a MARKED worktree
state() { OUT="${OUT}${OUT:+$'\n'}state: $(if [ -d "$1" ]; then echo kept; else echo gone; fi)"; }  # state <worktree>
work()  { echo "$2" > "$1/$2.txt"; git -C "$1" add "$2.txt"; git -C "$1" commit -q -m "$2"; }  # work <dir> <tag>
merge_into() {  # merge_into <parent> <branch> — merged in the main checkout, which then returns to main
  git -C "$R" checkout -q "$1" && git -C "$R" merge -q --no-ff -m "merge $2" "$2" && git -C "$R" checkout -q main
}
age() {  # age <worktree> — backdate it and its git admin dir past the 15-minute idle window
  local gd; gd=$(git -C "$1" rev-parse --absolute-git-dir)
  find "$1" "$gd" -exec touch -t 202001010000 {} +
}
sweep() {  # sweep <script> [args…] — run from the main checkout
  local s="$1"; shift
  OUT=$(cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$s" "$@" </dev/null 2>&1); RC=$?
}

# ── keep-guard fixtures: each takes the script to run, so the mutation section can reuse it ──
fx_G1() { fresh; mkwt g1 develop; work "$WT/g1" g1; merge_into develop g1; git -C "$R" worktree lock "$WT/g1"; age "$WT/g1"; sweep "$1"; }
fx_G2() { fresh; mkwt g2 develop; work "$WT/g2" g2; merge_into develop g2; age "$WT/g2"
          OUT=$(cd "$WT/g2" && CLAUDE_PROJECT_DIR="$R" bash "$1" </dev/null 2>&1); RC=$?; }
fx_G3() { fresh; mkwt g3 develop; work "$WT/g3" g3; merge_into develop g3; echo junk > "$WT/g3/untracked.txt"; age "$WT/g3"; sweep "$1"; }
fx_G4() { fresh; mkwt g4 develop; work "$WT/g4" g4; merge_into develop g4
          git -C "$R" rev-parse develop > "$(git -C "$WT/g4" rev-parse --absolute-git-dir)/MERGE_HEAD"; age "$WT/g4"; sweep "$1"; }
fx_G5() { fresh; mkwt g5 develop; work "$WT/g5" g5; git -C "$WT/g5" push -q origin g5 2>/dev/null; age "$WT/g5"; sweep "$1"; }
fx_G6() { fresh; mkwt g6 develop; work "$WT/g6" g6; merge_into develop g6; sweep "$1"; }
fx_IDX() { fx_G5 "$1"; sweep "$1"; }   # a second sweep inside the window must still report G5, not G6
fx_PR() { fresh; mkwt pr develop; work "$WT/pr" pr; merge_into develop pr; age "$WT/pr"   # its .git file gone: git lists it prunable
          rm -f "$WT/pr/.git"; touch -t 202001010000 "$WT/pr"; sweep "$1"; }
fx_LAG() { fresh; mkwt lag develop; work "$WT/lag" l1; git -C "$WT/lag" push -q origin lag 2>/dev/null
           work "$WT/lag" l2; merge_into develop lag; age "$WT/lag"; sweep "$1"; }   # origin/lag stops at l1
IN="$WT/d/.claude/worktrees/agent-x"
outer() {  # outer <ignored dir> — worktree d, otherwise removable: merged, clean (the dir is git-ignored)
  fresh; mkwt d develop; printf '%s\n' "$1" > "$WT/d/.gitignore"; git -C "$WT/d" add .gitignore; work "$WT/d" d; merge_into develop d
}
fx_G7() { outer .claude/worktrees/; git -C "$WT/d" worktree add -q -b agent-x "$IN" develop; mark "$IN"   # inner worktree, untracked work
          echo wip > "$IN/wip.txt"; age "$IN"; age "$WT/d"; sweep "$1"; }
fx_G7P() { outer .claude/worktrees/; git -C "$WT/d" worktree add -q -b agent-x "$IN" develop; mark "$IN"; echo wip > "$IN/wip.txt"
           age "$IN"; age "$WT/d"; rm -f "$IN/.git"; touch -t 202001010000 "$IN"; sweep "$1"; }   # inner prunable: no .git left
fx_G7R() { outer vendor/; git init -q "$WT/d/vendor/lib"; echo wip > "$WT/d/vendor/lib/wip.txt"; age "$WT/d"; sweep "$1"; }  # ignored clone
envwt() {  # envwt <name> — a marked, merged worktree that git-ignores .env, .env.*, .envrc and build.log
  fresh; mkwt "$1" develop; printf '.env\n.env.*\n.envrc\nbuild.log\n' > "$WT/$1/.gitignore"; git -C "$WT/$1" add .gitignore
  work "$WT/$1" "$1"; merge_into develop "$1"
}
fx_G8a() { envwt e8a; echo S=1 > "$WT/e8a/.env"; echo S=1 > "$R/.env"; echo log > "$WT/e8a/build.log"; echo x > "$WT/e8a/.envrc"
           age "$WT/e8a"; sweep "$1"; state "$WT/e8a"; }   # build.log and .envrc: ignored, absent from main, not G8's
fx_G8b() { envwt e8b; echo S=1 > "$WT/e8b/.env.local"; echo S=2 > "$R/.env.local"; age "$WT/e8b"; sweep "$1"; state "$WT/e8b"; }
fx_G8c() { envwt e8c; echo S=1 > "$WT/e8c/.env"; age "$WT/e8c"; sweep "$1"; state "$WT/e8c"; }
fx_G8d() { envwt e8d; mkdir -p "$WT/e8d/app" "$R/app"; echo S=1 > "$WT/e8d/app/.env"; echo S=2 > "$R/app/.env"; age "$WT/e8d"; sweep "$1"; state "$WT/e8d"; }
fx_G8n() {  # a wholly ignored dependency folder is never descended into: its .env files are not G8's
  envwt e8n; printf '.env\n.env.*\nnode_modules/\n.venv\n' > "$WT/e8n/.gitignore"; git -C "$WT/e8n" commit -qam deps; merge_into develop e8n
  mkdir -p "$WT/e8n/node_modules/x" "$WT/e8n/.venv/lib"; echo S=1 > "$WT/e8n/node_modules/x/.env"; echo S=1 > "$WT/e8n/.venv/lib/.env.local"
  age "$WT/e8n"; sweep "$1"; state "$WT/e8n"; }
S9=20261019T120000Z-0123abcd-0123-4567-89ab-0123456789ab
runwt() {  # runwt <name> — a marked, merged worktree holding an ignored run file .marvin/runs/$S9/K-1/x.md
  fresh; mkwt "$1" develop; work "$WT/$1" "$1"; merge_into develop "$1"
  mkdir -p "$WT/$1/.marvin/runs/$S9/K-1" "$R/.marvin/runs"
  printf '*\n' > "$WT/$1/.marvin/runs/.gitignore"; printf '*\n' > "$R/.marvin/runs/.gitignore"
  echo report > "$WT/$1/.marvin/runs/$S9/K-1/x.md"
}
fx_G9()  { runwt g9; age "$WT/g9"; sweep "$1"; state "$WT/g9"; }                       # not in the project
fx_G9c() { runwt g9c; mkdir -p "$R/.marvin/runs/$S9/K-1"; echo other > "$R/.marvin/runs/$S9/K-1/x.md"; age "$WT/g9c"; sweep "$1"; state "$WT/g9c"; }  # differs
fx_G9b() { runwt g9b; mkdir -p "$R/.marvin/runs/$S9/K-1"; echo report > "$R/.marvin/runs/$S9/K-1/x.md"; age "$WT/g9b"; sweep "$1"; state "$WT/g9b"; }  # identical
fx_G9g() { runwt g9g; mkdir -p "$R/.marvin/runs/$S9/K-1"; echo report > "$R/.marvin/runs/$S9/K-1/x.md"   # only .marvin/runs/.gitignore differs
           printf '*\n# local\n' > "$WT/g9g/.marvin/runs/.gitignore"; age "$WT/g9g"; sweep "$1" "${@:2}"; state "$WT/g9g"; }
fx_SC3() {  # an UNMARKED worktree that is prunable, and one whose directory is gone: skipped, no prune advice
  fresh; local n; for n in up um; do git -C "$R" worktree add -q -b "$n" "$WT/$n" develop; done
  rm -f "$WT/up/.git"; rm -rf "$WT/um"; sweep "$1"; }
fx_AR1() {  # --at-risk: an UNMARKED worktree whose ignored .env differs from the main checkout's is listed
  envwt ar1; rm -f "$(git -C "$WT/ar1" rev-parse --absolute-git-dir)/marvin-owned"; echo S=1 > "$WT/ar1/.env"; echo S=2 > "$R/.env"; sweep "$1" --at-risk; state "$WT/ar1"; }
fx_AR2() {  # --at-risk: unmarked run state the project lacks is listed (G9)
  runwt ar2; rm -f "$(git -C "$WT/ar2" rev-parse --absolute-git-dir)/marvin-owned"; sweep "$1" --at-risk; state "$WT/ar2"; }
fx_SC1() { fresh; git -C "$R" worktree add -q -b sc1 "$WT/sc1" develop; work "$WT/sc1" sc1; merge_into develop sc1; age "$WT/sc1"; sweep "$1" "${@:2}"; state "$WT/sc1"; }
fx_SC2() {  # a malformed marker, a valid line that is not the first, a symlinked valid marker: all unmarked
  local n gd; fresh; printf '%s\n' "$MARKLINE" > "$WORK/goodmarker"
  for n in bad late lnk; do git -C "$R" worktree add -q -b "$n" "$WT/$n" develop; work "$WT/$n" "$n"; merge_into develop "$n"; done
  gd=$(git -C "$WT/bad" rev-parse --absolute-git-dir); printf 'marvin-owned someone 1234 now\n' > "$gd/marvin-owned"
  gd=$(git -C "$WT/late" rev-parse --absolute-git-dir); printf 'junk\n%s\n' "$MARKLINE" > "$gd/marvin-owned"
  gd=$(git -C "$WT/lnk" rev-parse --absolute-git-dir); ln -s "$WORK/goodmarker" "$gd/marvin-owned"
  for n in bad late lnk; do age "$WT/$n"; done; touch -h -t 202001010000 "$gd/marvin-owned"; sweep "$1"   # touch follows a link: age the link itself
}
fx_MD() { fresh; setmode "$2"; mkwt md develop; work "$WT/md" md; merge_into develop md; age "$WT/md"; sweep "$1" "${@:3}"; state "$WT/md"; }  # fx_MD <script> <mode> [args]
fx_MD1() { fx_MD "$1" - --hook; }
fx_MD2() { fx_MD "$1" off --hook; }
fx_W1() {  # hook stdin cwd JSON-escaped (every / as \/): only a real JSON decoder sees the worktree the session stands in
  local e; fresh; mkwt w1 develop; work "$WT/w1" w1; merge_into develop w1; age "$WT/w1"
  e=$(printf '%s' "$WT/w1" | sed 's,/,\\/,g')
  OUT=$(cd "$R" && printf '{"session_id":"s","hook_event_name":"SessionStart","cwd":"%s"}' "$e" \
        | CLAUDE_PROJECT_DIR="$R" bash "$1" --hook 2>&1); RC=$?; state "$WT/w1"
}

hd "G1 a locked worktree is kept"
fx_G1 "$SWEEP"; assert_rc 0; assert_out "kept: $WT/g1 — G1 locked"; assert_there "$WT/g1"

hd "G2 the worktree a session stands in is kept (cwd, then hook stdin cwd)"
fx_G2 "$SWEEP"; assert_out "kept: $WT/g2 — G2 current checkout"; assert_there "$WT/g2"
OUT=$(cd "$R" && printf '{"session_id":"s","hook_event_name":"SessionStart","cwd":"%s"}' "$WT/g2" \
      | CLAUDE_PROJECT_DIR="$R" bash "$SWEEP" --hook 2>&1); RC=$?
assert_rc 0; assert_empty; assert_there "$WT/g2"

hd "G3 uncommitted or untracked changes keep it"
fx_G3 "$SWEEP"; assert_out "kept: $WT/g3 — G3 uncommitted or untracked changes"; assert_there "$WT/g3"

hd "G4 an operation in progress keeps it"
fx_G4 "$SWEEP"; assert_out "kept: $WT/g4 — G4"; assert_there "$WT/g4"

hd "G5 pushed but never merged — its own origin copy does not count as landed"
fx_G5 "$SWEEP"; assert_out "kept: $WT/g5 — G5 commits not in any other branch"; assert_there "$WT/g5"; assert_branch g5

hd "G6 recent activity keeps it"
fx_G6 "$SWEEP"; assert_out "kept: $WT/g6 — G6 active in the last 15 min"; assert_there "$WT/g6"

hd "IDX a second sweep inside the window still names the real guard (status writes no index)"
fx_IDX "$SWEEP"; assert_out "kept: $WT/g5 — G5"; assert_no_out "G6"

hd "G7 a worktree holding another worktree or a repository is kept, and so is what is inside it"
fx_G7 "$SWEEP"; assert_rc 0; assert_out "kept: $WT/d — G7 another worktree or repository inside it"; assert_out "kept: $IN — G3"
assert_there "$WT/d"; assert_there "$IN"
if [ -f "$IN/wip.txt" ]; then ok "inner work survives"; else bad "inner work deleted"; fi
sweep "$SWEEP" --check; assert_no_out "would remove: $WT/d"; assert_out "kept: $WT/d — G7"
fx_G7P "$SWEEP"; assert_out "kept: $WT/d — G7"; if [ -f "$IN/wip.txt" ]; then ok "prunable inner's work survives"; else bad "prunable inner's work deleted"; fi
fx_G7R "$SWEEP"; assert_out "kept: $WT/d — G7"; if [ -f "$WT/d/vendor/lib/wip.txt" ]; then ok "nested clone survives"; else bad "nested clone deleted"; fi

hd "R1 sub-branch merged into a LOCAL feature branch, pushed — removed, local branch deleted"
fresh; mkwt sub feat; work "$WT/sub" sub; git -C "$WT/sub" push -q -u origin sub 2>/dev/null; merge_into feat sub; age "$WT/sub"
if [ "$(git -C "$R" config --get branch.sub.remote)" = origin ]; then ok "push -u set branch.sub.remote"; else bad "push -u did not set branch.sub.remote"; fi
sweep "$SWEEP"; assert_rc 0; assert_out "removed: $WT/sub (branch sub deleted)"; assert_gone "$WT/sub"; assert_no_branch sub
if [ -z "$(git -C "$R" config --get branch.sub.remote)" ]; then ok "branch.sub config removed"; else bad "branch.sub config left behind"; fi
if git -C "$O" show-ref --verify --quiet refs/heads/sub; then ok "remote branch untouched"; else bad "remote branch deleted"; fi

hd "R5 origin holds only an older copy of the branch — removed, branch kept (origin copy is behind)"
fx_LAG "$SWEEP"; assert_rc 0; assert_out "removed: $WT/lag (branch lag kept: origin copy is behind)"; assert_gone "$WT/lag"; assert_branch lag

hd "R2 merged into develop, never pushed — removed, branch kept (no origin copy)"
fresh; mkwt r2 develop; work "$WT/r2" r2; merge_into develop r2; age "$WT/r2"
sweep "$SWEEP"; assert_out "removed: $WT/r2 (branch r2 kept: no origin copy)"; assert_gone "$WT/r2"; assert_branch r2

hd "R3 detached HEAD contained in main — removed"
fresh; git -C "$R" worktree add -q --detach "$WT/det" main; mark "$WT/det"; age "$WT/det"
sweep "$SWEEP"; assert_out "removed: $WT/det"; assert_gone "$WT/det"

hd "R4 a directory name with a space is printed encoded"
fresh; git -C "$R" worktree add -q -b spaced "$WT/my wt" develop; mark "$WT/my wt"; work "$WT/my wt" sp; merge_into develop spaced; age "$WT/my wt"
sweep "$SWEEP"; assert_out "removed: \"$WT/my wt\" (branch spaced kept: no origin copy)"; assert_gone "$WT/my wt"

hd "P1 a prunable entry (its .git file gone) is reported, never touched"
fx_PR "$SWEEP"; assert_rc 0; assert_out "kept: $WT/pr — prunable"; assert_there "$WT/pr"
sweep "$SWEEP" --check; assert_no_out "would remove"; assert_out "kept: $WT/pr — prunable"; assert_there "$WT/pr"

hd "P2 a prunable entry whose directory is gone prints exactly one kept line"
fresh; mkwt pm develop; work "$WT/pm" pm; merge_into develop pm; age "$WT/pm"; rm -rf "$WT/pm"
sweep "$SWEEP"; assert_rc 0; assert_out "kept: $WT/pm — "
if [ "$(printf '%s\n' "$OUT" | grep -Fc -- "$WT/pm")" = 1 ]; then ok "exactly one line"; else bad "not exactly one line for the path"; fi

hd "S1 a worktree outside .claude/worktrees/ is never touched or reported"
fresh; git -C "$R" worktree add -q -b outside "$WORK/outside" develop; work "$WORK/outside" out; merge_into develop outside; age "$WORK/outside"
sweep "$SWEEP"; assert_rc 0; assert_no_out "outside"; assert_there "$WORK/outside"

hd "S2 a symlinked .claude/worktrees is refused, never followed"
fresh; rm -rf "$WT"; mkdir -p "$WORK/real"; ln -s "$WORK/real" "$WT"
sweep "$SWEEP"; assert_rc 1; assert_out "refused:"

hd "S3 no .claude/worktrees directory — nothing to do"
fresh; rm -rf "$R/.claude"; sweep "$SWEEP"; assert_rc 0; assert_empty

hd "C1 --check reports and changes nothing"
fresh; mkwt c1 develop; work "$WT/c1" c1; merge_into develop c1; age "$WT/c1"
sweep "$SWEEP" --check; assert_rc 0; assert_out "would remove: $WT/c1"; assert_there "$WT/c1"; assert_branch c1

hd "H1 --hook prints one summary line when it removed something"
fresh; mkwt h1 develop; work "$WT/h1" h1; merge_into develop h1; age "$WT/h1"
sweep "$SWEEP" --hook; assert_rc 0; assert_out "Marvin: removed 1 finished agent worktree(s) under .claude/worktrees/: h1"
if [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]; then ok "exactly one line"; else bad "more than one line"; fi

hd "H2 --hook is silent when nothing was removed"
fx_G6 "$SWEEP"; sweep "$SWEEP" --hook; assert_rc 0; assert_empty

hd "H3 --hook does nothing outside a Marvin project"
fresh; rm -rf "$R/.marvin"; mkwt h3 develop; work "$WT/h3" h3; merge_into develop h3; age "$WT/h3"
sweep "$SWEEP" --hook; assert_rc 0; assert_empty; assert_there "$WT/h3"
sweep "$SWEEP" --check; assert_rc 0; assert_no_out "Marvin: worktree sweep is"   # a hand run there names no mode

hd "H4 --hook outside git exits 0 silently; the CLI exits 2"
mkdir -p "$WORK/plain"
OUT=$(cd "$WORK/plain" && CLAUDE_PROJECT_DIR="$WORK/plain" bash "$SWEEP" --hook </dev/null 2>&1); RC=$?; assert_rc 0; assert_empty
OUT=$(cd "$WORK/plain" && CLAUDE_PROJECT_DIR="$WORK/plain" bash "$SWEEP" </dev/null 2>&1); RC=$?; assert_rc 2; assert_out "not a git repository"

hd "U1 an unknown option is a usage error"
sweep "$SWEEP" --bogus; assert_rc 2; assert_out "usage"

SKIP1="skipped: 1 worktree(s) not marked by Marvin — left to the app"
hd "SC1 an unmarked, clean, landed, idle worktree is out of scope: kept, one skipped line by hand, silent in --hook"
fx_SC1 "$SWEEP"; assert_rc 0; assert_out "$SKIP1"; assert_no_out "$WT/sc1"; assert_there "$WT/sc1"; assert_branch sc1
fx_SC1 "$SWEEP" --check; assert_out "$SKIP1"; assert_no_out "would remove"
fx_SC1 "$SWEEP" --hook; assert_rc 0; assert_only "state: kept"
fresh; mkwt mk develop; work "$WT/mk" mk; merge_into develop mk; age "$WT/mk"
sweep "$SWEEP"; assert_out "removed: $WT/mk"; assert_no_out "skipped:"   # no skipped line when nothing was skipped

hd "SC2 a malformed marker, a valid line that is not the first, a symlinked marker: all unmarked"
fx_SC2 "$SWEEP"; assert_rc 0; assert_out "skipped: 3 worktree(s) not marked by Marvin — left to the app"; assert_no_out "removed:"
assert_there "$WT/bad"; assert_there "$WT/late"; assert_there "$WT/lnk"

hd "SC3 an unmarked prunable or missing worktree is skipped — no kept line, no prune advice"
fx_SC3 "$SWEEP"; assert_rc 0; assert_out "skipped: 2 worktree(s) not marked by Marvin — left to the app"; assert_no_out "kept:"; assert_no_out "prune"
fresh; git -C "$R" worktree add -q -b ul "$WT/ul-real" develop; mv "$WT/ul-real" "$WORK/real"; ln -s "$WORK/real" "$WT/ul-real"
sweep "$SWEEP"; assert_out "skipped: 1 worktree(s) not marked by Marvin"; assert_no_out "never followed"   # an unmarked symlink entry
fresh; git -C "$R" worktree add -q -b ml "$WT/ml-real" develop; mark "$WT/ml-real"; mv "$WT/ml-real" "$WORK/real"; ln -s "$WORK/real" "$WT/ml-real"
sweep "$SWEEP"; assert_out "kept: $WT/ml-real — symlink — never followed"; assert_no_out "skipped:"   # a marked one keeps its line

hd "MD1 worktree_sweep absent: --hook is check mode — nothing removed, one summary line"
fx_MD1 "$SWEEP"; assert_rc 0; assert_out "state: kept"; assert_branch md
assert_only "Marvin: worktree sweep in check mode — would remove 1: md"$'\n'"state: kept"
fresh; setmode check; mkwt g6 develop; work "$WT/g6" g6; merge_into develop g6; sweep "$SWEEP" --hook; assert_empty   # check mode, only a G6 keep: silent

hd "MD2 worktree_sweep: off — --hook is silent and removes nothing"
fx_MD2 "$SWEEP"; assert_rc 0; assert_only "state: kept"

hd "MD3 an invalid worktree_sweep is check mode, and the summary names the value"
fx_MD "$SWEEP" bogus --hook; assert_rc 0; assert_out "state: kept"
assert_out "Marvin: worktree sweep in check mode — would remove 1: md (invalid worktree_sweep: bogus)"
fx_MD "$SWEEP" CHECK --hook; assert_out "would remove 1: md"; assert_no_out "invalid"   # case-insensitive, valid
fx_MD "$SWEEP" On --hook; assert_out "Marvin: removed 1 finished agent worktree(s) under .claude/worktrees/: md"; assert_out "state: gone"

hd "MD4 a hand run always sweeps, and names a mode that is not on"
fx_MD "$SWEEP" off; assert_rc 0; assert_out "removed: $WT/md"; assert_out "state: gone"
assert_out "Marvin: worktree sweep is off (worktree_sweep in .marvin/PROJECT-INFO.md)"
fx_MD "$SWEEP" - --check; assert_out "would remove: $WT/md"; assert_out "Marvin: worktree sweep is check (worktree_sweep in .marvin/PROJECT-INFO.md)"
fx_MD "$SWEEP" bogus; assert_out "removed: $WT/md"; assert_out "Marvin: worktree sweep is check (worktree_sweep in .marvin/PROJECT-INFO.md)"
fx_MD "$SWEEP" on; assert_out "removed: $WT/md"; assert_no_out "Marvin: worktree sweep is"
fx_MD "$SWEEP" off --hook --check; assert_only "state: kept"   # off wins over --check in a hook

hd "G8 an ignored .env / .env.* keeps the worktree unless the main checkout holds the same bytes"
fx_G8a "$SWEEP"; assert_rc 0; assert_out "removed: $WT/e8a"; assert_out "state: gone"
fx_G8b "$SWEEP"; assert_out "kept: $WT/e8b — G8 ignored .env.local differs from the main checkout"; assert_out "state: kept"
fx_G8c "$SWEEP"; assert_out "kept: $WT/e8c — G8 ignored .env absent from the main checkout"; assert_out "state: kept"
fx_G8d "$SWEEP"; assert_out "kept: $WT/e8d — G8 ignored app/.env differs from the main checkout"; assert_out "state: kept"
fx_G8b "$SWEEP" --check; assert_out "kept: $WT/e8b — G8"; assert_no_out "would remove"
fx_G8n "$SWEEP"; assert_out "removed: $WT/e8n"; assert_out "state: gone"; assert_no_out "G8"   # node_modules/x/.env, .venv/lib/.env.local: not descended into

hd "G9 an ignored run file under .marvin/runs/ keeps the worktree unless the project holds the same bytes"
fx_G9 "$SWEEP";  assert_out "kept: $WT/g9 — G9 run state not in the project: .marvin/runs/$S9/K-1/x.md"; assert_out "state: kept"
fx_G9c "$SWEEP"; assert_out "kept: $WT/g9c — G9 run state not in the project"; assert_out "state: kept"
fx_G9b "$SWEEP"; assert_out "removed: $WT/g9b"; assert_out "state: gone"
fx_G9g "$SWEEP"; assert_out "removed: $WT/g9g"; assert_out "state: gone"; assert_no_out "G9"   # .marvin/runs/.gitignore is not run state

hd "AR1 --at-risk lists every worktree with a G8 or G9 condition, marked or NOT, and removes nothing"
fx_AR1 "$SWEEP"; assert_rc 0; assert_only "at-risk: $WT/ar1 — G8 ignored .env differs from the main checkout"$'\n'"state: kept"
fx_AR2 "$SWEEP"; assert_rc 0; assert_only "at-risk: $WT/ar2 — G9 run state not in the project: .marvin/runs/$S9/K-1/x.md"$'\n'"state: kept"
fresh; git -C "$R" worktree add -q -b clean "$WT/clean" develop; work "$WT/clean" c; mkwt mk develop; work "$WT/mk" mk; merge_into develop mk; age "$WT/mk"
sweep "$SWEEP" --at-risk; assert_rc 0; assert_empty; assert_there "$WT/clean"; assert_there "$WT/mk"   # clean ones: no line; a removable marked one: untouched
fx_G9g "$SWEEP" --at-risk; assert_only "state: kept"   # the runs .gitignore never counts
fresh; envwt arh; echo S=1 > "$WT/arh/.env"; OUT=$(cd "$R" && CLAUDE_PROJECT_DIR="$R" bash "$SWEEP" --at-risk --hook </dev/null 2>&1); RC=$?
assert_rc 0; assert_empty   # never in --hook mode
R0=$R; R="$WORK/my repo"; WT="$R/.claude/worktrees"; fx_AR1 "$SWEEP"; assert_out "at-risk: \"$WT/ar1\" — G8"; rm -rf "$R"; R=$R0; WT="$R/.claude/worktrees"

hd "W1 a JSON-escaped hook stdin cwd still names the worktree the session stands in (G2)"
fx_W1 "$SWEEP"; assert_rc 0; assert_only "state: kept"; assert_branch w1

# ── mutations: each reverts one guard in a copy (the hook lib beside it); the guard's fixture must then fail ──
MUT="$WORK/mut"; mkdir -p "$MUT/lib"; cp "$SCRIPT_DIR/lib/marvin-hook-lib.sh" "$MUT/lib/"
mutation() {  # mutation <name> <fixture-fn> <exact script line> <replacement> <text the real script prints>
  local m="$MUT/mutant-$1.sh"
  A="$3" B="$4" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$SWEEP" > "$m"   # ENVIRON: no escape processing
  if cmp -s "$m" "$SWEEP"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  "$2" "$m"
  if printf '%s\n' "$OUT" | grep -Fq -- "$5"; then bad "mutation $1 survived ($2 still printed: $5)"; else ok "mutation $1 caught"; fi
}
hd "M mutations"
mutation G1 fx_G1 '  [ -n "$locked" ] && { keep "$p" "G1 locked"; return; }' '  :' "G1 locked"
mutation G2 fx_G2 '  is_current "$p_phys" && { keep "$p" "G2 current checkout"; return; }' '  :' "G2 current checkout"
mutation G3 fx_G3 '  [ -n "$st" ] && { keep "$p" "G3 uncommitted or untracked changes"; return; }' '  :' "G3 uncommitted"
mutation G4 fx_G4 '  in_progress "$gd" && { keep "$p" "G4 merge, rebase, cherry-pick, revert or bisect in progress"; return; }' '  :' "G4"
mutation G5 fx_G5 '  landed "$sha" "$b" || { keep "$p" "G5 commits not in any other branch"; return; }' '  :' "G5 commits"
mutation G6 fx_G6 '  recent "$p" "$gd" && { keep "$p" "G6 active in the last $IDLE_MIN min"; return; }' '  :' "G6 active"
mutation G7 fx_G7 '  nested "$p" "$p_phys" && { keep "$p" "G7 another worktree or repository inside it"; return; }' '  :' "G7 another"
mutation G7LISTED fx_G7P '    case "$op/" in "$w2"/?*|"$w1"/?*) return 0 ;; esac   # a listed worktree, prunable ones too' '    :' "G7 another"
mutation G7REPO fx_G7R '  [ -n "$(find "$1" -mindepth 2 -name .git -print -quit 2>/dev/null)" ]   # a clone or submodule' '  false' "G7 another"
mutation NOLOCK fx_IDX '  st=$(git -C "$p" --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null) || { keep "$p" "G3 status unreadable"; return; }' \
                       '  st=$(git -C "$p" status --porcelain --untracked-files=all 2>/dev/null) || { keep "$p" "G3 status unreadable"; return; }' "G5 commits"
mutation PRUNABLE fx_PR '    keep "$p" "prunable — run git worktree prune"; return; fi' '    fi' "— prunable"
mutation ORIGBEHIND fx_LAG '      if ! git -C "$ROOT" merge-base --is-ancestor "$sha" "refs/remotes/origin/$b" 2>/dev/null; then note=" (branch $(q "$b") kept: origin copy is behind)"' \
                           '      if false; then note=""' "origin copy is behind"
mutation SCOPE fx_SC1 '  mh_is_marked "$p" || { skipped; return 0; }   # not Marvin'"'"'s: left to the app' '  :' "skipped: 1"
mutation SCOPEPRUNE fx_SC3 '  if [ -n "$prunable" ]; then entry_marked || { skipped; return 0; }' '  if [ -n "$prunable" ]; then' "skipped: 2"
mutation SCOPEMISSING fx_SC3 '    entry_marked || { skipped; return 0; }; keep "$p" "missing — run git worktree prune"; return 0; }' '    keep "$p" "missing — run git worktree prune"; return 0; }' "skipped: 2"
mutation G8DIR fx_G8n '  git -C "$1" ls-files -z --others --ignored --exclude-standard --directory -- '"':(glob)**/.env' ':(glob)**/.env.*'"' 2>/dev/null | {' \
                      '  git -C "$1" ls-files -z --others --ignored --exclude-standard -- '"':(glob)**/.env' ':(glob)**/.env.*'"' 2>/dev/null | {' "state: gone"
mutation G9IGNORE fx_G9g '      case "$f" in .marvin/runs/.gitignore) continue ;; .marvin/runs/?*) ;; *) continue ;; esac' '      case "$f" in .marvin/runs/?*) ;; *) continue ;; esac' "state: gone"
mutation ATRISK fx_AR1 '      why=$(g8 "$p") && why=$(g9 "$p") && return 0' '      return 0' "at-risk: $WT/ar1"
mutation ATRISKG9 fx_AR2 '      why=$(g8 "$p") && why=$(g9 "$p") && return 0' '      why=$(g8 "$p") && return 0' "at-risk: $WT/ar2"
mutation ATRISKONLY fx_AR1 '  if [ "$ATRISK" = 1 ]; then   # report only, marked or not; a prunable entry has no checkout git can list' '  if false; then' "at-risk: $WT/ar1"
mutation G8 fx_G8b '  why=$(g8 "$p") || { keep "$p" "$why"; return; }' '  :' "G8 ignored .env.local differs"
mutation G8ABSENT fx_G8c '      if [ ! -e "$ROOT/$f" ] && [ ! -L "$ROOT/$f" ]; then printf '"'"'G8 ignored %s absent from the main checkout'"'"' "$(q "$f")"; exit 1; fi' '      :' "G8 ignored .env absent"
mutation G8DEPTH fx_G8d '  git -C "$1" ls-files -z --others --ignored --exclude-standard --directory -- '"':(glob)**/.env' ':(glob)**/.env.*'"' 2>/dev/null | {' \
                        '  git -C "$1" ls-files -z --others --ignored --exclude-standard --directory -- .env .env.* 2>/dev/null | {' "G8 ignored app/.env"
mutation G9 fx_G9 '  why=$(g9 "$p") || { keep "$p" "$why"; return; }' '  :' "G9 run state"
mutation G9CMP fx_G9c '      [ -n "$RUNS" ] && cmp -s "$1/$f" "$RUNS/${f#.marvin/runs/}" || { printf '"'"'G9 run state not in the project: %s'"'"' "$(q "$f")"; exit 1; }' \
                      '      [ -n "$RUNS" ] && [ -e "$RUNS/${f#.marvin/runs/}" ] || { printf '"'"'G9 run state not in the project: %s'"'"' "$(q "$f")"; exit 1; }' "G9 run state"
mutation MODE-OFF fx_MD2 '  [ "$SWEEP_MODE" = off ] && exit 0' '  :' "state: kept"
mutation MODE-CHECK fx_MD1 '  [ "$SWEEP_MODE" = check ] && MODE=check' '  :' "would remove 1: md"
mutation MODE-DEFAULT fx_MD1 'mh_mode "$fm" worktree_sweep "on check off" check >/dev/null; SWEEP_MODE=$MH_MODE; SWEEP_INVALID=$MH_MODE_INVALID' \
                             'mh_mode "$fm" worktree_sweep "on check off" on >/dev/null; SWEEP_MODE=$MH_MODE; SWEEP_INVALID=$MH_MODE_INVALID' "would remove 1: md"
mutation MHGET fx_W1 '  HOOK_CWD=$(printf '"'"'%s'"'"' "$MH_IN" | mh_get cwd 2>/dev/null) || HOOK_CWD=""' \
                     '  HOOK_CWD=$(printf '"'"'%s'"'"' "$MH_IN" | grep -o '"'"'"cwd"[[:space:]]*:[[:space:]]*"[^"]*"'"'"' | head -n1 | sed -E '"'"'s/^"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//'"'"')' "state: kept"

printf '\n----\ntest-worktree-sweep: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
