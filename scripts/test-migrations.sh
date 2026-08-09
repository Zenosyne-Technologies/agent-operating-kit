#!/usr/bin/env bash
# test-migrations.sh — behavioural test suite for the kit's release migration scripts.
#
# Every fixture below is a defect that was reproduced destroying consumer data or
# half-finishing a migration. Each test names the mechanic it pins: revert that mechanic in
# scripts/migrate-v0.21.0.sh and the named assertion must fail.
#
# Run from anywhere: bash scripts/test-migrations.sh
# Exit 0 = all assertions pass.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MIGRATE="$SCRIPT_DIR/migrate-v0.21.0.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-migtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASSED=0; FAILED=0; CURRENT=""
OUT=""; RC=0

hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

tracked()     { git ls-files | grep -Fxq -- "$1"; }          # index, case-EXACT; never `ls`
assert_tracked()     { tracked "$1"; chk $? "tracked: $1${2:+ — $2}"; }
assert_not_tracked() { if tracked "$1"; then bad "NOT tracked: $1${2:+ — $2}"; else ok "not tracked: $1${2:+ — $2}"; fi; }
assert_rc()          { if [ "$RC" = "$1" ]; then ok "exit $1${2:+ — $2}"; else bad "exit $RC, want $1${2:+ — $2}"; fi; }
assert_out()         { printf '%s\n' "$OUT" | grep -Fq -- "$1"; chk $? "report: $1"; }
assert_no_out()      { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "report must not say: $1"; else ok "report silent on: $1"; fi; }
assert_file_has()    { grep -Fq -- "$2" "$1"; chk $? "$1 contains \"$2\"${3:+ — $3}"; }
assert_file_lacks()  { if grep -Fq -- "$2" "$1"; then bad "$1 must not contain \"$2\"${3:+ — $3}"; else ok "$1 free of \"$2\"${3:+ — $3}"; fi; }
assert_clean()       { if [ -z "$(git status --porcelain)" ]; then ok "working tree clean${1:+ — $1}"; else bad "working tree dirty${1:+ — $1}: $(git status --porcelain | tr '\n' ' ')"; fi; }
assert_eq()          { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }

run_migrate() { OUT=$(bash "$MIGRATE" "$@" 2>&1); RC=$?; return 0; }

# Extract a shell function's body from the migration script, for the STRUCTURAL pins below.
fn_body() { awk -v f="^$1\\\\(\\\\)" '$0 ~ f {s=1} s {print} s && /}/ {exit}' "$MIGRATE"; }

# Is this filesystem case-insensitive? It decides whether the BEHAVIOURAL case-guard pin (T02)
# can fire at all: on a case-sensitive filesystem the correct guard and the buggy one behave
# identically, so only the structural pin (T02S) can detect that regression there. CI runs on
# ubuntu-latest — case-sensitive — which is exactly why T02S exists.
case_insensitive_fs() {
  local d rc=1
  d=$(mktemp -d "${TMPDIR:-/tmp}/marvin-casefs.XXXXXX")
  : > "$d/CaseProbe"
  [ -e "$d/caseprobe" ] && rc=0
  rm -f "$d/CaseProbe"; rmdir "$d"
  return "$rc"
}
if case_insensitive_fs; then
  FS_KIND="case-insensitive"
  FS_NOTE="both case-guard pins active: T02 (behavioural) + T02S (structural)"
else
  FS_KIND="case-sensitive"
  FS_NOTE="T02's behavioural pin CANNOT detect a disk-test regression here — T02S (structural) is the pin that covers it"
fi
printf 'filesystem: %s — %s\n' "$FS_KIND" "$FS_NOTE"

snapshot() {   # everything the migration could possibly perturb, in one blob
  git status --porcelain
  git rev-parse HEAD
  find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs cksum
}

# ── fixture builders ─────────────────────────────────────────────────────────────────────────
CASCADE="briefing documentation-agent handbooks label-syntax planning-research ponytail
reporting security stats-collection-brief ticket-filing token-economics tracker-config
validation-agent"

