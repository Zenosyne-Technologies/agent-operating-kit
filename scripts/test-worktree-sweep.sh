#!/usr/bin/env bash
# test-worktree-sweep.sh — behavioural tests for scripts/marvin-worktree-sweep.sh (AOS-196).
# Real repos in a temp dir: a bare origin, a clone carrying .marvin/, and agent worktrees under
# .claude/worktrees/. One fixture per keep-guard (G1–G6) asserting its NAMED reason (git's own
# refusal must not mask a missing guard), removal fixtures, scope fixtures, --check and --hook.
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
}
mkwt()  { git -C "$R" worktree add -q -b "$1" "$WT/$1" "$2"; }              # mkwt <name> <base>
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

hd "R1 sub-branch merged into a LOCAL feature branch, pushed — removed, local branch deleted"
fresh; mkwt sub feat; work "$WT/sub" sub; git -C "$WT/sub" push -q origin sub 2>/dev/null; merge_into feat sub; age "$WT/sub"
sweep "$SWEEP"; assert_rc 0; assert_out "removed: $WT/sub (branch sub deleted)"; assert_gone "$WT/sub"; assert_no_branch sub
if git -C "$O" show-ref --verify --quiet refs/heads/sub; then ok "remote branch untouched"; else bad "remote branch deleted"; fi

hd "R2 merged into develop, never pushed — removed, branch kept (no origin copy)"
fresh; mkwt r2 develop; work "$WT/r2" r2; merge_into develop r2; age "$WT/r2"
sweep "$SWEEP"; assert_out "removed: $WT/r2 (branch r2 kept: no origin copy)"; assert_gone "$WT/r2"; assert_branch r2

hd "R3 detached HEAD contained in main — removed"
fresh; git -C "$R" worktree add -q --detach "$WT/det" main; age "$WT/det"
sweep "$SWEEP"; assert_out "removed: $WT/det"; assert_gone "$WT/det"

hd "R4 a directory name with a space is printed encoded"
fresh; git -C "$R" worktree add -q -b spaced "$WT/my wt" develop; work "$WT/my wt" sp; merge_into develop spaced; age "$WT/my wt"
sweep "$SWEEP"; assert_out "removed: \"$WT/my wt\" (branch spaced kept: no origin copy)"; assert_gone "$WT/my wt"

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

hd "H4 --hook outside git exits 0 silently; the CLI exits 2"
mkdir -p "$WORK/plain"
OUT=$(cd "$WORK/plain" && CLAUDE_PROJECT_DIR="$WORK/plain" bash "$SWEEP" --hook </dev/null 2>&1); RC=$?; assert_rc 0; assert_empty
OUT=$(cd "$WORK/plain" && CLAUDE_PROJECT_DIR="$WORK/plain" bash "$SWEEP" </dev/null 2>&1); RC=$?; assert_rc 2; assert_out "not a git repository"

hd "U1 an unknown option is a usage error"
sweep "$SWEEP" --bogus; assert_rc 2; assert_out "usage"

# ── mutations: each reverts one guard in a copy; the guard's fixture must then fail ────────────
mutation() {  # mutation <name> <fixture-fn> <exact script line> <replacement> <text the real script prints>
  local m="$WORK/mutant-$1.sh"
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
mutation NOLOCK fx_IDX '  st=$(git -C "$p" --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null) || { keep "$p" "G3 status unreadable"; return; }' \
                       '  st=$(git -C "$p" status --porcelain --untracked-files=all 2>/dev/null) || { keep "$p" "G3 status unreadable"; return; }' "G5 commits"

printf '\n----\ntest-worktree-sweep: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