mk_repo() {  # mk_repo <name> — a committed v0.20.0 install, decoys included
  local d="$WORK/$1"
  rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
  git init -q .
  git config user.email test@example.com
  git config user.name "kit test"
  git config commit.gpgsign false
  mkdir -p .docs/agents .docs/marvin .docs/project-management .docs/reports src
  local f
  for f in $CASCADE; do printf 'kit cascade file %s\nsee `.docs/agents/briefing.md`\n' "$f" > ".docs/agents/$f.md"; done
  # a Local-tracker config: its `.docs/project-management/INDEX.md` refs MUST survive verbatim
  cat > .docs/agents/tracker-config.md <<'EOF'
# Tracker configuration — Local
Issue index: `.docs/project-management/INDEX.md` (allocator: `next_issue`).
Within the index folder the file is named INDEX.md.
Filing rules: `.docs/agents/ticket-filing.md`.
EOF
  printf -- '---\nkit_version: 0.20.0\n---\nProject facts.\n' > .docs/PROJECT-INFO.md
  printf 'Marvin memory.\n' > .docs/marvin/MEMORY.md
  local a
  for a in developer user admin; do
    mkdir -p ".docs/handbooks/$a"
    printf '# %s handbook\nGrown per `.docs/agents/handbooks.md`.\n' "$a" > ".docs/handbooks/$a/INDEX.md"
  done
  printf '# Issue index\nnext_issue: 42\n' > .docs/project-management/INDEX.md
  printf 'weekly report\n' > .docs/reports/2026-01.md
  printf 'console.log(1)\n' > src/app.js
  cat > CLAUDE.md <<'EOF'
# Project rules
- Cascade: `.docs/agents/briefing.md`, `.docs/agents/security.md`, `.docs/agents/handbooks.md`
- Project facts: `.docs/PROJECT-INFO.md`
- Memory: `.docs/marvin/MEMORY.md`
- Developer handbook: `.docs/handbooks/developer/INDEX.md`
- User handbook: `.docs/handbooks/user/INDEX.md`
- Issue log: `.docs/project-management/INDEX.md`
EOF
  git add -- . >/dev/null
  git commit -qm "v0.20.0 install"
}

commit_all() { git add -- . >/dev/null; git commit -qm "$1"; }

# ═════════════════════════════════════════════════════════════════════════════════════════════
hd "T00 --check is a pure dry run (DoD 1)"
mk_repo t00
before=$(snapshot)
run_migrate --check
after=$(snapshot)
assert_rc 0
assert_eq "$after" "$before" "repository byte-identical before/after --check"
assert_out "move:    .docs/agents/briefing.md -> .marvin/agents/briefing.md"
assert_out "rename:  .docs/handbooks/developer/INDEX.md -> .docs/handbooks/developer/index.md"
assert_out "rewrite: CLAUDE.md"
assert_out "mode=check"
assert_not_tracked ".marvin/agents/briefing.md" "check mode moved nothing"

# ── defect 1: `git mv` into `.marvin/…` without mkdir -p (and `.marvin` alone is not enough)
hd "T01 defect 1 — destination directories are created before the moves"
mk_repo t01
run_migrate
assert_rc 0
assert_out "failures=0"
assert_tracked ".marvin/agents/briefing.md" "cascade landed — dies without mkdir -p .marvin/agents"
assert_tracked ".marvin/PROJECT-INFO.md"
assert_tracked ".marvin/MEMORY.md"
assert_not_tracked ".docs/agents/briefing.md"

# ── defect 2: a filesystem-existence guard on a case-only rename skips it (same inode)
hd "T02 defect 2 — case-only handbook rename is index-guarded, not disk-guarded"
mk_repo t02
run_migrate
assert_rc 0
for a in developer user admin; do
  assert_tracked ".docs/handbooks/$a/index.md" "lowercased (a disk guard would skip this)"
  assert_not_tracked ".docs/handbooks/$a/INDEX.md"
done
assert_not_tracked ".docs/handbooks/developer/__index.tmp"

# ── defect 2, structurally. The behavioural fixture above is inert on a case-sensitive
#    filesystem (the mutant and the correct code do the same thing there), and CI runs on
#    ubuntu-latest. So the guard is ALSO pinned by inspecting its implementation: the case-only
#    destination test must be the index test and nothing else.
hd "T02S defect 2 (structural) — the case-only guard contains no filesystem-existence test"
case_body=$(fn_body dst_occupied_case)
real_body=$(fn_body dst_occupied_real)
if [ -n "$case_body" ]; then ok "dst_occupied_case() found"; else bad "dst_occupied_case() not found — the guard was renamed or removed"; fi
if printf '%s' "$case_body" | grep -Eq '(\[\[?|test)[[:space:]]+-(e|f|d|s|L|h|r|w|x)[[:space:]]'; then
  bad "dst_occupied_case() performs a filesystem test — INDEX.md and index.md are one inode; this silently skips the rename"
else
  ok "dst_occupied_case() performs no filesystem test (pin holds on any filesystem)"
fi
printf '%s' "$case_body" | grep -q 'tracked_exact'
chk $? "dst_occupied_case() is the index-membership test"
printf '%s' "$real_body" | grep -Eq '\[[[:space:]]+-e[[:space:]]'
chk $? "dst_occupied_real() DOES test the disk (the asymmetry is deliberate)"
printf '   note  active pin here: %s\n' "$FS_NOTE"

# ── defect 3: an interrupted two-step rename latches the source guard off forever
hd "T03 defect 3 — __index.tmp is a resume marker, not debris"
mk_repo t03
git mv .docs/handbooks/developer/INDEX.md .docs/handbooks/developer/__index.tmp
commit_all "interrupted migration"
assert_tracked ".docs/handbooks/developer/__index.tmp" "fixture: only the temp name survives"
assert_not_tracked ".docs/handbooks/developer/INDEX.md" "fixture: the source guard is latched off"
run_migrate
assert_rc 0
assert_tracked ".docs/handbooks/developer/index.md" "resumed from the temp name"
assert_not_tracked ".docs/handbooks/developer/__index.tmp" "no resume marker shipped"

# ── defect 4: unconditional `rmdir .docs/marvin` aborts the run when a consumer keeps files
hd "T04 defect 4 — pruning an emptied source directory is best effort"
mk_repo t04
printf 'consumer notes\n' > .docs/marvin/notes.md
commit_all "consumer file in .docs/marvin"
run_migrate
assert_rc 0 "run completed past the rmdir"
assert_tracked ".docs/marvin/notes.md" "consumer file survived"
assert_tracked ".marvin/MEMORY.md"
assert_tracked ".docs/handbooks/developer/index.md" "handbook renames still ran after the rmdir"
assert_clean

# ── defect 5: a source-only guard permits `.marvin/agents/agents/` nesting
hd "T05 defect 5 — a tracked destination is a collision, never a nested move"
mk_repo t05
mkdir -p .marvin/agents
printf 'hand-migrated\n' > .marvin/agents/briefing.md
commit_all "consumer hand-migrated one file"
run_migrate
assert_rc 3 "collisions present"
assert_out "collision: .docs/agents/briefing.md -> .marvin/agents/briefing.md"
assert_tracked ".docs/agents/briefing.md" "source untouched on collision"
assert_not_tracked ".marvin/agents/agents/briefing.md" "no nesting"
assert_eq "$(git ls-files | grep -c '\.marvin/agents/agents/')" "0" "no .marvin/agents/agents/ path at all"
assert_tracked ".marvin/agents/security.md" "non-colliding files still migrated"
assert_file_has ".marvin/agents/briefing.md" "hand-migrated" "consumer content not overwritten"

# ── defect 6: an index-only guard is blind to a destination present on disk but untracked.
#    `.marvin/` is gitignored here on purpose: without it the stray copy makes the tree dirty,
#    the clean-tree precondition fires first, and the destination guard is never exercised.
hd "T06 defect 6 — destination guard tests the disk as well as the index"
mk_repo t06
printf '.marvin/\n' > .gitignore
commit_all "gitignore .marvin"
mkdir -p .marvin/agents
printf 'hand-copied, untracked\n' > .marvin/agents/briefing.md
assert_clean "ignored stray copy leaves the tree clean"
run_migrate
assert_rc 3 "collisions present"
assert_out "collision: .docs/agents/briefing.md -> .marvin/agents/briefing.md"
assert_tracked ".docs/agents/briefing.md" "source untouched — an index-only guard would nest it"
assert_eq "$(git ls-files | grep -c '\.marvin/agents/agents/')" "0" "no .marvin/agents/agents/ path"
assert_file_has ".marvin/agents/briefing.md" "hand-copied, untracked" "untracked file not clobbered"

# ── defect 7: no clean-tree precondition → consumer WIP and `.env.local` swept into the commit
hd "T07 defect 7 — a dirty tree is refused, and nothing is staged or stashed"
mk_repo t07
head_before=$(git rev-parse HEAD)
printf 'work in progress\n' >> src/app.js
printf 'SECRET=hunter2\n' > .env.local
run_migrate
assert_rc 2 "refused"
assert_out "result=dirty-refused"
assert_eq "$(git rev-parse HEAD)" "$head_before" "HEAD unchanged"
assert_eq "$(git diff --cached --name-only | wc -l | tr -d ' ')" "0" ".env.local and WIP never staged"
assert_not_tracked ".env.local"
assert_not_tracked ".marvin/agents/briefing.md" "no move happened"
assert_tracked ".docs/agents/briefing.md"
assert_eq "$(git stash list | wc -l | tr -d ' ')" "0" "no stash created on the user's behalf"

# ── defect 8: a whole-directory move silently relocates consumer-authored files
hd "T08 defect 8 — consumer files in .docs/agents/ stay put, are reported, and keep their references"
mk_repo t08
printf 'oncall runbook\n' > .docs/agents/oncall-runbook.md
printf '%s\n' '- Oncall: `.docs/agents/oncall-runbook.md`' >> CLAUDE.md
printf 'Escalate per `.docs/agents/oncall-runbook.md`.\n' >> .docs/agents/ticket-filing.md
commit_all "consumer runbook, cited from CLAUDE.md and a kit file"
run_migrate
assert_rc 0
assert_tracked ".docs/agents/oncall-runbook.md" "still at its original path"
assert_out "declined: .docs/agents/oncall-runbook.md"
assert_not_tracked ".marvin/agents/oncall-runbook.md"
# A reference to a file the allowlist refused to move must NOT be retargeted: that is the same
# locations-vs-references inconsistency the atomic commit exists to prevent, inside a run that
# reports result=ok.
assert_file_has "CLAUDE.md" ".docs/agents/oncall-runbook.md" "declined path still referenced where it lives"
assert_file_lacks "CLAUDE.md" ".marvin/agents/oncall-runbook.md"
assert_file_has ".marvin/agents/ticket-filing.md" ".docs/agents/oncall-runbook.md" "same inside a migrated file"
assert_file_lacks ".marvin/agents/ticket-filing.md" ".marvin/agents/oncall-runbook.md"
assert_file_has "CLAUDE.md" ".marvin/agents/briefing.md" "kit references still retargeted"

# ── defect 9: `git rm -r "the stale one"` — an undefined, unbounded, recursive delete
hd "T09 defect 9 — the migration contains no recursive delete, and deletes nothing on collision"
if grep -nE 'git[[:space:]]+rm|rm[[:space:]]+-[a-zA-Z]*r|rm[[:space:]]+-rf' "$MIGRATE" | grep -v 'no recursive delete'; then
  bad 'recursive delete or `git rm` present in migrate-v0.21.0.sh'
else
  ok "no \`git rm\` and no recursive rm in migrate-v0.21.0.sh"
fi
if grep -nE 'git[[:space:]]+add[[:space:]]+(-A|--all|\.)' "$MIGRATE"; then
  bad "blanket staging sweep present in migrate-v0.21.0.sh"
else
  ok "staging is by explicit path only"
fi

# ── defect 10: a blanket INDEX.md rewrite corrupts a Local-tracker config
hd "T10 defect 10 — INDEX.md lowercasing is anchored to handbook paths only"
mk_repo t10
run_migrate
assert_rc 0
assert_file_has ".marvin/agents/tracker-config.md" ".docs/project-management/INDEX.md" "tracker index ref verbatim"
assert_file_has ".marvin/agents/tracker-config.md" "the file is named INDEX.md" "bare INDEX.md ref verbatim"
assert_file_has ".marvin/agents/tracker-config.md" ".marvin/agents/ticket-filing.md" "cascade ref retargeted"
assert_file_has "CLAUDE.md" ".docs/project-management/INDEX.md" "issue-log ref survived"
assert_file_has "CLAUDE.md" ".docs/handbooks/developer/index.md" "handbook ref lowercased"
assert_file_lacks "CLAUDE.md" ".docs/handbooks/developer/INDEX.md"

# ── defect 11: the staging set excluded the CLAUDE.md rewrite → dirty tree + broken revert
hd "T11 defect 11 — renames and the CLAUDE.md rewrite land in ONE commit"
mk_repo t11
run_migrate
assert_rc 0
assert_clean "nothing left unstaged after the run"
git show --name-only --format= HEAD | grep -Fxq CLAUDE.md
chk $? "CLAUDE.md is part of the migration commit"
git show --name-only --format= HEAD | grep -Fxq .marvin/agents/briefing.md
chk $? "the moves are in the same commit"
assert_file_lacks "CLAUDE.md" ".docs/agents/"
assert_file_lacks "CLAUDE.md" ".docs/PROJECT-INFO.md"
assert_file_lacks "CLAUDE.md" ".docs/marvin/"
assert_eq "$(git rev-list --count HEAD)" "2" "exactly one migration commit"

# ── defect 12: a fixed 13-file list strands Jira's convert-milestones-brief.md
hd "T12 defect 12 — the Jira-only cascade file migrates too"
mk_repo t12
printf 'convert milestones brief, see `.docs/agents/tracker-config.md`\n' > .docs/agents/convert-milestones-brief.md
commit_all "jira install"
run_migrate
assert_rc 0
assert_tracked ".marvin/agents/convert-milestones-brief.md" "not stranded in .docs/agents/"
assert_not_tracked ".docs/agents/convert-milestones-brief.md"
assert_no_out "declined: .docs/agents/convert-milestones-brief.md"
assert_file_has ".marvin/agents/convert-milestones-brief.md" ".marvin/agents/tracker-config.md"

# ── idempotence (DoD 4)
hd "T13 second run — zero moves, clean tree, unchanged HEAD"
mk_repo t13
run_migrate
assert_rc 0
head_after=$(git rev-parse HEAD)
run_migrate
assert_rc 0
assert_out "moved=0"
assert_out "nothing to migrate"
assert_eq "$(git rev-parse HEAD)" "$head_after" "HEAD unchanged on re-run"
assert_clean "clean after re-run"

# ── revert consistency (DoD 3)
hd "T14 git revert HEAD restores locations AND references together"
mk_repo t14
run_migrate
assert_rc 0
git revert --no-edit HEAD >/dev/null 2>&1
chk $? "git revert HEAD applies cleanly"
assert_tracked ".docs/agents/briefing.md" "cascade back where it was"
assert_not_tracked ".marvin/agents/briefing.md"
assert_tracked ".docs/PROJECT-INFO.md"
assert_not_tracked ".marvin/PROJECT-INFO.md"
assert_tracked ".docs/handbooks/developer/INDEX.md" "handbook index back to uppercase"
assert_not_tracked ".docs/handbooks/developer/index.md"
assert_file_has "CLAUDE.md" ".docs/agents/briefing.md" "references consistent with locations"
assert_file_has "CLAUDE.md" ".docs/handbooks/developer/INDEX.md"
assert_file_lacks "CLAUDE.md" ".marvin/"
assert_clean "clean after revert"

# ── pre-`.docs/` install migrates in one hop
hd "T15 legacy docs/agents/ install migrates straight to .marvin/agents/"
mk_repo t15
git rm -q -f .docs/agents/briefing.md >/dev/null
mkdir -p docs/agents
printf 'legacy cascade, see `docs/agents/security.md`\n' > docs/agents/briefing.md
printf '%s\n' '- Legacy cascade: `docs/agents/briefing.md`' >> CLAUDE.md
commit_all "pre-.docs install"
run_migrate
assert_rc 0
assert_tracked ".marvin/agents/briefing.md" "one hop from docs/agents/"
assert_not_tracked "docs/agents/briefing.md"
assert_file_has "CLAUDE.md" "\`.marvin/agents/briefing.md\`" "legacy reference rewritten"

# ── --no-commit
hd "T16 --no-commit stages without committing"
mk_repo t16
head_before=$(git rev-parse HEAD)
run_migrate --no-commit
assert_rc 0
assert_eq "$(git rev-parse HEAD)" "$head_before" "HEAD unchanged"
assert_out "staged, not committed"
if [ -n "$(git diff --cached --name-only)" ]; then ok "changes are staged"; else bad "nothing staged"; fi

# ── staging: defense in depth behind the clean-tree gate.
#    On a clean tree a blanket sweep and explicit paths stage the same set, so the only
#    behaviourally reachable sweep regression is one combined with the `-f` the script already
#    needs (`git add -f -A` / `git add -f .`). This fixture puts ignored foreign files in reach
#    of the staging call and asserts they never enter the commit.
hd "T18 staging never sweeps foreign files that are in reach"
mk_repo t18
printf '%s\n' '.marvin/' '.env.local' > .gitignore
commit_all "gitignore .marvin and .env.local"
mkdir -p .marvin/agents
printf 'stray, not a cascade file\n' > .marvin/agents/zz-stray.md
printf 'SECRET=hunter2\n' > .env.local
assert_clean "ignored foreign files leave the tree clean"
run_migrate
assert_rc 0
assert_not_tracked ".marvin/agents/zz-stray.md" "foreign file beside the destination not staged"
assert_not_tracked ".env.local"
if git show --name-only --format= HEAD | grep -Fxq .marvin/agents/zz-stray.md; then
  bad "the stray file entered the migration commit"; else ok "migration commit free of the stray file"; fi
assert_file_has ".marvin/agents/zz-stray.md" "stray, not a cascade file" "left untouched on disk"

# ── flags: an invocation containing --check must never modify anything
hd "T19 --check and --no-commit are mutually exclusive, in either order"
mk_repo t19
before=$(snapshot)
run_migrate --check --no-commit
assert_rc 4 "--check --no-commit rejected"
assert_out "mutually exclusive"
run_migrate --no-commit --check
assert_rc 4 "--no-commit --check rejected"
after=$(snapshot)
assert_eq "$after" "$before" "repository untouched by both rejected invocations"
assert_not_tracked ".marvin/agents/briefing.md" "no move happened"

# ── a dry run changes nothing, so it must be available on a dirty tree too
hd "T20 --check works on a dirty tree and reports it"
mk_repo t20
printf 'work in progress\n' >> src/app.js
printf 'SECRET=hunter2\n' > .env.local
before=$(snapshot)
run_migrate --check
assert_rc 2 "exit 2 = a real run would refuse"
assert_out "move:    .docs/agents/briefing.md -> .marvin/agents/briefing.md"
assert_out "result=plan-only-tree-dirty"
assert_out ".env.local"
after=$(snapshot)
assert_eq "$after" "$before" "dry run changed nothing on a dirty tree"
assert_eq "$(git diff --cached --name-only | wc -l | tr -d ' ')" "0" "nothing staged"

# ── two source roots targeting one destination is a plan-time collision, not a mid-run failure
hd "T21 dual source roots collide at plan time"
mk_repo t21
mkdir -p docs/agents
printf 'legacy briefing\n' > docs/agents/briefing.md
printf '%s\n' '- Legacy: `docs/agents/briefing.md`' >> CLAUDE.md
commit_all "both cascade roots present"
run_migrate --check
assert_rc 3 "the dry run already reports the conflict"
assert_out "collision: .docs/agents/briefing.md -> .marvin/agents/briefing.md (another source targets the same destination: docs/agents/briefing.md)"
assert_out "collision: docs/agents/briefing.md -> .marvin/agents/briefing.md (another source targets the same destination: .docs/agents/briefing.md)"
assert_no_out "move:    .docs/agents/briefing.md"
assert_no_out "move:    docs/agents/briefing.md"
run_migrate
assert_rc 3 "real run reports the same conflict"
assert_out "failures=0" "no move was attempted and failed mid-run"
assert_tracked ".docs/agents/briefing.md" "both sources survive"
assert_tracked "docs/agents/briefing.md"
assert_not_tracked ".marvin/agents/briefing.md"
assert_file_has "CLAUDE.md" ".docs/agents/briefing.md" "references to the unmoved files are left alone"
assert_file_has "CLAUDE.md" "\`docs/agents/briefing.md\`"
assert_tracked ".marvin/agents/security.md" "the rest of the cascade still migrated"
assert_clean

# ── not a git work tree
hd "T17 refuses outside a git work tree"
mkdir -p "$WORK/t17"; cd "$WORK/t17" || exit 1
OUT=$(cd "$WORK/t17" && env GIT_CEILING_DIRECTORIES="$WORK" bash "$MIGRATE" 2>&1); RC=$?
assert_rc 4
assert_out "not a git work tree"

# ═════════════════════════════════════════════════════════════════════════════════════════════
cd "$SCRIPT_DIR" || exit 1
printf '\n----\ntest-migrations: %d passed, %d failed  [filesystem: %s — %s]\n' \
  "$PASSED" "$FAILED" "$FS_KIND" "$FS_NOTE"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
