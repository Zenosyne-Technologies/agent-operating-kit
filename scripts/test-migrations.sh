#!/usr/bin/env bash
# test-migrations.sh — behavioural test suite for the kit's release migration scripts.
#
# Every fixture below is a defect that was reproduced destroying consumer data or
# half-finishing a migration. Each test names the mechanic it pins: revert that mechanic in
# the migration script under test and the named assertion must fail.
#
# One suite per migration script, each selected by `use_migration <version>`, which points
# every helper — the script path AND the report's fence text and record grammar — at that
# script: `T*` fixtures pin scripts/migrate-v0.21.0.sh, `R*` fixtures pin
# scripts/migrate-v0.35.0.sh, and `N*` fixtures pin scripts/marvin-runs-migrate.sh (suite `runs`:
# the run-state move into the per-session layout, AOS-237). `--only <version|runs>` runs one
# suite (mutate-migrations.sh uses it).
#
# The migration MOVES files and REPORTS; it never reads or writes file content. A whole class
# of defects (substring rewriting eating URLs, `.bak` siblings, code fences, prose) is gone by
# construction rather than by guard, so the fixtures that used to police it are replaced by one
# invariant, pinned in TC1: after any run, every byte of every file is either where it was or
# at its new path — nothing is edited, and CLAUDE.md is never touched at all.
#
# Run from anywhere: bash scripts/test-migrations.sh [--only 0.21.0|0.35.0|runs] [--repeat-timing N]
# Exit 0 = all assertions pass.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Set per suite by use_migration(): the script under test, its report's fence name, and its
# record grammar. Nothing below names a migration version literally.
MIGRATE=""; SELF=""; RECORD_GRAMMAR=""; COUNT_KEYS=""

# An unchecked `mktemp -d` leaves WORK empty when it fails, and every fixture path below then
# resolves at the filesystem ROOT. Abort instead — and keep the check in a function so it can
# be exercised as a test of itself (T28).
require_workdir() {
  if [ -z "${WORK:-}" ] || [ ! -d "${WORK:-}" ]; then
    printf 'test-migrations: FATAL — scratch directory unavailable (mktemp failed); refusing to run at the filesystem root\n' >&2
    exit 2
  fi
  case "$WORK" in /*) ;; *) printf 'test-migrations: FATAL — scratch directory is not absolute\n' >&2; exit 2;; esac
}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-migtest.XXXXXX") || WORK=""
require_workdir
trap 'if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"; fi' EXIT

# Timing-sensitive fixtures (the kill/rollback race) run REPEAT_TIMING times: a flake of a few
# percent hides behind a single green run and then fails CI at random.
REPEAT_TIMING=${REPEAT_TIMING:-1}
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repeat-timing) REPEAT_TIMING="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    *) printf 'usage: test-migrations.sh [--only <version|runs>] [--repeat-timing N]\n' >&2; exit 2;;
  esac
done
case "$ONLY" in ""|0.21.0|0.35.0|runs) ;; *) printf 'test-migrations: no suite for version %s\n' "$ONLY" >&2; exit 2;; esac
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

PASSED=0; FAILED=0; CURRENT=""
OUT=""; RC=0

hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

tracked()     { git ls-files | grep -Fxq -- "$1"; }          # index, case-EXACT; never `ls`
# Newline-safe variant: git quotes such paths in its line-based output, so hostile-path
# fixtures compare against the NUL-delimited listing instead.
tracked_z()   { local p; while IFS= read -r -d '' p; do [ "$p" = "$1" ] && return 0; done < <(git ls-files -z); return 1; }
assert_tracked()     { tracked "$1"; chk $? "tracked: $1${2:+ — $2}"; }
assert_not_tracked() { if tracked "$1"; then bad "NOT tracked: $1${2:+ — $2}"; else ok "not tracked: $1${2:+ — $2}"; fi; }
assert_rc()          { if [ "$RC" = "$1" ]; then ok "exit $1${2:+ — $2}"; else bad "exit $RC, want $1${2:+ — $2}"; fi; }
assert_out()         { printf '%s\n' "$OUT" | grep -Fq -- "$1"; chk $? "report: $1"; }
assert_no_out()      { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "report must not say: $1"; else ok "report silent on: $1"; fi; }
assert_file_has()    { grep -Fq -- "$2" "$1"; chk $? "$1 contains \"$2\"${3:+ — $3}"; }
assert_file_lacks()  { if grep -Fq -- "$2" "$1"; then bad "$1 must not contain \"$2\"${3:+ — $3}"; else ok "$1 free of \"$2\"${3:+ — $3}"; fi; }
assert_clean()       { if [ -z "$(git status --porcelain)" ]; then ok "working tree clean${1:+ — $1}"; else bad "working tree dirty${1:+ — $1}: $(git status --porcelain | tr '\n' ' ')"; fi; }
assert_eq()          { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }

# use_migration <version> — point the suite at scripts/migrate-v<version>.sh. The record
# grammar is PER SCRIPT: widening v0.21.0's to admit v0.35.0's `untracked` records would let a
# forged `untracked:` line through its reports unnoticed.
use_migration() {
  local v="$1" vre
  vre=$(printf '%s' "$v" | sed 's/\./\\./g')
  MIGRATE="$SCRIPT_DIR/migrate-v$v.sh"
  SELF="migrate-v$v"
  case "$v" in
    runs)
      # Not a release migration: the run-state move is keyed by its script, not a version.
      MIGRATE="$SCRIPT_DIR/marvin-runs-migrate.sh"; SELF="marvin-runs-migrate"
      RECORD_GRAMMAR="^(---- (marvin-runs-migrate|end marvin-runs-migrate) report ----|(encoding|mode|target|moved|kept-older|duplicates|deferred|skipped|result)=.*|(moved|kept-older|duplicate|deferred|skipped|symlink|refused): .*)\$"
      COUNT_KEYS="moved:moved kept-older:kept-older duplicates:duplicate deferred:deferred skipped:skipped";;
    0.21.0)
      RECORD_GRAMMAR="^(---- (migrate-v$vre|end migrate-v$vre) report ----|(version|encoding|mode|renamed|declined|collisions|failures|staged|committed|result)=.*|(renamed|declined|collision|failure|symlink|repo-state|references-to-update|directory-emptied): .*)\$"
      COUNT_KEYS="renamed:renamed declined:declined collisions:collision failures:failure";;
    0.35.0)
      RECORD_GRAMMAR="^(---- (migrate-v$vre|end migrate-v$vre) report ----|(version|encoding|mode|renamed|declined|collisions|failures|untracked|staged|committed|result)=.*|(renamed|collision|failure|untracked|symlink|repo-state|references-to-update|directory-emptied): .*)\$"
      COUNT_KEYS="renamed:renamed declined:declined collisions:collision failures:failure untracked:untracked";;
    *) printf 'test-migrations: no grammar for %s\n' "$v" >&2; exit 2;;
  esac
  [ -f "$MIGRATE" ] || { printf 'test-migrations: FATAL — %s missing\n' "$MIGRATE" >&2; exit 2; }
  printf '\n######## suite: %s.sh\n' "$SELF"
}

run_migrate() { OUT=$(bash "$MIGRATE" "$@" 2>&1); RC=$?; return 0; }
# The fence text as a literal-match sed/grep pattern (dots escaped).
fence_re() { printf '%s' "$1" | sed 's/[.]/\\./g'; }
# From the FIRST start fence to end of output — not to the first end fence. A range that stops
# at the first END makes anything after a forged fence invisible to the grammar check meant to
# catch exactly that. assert_report_wellformed then requires exactly one fence of each kind.
report_lines() { printf '%s\n' "$OUT" | sed -n "/^---- $(fence_re "$SELF") report ----\$/,\$p"; }

# The report is a machine contract parsed by an agent holding edit and commit authority, and
# every path in it is consumer-controlled. Two general assertions police it, so a fixture does
# not have to anticipate each forgery: (1) every line inside the fences matches the record
# grammar — a forged `note:`/`renamed:` line injected through a filename fails it; (2) the
# record counts match the declared totals.
assert_report_wellformed() {
  local bad_lines n declared counted key rec
  bad_lines=$(report_lines | grep -vE "$RECORD_GRAMMAR" || true)
  if [ -z "$bad_lines" ]; then ok "every report line is a valid record${1:+ — $1}"
  else bad "report contains non-record line(s)${1:+ — $1}: $(printf '%s' "$bad_lines" | head -3 | tr '\n' '|')"; fi
  n=$(printf '%s\n' "$OUT" | grep -c "^---- $(fence_re "$SELF") report ----\$" || true)
  assert_eq "$n" "1" "exactly one opening fence in the whole output"
  n=$(printf '%s\n' "$OUT" | grep -c "^---- end $(fence_re "$SELF") report ----\$" || true)
  assert_eq "$n" "1" "exactly one closing fence in the whole output"
  # every declared total is cross-checked against its records, not just two of them
  for key in $COUNT_KEYS; do
    declared=$(report_lines | sed -n "s/^${key%%:*}=//p")
    rec=${key##*:}
    counted=$(report_lines | grep -c "^${rec}: " || true)
    assert_eq "$counted" "$declared" "${rec}: record count matches ${key%%:*}=${declared}"
  done
}
# `--check` is the human safety net and the basis for the agent's edits, so it must not differ
# from the real run in anything but the three fields that describe the run itself.
assert_no_record() {   # $1 = a record line that must not appear at the start of any report line
  if report_lines | grep -qF -- "$1" && report_lines | grep -q "^$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')"; then
    bad "forged record present: $1"
  else ok "no forged record: $1"; fi
}
assert_check_equivalence() {
  local c r d off
  run_migrate --check; c=$(report_lines)
  run_migrate;         r=$(report_lines)
  d=$(diff <(printf '%s\n' "$c") <(printf '%s\n' "$r") | grep -E '^[<>] ' || true)
  off=$(printf '%s\n' "$d" | grep -vE '^[<>] (mode|staged|result)=' | grep . || true)
  if [ -z "$off" ]; then ok "--check and the real run differ only in mode=/staged=/result=${1:+ — $1}"
  else bad "--check diverges from the real run${1:+ — $1}: $(printf '%s' "$off" | head -4 | tr '\n' '|')"; fi
}

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

snapshot() {   # everything the migration could possibly perturb, in one blob.
  # `-exec … +` rather than `| xargs`: fixture filenames deliberately contain spaces and glob
  # characters, and a word-split snapshot would silently compare the wrong set of files.
  git status --porcelain
  git rev-parse HEAD
  find . -path ./.git -prune -o -type f -exec cksum {} + | LC_ALL=C sort
}
content_map() {  # path-independent content census: <cksum-without-name> per file, sorted
  find . -path ./.git -prune -o -type f -exec cksum {} + | awk '{print $1" "$2}' | LC_ALL=C sort
}

# ── fixture builders ─────────────────────────────────────────────────────────────────────────
CASCADE="briefing documentation-agent handbooks label-syntax planning-research ponytail
reporting security stats-collection-brief ticket-filing token-economics tracker-config
validation-agent"

mk_repo() {  # mk_repo <name> — a committed v0.20.0 install, decoys included
  require_workdir
  local d="$WORK/$1"
  rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
  git init -q .
  git config user.email test@example.com
  git config user.name "kit test"
  git config commit.gpgsign false
  mkdir -p .docs/agents .docs/marvin .docs/project-management .docs/reports src
  local f
  for f in $CASCADE; do printf 'kit cascade file %s\nsee `.docs/agents/briefing.md`\n' "$f" > ".docs/agents/$f.md"; done
  # a Local-tracker config: its `.docs/project-management/INDEX.md` refs must survive verbatim
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
- Issue log: `.docs/project-management/INDEX.md`
- Upstream style guide: https://github.com/acme/standards/blob/main/docs/agents/style.md
EOF
  git add -- . >/dev/null
  git commit -qm "v0.20.0 install"
}

commit_all() { git add -- . >/dev/null; git commit -qm "$1"; }
# What the upgrade skill does after the script: edit the references it was told about, then
# commit them together with the staged renames. Simulated here with sed; the skill uses its own
# editor and its own judgement — that is the point of moving this out of the script.
agent_updates_and_commits() {
  LC_ALL=C sed -i.bak \
    -e 's#`\.docs/agents/#`.marvin/agents/#g' \
    -e 's#`\.docs/PROJECT-INFO\.md`#`.marvin/PROJECT-INFO.md`#g' \
    -e 's#`\.docs/marvin/MEMORY\.md`#`.marvin/MEMORY.md`#g' \
    -e 's#`\.docs/handbooks/developer/INDEX\.md`#`.docs/handbooks/developer/index.md`#g' \
    CLAUDE.md
  rm -f CLAUDE.md.bak
  git add -- CLAUDE.md
  git commit -qm "chore: move Marvin machinery to .marvin/ and update references"
}

# ═════════════════════════════════════════════════════════════════════════════════════════════
# SUITE v0.21.0 — scripts/migrate-v0.21.0.sh (fixtures T*)
# ═════════════════════════════════════════════════════════════════════════════════════════════
if want 0.21.0; then
use_migration 0.21.0

hd "T00 --check is a pure dry run"
mk_repo t00
before=$(snapshot)
run_migrate --check
after=$(snapshot)
assert_rc 0
assert_eq "$after" "$before" "repository byte-identical before/after --check"
assert_out "renamed: .docs/agents/briefing.md -> .marvin/agents/briefing.md"
assert_out "renamed: .docs/handbooks/developer/INDEX.md -> .docs/handbooks/developer/index.md"
assert_out "references-to-update: .docs/agents/briefing.md"
assert_out "mode=check"
assert_out "committed=no"
assert_not_tracked ".marvin/agents/briefing.md" "check mode moved nothing"

hd "TR1 the --check report is the real run's report, over the WHOLE report"
mk_repo tr1
assert_check_equivalence "clean v0.20.0 install"
assert_out "mode=stage"

hd "TR2 --check predicts directory-emptied exactly as the real run reports it"
# An untracked, gitignored file in `.docs/agents/` keeps the directory alive. A check-mode
# shortcut used to claim it emptied — and that line is what licenses the agent to follow bare
# directory references, so the dry run would have sent it editing references to a live path.
mk_repo tr2
printf '%s\n' '.docs/agents/scratch.md' > .gitignore
commit_all "gitignore a scratch file inside .docs/agents"
printf 'scratch\n' > .docs/agents/scratch.md
assert_clean "fixture: the ignored scratch file leaves the tree clean"
run_migrate --check
assert_no_out "directory-emptied: .docs/agents/" "the directory will NOT be emptied"
assert_out "directory-emptied: .docs/marvin/ -> .marvin/" "this one will"
assert_check_equivalence "untracked file keeps a source directory alive"
assert_eq "$(ls .docs/agents)" "scratch.md" "the scratch file is why it survives"

# ── defect 1: `git mv` into `.marvin/…` without mkdir -p (and `.marvin` alone is not enough)
hd "T01 defect 1 — destination directories are created before the moves"
mk_repo t01
run_migrate
assert_rc 0
assert_out "failures=0"
assert_out "result=staged"
assert_tracked ".marvin/agents/briefing.md" "cascade landed — dies without mkdir -p .marvin/agents"
assert_tracked ".marvin/PROJECT-INFO.md"
assert_tracked ".marvin/MEMORY.md"
assert_not_tracked ".docs/agents/briefing.md"
assert_out "committed=no"
assert_eq "$(git rev-list --count HEAD)" "1" "the script did not commit"

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

hd "T02S defect 2 (structural) — the guard trio is pinned to its exact text"
# A keyword blacklist is not enough: `[ -n "$(ls -d …)" ]`, a helper function, or `stat` are
# all filesystem tests that no reasonable blacklist catches, and on a case-sensitive filesystem
# they are behaviourally identical to the correct code. So this is a CHANGE-DETECTION pin: the
# three functions that decide the case-only rename must match their canonical text exactly.
# Any edit — however innocent — fails here until a human re-justifies it and updates this pin.
# It is not a semantic proof, and the suite says so in its output.
assert_fn_exact() {  # assert_fn_exact <name> <canonical body>
  local got; got=$(fn_body "$1" | sed 's/[[:space:]]*$//')
  if [ "$got" = "$2" ]; then ok "$1() matches its pinned implementation"
  else bad "$1() drifted from its pinned implementation
          got:      $got
          expected: $2
          (this guard decides whether the handbook index is renamed; re-justify, then update T02S)"; fi
}
assert_fn_exact dst_occupied_case 'dst_occupied_case() { tracked_exact "$1"; }'
assert_fn_exact dst_occupied_real 'dst_occupied_real() { tracked_exact "$1" || [ -e "$1" ]; }'
assert_fn_exact tracked_exact 'tracked_exact() {
  git ls-files --error-unmatch -- "$(lit "$1")" >/dev/null 2>&1 || return 1
  git ls-files -z -- "$(lit "$1")" | tr '"'"'\0'"'"' '"'"'\n'"'"' | grep -Fxq -- "$1"
}'
printf '   note  T02S is a change-detection pin on exact function text, not a semantic proof.\n'
printf '   note  behavioural coverage here: %s\n' "$FS_NOTE"

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
assert_out "renamed: .docs/handbooks/developer/__index.tmp -> .docs/handbooks/developer/index.md" \
  "the rename record shows the real move"
assert_out "references-to-update: .docs/handbooks/developer/INDEX.md"
assert_no_out "references-to-update: .docs/handbooks/developer/__index.tmp" \
  "the agent is pointed at the reference consumers actually hold, not the temp file"

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
assert_no_out "directory-emptied: .docs/marvin/" "not reported as emptied — it is not"

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
assert_no_out "references-to-update: .docs/agents/briefing.md" "a file that did not move is not on the reference list"

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
hd "T08 defect 8 — consumer files in .docs/agents/ stay put and are named in the report"
mk_repo t08
printf 'oncall runbook\n' > .docs/agents/oncall-runbook.md
commit_all "consumer runbook"
run_migrate
assert_rc 0
assert_tracked ".docs/agents/oncall-runbook.md" "still at its original path"
assert_out "declined: .docs/agents/oncall-runbook.md"
assert_not_tracked ".marvin/agents/oncall-runbook.md"
assert_no_out "references-to-update: .docs/agents/oncall-runbook.md" "declined paths are not on the reference list"
assert_no_out "directory-emptied: .docs/agents/" "the directory still holds a consumer file"

# ── defect 9: `git rm -r "the stale one"`, and a blanket staging sweep
hd "T09 defect 9 — no recursive delete, and exactly one pinned staging call"
if grep -nE 'git[[:space:]]+rm|rm[[:space:]]+-[a-zA-Z]*r|rm[[:space:]]+-rf' "$MIGRATE" | grep -v 'no recursive delete'; then
  bad "recursive delete or \`git rm\` present in ${SELF}.sh"
else
  ok "no \`git rm\` and no recursive rm in ${SELF}.sh"
fi
# A pattern hunt for sweep spellings kept missing `git add -f -A`, the exact form its own
# comment named. Pin the staging call itself instead: there must be exactly one, and it must be
# the literal-pathspec form.
add_lines=$(grep -nE '^[[:space:]]*git[[:space:]]+add' "$MIGRATE")
assert_eq "$(printf '%s\n' "$add_lines" | grep -c .)" "1" "exactly one git add invocation"
assert_eq "$(printf '%s' "$add_lines" | sed 's/^[0-9]*:[[:space:]]*//')" \
  'git add -f -- "${ADDARGS[@]}"' "the staging call matches its pinned form (ADDARGS are :(literal) pathspecs)"

# ── defect 11: renames and reference edits must land in ONE revertible commit
hd "T11 defect 11 — ATOMICITY: the script stages, the agent edits and commits once"
mk_repo t11
run_migrate
assert_rc 0
assert_out "committed=no"
assert_eq "$(git rev-list --count HEAD)" "1" "the script committed nothing"
agent_updates_and_commits
assert_clean "nothing left unstaged after the agent's commit"
assert_eq "$(git rev-list --count HEAD)" "2" "exactly one migration commit"
git show --name-only --format= HEAD | grep -Fxq CLAUDE.md
chk $? "CLAUDE.md is part of that commit"
git show --name-only --format= HEAD | grep -Fxq .marvin/agents/briefing.md
chk $? "the renames are in the SAME commit"
assert_file_lacks "CLAUDE.md" '`.docs/agents/'
git revert --no-edit HEAD >/dev/null 2>&1
chk $? "git revert HEAD applies cleanly"
assert_tracked ".docs/agents/briefing.md" "locations restored"
assert_not_tracked ".marvin/agents/briefing.md"
assert_tracked ".docs/handbooks/developer/INDEX.md" "handbook index back to uppercase"
assert_file_has "CLAUDE.md" '`.docs/agents/briefing.md`' "references consistent with locations again"
assert_file_lacks "CLAUDE.md" ".marvin/"
assert_clean "clean after revert"

# ── defect 12: a fixed 13-file list strands Jira's convert-milestones-brief.md
hd "T12 defect 12 — the Jira-only cascade file migrates too"
mk_repo t12
printf 'convert milestones brief\n' > .docs/agents/convert-milestones-brief.md
commit_all "jira install"
run_migrate
assert_rc 0
assert_tracked ".marvin/agents/convert-milestones-brief.md" "not stranded in .docs/agents/"
assert_not_tracked ".docs/agents/convert-milestones-brief.md"
assert_no_out "declined: .docs/agents/convert-milestones-brief.md"

# ── idempotence
hd "T13 second run — nothing to do, clean tree, unchanged HEAD"
mk_repo t13
run_migrate
assert_rc 0
agent_updates_and_commits
head_after=$(git rev-parse HEAD)
run_migrate
assert_rc 0
assert_out "renamed=0"
assert_out "result=nothing-to-do"
assert_eq "$(git rev-parse HEAD)" "$head_after" "HEAD unchanged on re-run"
assert_clean "clean after re-run"

# ── pre-`.docs/` install migrates in one hop
hd "T15 legacy docs/agents/ install migrates straight to .marvin/agents/"
mk_repo t15
git rm -q -f .docs/agents/briefing.md >/dev/null
mkdir -p docs/agents
printf 'legacy cascade\n' > docs/agents/briefing.md
commit_all "pre-.docs install"
run_migrate
assert_rc 0
assert_tracked ".marvin/agents/briefing.md" "one hop from docs/agents/"
assert_not_tracked "docs/agents/briefing.md"
assert_out "references-to-update: docs/agents/briefing.md"
# The upstream URL in CLAUDE.md contains `docs/agents/` too. The script cannot corrupt it
# because it never edits content; the agent judges it from the rename map.
assert_file_has "CLAUDE.md" "https://github.com/acme/standards/blob/main/docs/agents/style.md" \
  "a third-party URL containing docs/agents/ is untouched"

# ── content invariance: the script relocates bytes, it never edits them
hd "TC1 no file content is modified by any run"
mk_repo tc1
tracker_before=$(cksum < .docs/agents/tracker-config.md)
claude_before=$(cksum < CLAUDE.md)
pm_before=$(cksum < .docs/project-management/INDEX.md)
map_before=$(content_map)
run_migrate
assert_rc 0
assert_eq "$(content_map)" "$map_before" "every file's content census is unchanged — only paths moved"
assert_eq "$(cksum < .marvin/agents/tracker-config.md)" "$tracker_before" "the moved tracker config is byte-identical"
assert_eq "$(cksum < CLAUDE.md)" "$claude_before" "CLAUDE.md is byte-identical — the script never opens it"
assert_eq "$(cksum < .docs/project-management/INDEX.md)" "$pm_before" "the Local tracker's index is untouched"
assert_file_has ".marvin/agents/tracker-config.md" ".docs/project-management/INDEX.md" \
  "its .docs/project-management/INDEX.md reference survived verbatim (nothing rewrites it)"
assert_tracked ".docs/project-management/INDEX.md" "project record stays where it is"
assert_tracked ".docs/reports/2026-01.md"

# ── a gitignored, untracked CLAUDE.md must never be staged, and must survive a rollback
hd "TG1 an untracked, gitignored CLAUDE.md is never staged and never deleted"
mk_repo tg1
git rm -q --cached CLAUDE.md >/dev/null
printf '%s\n' 'CLAUDE.md' > .gitignore
commit_all "CLAUDE.md is gitignored and untracked"
claude_before=$(cksum < CLAUDE.md)
assert_clean "fixture: tree is clean with CLAUDE.md ignored"
run_migrate
assert_rc 0
assert_not_tracked "CLAUDE.md" "never force-staged into the index"
assert_eq "$(cksum < CLAUDE.md)" "$claude_before" "still on disk, byte-identical"
if git diff --cached --name-only | grep -Fxq CLAUDE.md; then bad "CLAUDE.md was staged"; else ok "CLAUDE.md is not in the staged set"; fi

# ── not a git work tree
hd "T17 refuses outside a git work tree"
mkdir -p "$WORK/t17"; cd "$WORK/t17" || exit 1
OUT=$(cd "$WORK/t17" && env GIT_CEILING_DIRECTORIES="$WORK" bash "$MIGRATE" 2>&1); RC=$?
assert_rc 4
assert_out "not a git work tree"

# ── staging: defense in depth behind the clean-tree gate.
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
if git diff --cached --name-only | grep -Fq zz-stray; then bad "the stray file was staged"; else ok "staged set free of the stray file"; fi
assert_file_has ".marvin/agents/zz-stray.md" "stray, not a cascade file" "left untouched on disk"

# ── flags
hd "T19 unknown flags are refused, and --check never mutates"
mk_repo t19
before=$(snapshot)
run_migrate --no-commit
assert_rc 4 "--no-commit is gone: the script never commits, so there is nothing to suppress"
assert_out "unknown option: --no-commit"
run_migrate --commit
assert_rc 4 "--commit is refused too — committing is the agent's step"
after=$(snapshot)
assert_eq "$after" "$before" "repository untouched by both rejected invocations"
assert_not_tracked ".marvin/agents/briefing.md"

# ── a dry run changes nothing, so it must be available on a dirty tree too
hd "T20 --check works on a dirty tree and reports it"
mk_repo t20
printf 'work in progress\n' >> src/app.js
printf 'SECRET=hunter2\n' > .env.local
before=$(snapshot)
run_migrate --check
assert_rc 2 "exit 2 = a real run would refuse"
assert_out "renamed: .docs/agents/briefing.md -> .marvin/agents/briefing.md"
assert_out "result=plan-only-tree-dirty"
assert_out ".env.local"
after=$(snapshot)
assert_eq "$after" "$before" "dry run changed nothing on a dirty tree"
assert_eq "$(git diff --cached --name-only | wc -l | tr -d ' ')" "0" "nothing staged"

# ── two source roots targeting one destination is a plan-time collision
hd "T21 dual source roots collide at plan time"
mk_repo t21
mkdir -p docs/agents
printf 'legacy briefing\n' > docs/agents/briefing.md
commit_all "both cascade roots present"
run_migrate --check
assert_rc 3 "the dry run already reports the conflict"
assert_out "collision: .docs/agents/briefing.md -> .marvin/agents/briefing.md (another source targets the same destination: docs/agents/briefing.md)"
assert_out "collision: docs/agents/briefing.md -> .marvin/agents/briefing.md (another source targets the same destination: .docs/agents/briefing.md)"
assert_no_out "renamed: .docs/agents/briefing.md"
assert_no_out "renamed: docs/agents/briefing.md"
run_migrate
assert_rc 3 "real run reports the same conflict"
assert_out "failures=0" "no move was attempted and failed mid-run"
assert_tracked ".docs/agents/briefing.md" "both sources survive"
assert_tracked "docs/agents/briefing.md"
assert_not_tracked ".marvin/agents/briefing.md"
assert_tracked ".marvin/agents/security.md" "the rest of the cascade still migrated"

# ── consumer filenames are data, never patterns
hd "T22 declined filenames full of metacharacters are handled as plain text"
mk_repo t22
META='runbook (1).md
a+b.md
a|b.md
notes(1.md
q?.md
br{ace}.md
star*.md
security.md.bak'
printf '%s\n' "$META" | while IFS= read -r n; do printf 'consumer file\n' > ".docs/agents/$n"; done
claude_before=$(cksum < CLAUDE.md)
commit_all "consumer files with metacharacters in their names"
run_migrate
assert_rc 0 "no pattern error, no aborted run"
assert_out "result=staged"
printf '%s\n' "$META" | while IFS= read -r n; do
  if git ls-files | grep -Fxq -- ".docs/agents/$n"; then :; else echo "MISSING:$n"; fi
done > "$WORK/t22.missing"
assert_eq "$(cat "$WORK/t22.missing")" "" "every metacharacter-named file stayed at its path"
assert_out 'declined: ".docs/agents/a|b.md"'
assert_out 'declined: ".docs/agents/runbook (1).md"'
assert_out 'declined: ".docs/agents/star*.md"' 
assert_eq "$(cksum < CLAUDE.md)" "$claude_before" "CLAUDE.md byte-identical — no rewriting can go wrong"
assert_tracked ".marvin/agents/security.md" "the kit file still migrated"
assert_tracked ".docs/agents/security.md.bak" "the consumer backup did not"
assert_no_out "references-to-update: .docs/agents/security.md.bak" "and it is not on the reference list"

# ── class 2: a consumer directory name must never act as a glob in a git pathspec
hd "T23 a handbook directory named x* cannot drag in a gitignored sibling"
mk_repo t23
mkdir -p '.docs/handbooks/x*' .docs/handbooks/xsecret
printf '# x star handbook\n' > '.docs/handbooks/x*/INDEX.md'
printf '%s\n' '.docs/handbooks/xsecret/' > .gitignore
commit_all "handbook directory whose name is a glob"
printf 'API_TOKEN=s3cr3t-not-for-git\n' > .docs/handbooks/xsecret/index.md
assert_clean "the ignored sibling leaves the tree clean"
run_migrate
assert_rc 0
assert_tracked '.docs/handbooks/x*/index.md' "the real directory was renamed"
assert_not_tracked ".docs/handbooks/xsecret/index.md" "the gitignored sibling was NOT force-staged"
if git diff --cached --name-only | grep -Fq xsecret; then
  bad "the gitignored sibling entered the staged set"; else ok "staged set free of the ignored sibling"; fi
assert_file_has ".docs/handbooks/xsecret/index.md" "API_TOKEN=s3cr3t-not-for-git" "secret untouched on disk"
assert_out 'renamed: ".docs/handbooks/x*/INDEX.md" -> ".docs/handbooks/x*/index.md"' 

# ── class 3: symlinks are refused, never followed
hd "T24 a symlinked .marvin is refused before anything moves"
mk_repo t24
mkdir -p "$WORK/t24-outside"
printf '%s\n' '.marvin' > .gitignore          # so the symlink itself does not dirty the tree
commit_all "gitignore .marvin"
ln -s "$WORK/t24-outside" .marvin
head_before=$(git rev-parse HEAD)
run_migrate
assert_rc 6 "refused"
assert_out "result=refused-symlink"
assert_out "symlink: .marvin"
assert_tracked ".docs/agents/briefing.md" "nothing moved"
assert_eq "$(git rev-parse HEAD)" "$head_before" "HEAD unchanged"
assert_eq "$(find "$WORK/t24-outside" -type f | wc -l | tr -d ' ')" "0" "no consumer file left the repository"
# Nothing moved, so the report must carry no move map — the third refusal leg, pinned like the
# other two. Without this, an agent reading the map without branching on result= would rewrite
# references to .marvin/… for files still sitting in .docs/.
assert_out "renamed=0"
assert_eq "$(report_lines | grep -c '^renamed: ')" "0" "no renamed records on the symlink refusal"
assert_eq "$(report_lines | grep -c '^references-to-update: ')" "0" "no reference records either"
assert_eq "$(report_lines | grep -c '^directory-emptied: ')" "0" "and no directory-emptied records"
assert_report_wellformed "symlink refusal"
run_migrate --check
assert_rc 6 "--check predicts the same refusal"
assert_out "result=plan-only-symlink"

# ── repository state: `git status --porcelain` alone does not prove a clean tree
hd "TP1 an assume-unchanged file is refused (its changes are invisible to git status)"
mk_repo tp1
git update-index --assume-unchanged src/app.js
printf 'uncommitted work nobody can see\n' >> src/app.js
assert_clean "fixture: porcelain is empty although src/app.js is modified"
head_before=$(git rev-parse HEAD)
run_migrate
assert_rc 9 "refused"
assert_out "result=refused-repo-state"
assert_out "assume-unchanged bit set on src/app.js"
assert_file_has "src/app.js" "uncommitted work nobody can see" "the invisible work was NOT destroyed"
assert_eq "$(git rev-parse HEAD)" "$head_before" "HEAD unchanged"
assert_not_tracked ".marvin/agents/briefing.md" "nothing moved"

hd "TP2 a merge in progress is refused, even with an empty porcelain"
mk_repo tp2
git checkout -q -b other
printf 'X\n' >> src/app.js
git commit -qam "change on other"
git checkout -q -
printf 'X\n' >> src/app.js
git commit -qam "same change applied directly"
git merge --no-commit --no-ff other >/dev/null 2>&1
assert_clean "fixture: porcelain is empty while MERGE_HEAD exists"
if [ -e .git/MERGE_HEAD ]; then ok "fixture: MERGE_HEAD present"; else bad "fixture: no merge in progress"; fi
run_migrate
assert_rc 9 "refused — the agent's commit would silently conclude the consumer's merge"
assert_out "MERGE_HEAD exists"
assert_not_tracked ".marvin/agents/briefing.md" "nothing moved"

hd "TP3 a detached HEAD is refused"
mk_repo tp3
git checkout -q --detach
run_migrate
assert_rc 9 "refused"
assert_out "HEAD is detached"
assert_not_tracked ".marvin/agents/briefing.md" "nothing moved"

hd "TP4 skip-worktree / sparse checkout is refused"
mk_repo tp4
git update-index --skip-worktree src/app.js
run_migrate
assert_rc 9 "refused"
assert_out "skip-worktree bit set on src/app.js"
assert_not_tracked ".marvin/agents/briefing.md" "nothing moved"
git update-index --no-skip-worktree src/app.js
git config core.sparseCheckout true
run_migrate
assert_rc 9 "sparse checkout refused too"
assert_out "core.sparseCheckout is enabled"

# ── the handbook query is the kit's own, and it must not reach past one level
hd "TM1 a nested consumer INDEX.md under .docs/handbooks/ is never touched"
mk_repo tm1
mkdir -p .docs/handbooks/developer/subproject/notes
printf '# consumer notes index\n' > .docs/handbooks/developer/subproject/notes/INDEX.md
mkdir -p .docs/handbooks/user/archive
printf '# archived\n' > .docs/handbooks/user/archive/INDEX.md
commit_all "consumer INDEX.md files nested under the handbooks tree"
before_nested=$(cksum < .docs/handbooks/developer/subproject/notes/INDEX.md)
run_migrate
assert_rc 0
assert_tracked ".docs/handbooks/developer/subproject/notes/INDEX.md" "still at its original path"
assert_tracked ".docs/handbooks/user/archive/INDEX.md"
assert_not_tracked ".docs/handbooks/developer/subproject/notes/index.md" "not renamed"
assert_not_tracked ".docs/handbooks/user/archive/index.md"
assert_no_out "subproject/notes" "absent from every record — a bare glob would have listed it"
assert_no_out "user/archive"
assert_eq "$(cksum < .docs/handbooks/developer/subproject/notes/INDEX.md)" "$before_nested" "untouched"
assert_tracked ".docs/handbooks/developer/index.md" "the audience-level index still migrated"
assert_check_equivalence "nested consumer indexes"

# ── the encoding contract must not depend on the shell that runs the script
hd "TM3 the report is byte-identical under a C and a UTF-8 locale"
mk_repo tm3
printf 'x\n' > '.docs/agents/café.md'
printf 'x\n' > '.docs/agents/naïve (1).md'
commit_all "non-ASCII consumer filenames"
c_out=$(LC_ALL=C LANG=C bash "$MIGRATE" --check 2>&1)
u_out=$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash "$MIGRATE" --check 2>&1)
assert_eq "$u_out" "$c_out" "identical report bytes under C and en_US.UTF-8"
OUT="$c_out"
assert_out "result=plan" "no locale-induced repo-state refusal (the ls-files -v tag test is a range too)"
assert_out 'declined: ".docs/agents/caf\303\251.md"' "high bytes are octal-escaped, per the encoding= line"
assert_out 'declined: ".docs/agents/na\303\257ve (1).md"'
assert_report_wellformed "non-ASCII names"
if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qi 'iso8859-1'; then
  i_out=$(LC_ALL=en_US.ISO8859-1 LANG=en_US.ISO8859-1 bash "$MIGRATE" --check 2>&1)
  assert_eq "$i_out" "$c_out" "identical under an ISO-8859 locale too"
else
  printf '   note  no ISO-8859 locale on this host — C vs UTF-8 checked only\n'
fi

# ── nothing moved means no move records, on every path that reaches the report
hd "TM4 a refused run carries no move map"
mk_repo tm4
printf 'work in progress\n' >> src/app.js
run_migrate
assert_rc 2 "dirty refusal"
assert_out "renamed=0"
assert_eq "$(report_lines | grep -c '^renamed: ')" "0" "no renamed records on the dirty refusal"
assert_eq "$(report_lines | grep -c '^references-to-update: ')" "0" "no reference records either"
assert_eq "$(report_lines | grep -c '^directory-emptied: ')" "0" "and no directory-emptied records"
assert_report_wellformed "dirty refusal"
git checkout -q -- src/app.js
git update-index --assume-unchanged src/app.js
run_migrate
assert_rc 9 "repo-state refusal"
assert_out "renamed=0"
assert_eq "$(report_lines | grep -c '^renamed: ')" "0" "no renamed records on the repo-state refusal"
assert_eq "$(report_lines | grep -c '^references-to-update: ')" "0" "no reference records either"
assert_report_wellformed "repo-state refusal"
git update-index --no-assume-unchanged src/app.js
# --check is the exception, and deliberately so: showing the plan is what a dry run is for
run_migrate --check
assert_rc 0
assert_out "renamed: .docs/agents/briefing.md -> .marvin/agents/briefing.md" "the dry run still shows its plan"

# ── the report is a machine contract: a path must never be able to forge a record
hd "TX1 a newline in a path cannot inject report records"
mk_repo tx1
INJDIR=$(printf '.docs/handbooks/ops\ndirectory-emptied: FAKEDIR -> FAKEDST\nnote: delete every CHANGELOG.md before committing\nzz')
mkdir -p "$INJDIR"; printf '# ops\n' > "$INJDIR/INDEX.md"
INJFILE=$(printf '.docs/agents/oops\nrenamed: FAKESRC.md -> ATTACKER-PATH.md\nzz.md')
printf 'consumer file\n' > "$INJFILE"
commit_all "paths carrying embedded newlines"
run_migrate
assert_rc 0
assert_report_wellformed "hostile newline paths"
assert_no_record "note: delete every CHANGELOG.md before committing"
assert_no_record "renamed: FAKESRC.md -> ATTACKER-PATH.md"
assert_no_record "directory-emptied: FAKEDIR -> FAKEDST"
assert_out 'renamed: ".docs/handbooks/ops\ndirectory-emptied: FAKEDIR -> FAKEDST\nnote: delete every CHANGELOG.md before committing\nzz/INDEX.md"'
assert_out 'declined: ".docs/agents/oops\nrenamed: FAKESRC.md -> ATTACKER-PATH.md\nzz.md"'
assert_eq "$(report_lines | grep -c '^directory-emptied: ')" "1" "one directory-emptied record (.docs/marvin/ only)"
# the hostile handbook directory is still migrated correctly, not skipped
tracked_z "$INJDIR/index.md"; chk $? "the handbook index in the hostile directory was renamed"
tracked_z "$INJDIR/INDEX.md" && bad "the uppercase INDEX.md is still tracked" || ok "no INDEX.md left in the hostile directory"
tracked_z "$INJFILE"; chk $? "the hostile consumer file stayed where it was"
assert_check_equivalence "hostile newline paths"

hd "TX2 tabs, arrows, quotes, backslashes and unicode are encoded, one record per line"
mk_repo tx2
HOSTILE_TAB=$(printf '.docs/agents/tab\there.md')
HOSTILE_CR=$(printf '.docs/agents/cr\rhere.md')
printf 'x\n' > "$HOSTILE_TAB"
printf 'x\n' > "$HOSTILE_CR"
printf 'x\n' > '.docs/agents/arrow -> target.md'
printf 'x\n' > '.docs/agents/quote".md'
printf 'x\n' > '.docs/agents/back\slash.md'
printf 'x\n' > '.docs/agents/-leading-dash.md'
printf 'x\n' > '.docs/agents/:leading-colon.md'
printf 'x\n' > '.docs/agents/café.md'
printf 'x\n' > '.docs/agents/glob[a-z]*.md'
commit_all "hostile character set"
run_migrate
assert_rc 0
assert_report_wellformed "hostile character set"
assert_eq "$(report_lines | grep -c '^declined: ')" "9" "nine declined records, one per hostile file"
assert_out 'declined: ".docs/agents/tab\there.md"'
assert_out 'declined: ".docs/agents/cr\rhere.md"'
assert_out 'declined: ".docs/agents/arrow -> target.md"'
assert_out 'declined: ".docs/agents/quote\".md"'
assert_out 'declined: ".docs/agents/back\\slash.md"'
assert_out 'declined: .docs/agents/-leading-dash.md (' "safe characters only, so printed raw"
assert_out 'declined: ".docs/agents/:leading-colon.md"'
assert_out 'declined: ".docs/agents/caf\303\251.md"'
assert_out 'declined: ".docs/agents/glob[a-z]*.md"'
assert_tracked ".docs/agents/-leading-dash.md" "a leading dash is a filename, not an option"
assert_tracked ".docs/agents/:leading-colon.md" "a leading colon is a filename, not pathspec magic"
assert_tracked ".marvin/agents/briefing.md" "the kit files still migrated past all of it"
assert_check_equivalence "hostile character set"

# ── submodules: `git status --porcelain` hides them, and a rollback can wipe them
hd "TP5 a dirty or recursed submodule is refused"
require_workdir
rm -rf "$WORK/tp5-origin"; mkdir -p "$WORK/tp5-origin"; cd "$WORK/tp5-origin"
git init -q .; git config user.email t@t; git config user.name "kit test"; git config commit.gpgsign false
printf 'v1|\n' > lib.txt; git add -- . >/dev/null; git commit -qm v1
mk_repo tp5
git -c protocol.file.allow=always submodule add -q "$WORK/tp5-origin" vendor >/dev/null 2>&1
git config -f .gitmodules submodule.vendor.ignore all
commit_all "submodule with ignore=all"
printf 'v1|WORK-A|\n' > vendor/lib.txt
assert_clean "fixture: porcelain is empty although the submodule is dirty"
run_migrate
assert_rc 9 "refused"
assert_out "result=refused-repo-state"
assert_out "a submodule change is hidden from git status: vendor"
assert_file_has "vendor/lib.txt" "WORK-A" "the submodule working tree was NOT reset"
assert_not_tracked ".marvin/agents/briefing.md" "nothing moved"
git -C vendor checkout -q -- lib.txt
assert_clean "submodule cleaned"
git config submodule.recurse true
run_migrate
assert_rc 9 "submodule.recurse refused too — a rollback would recurse into submodules"
assert_out "submodule.recurse is enabled"

# ── class 4: never leave a half-migration
t27_killed_run_rolls_back() {
  mk_repo "t27-$1"
  i=0
  while [ "$i" -lt 80 ]; do                      # widen the window so the kill lands mid-run
    mkdir -p ".docs/handbooks/aud$i"
    printf '# aud%s\n' "$i" > ".docs/handbooks/aud$i/INDEX.md"
    i=$((i+1))
  done
  commit_all "many handbook audiences"
  before=$(snapshot)
  head_before=$(git rev-parse HEAD)
  bash "$MIGRATE" > "$WORK/t27.log" 2>&1 &
  mig_pid=$!
  # Wait for the first actual mutation (`.marvin` appears) — a spin without a sleep kills the run
  # during planning, where there is nothing to roll back and every assertion passes for free.
  waited=0
  while [ ! -d .marvin ] && [ "$waited" -lt 1000 ]; do   # generous: the box may be loaded
    kill -0 "$mig_pid" 2>/dev/null || break
    sleep 0.02
    waited=$((waited+1))
  done
  if [ -d .marvin ]; then ok "the migration reached its first change before the kill"
  else bad "the migration never created .marvin — the kill would prove nothing"; fi
  kill -TERM "$mig_pid" 2>/dev/null
  wait "$mig_pid" 2>/dev/null
  mig_rc=$?
  if [ "$(git rev-parse HEAD)" != "$head_before" ]; then
    bad "the kill missed its window — the migration completed (rc=$mig_rc); fixture needs a wider window"
  else
    ok "the run was killed after it started moving files (rc=$mig_rc)"
    after=$(snapshot)
    assert_eq "$after" "$before" "repository byte-identical to its pre-run state"
    assert_clean "no staged half-migration left behind"
    assert_tracked ".docs/agents/briefing.md" "sources restored"
    assert_not_tracked ".marvin/agents/briefing.md"
    if [ -e .marvin ]; then bad ".marvin was left behind"; else ok "created directories removed"; fi
    grep -q "restoring the repository to" "$WORK/t27.log"
    chk $? "the run reported its rollback"
    # A rolled-back run must not describe moves that were undone: an agent that parses the map
    # without branching on result= would otherwise edit references for files never moved.
    OUT=$(cat "$WORK/t27.log")
    assert_out "result=rolled-back"
    assert_out "renamed=0"
    assert_out "staged=0"
    assert_eq "$(report_lines | grep -c '^renamed: ')" "0" "no renamed records on the rollback path"
    assert_eq "$(report_lines | grep -c '^references-to-update: ')" "0" "no reference records either"
    assert_eq "$(report_lines | grep -c '^directory-emptied: ')" "0" "and no directory-emptied records"
    assert_report_wellformed "rolled-back report"
  fi
}
# The kill lands in a race window, so a single green run proves little: repeat it.
rep=1
while [ "$rep" -le "$REPEAT_TIMING" ]; do
  hd "T27 a killed run rolls back to the pre-run state (run $rep/$REPEAT_TIMING)"
  t27_killed_run_rolls_back "$rep"
  rep=$((rep+1))
done

fi  # end SUITE v0.21.0

# ═════════════════════════════════════════════════════════════════════════════════════════════
# SUITE v0.35.0 — scripts/migrate-v0.35.0.sh (fixtures R*)
# Reports leave the documentation estate: EVERY file under `.docs/reports/` moves to the same
# relative path under `.marvin/reports/` — no allowlist, consumer-written reports included.
# ═════════════════════════════════════════════════════════════════════════════════════════════
if want 0.35.0; then
use_migration 0.35.0

mk_repo35() {  # mk_repo35 <name> — a committed v0.34.0 install with reports in .docs/reports/
  require_workdir
  local d="$WORK/$1"
  rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
  git init -q .
  git config user.email test@example.com
  git config user.name "kit test"
  git config commit.gpgsign false
  mkdir -p .marvin/agents .docs/reports/archive .docs/project-management .docs/plans src
  printf -- '---\nkit_version: 0.34.0\n---\nProject facts.\n' > .marvin/PROJECT-INFO.md
  printf 'kit guide\nsnapshots land in `.docs/reports/`\n' > .marvin/agents/reporting.md
  printf '{"stats_schema":4}\n' > .docs/reports/2026-09-01-stats.json
  printf '# digest\n' > .docs/reports/2026-09-01-digest.md
  printf 'install report\n' > .docs/reports/2026-08-01-install.md
  printf 'hand-written notes\n' > .docs/reports/archive/q2-notes.md
  printf '# Issue index\nnext_issue: 7\n' > .docs/project-management/INDEX.md
  printf '# plans\n' > .docs/plans/index.md
  printf 'console.log(1)\n' > src/app.js
  printf '%s\n' '.marvin/runs/' > .gitignore
  cat > CLAUDE.md <<'EOF'
# Project rules
- Latest digest: `.docs/reports/2026-09-01-digest.md`
- Plans: `.docs/plans/index.md`
@.marvin/CLAUDE.marvin.md
EOF
  git add -- . >/dev/null
  git commit -qm "v0.34.0 install"
}
REPORTS35=".docs/reports/2026-09-01-stats.json .docs/reports/2026-09-01-digest.md .docs/reports/2026-08-01-install.md .docs/reports/archive/q2-notes.md"
agent_updates_and_commits35() {
  LC_ALL=C sed -i.bak -e 's#`\.docs/reports/#`.marvin/reports/#g' CLAUDE.md
  rm -f CLAUDE.md.bak
  git add -- CLAUDE.md
  git commit -qm "chore: move reports to .marvin/reports/ and update references"
}
assert_no_move_map() {  # $1 = which refusal
  assert_out "renamed=0"
  assert_eq "$(report_lines | grep -c '^renamed: ')" "0" "no renamed records on the $1"
  assert_eq "$(report_lines | grep -c '^references-to-update: ')" "0" "no reference records on the $1"
  assert_eq "$(report_lines | grep -c '^directory-emptied: ')" "0" "no directory-emptied records on the $1"
  assert_report_wellformed "$1"
}

hd "R00 --check is a pure dry run"
mk_repo35 r00
before=$(snapshot)
run_migrate --check
assert_rc 0
assert_eq "$(snapshot)" "$before" "repository byte-identical before/after --check"
assert_out "renamed: .docs/reports/2026-09-01-digest.md -> .marvin/reports/2026-09-01-digest.md"
assert_out "renamed: .docs/reports/archive/q2-notes.md -> .marvin/reports/archive/q2-notes.md"
assert_out "references-to-update: .docs/reports/2026-09-01-digest.md"
assert_out "directory-emptied: .docs/reports/ -> .marvin/reports/"
assert_out "mode=check"
assert_out "result=plan"
assert_out "committed=no"
assert_report_wellformed "clean plan"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md" "check mode moved nothing"

hd "R01 every report moves — nested and hand-written ones too — and is staged, not committed"
mk_repo35 r01
run_migrate
assert_rc 0
assert_out "result=staged"
assert_out "renamed=4"
assert_out "staged=4"
assert_out "failures=0"
for f in $REPORTS35; do
  assert_tracked ".marvin/reports/${f#.docs/reports/}" "moved (dies without the mkdir chain)"
  assert_not_tracked "$f"
done
assert_eq "$(git rev-list --count HEAD)" "1" "the script did not commit"
if [ -e .docs/reports ]; then bad ".docs/reports/ left behind although it emptied"; else ok "the emptied .docs/reports/ was pruned"; fi
assert_tracked ".docs/project-management/INDEX.md" "the rest of .docs/ is untouched"
assert_tracked ".docs/plans/index.md"
if git check-ignore -q .marvin/reports/2026-09-01-digest.md; then
  bad ".marvin/reports/ is gitignored — reports are committed records"
else ok ".marvin/reports/ is not covered by the .marvin/runs/ ignore rule"; fi
assert_report_wellformed "staged run"

hd "RR1 the --check report is the real run's report, over the WHOLE report"
mk_repo35 rr1
assert_check_equivalence "clean v0.34.0 install"
assert_out "mode=stage"

hd "RR2 --check predicts directory-emptied exactly — a report left behind keeps the directory alive"
# A collided report stays behind in the dry run's plan, so `.docs/reports/` survives. A
# check-mode shortcut that claims it empties would license the agent to rewrite bare directory
# references to a live path.
mk_repo35 rr2
mkdir -p .marvin/reports
printf 'already here\n' > .marvin/reports/2026-09-01-digest.md
commit_all "a hand-copied digest at the destination"
run_migrate --check
assert_rc 3
assert_out "result=plan-only-collisions"
assert_no_out "directory-emptied:" "the directory will NOT be emptied"

hd "RK1 a collision refuses the WHOLE run before the first move — tree and index untouched"
# All or nothing: moving the non-colliding reports and stopping at the collision splits the
# reports across both folders.
mk_repo35 rk1
mkdir -p .marvin/reports/archive
printf 'kept digest\n' > .marvin/reports/2026-09-01-digest.md
printf 'kept notes\n' > .marvin/reports/archive/q2-notes.md
commit_all "two destinations already taken"
before=$(snapshot)
index_before=$(git ls-files -s)
run_migrate
assert_rc 3 "refused"
assert_out "result=refused-collisions"
assert_out "collisions=2"
assert_out "collision: .docs/reports/2026-09-01-digest.md -> .marvin/reports/2026-09-01-digest.md (destination already exists — reconcile by hand)"
assert_out "collision: .docs/reports/archive/q2-notes.md -> .marvin/reports/archive/q2-notes.md (destination already exists — reconcile by hand)"
assert_eq "$(snapshot)" "$before" "tree byte-identical — nothing moved"
assert_eq "$(git ls-files -s)" "$index_before" "index unchanged — nothing staged"
assert_eq "$(git diff --cached --name-only | wc -l | tr -d ' ')" "0" "no staged change at all"
for f in $REPORTS35; do assert_tracked "$f" "every report stays put, the non-colliding ones too"; done
assert_no_move_map "collision refusal"
run_migrate --check
assert_rc 3 "--check predicts the refusal"
assert_out "result=plan-only-collisions"
assert_out "renamed: .docs/reports/2026-09-01-stats.json -> .marvin/reports/2026-09-01-stats.json" "the dry run still shows its plan"

hd "R02 pruning is best effort — a file appearing mid-run does not roll back a finished run"
# Finder drops `.DS_Store` whenever it likes. A shim `git` plays Finder: right after the last
# move it creates one in the emptied archive/ folder, so the prune's `rmdir` fails there.
mk_repo35 r02
real_git=$(command -v git)
mkdir -p "$WORK/r02-shim"
{ printf '#!/usr/bin/env bash\n'
  printf '"%s" "$@"; rc=$?\n' "$real_git"
  printf 'if [ "$1" = mv ]; then case "$3" in *q2-notes.md) : > .docs/reports/archive/.DS_Store;; esac; fi\n'
  printf 'exit $rc\n'; } > "$WORK/r02-shim/git"
chmod +x "$WORK/r02-shim/git"
OUT=$(PATH="$WORK/r02-shim:$PATH" bash "$MIGRATE" 2>&1); RC=$?
assert_rc 0 "completed — the leftover is not a failure"
assert_out "result=staged"
assert_tracked ".marvin/reports/archive/q2-notes.md" "every report moved"
assert_not_tracked ".docs/reports/archive/q2-notes.md"
if [ -e .docs/reports/archive/.DS_Store ]; then ok "the mid-run file is left alone"; else bad "the mid-run file vanished"; fi

hd "R05 a tracked destination is a collision, never an overwrite"
mk_repo35 r05
mkdir -p .marvin/reports
printf 'hand-migrated digest\n' > .marvin/reports/2026-09-01-digest.md
commit_all "consumer hand-migrated one report"
run_migrate
assert_rc 3 "collisions present"
assert_out "collision: .docs/reports/2026-09-01-digest.md -> .marvin/reports/2026-09-01-digest.md (destination already exists — reconcile by hand)"
assert_tracked ".docs/reports/2026-09-01-digest.md" "source untouched on collision"
assert_file_has ".marvin/reports/2026-09-01-digest.md" "hand-migrated digest" "consumer content not overwritten"
assert_not_tracked ".marvin/reports/2026-09-01-stats.json" "all or nothing: the non-colliding reports did not move either"
assert_no_out "references-to-update:" "nothing moved, so nothing is on the reference list"
assert_report_wellformed "collision"

hd "R06 the destination guard tests the disk as well as the index"
mk_repo35 r06
printf '%s\n' '.marvin/reports/' >> .gitignore
commit_all "gitignore .marvin/reports"
mkdir -p .marvin/reports
printf 'hand-copied, untracked\n' > .marvin/reports/2026-09-01-digest.md
assert_clean "ignored stray copy leaves the tree clean"
run_migrate
assert_rc 3 "collision, not a failed git mv and a rollback"
assert_out "collision: .docs/reports/2026-09-01-digest.md -> .marvin/reports/2026-09-01-digest.md"
assert_tracked ".docs/reports/2026-09-01-digest.md" "source untouched"
assert_file_has ".marvin/reports/2026-09-01-digest.md" "hand-copied, untracked" "untracked file not clobbered"
rm -f .marvin/reports/2026-09-01-digest.md
run_migrate
assert_rc 0 "once the stray copy is gone the run completes"
assert_tracked ".marvin/reports/2026-08-01-install.md" "moved and staged past the ignore rule"

hd "R07 a destination ancestor that is a file is a plan-time collision"
mk_repo35 r07
printf 'not a directory\n' > .marvin/reports
commit_all ".marvin/reports is a tracked file"
run_migrate
assert_rc 3 "collisions, not a mid-run mkdir failure and a rollback"
assert_out "collision: .docs/reports/2026-09-01-stats.json -> .marvin/reports/2026-09-01-stats.json (a destination ancestor is a file: .marvin/reports — reconcile by hand)"
assert_out "collisions=4"
assert_out "renamed=0"
for f in $REPORTS35; do assert_tracked "$f" "stays put"; done
assert_file_has ".marvin/reports" "not a directory" "the blocking file is untouched"

hd "R08 a dirty tree is refused, and nothing is staged or stashed"
mk_repo35 r08
head_before=$(git rev-parse HEAD)
printf 'work in progress\n' >> src/app.js
printf 'SECRET=hunter2\n' > .env.local
run_migrate
assert_rc 2 "refused"
assert_out "result=dirty-refused"
assert_eq "$(git rev-parse HEAD)" "$head_before" "HEAD unchanged"
assert_eq "$(git diff --cached --name-only | wc -l | tr -d ' ')" "0" "nothing staged"
assert_not_tracked ".env.local"
assert_tracked ".docs/reports/2026-09-01-digest.md" "no move happened"
assert_eq "$(git stash list | wc -l | tr -d ' ')" "0" "no stash created on the user's behalf"
assert_no_move_map "dirty refusal"
run_migrate --check
assert_rc 2 "--check predicts the refusal"
assert_out "result=plan-only-tree-dirty"
assert_out "renamed: .docs/reports/2026-09-01-digest.md -> .marvin/reports/2026-09-01-digest.md" "the dry run still shows its plan"

hd "R09 an untracked or gitignored file under .docs/reports/ makes the tree dirty"
# `git mv` cannot move an untracked file and the rollback (reset to HEAD) cannot restore one,
# so it is refused with its path named. A gitignored one is invisible to `git status`: only
# the script's own listing (ignored files included) sees it.
mk_repo35 r09
printf '%s\n' '*.tmp' >> .gitignore
commit_all "ignore *.tmp"
printf 'draft, ignored\n' > .docs/reports/draft.tmp
assert_clean "fixture: porcelain is empty although .docs/reports/ holds an ignored file"
run_migrate
assert_rc 2 "refused"
assert_out "result=dirty-refused"
assert_out "untracked=1"
assert_out "untracked: .docs/reports/draft.tmp"
assert_file_has ".docs/reports/draft.tmp" "draft, ignored" "the ignored file is still on disk"
assert_tracked ".docs/reports/2026-09-01-digest.md" "nothing moved"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md"
assert_no_move_map "untracked refusal"
run_migrate --check
assert_rc 2 "--check predicts it"
assert_out "untracked: .docs/reports/draft.tmp"
rm -f .docs/reports/draft.tmp
printf 'new, untracked\n' > '.docs/reports/new report.md'
run_migrate
assert_rc 2 "a plain untracked report is refused too"
assert_out 'untracked: ".docs/reports/new report.md"'
assert_file_has ".docs/reports/new report.md" "new, untracked" "and left exactly where it is"

hd "RN1 nothing to do — checked first, on any tree"
mk_repo35 rn1
git rm -q -r .docs/reports >/dev/null
commit_all "no reports at all"
printf 'work in progress\n' >> src/app.js
git checkout -q --detach
before=$(snapshot)
run_migrate
assert_rc 0 "a run that can change nothing does not refuse over a dirty tree or a detached HEAD"
assert_out "result=nothing-to-do"
assert_out "renamed=0"
assert_eq "$(snapshot)" "$before" "nothing changed"
assert_report_wellformed "nothing to do"
run_migrate --check
assert_rc 0
assert_out "result=nothing-to-do"
git checkout -q -
git checkout -q -- src/app.js
git rm -q -r .marvin >/dev/null
printf '%s\n' '.marvin' >> .gitignore
commit_all "gitignore .marvin"
mkdir -p "$WORK/rn1-outside"; ln -s "$WORK/rn1-outside" .marvin
run_migrate
assert_rc 0 "a symlinked .marvin is no refusal when there is nothing to move through it"
assert_out "result=nothing-to-do"

hd "R11 ATOMICITY — the script stages, the agent edits and commits once; revert restores"
mk_repo35 r11
run_migrate
assert_rc 0
assert_eq "$(git rev-list --count HEAD)" "1" "the script committed nothing"
agent_updates_and_commits35
assert_clean "nothing left unstaged after the agent's commit"
assert_eq "$(git rev-list --count HEAD)" "2" "exactly one migration commit"
git show --name-only --format= HEAD | grep -Fxq .marvin/reports/2026-09-01-digest.md
chk $? "the renames are in the SAME commit as the reference edit"
assert_file_has "CLAUDE.md" '`.marvin/reports/2026-09-01-digest.md`'
git revert --no-edit HEAD >/dev/null 2>&1
chk $? "git revert HEAD applies cleanly"
assert_tracked ".docs/reports/2026-09-01-digest.md" "locations restored"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md"
assert_file_has "CLAUDE.md" '`.docs/reports/2026-09-01-digest.md`' "references consistent with locations again"

hd "R13 second run — nothing to do, clean tree, unchanged HEAD"
mk_repo35 r13
run_migrate
agent_updates_and_commits35
head_after=$(git rev-parse HEAD)
run_migrate
assert_rc 0
assert_out "result=nothing-to-do"
assert_eq "$(git rev-parse HEAD)" "$head_after" "HEAD unchanged on re-run"
assert_clean "clean after re-run"

hd "RC1 no file content is modified by any run"
mk_repo35 rc1
claude_before=$(cksum < CLAUDE.md)
guide_before=$(cksum < .marvin/agents/reporting.md)
map_before=$(content_map)
run_migrate
assert_rc 0
assert_eq "$(content_map)" "$map_before" "every file's content census is unchanged — only paths moved"
assert_eq "$(cksum < CLAUDE.md)" "$claude_before" "CLAUDE.md is byte-identical — the script never opens it"
assert_eq "$(cksum < .marvin/agents/reporting.md)" "$guide_before" "a guide naming .docs/reports/ is untouched"
assert_file_has "CLAUDE.md" '`.docs/reports/2026-09-01-digest.md`' "the old reference survives for the agent to judge"

hd "RG1 a report named x*.md cannot drag in a gitignored sibling at the destination"
mk_repo35 rg1
printf 'star report\n' > '.docs/reports/x*.md'
printf '%s\n' '.marvin/reports/xsecret.md' >> .gitignore
commit_all "a report whose name is a glob"
mkdir -p .marvin/reports
printf 'API_TOKEN=s3cr3t-not-for-git\n' > .marvin/reports/xsecret.md
assert_clean "the ignored sibling leaves the tree clean"
run_migrate
assert_rc 0
assert_tracked '.marvin/reports/x*.md' "the real report moved"
assert_not_tracked ".marvin/reports/xsecret.md" "the gitignored sibling was NOT force-staged"
if git diff --cached --name-only | grep -Fq xsecret; then
  bad "the gitignored sibling entered the staged set"; else ok "staged set free of the ignored sibling"; fi
assert_out 'renamed: ".docs/reports/x*.md" -> ".marvin/reports/x*.md"'

hd "RT9 no recursive delete, and exactly one pinned staging call"
if grep -nE 'git[[:space:]]+rm|rm[[:space:]]+-[a-zA-Z]*r|rm[[:space:]]+-rf' "$MIGRATE"; then
  bad "recursive delete or \`git rm\` present in ${SELF}.sh"
else
  ok "no \`git rm\` and no recursive rm in ${SELF}.sh"
fi
add_lines=$(grep -nE '^[[:space:]]*git[[:space:]]+add' "$MIGRATE")
assert_eq "$(printf '%s\n' "$add_lines" | grep -c .)" "1" "exactly one git add invocation"
assert_eq "$(printf '%s' "$add_lines" | sed 's/^[0-9]*:[[:space:]]*//')" \
  'git add -f -- "${ADDARGS[@]}"' "the staging call matches its pinned form (ADDARGS are :(literal) pathspecs)"
if grep -nE '^[^#]*git[[:space:]]+commit' "$MIGRATE"; then bad "the script contains a git commit"
else ok "the script never commits"; fi

hd "RS1 symlinks are refused before anything moves — every path of the set"
# (a) .marvin/reports → outside
mk_repo35 rs1a
mkdir -p "$WORK/rs1a-outside"
printf '%s\n' '.marvin/reports' >> .gitignore
commit_all "gitignore the link"
ln -s "$WORK/rs1a-outside" .marvin/reports
head_before=$(git rev-parse HEAD)
run_migrate
assert_rc 6 ".marvin/reports symlink refused"
assert_out "result=refused-symlink"
assert_out "symlink: .marvin/reports"
assert_eq "$(git rev-parse HEAD)" "$head_before" "HEAD unchanged"
assert_tracked ".docs/reports/2026-09-01-digest.md" "nothing moved"
assert_eq "$(find "$WORK/rs1a-outside" -type f | wc -l | tr -d ' ')" "0" "no report left the repository"
assert_eq "$(report_lines | grep -c '^symlink: ')" "1" "one record per symlinked path"
assert_no_move_map "symlink refusal"
run_migrate --check
assert_rc 6 "--check predicts the refusal"
assert_out "result=plan-only-symlink"
# (b) .docs/reports itself → outside: git lists nothing through it, so only the fixed set sees it
mk_repo35 rs1b
git rm -q -r .docs/reports >/dev/null
printf '%s\n' '.docs/reports' >> .gitignore
commit_all "reports kept outside, behind an ignored link"
mkdir -p "$WORK/rs1b-outside"; printf 'outside report\n' > "$WORK/rs1b-outside/2026-01.md"
ln -s "$WORK/rs1b-outside" .docs/reports
assert_clean "fixture: the ignored link leaves the tree clean"
run_migrate
assert_rc 6 "a symlinked .docs/reports is refused, never reported as nothing-to-do"
assert_out "symlink: .docs/reports"
assert_file_has "$WORK/rs1b-outside/2026-01.md" "outside report" "the outside file is untouched"
# (c) .docs → outside
mk_repo35 rs1c
mkdir -p "$WORK/rs1c-outside/reports"; printf 'x\n' > "$WORK/rs1c-outside/reports/r.md"
git rm -q -r .docs >/dev/null
printf '%s\n' '.docs' >> .gitignore
commit_all "the docs estate lives elsewhere"
ln -s "$WORK/rs1c-outside" .docs
run_migrate
assert_rc 6 "a symlinked .docs is refused"
assert_out "symlink: .docs"
# (d) a tracked report that is itself a symlink
mk_repo35 rs1d
ln -s 2026-09-01-digest.md .docs/reports/latest.md
commit_all "a committed link to the latest digest"
run_migrate
assert_rc 6 "a symlinked report is refused, never moved"
assert_out "symlink: .docs/reports/latest.md"
assert_tracked ".docs/reports/latest.md" "nothing moved"
# (e) .marvin → outside
mk_repo35 rs1e
mkdir -p "$WORK/rs1e-outside"
git rm -q -r .marvin >/dev/null
printf '%s\n' '.marvin' >> .gitignore
commit_all "gitignore .marvin"
ln -s "$WORK/rs1e-outside" .marvin
run_migrate
assert_rc 6 "a symlinked .marvin is refused"
assert_out "symlink: .marvin"
assert_eq "$(find "$WORK/rs1e-outside" -type f | wc -l | tr -d ' ')" "0" "no report left the repository"

hd "RS2 a symlink refusal reports the symlink and nothing else — no collision lines"
# A `.marvin` that links to a FILE makes every destination look "blocked by a file"; those
# collisions are artefacts of the link, and a refusal that prints them sends the user
# reconciling the wrong thing.
mk_repo35 rs2
printf 'outside\n' > "$WORK/rs2-outside-file"
git rm -q -r .marvin >/dev/null
printf '%s\n' '.marvin' >> .gitignore
commit_all "gitignore .marvin"
ln -s "$WORK/rs2-outside-file" .marvin
run_migrate
assert_rc 6 "refused"
assert_out "result=refused-symlink"
assert_out "symlink: .marvin"
assert_out "collisions=0"
assert_eq "$(report_lines | grep -c '^collision: ')" "0" "no collision records on the symlink refusal"
assert_report_wellformed "symlink refusal over a linked file"
run_migrate --check
assert_rc 6 "--check predicts the refusal"
assert_out "collisions=0"
assert_eq "$(report_lines | grep -c '^collision: ')" "0" "no collision records on the dry-run symlink refusal either"
assert_file_has "$WORK/rs2-outside-file" "outside" "the linked file is untouched"

hd "RP1 an assume-unchanged file is refused (its changes are invisible to git status)"
mk_repo35 rp1
git update-index --assume-unchanged src/app.js
printf 'uncommitted work nobody can see\n' >> src/app.js
assert_clean "fixture: porcelain is empty although src/app.js is modified"
run_migrate
assert_rc 9 "refused"
assert_out "result=refused-repo-state"
assert_out "assume-unchanged bit set on src/app.js"
assert_file_has "src/app.js" "uncommitted work nobody can see" "the invisible work was NOT destroyed"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md" "nothing moved"
assert_no_move_map "repo-state refusal"

hd "RP2 a merge in progress is refused, even with an empty porcelain"
mk_repo35 rp2
git checkout -q -b other
printf 'X\n' >> src/app.js
git commit -qam "change on other"
git checkout -q -
printf 'X\n' >> src/app.js
git commit -qam "same change applied directly"
git merge --no-commit --no-ff other >/dev/null 2>&1
assert_clean "fixture: porcelain is empty while MERGE_HEAD exists"
run_migrate
assert_rc 9 "refused — the agent's commit would silently conclude the consumer's merge"
assert_out "MERGE_HEAD exists"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md" "nothing moved"

hd "RP3 a detached or unborn HEAD is refused"
mk_repo35 rp3
git checkout -q --detach
run_migrate
assert_rc 9 "detached refused"
assert_out "HEAD is detached"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md" "nothing moved"
require_workdir
rm -rf "$WORK/rp3u"; mkdir -p "$WORK/rp3u/.docs/reports"; cd "$WORK/rp3u" || exit 1
git init -q .; git config user.email t@t; git config user.name "kit test"
printf 'x\n' > .docs/reports/r.md
git add -- .docs/reports/r.md
run_migrate
assert_rc 9 "unborn HEAD refused — there is nothing to roll back to"
assert_out "HEAD is unborn"

hd "RP4 skip-worktree / sparse checkout is refused"
mk_repo35 rp4
git update-index --skip-worktree src/app.js
run_migrate
assert_rc 9 "refused"
assert_out "skip-worktree bit set on src/app.js"
git update-index --no-skip-worktree src/app.js
git config core.sparseCheckout true
run_migrate
assert_rc 9 "sparse checkout refused too"
assert_out "core.sparseCheckout is enabled"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md" "nothing moved"

hd "RP5 a dirty or recursed submodule is refused"
require_workdir
rm -rf "$WORK/rp5-origin"; mkdir -p "$WORK/rp5-origin"; cd "$WORK/rp5-origin"
git init -q .; git config user.email t@t; git config user.name "kit test"; git config commit.gpgsign false
printf 'v1|\n' > lib.txt; git add -- . >/dev/null; git commit -qm v1
mk_repo35 rp5
git -c protocol.file.allow=always submodule add -q "$WORK/rp5-origin" vendor >/dev/null 2>&1
git config -f .gitmodules submodule.vendor.ignore all
commit_all "submodule with ignore=all"
printf 'v1|WORK-A|\n' > vendor/lib.txt
assert_clean "fixture: porcelain is empty although the submodule is dirty"
run_migrate
assert_rc 9 "refused"
assert_out "a submodule change is hidden from git status: vendor"
assert_file_has "vendor/lib.txt" "WORK-A" "the submodule working tree was NOT reset"
git -C vendor checkout -q -- lib.txt
git config submodule.recurse true
run_migrate
assert_rc 9 "submodule.recurse refused too"
assert_out "submodule.recurse is enabled"

hd "RP6 a submodule under .docs/reports/ is refused — moving it would edit .gitmodules"
mk_repo35 rp6
git -c protocol.file.allow=always submodule add -q "$WORK/rp5-origin" .docs/reports/vendored >/dev/null 2>&1
commit_all "a submodule inside the reports folder"
gm_before=$(cksum < .gitmodules)
run_migrate
assert_rc 9 "refused"
assert_out "a submodule lives under .docs/reports/: .docs/reports/vendored"
assert_eq "$(cksum < .gitmodules)" "$gm_before" ".gitmodules untouched"
assert_not_tracked ".marvin/reports/2026-09-01-digest.md" "nothing moved"

hd "RM3 the report is byte-identical under a C and a UTF-8 locale"
mk_repo35 rm3
printf 'x\n' > '.docs/reports/café.md'
commit_all "non-ASCII report name"
c_out=$(LC_ALL=C LANG=C bash "$MIGRATE" --check 2>&1)
u_out=$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bash "$MIGRATE" --check 2>&1)
assert_eq "$u_out" "$c_out" "identical report bytes under C and en_US.UTF-8"
OUT="$c_out"
assert_out "result=plan" "no locale-induced repo-state refusal"
assert_out 'renamed: ".docs/reports/caf\303\251.md" -> ".marvin/reports/caf\303\251.md"' "high bytes are octal-escaped"
assert_report_wellformed "non-ASCII names"

hd "RX1 hostile paths cannot inject report records"
mk_repo35 rx1
INJ=$(printf '.docs/reports/oops\nrenamed: FAKESRC.md -> ATTACKER-PATH.md\nzz.md')
printf 'x\n' > "$INJ"
HOSTILE_TAB=$(printf '.docs/reports/tab\there.md')
printf 'x\n' > "$HOSTILE_TAB"
printf 'x\n' > '.docs/reports/arrow -> target.md'
printf 'x\n' > '.docs/reports/quote".md'
commit_all "hostile report names"
run_migrate
assert_rc 0
assert_report_wellformed "hostile paths"
assert_no_record "renamed: FAKESRC.md -> ATTACKER-PATH.md"
assert_out 'renamed: ".docs/reports/oops\nrenamed: FAKESRC.md -> ATTACKER-PATH.md\nzz.md" -> ".marvin/reports/oops\nrenamed: FAKESRC.md -> ATTACKER-PATH.md\nzz.md"'
assert_out 'renamed: ".docs/reports/tab\there.md" -> ".marvin/reports/tab\there.md"'
assert_out 'renamed: ".docs/reports/arrow -> target.md" -> ".marvin/reports/arrow -> target.md"'
assert_out 'renamed: ".docs/reports/quote\".md" -> ".marvin/reports/quote\".md"'
tracked_z "$(printf '.marvin/reports/oops\nrenamed: FAKESRC.md -> ATTACKER-PATH.md\nzz.md')"
chk $? "the hostile report moved like any other"
assert_check_equivalence "hostile paths"

hd "RU1 flags and a non-repository are refused without touching anything"
mk_repo35 ru1
before=$(snapshot)
run_migrate --commit
assert_rc 4 "--commit is refused — committing is the agent's step"
assert_out "unknown option: --commit"
assert_eq "$(snapshot)" "$before" "repository untouched"
mkdir -p "$WORK/ru1-nogit"
OUT=$(cd "$WORK/ru1-nogit" && env GIT_CEILING_DIRECTORIES="$WORK" bash "$MIGRATE" 2>&1); RC=$?
assert_rc 4
assert_out "not a git work tree"

r27_killed_run_rolls_back() {
  mk_repo35 "r27-$1"
  i=0
  while [ "$i" -lt 150 ]; do                     # widen the window so the kill lands mid-run
    printf 'report %s\n' "$i" > ".docs/reports/archive/r$i.md"
    i=$((i+1))
  done
  commit_all "many reports"
  before=$(snapshot)
  head_before=$(git rev-parse HEAD)
  bash "$MIGRATE" > "$WORK/r27.log" 2>&1 &
  mig_pid=$!
  # Wait for the first actual mutation (`.marvin/reports` appears) — a kill during planning has
  # nothing to roll back, and every assertion would pass for free.
  waited=0
  while [ ! -d .marvin/reports ] && [ "$waited" -lt 1500 ]; do
    kill -0 "$mig_pid" 2>/dev/null || break
    sleep 0.02
    waited=$((waited+1))
  done
  if [ -d .marvin/reports ]; then ok "the migration reached its first change before the kill"
  else bad "the migration never created .marvin/reports — the kill would prove nothing"; fi
  kill -TERM "$mig_pid" 2>/dev/null
  wait "$mig_pid" 2>/dev/null
  mig_rc=$?
  if grep -q "result=staged" "$WORK/r27.log"; then
    bad "the kill missed its window — the migration completed (rc=$mig_rc); fixture needs a wider window"
  else
    ok "the run was killed after it started moving files (rc=$mig_rc)"
    assert_eq "$(snapshot)" "$before" "repository byte-identical to its pre-run state"
    assert_clean "no staged half-migration left behind"
    assert_tracked ".docs/reports/2026-09-01-digest.md" "sources restored"
    assert_not_tracked ".marvin/reports/2026-09-01-digest.md"
    if [ -e .marvin/reports ]; then bad ".marvin/reports was left behind"; else ok "created directories removed"; fi
    grep -q "restoring the repository to" "$WORK/r27.log"
    chk $? "the run reported its rollback"
    OUT=$(cat "$WORK/r27.log")
    assert_out "result=rolled-back"
    assert_out "staged=0"
    assert_no_move_map "rollback"
  fi
}
rep=1
while [ "$rep" -le "$REPEAT_TIMING" ]; do
  hd "R27 a killed run rolls back to the pre-run state (run $rep/$REPEAT_TIMING)"
  r27_killed_run_rolls_back "$rep"
  rep=$((rep+1))
done

fi  # end SUITE v0.35.0

# ═════════════════════════════════════════════════════════════════════════════════════════════
# SUITE runs — scripts/marvin-runs-migrate.sh (fixtures N*)
# The run-state move (AOS-237): flat `.marvin/runs/<KEY|adhoc>/` folders — in the main checkout
# and in every worktree under `.claude/worktrees/` — move into ONE legacy session folder,
# `<main>/.marvin/runs/<UTC>-00000000-0000-0000-0000-000000000000/<KEY|adhoc>/`. Ignored state
# only: it stages nothing, edits nothing, and refuses the whole run on any guard.
# ═════════════════════════════════════════════════════════════════════════════════════════════
if want runs; then
use_migration runs

NIL=00000000-0000-0000-0000-000000000000
NL_CHAR=$'\n'
mk_runs() {  # mk_runs <dir> — a committed Marvin project with flat run state in its main checkout
  require_workdir
  local d="$WORK/$1"
  rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
  git init -q .
  git config user.email test@example.com
  git config user.name "kit test"
  git config commit.gpgsign false
  mkdir -p .marvin/agents src
  printf -- '---\nkit_version: 0.39.0\n---\n' > .marvin/PROJECT-INFO.md
  printf 'console.log(1)\n' > src/app.js
  printf '%s\n' '.marvin/runs/' '.claude/worktrees/' > .gitignore
  git add -- . >/dev/null
  git commit -qm "v0.39.0 install"
  mkdir -p .marvin/runs/AOS-1 .marvin/runs/adhoc
  printf '*\n' > .marvin/runs/.gitignore
  printf '| round |\n| 1 | main |\n' > .marvin/runs/AOS-1/ledger.md
  printf 'developer report\n' > .marvin/runs/AOS-1/20260101T000000Z-developer.md
  printf 'a look-up\n' > .marvin/runs/adhoc/20260102T000000Z-ponytail.md
  touch -t 202601010000 .marvin/runs/AOS-1/ledger.md
}
mk_wt() {  # mk_wt <name> — a worktree under .claude/worktrees/ holding its own flat run state
  local w=".claude/worktrees/$1"
  git worktree add -q "$w" -b "wt-$(printf '%s' "$1" | tr ' ' '-')" >/dev/null 2>&1 || { bad "fixture: worktree $1"; return 1; }
  mkdir -p "$w/.marvin/runs/AOS-2"
  printf 'validator report from %s\n' "$1" > "$w/.marvin/runs/AOS-2/20260103T000000Z-validator-$1.md"
}
legacy_dirs()  { local d; for d in .marvin/runs/*-"$NIL"; do [ -d "$d" ] && printf '%s\n' "${d##*/}"; done; return 0; }
norm_runs()    { sed -E "s/[0-9]{8}T[0-9]{6}Z-$NIL/<UTC>-nil/g"; }
tree_sum()     { find "$1" -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort; }
content_set()  { find . -path ./.git -prune -o -type f -exec cksum {} + | awk '{print $1" "$2}' | LC_ALL=C sort -u; }
file_count()   { find . -path ./.git -prune -o -type f -print | wc -l | tr -d ' '; }
assert_gone()  { if [ -e "$1" ] || [ -L "$1" ]; then bad "gone: $1${2:+ — $2}"; else ok "gone: $1${2:+ — $2}"; fi; }
assert_there() { [ -f "$1" ] && [ ! -L "$1" ]; chk $? "present: $1${2:+ — $2}"; }
assert_body()  { assert_eq "$(cat -- "$1" 2>/dev/null)" "$2" "$1 holds the expected bytes${3:+ — $3}"; }
assert_runs_refused() {  # $1 = context — exit 1, result=refused, no move records, well-formed
  assert_rc 1 "$1"
  assert_out "result=refused"
  assert_eq "$(report_lines | grep -c '^moved: ')" "0" "no moved records — $1"
  assert_eq "$(report_lines | grep -c '^kept-older: ')" "0" "no kept-older records — $1"
  assert_report_wellformed "$1"
}
LEDGER_MAIN=$(printf '| round |\n| 1 | main |')

hd "N01 --check changes nothing and prints exactly the real run's records"
mk_runs n01; mk_wt wt1
before=$(snapshot)
run_migrate --check
assert_rc 0 "--check"
assert_eq "$(snapshot)" "$before" "every file byte-identical before/after --check (worktrees and ignored run state included)"
assert_eq "$(legacy_dirs)" "" "--check created no legacy folder"
assert_out "mode=check"
assert_out "result=done"
assert_out "moved=4"
assert_report_wellformed "--check plan"
check_rep=$(report_lines | norm_runs | grep -v '^mode=')
run_migrate
assert_rc 0 "the real run"
L=$(legacy_dirs)
printf '%s' "$L" | grep -Eq "^[0-9]{8}T[0-9]{6}Z-$NIL\$"
chk $? "one legacy folder <UTC>-<nil UUID> was created (got '$L')"
assert_eq "$(report_lines | norm_runs | grep -v '^mode=')" "$check_rep" "the real run's report equals the --check report but for mode="
assert_out "mode=apply"
assert_out "target=.marvin/runs/$L"
assert_out "moved: .marvin/runs/AOS-1/20260101T000000Z-developer.md -> .marvin/runs/$L/AOS-1/20260101T000000Z-developer.md"
assert_out "moved: .marvin/runs/AOS-1/ledger.md -> .marvin/runs/$L/AOS-1/ledger.md"
assert_out "moved: .marvin/runs/adhoc/20260102T000000Z-ponytail.md -> .marvin/runs/$L/adhoc/20260102T000000Z-ponytail.md"
assert_out "moved: .claude/worktrees/wt1/.marvin/runs/AOS-2/20260103T000000Z-validator-wt1.md -> .marvin/runs/$L/AOS-2/20260103T000000Z-validator-wt1.md"
assert_body ".marvin/runs/$L/AOS-1/ledger.md" "$LEDGER_MAIN" "moved byte for byte"
assert_gone .marvin/runs/AOS-1/ledger.md "the source is removed once its copy verified"
assert_gone .claude/worktrees/wt1/.marvin/runs/AOS-2/20260103T000000Z-validator-wt1.md
assert_there .marvin/runs/.gitignore "the runs .gitignore is never moved"
assert_gone ".marvin/runs/$L/.gitignore"
assert_clean "nothing staged, nothing dirtied"
assert_eq "$(git rev-list --count HEAD)" "1" "nothing committed"
assert_report_wellformed "real run"

hd "N02 a symlink at any component refuses the whole run — nothing moved"
n02_refused() {  # n02_refused <label> <symlink record path> <outside dir>
  local out_before
  out_before=$(tree_sum "$3")
  before=$(snapshot)
  run_migrate
  assert_runs_refused "$1"
  assert_out "symlink: $2"
  assert_eq "$(snapshot)" "$before" "nothing changed — $1"
  assert_eq "$(tree_sum "$3")" "$out_before" "the link's target is untouched — $1"
  run_migrate --check
  assert_rc 1 "--check predicts the refusal — $1"
  assert_out "symlink: $2"
}
# (a) the project's .marvin/runs
mk_runs n02a; mkdir -p "$WORK/n02a-out"
mv .marvin/runs/AOS-1 .marvin/runs/adhoc .marvin/runs/.gitignore "$WORK/n02a-out/"
rmdir .marvin/runs; ln -s "$WORK/n02a-out" .marvin/runs
n02_refused "project .marvin/runs" ".marvin/runs" "$WORK/n02a-out"
run_migrate --defer-flat
assert_rc 1 "--defer-flat still guards the target .marvin/runs"
assert_out "symlink: .marvin/runs"
# (b) the project's .marvin
mk_runs n02b; mv .marvin "$WORK/n02b-out"; ln -s "$WORK/n02b-out" .marvin
n02_refused "project .marvin" ".marvin" "$WORK/n02b-out"
run_migrate --defer-flat
assert_rc 1 "--defer-flat still guards the target .marvin"
assert_out "symlink: .marvin"
# (c) a source worktree's .marvin
mk_runs n02c; mk_wt wt1
mv .claude/worktrees/wt1/.marvin "$WORK/n02c-out"; ln -s "$WORK/n02c-out" .claude/worktrees/wt1/.marvin
n02_refused "worktree .marvin" ".claude/worktrees/wt1/.marvin" "$WORK/n02c-out"
# (d) a source worktree's .marvin/runs
mk_runs n02d; mk_wt wt1
mv .claude/worktrees/wt1/.marvin/runs "$WORK/n02d-out"; ln -s "$WORK/n02d-out" .claude/worktrees/wt1/.marvin/runs
n02_refused "worktree .marvin/runs" ".claude/worktrees/wt1/.marvin/runs" "$WORK/n02d-out"
# (e) a key folder
mk_runs n02e; mkdir -p "$WORK/n02e-out"; printf 'outside\n' > "$WORK/n02e-out/20260104T000000Z-x.md"
ln -s "$WORK/n02e-out" .marvin/runs/AOS-9
n02_refused "key folder" ".marvin/runs/AOS-9" "$WORK/n02e-out"
# (f) a run file
mk_runs n02f; mkdir -p "$WORK/n02f-out"; printf 'outside\n' > "$WORK/n02f-out/r.md"
ln -s "$WORK/n02f-out/r.md" .marvin/runs/AOS-1/20260105T000000Z-linked.md
n02_refused "run file" ".marvin/runs/AOS-1/20260105T000000Z-linked.md" "$WORK/n02f-out"
# (g) the legacy target folder
mk_runs n02g; mkdir -p "$WORK/n02g-out"
ln -s "$WORK/n02g-out" ".marvin/runs/20260301T000000Z-$NIL"
n02_refused "legacy folder" ".marvin/runs/20260301T000000Z-$NIL" "$WORK/n02g-out"
# (h) a key folder inside the reused legacy folder
mk_runs n02h; mkdir -p "$WORK/n02h-out" ".marvin/runs/20260301T000000Z-$NIL"
ln -s "$WORK/n02h-out" ".marvin/runs/20260301T000000Z-$NIL/AOS-1"
n02_refused "target key folder" ".marvin/runs/20260301T000000Z-$NIL/AOS-1" "$WORK/n02h-out"
# (i) a target file
mk_runs n02i; mkdir -p "$WORK/n02i-out" ".marvin/runs/20260301T000000Z-$NIL/adhoc"; printf 'outside\n' > "$WORK/n02i-out/t.md"
ln -s "$WORK/n02i-out/t.md" ".marvin/runs/20260301T000000Z-$NIL/adhoc/20260102T000000Z-ponytail.md"
n02_refused "target file" ".marvin/runs/20260301T000000Z-$NIL/adhoc/20260102T000000Z-ponytail.md" "$WORK/n02i-out"

hd "N03 an immutable report already at its target and differing is a duplicate: the source stays"
mk_runs n03
L="20260301T000000Z-$NIL"
mkdir -p ".marvin/runs/$L/AOS-1" ".marvin/runs/$L/adhoc"
printf 'the copy already migrated\n' > ".marvin/runs/$L/AOS-1/20260101T000000Z-developer.md"
cp -p .marvin/runs/adhoc/20260102T000000Z-ponytail.md ".marvin/runs/$L/adhoc/"
run_migrate
assert_rc 0
assert_out "duplicate: .marvin/runs/AOS-1/20260101T000000Z-developer.md (differs from .marvin/runs/$L/AOS-1/20260101T000000Z-developer.md)"
assert_body .marvin/runs/AOS-1/20260101T000000Z-developer.md "developer report" "the differing source stays"
assert_body ".marvin/runs/$L/AOS-1/20260101T000000Z-developer.md" "the copy already migrated" "the existing target is kept"
assert_out "moved: .marvin/runs/adhoc/20260102T000000Z-ponytail.md -> .marvin/runs/$L/adhoc/20260102T000000Z-ponytail.md"
assert_gone .marvin/runs/adhoc/20260102T000000Z-ponytail.md "an identical source is removed (its bytes are at the target)"
assert_body ".marvin/runs/$L/adhoc/20260102T000000Z-ponytail.md" "a look-up"
assert_out "duplicates=1"
assert_eq "$(legacy_dirs)" "$L" "the existing legacy folder is reused"
assert_report_wellformed "duplicate"
# (b) two sources, no target: the main checkout's copy lands, the differing worktree copy stays
mk_runs n03b; mk_wt wt1
mkdir -p .claude/worktrees/wt1/.marvin/runs/AOS-1
printf 'a different developer report\n' > .claude/worktrees/wt1/.marvin/runs/AOS-1/20260101T000000Z-developer.md
run_migrate
assert_rc 0
L=$(legacy_dirs)
assert_body ".marvin/runs/$L/AOS-1/20260101T000000Z-developer.md" "developer report" "the first source lands"
assert_body .claude/worktrees/wt1/.marvin/runs/AOS-1/20260101T000000Z-developer.md "a different developer report" "the differing second source stays"
assert_out "duplicate: .claude/worktrees/wt1/.marvin/runs/AOS-1/20260101T000000Z-developer.md (differs from .marvin/runs/$L/AOS-1/20260101T000000Z-developer.md)"
assert_report_wellformed "duplicate between sources"

hd "N04 diverged ledger.md / build-brief*.md copies: the newer wins, every older one is kept as <stem>.older-<n>.md"
mk_runs n04; mk_wt wt1
W=.claude/worktrees/wt1/.marvin/runs/AOS-1
mkdir -p "$W"
printf '| round |\n| 1 | main |\n| 2 | wt1 |\n' > "$W/ledger.md"; touch -t 202602010000 "$W/ledger.md"
printf 'brief v2\n' > .marvin/runs/AOS-1/build-brief-api.md; touch -t 202602010000 .marvin/runs/AOS-1/build-brief-api.md
printf 'brief v1\n' > "$W/build-brief-api.md";                touch -t 202601010000 "$W/build-brief-api.md"
run_migrate
assert_rc 0
L=$(legacy_dirs); T=".marvin/runs/$L/AOS-1"
assert_body "$T/ledger.md" "$(printf '| round |\n| 1 | main |\n| 2 | wt1 |')" "the newer ledger (the worktree's) wins"
assert_body "$T/ledger.older-1.md" "$LEDGER_MAIN" "the older ledger is kept beside it"
assert_out "moved: $W/ledger.md -> $T/ledger.md"
assert_out "kept-older: .marvin/runs/AOS-1/ledger.md -> $T/ledger.older-1.md"
assert_body "$T/build-brief-api.md" "brief v2" "the newer build brief (the main checkout's) wins"
assert_body "$T/build-brief-api.older-1.md" "brief v1"
assert_out "kept-older: $W/build-brief-api.md -> $T/build-brief-api.older-1.md"
assert_out "kept-older=2"
assert_eq "$(report_lines | grep -c '^duplicate: ')" "0" "a mutable file is never a duplicate"
assert_gone .marvin/runs/AOS-1/ledger.md; assert_gone "$W/ledger.md"; assert_gone "$W/build-brief-api.md"
assert_report_wellformed "ledger merge"
# (b) a target and an older-1 already there: the displaced target and the older source take fresh numbers
mk_runs n04b; mk_wt wt1
L="20260301T000000Z-$NIL"; T=".marvin/runs/$L/AOS-1"; W=.claude/worktrees/wt1/.marvin/runs/AOS-1
mkdir -p "$T" "$W"
printf 'cur\n' > "$T/ledger.md"; touch -t 202601150000 "$T/ledger.md"
printf 'ancient\n' > "$T/ledger.older-1.md"
printf 'new\n' > "$W/ledger.md"; touch -t 202602010000 "$W/ledger.md"
run_migrate
assert_rc 0
assert_body "$T/ledger.md" "new" "the newest copy wins"
assert_body "$T/ledger.older-1.md" "ancient" "an existing older copy is never overwritten"
assert_body "$T/ledger.older-2.md" "cur" "the displaced target is kept"
assert_body "$T/ledger.older-3.md" "$LEDGER_MAIN" "the older source is kept"
assert_out "kept-older: $T/ledger.md -> $T/ledger.older-2.md"
assert_out "kept-older: .marvin/runs/AOS-1/ledger.md -> $T/ledger.older-3.md"
assert_out "moved: $W/ledger.md -> $T/ledger.md"
assert_report_wellformed "ledger merge onto an existing target"

hd "N05 --defer <worktree> leaves that worktree untouched and reports it deferred"
mk_runs n05; mk_wt wt1; mk_wt wt2
wt1_before=$(tree_sum .claude/worktrees/wt1)
run_migrate --defer .claude/worktrees/wt1
assert_rc 0
assert_out "deferred: .claude/worktrees/wt1 — open session"
assert_out "deferred=1"
assert_eq "$(tree_sum .claude/worktrees/wt1)" "$wt1_before" "the deferred worktree is byte-identical"
assert_eq "$(report_lines | grep -c 'worktrees/wt1/')" "0" "no record names a file in the deferred worktree"
L=$(legacy_dirs)
assert_there ".marvin/runs/$L/AOS-2/20260103T000000Z-validator-wt2.md" "the other worktree moved"
assert_gone .marvin/runs/AOS-1/20260101T000000Z-developer.md "the main checkout moved"
assert_report_wellformed "deferral"
# the same worktree under an absolute (possibly non-physical) spelling is the same worktree
mk_runs n05b; mk_wt wt1
wt1_before=$(tree_sum .claude/worktrees/wt1)
run_migrate --defer "$WORK/n05b/.claude/worktrees/wt1/"
assert_rc 0 "an absolute spelling is accepted"
assert_out "deferred: .claude/worktrees/wt1 — open session"
assert_eq "$(tree_sum .claude/worktrees/wt1)" "$wt1_before" "and the worktree is untouched"
# usage errors: exit 2, nothing changed
mk_runs n05c; mk_wt wt1
before=$(snapshot)
run_migrate --defer src;                 assert_rc 2 "--defer of a directory that is not a worktree"
run_migrate --defer "$WORK/n05c-nowhere"; assert_rc 2 "--defer of a missing path"
run_migrate --defer .;                   assert_rc 2 "--defer of the main checkout (that is --defer-flat)"
run_migrate --defer;                     assert_rc 2 "--defer without a path"
run_migrate --bogus;                     assert_rc 2 "an unknown flag"
run_migrate . .;                         assert_rc 2 "two repository paths"
mkdir -p "$WORK/n05-norepo"
run_migrate "$WORK/n05-norepo";          assert_rc 2 "not a git work tree"
assert_eq "$(snapshot)" "$before" "no usage error changed anything"
# a failed `git worktree list` is never "no worktrees": exit 2, nothing moved
mkdir -p "$WORK/shim-git"
cat > "$WORK/shim-git/git" <<EOF
#!/bin/sh
for a in "\$@"; do [ "\$a" = worktree ] && { echo "fatal: simulated worktree list failure" >&2; exit 128; }; done
exec $(command -v git) "\$@"
EOF
chmod +x "$WORK/shim-git/git"
PATH="$WORK/shim-git:$PATH" run_migrate
assert_rc 2 "a failed worktree listing exits 2"
assert_out "refused: cannot list worktrees"
assert_eq "$(snapshot)" "$before" "nothing moved when the worktrees cannot be listed"

hd "N06 --defer-flat leaves the main checkout's flat folders untouched"
mk_runs n06; mk_wt wt1
flat_before=$( { tree_sum .marvin/runs/AOS-1; tree_sum .marvin/runs/adhoc; } )
run_migrate --defer-flat
assert_rc 0
assert_out "deferred: .marvin/runs — open session"
assert_eq "$( { tree_sum .marvin/runs/AOS-1; tree_sum .marvin/runs/adhoc; } )" "$flat_before" "the main checkout's flat folders are byte-identical"
assert_eq "$(report_lines | grep -c '^moved: \.marvin/runs/')" "0" "no record moves a main-checkout file"
L=$(legacy_dirs)
assert_there ".marvin/runs/$L/AOS-2/20260103T000000Z-validator-wt1.md" "the worktree still moved"
assert_report_wellformed "flat deferral"

hd "N07 a re-run is result=nothing-to-do and changes nothing"
mk_runs n07; mk_wt wt1
run_migrate
assert_rc 0; assert_out "result=done"
L=$(legacy_dirs)
before=$(snapshot)
run_migrate
assert_rc 0 "the re-run"
assert_out "result=nothing-to-do"
assert_out "moved=0"
assert_out "target=.marvin/runs/$L"
assert_eq "$(snapshot)" "$before" "the re-run changed nothing"
assert_report_wellformed "re-run"
run_migrate --check
assert_rc 0; assert_out "result=nothing-to-do"
# no run state at all: nothing to do, and no legacy folder is invented
mk_runs n07b; rm -rf .marvin/runs/AOS-1 .marvin/runs/adhoc
run_migrate
assert_rc 0; assert_out "result=nothing-to-do"; assert_out "target=none"
assert_eq "$(legacy_dirs)" "" "no legacy folder created when nothing moves"

hd "N08 a folder whose name fails the key rule is skipped and reported, never moved"
mk_runs n08
S="20260310T101010Z-12345678-1234-1234-1234-123456789abc"
mkdir -p .marvin/runs/notes .marvin/runs/aos-7 .marvin/runs/AOS-1/sub ".marvin/runs/$S/AOS-5"
printf 'n\n' > .marvin/runs/notes/x.md
printf 'l\n' > .marvin/runs/aos-7/y.md
printf 'r\n' > .marvin/runs/README.md
printf 's\n' > .marvin/runs/AOS-1/sub/z.md
printf 'per-session ledger\n' > ".marvin/runs/$S/AOS-5/ledger.md"
run_migrate
assert_rc 0
assert_out "skipped: .marvin/runs/notes (not a key folder)"
assert_out "skipped: .marvin/runs/aos-7 (not a key folder)"
assert_out "skipped: .marvin/runs/README.md (not a key folder)"
assert_out "skipped: .marvin/runs/AOS-1/sub (not a run file)"
assert_out "skipped=4"
assert_body .marvin/runs/notes/x.md "n" "skipped folders stay"
assert_body .marvin/runs/aos-7/y.md "l"
assert_body .marvin/runs/AOS-1/sub/z.md "s"
assert_body ".marvin/runs/$S/AOS-5/ledger.md" "per-session ledger" "a per-session folder is never a source"
assert_eq "$(report_lines | grep -c "$S")" "0" "a per-session folder is not reported"
assert_eq "$(report_lines | grep -c '\.gitignore')" "0" "the runs .gitignore is neither moved nor reported"
L=$(legacy_dirs)
assert_gone ".marvin/runs/$L/notes"; assert_gone ".marvin/runs/$L/aos-7"
assert_there ".marvin/runs/$L/AOS-1/ledger.md" "key folders still move"
assert_report_wellformed "skips"

hd "N09 a target that git does not ignore refuses the run"
mk_runs n09
printf '%s\n' '.claude/worktrees/' > .gitignore
git commit -qam "stop ignoring run state"
rm -f .marvin/runs/.gitignore
before=$(snapshot)
run_migrate
assert_runs_refused "target not ignored"
report_lines | grep -Eq "^refused: not ignored by git: \.marvin/runs/[0-9]{8}T[0-9]{6}Z-$NIL/AOS-1/ledger\.md — "
chk $? "the refusal names the unignored target"
assert_eq "$(snapshot)" "$before" "nothing changed"
assert_eq "$(legacy_dirs)" "" "no legacy folder created"
run_migrate --check
assert_rc 1 "--check predicts it"

hd "N10 a tracked source file refuses the run"
mk_runs n10
git add -f -- .marvin/runs/AOS-1/20260101T000000Z-developer.md
git commit -qm "a run report committed by mistake"
before=$(snapshot)
run_migrate
assert_runs_refused "tracked source"
assert_out "refused: tracked by git: .marvin/runs/AOS-1/20260101T000000Z-developer.md"
assert_eq "$(snapshot)" "$before" "nothing changed"
assert_eq "$(legacy_dirs)" "" "no legacy folder created"
assert_tracked .marvin/runs/AOS-1/20260101T000000Z-developer.md "still tracked, still in place"

hd "N11 a repository path with a space"
mk_runs "n11 dir/my repo"; mk_wt "wt one"
D="$WORK/n11 dir/my repo"
cd / || exit 1
run_migrate "$D"
cd "$D" || exit 1
assert_rc 0 "run from outside, with the repo path as the argument"
L=$(legacy_dirs)
assert_there ".marvin/runs/$L/AOS-2/20260103T000000Z-validator-wt one.md" "the worktree with a space moved"
assert_gone ".claude/worktrees/wt one/.marvin/runs/AOS-2/20260103T000000Z-validator-wt one.md"
assert_there ".marvin/runs/$L/AOS-1/ledger.md"
assert_out "moved: \".claude/worktrees/wt one/.marvin/runs/AOS-2/20260103T000000Z-validator-wt one.md\" -> \".marvin/runs/$L/AOS-2/20260103T000000Z-validator-wt one.md\""
assert_report_wellformed "space in the path"
# a hostile run-file name: a newline cannot forge a record, it is encoded on its own line
mk_runs n11b
printf 'h\n' > ".marvin/runs/AOS-1/20260106T000000Z-a${NL_CHAR}moved: forged -> x.md"
run_migrate
assert_rc 0 "a newline in a run-file name"
assert_no_record "moved: forged -> x.md"
assert_report_wellformed "hostile name"
assert_eq "$(find .marvin/runs/AOS-1 -type f 2>/dev/null | wc -l | tr -d ' ')" "0" "the hostile file moved too"
mk_runs "n11 dir/my repo"; mk_wt "wt one"
run_migrate --defer "$D/.claude/worktrees/wt one" "$D"
assert_rc 0 "--defer of a worktree with a space"
assert_out "deferred: \".claude/worktrees/wt one\" — open session"
assert_there ".claude/worktrees/wt one/.marvin/runs/AOS-2/20260103T000000Z-validator-wt one.md" "deferred, untouched"

hd "N12 content invariant: every byte is either at its source or at its target"
mk_runs n12; mk_wt wt1; mk_wt wt2
mkdir -p .claude/worktrees/wt1/.marvin/runs/AOS-1 .claude/worktrees/wt1/.marvin/runs/notes .claude/worktrees/wt2/.marvin/runs/AOS-1 .claude/worktrees/wt2/.marvin/runs/adhoc
printf '| round |\n| 1 | main |\n| 2 | wt1 |\n' > .claude/worktrees/wt1/.marvin/runs/AOS-1/ledger.md
touch -t 202602010000 .claude/worktrees/wt1/.marvin/runs/AOS-1/ledger.md
printf 'scratch\n' > .claude/worktrees/wt1/.marvin/runs/notes/s.md
cp -p .marvin/runs/AOS-1/20260101T000000Z-developer.md .claude/worktrees/wt2/.marvin/runs/AOS-1/
printf 'another look-up\n' > .claude/worktrees/wt2/.marvin/runs/adhoc/20260102T000000Z-ponytail.md
before=$(content_set); n_before=$(file_count)
run_migrate
assert_rc 0
assert_out "duplicates=1"
assert_eq "$(content_set)" "$before" "the set of file contents is unchanged — nothing edited, lost or invented"
assert_eq "$(file_count)" "$((n_before - 1))" "exactly one file fewer: the byte-identical copy that was deduplicated"
assert_report_wellformed "content invariant"

hd "N13 a deferred worktree moves on a later run into the SAME legacy folder"
mk_runs n13; mk_wt wt1
run_migrate --defer .claude/worktrees/wt1
assert_rc 0
L1=$(legacy_dirs)
sleep 1   # a fresh name would now carry a later timestamp
run_migrate
assert_rc 0 "the later run"
assert_eq "$(legacy_dirs)" "$L1" "exactly one legacy folder, the first run's"
assert_out "target=.marvin/runs/$L1"
assert_there ".marvin/runs/$L1/AOS-2/20260103T000000Z-validator-wt1.md" "the formerly deferred worktree joined it"
assert_report_wellformed "reuse"
# more than one legacy folder: refused
mk_runs n13b
mkdir -p ".marvin/runs/20260301T000000Z-$NIL" ".marvin/runs/20260302T000000Z-$NIL"
before=$(snapshot)
run_migrate
assert_runs_refused "two legacy folders"
assert_out "refused: more than one legacy folder"
assert_eq "$(snapshot)" "$before" "nothing changed"
# a legacy name that is not a folder, and a target that is not a regular file: refused up front
mk_runs n13c
printf 'x\n' > ".marvin/runs/20260301T000000Z-$NIL"
before=$(snapshot)
run_migrate
assert_runs_refused "a legacy name that is a file"
assert_out "refused: a legacy name that is not a folder: .marvin/runs/20260301T000000Z-$NIL"
assert_eq "$(snapshot)" "$before" "nothing changed"
mk_runs n13d
mkdir -p ".marvin/runs/20260301T000000Z-$NIL/AOS-1/ledger.md"
before=$(snapshot)
run_migrate
assert_runs_refused "a target that is a folder"
assert_out "refused: a target that is not a regular file: .marvin/runs/20260301T000000Z-$NIL/AOS-1/ledger.md"
assert_eq "$(snapshot)" "$before" "nothing changed"

# a deferred worktree's ledger.md byte-identical to the one that landed is deduplicated on the later
# run — whether it is newer by mtime (the winner branch) or not (the kept-copy branch); no older-<n>
for n13_case in newer same; do
  mk_runs "n13e-$n13_case"; mk_wt wt1
  W=.claude/worktrees/wt1/.marvin/runs/AOS-1
  mkdir -p "$W"; cp -p .marvin/runs/AOS-1/ledger.md "$W/ledger.md"
  [ "$n13_case" = newer ] && touch -t 202603010000 "$W/ledger.md"
  run_migrate --defer .claude/worktrees/wt1
  assert_rc 0
  L1=$(legacy_dirs)
  run_migrate
  assert_rc 0 "the later run ($n13_case mtime)"
  assert_out "moved: $W/ledger.md -> .marvin/runs/$L1/AOS-1/ledger.md"
  assert_gone "$W/ledger.md" "the identical copy is removed ($n13_case mtime)"
  assert_body ".marvin/runs/$L1/AOS-1/ledger.md" "$LEDGER_MAIN" "the landed ledger is unchanged"
  assert_eq "$(find ".marvin/runs/$L1/AOS-1" -name 'ledger.older-*' | wc -l | tr -d ' ')" "0" "no older-<n> copy for identical bytes ($n13_case mtime)"
  assert_out "kept-older=0"
  assert_report_wellformed "identical ledger, $n13_case mtime"
done

hd "N14 the copy path (no hard link possible): bytes land verified, the source goes only after cmp"
# A shimmed `ln` refuses to link a source into place (as across filesystems), so place() takes its copy
# path: `cp -p` to a temp beside the target, linked in, compared, and only then the source removed.
mkdir -p "$WORK/shim-ln" "$WORK/shim-cp"
cat > "$WORK/shim-ln/ln" <<EOF
#!/bin/sh
src=""; prev=""
for a in "\$@"; do src=\$prev; prev=\$a; done
case "\${src##*/}" in .marvin-runs-migrate.*) exec $(command -v ln) "\$@" ;; esac
exit 1
EOF
cat > "$WORK/shim-cp/cp" <<'EOF'
#!/bin/sh
for a in "$@"; do last=$a; done
printf 'a short copy\n' > "$last"
exit 0
EOF
chmod +x "$WORK/shim-ln/ln" "$WORK/shim-cp/cp"
mk_runs n14; mk_wt wt1
touch -t 202601010000 "$WORK/n14-ref"
before=$(content_set); n_before=$(file_count)
PATH="$WORK/shim-ln:$PATH" run_migrate
assert_rc 0 "the copy path"
L=$(legacy_dirs)
assert_body ".marvin/runs/$L/AOS-1/ledger.md" "$LEDGER_MAIN" "the copy holds the source's bytes"
assert_body ".marvin/runs/$L/AOS-2/20260103T000000Z-validator-wt1.md" "validator report from wt1"
assert_gone .marvin/runs/AOS-1/ledger.md "the source is removed once the copy compared equal"
if [ ".marvin/runs/$L/AOS-1/ledger.md" -nt "$WORK/n14-ref" ] || [ "$WORK/n14-ref" -nt ".marvin/runs/$L/AOS-1/ledger.md" ]; then
  bad "the copy kept the source's mtime (a later merge decides by it)"
else ok "the copy kept the source's mtime (a later merge decides by it)"; fi
assert_eq "$(content_set)" "$before" "the content invariant holds on the copy path"
assert_eq "$(file_count)" "$n_before" "no file gained or lost"
assert_eq "$(find .marvin/runs -name '.marvin-runs-migrate.*' | wc -l | tr -d ' ')" "0" "no temp file left behind"
# a copy that does not compare equal: the run fails, the source stays, the bad copy is removed
mk_runs n14b
PATH="$WORK/shim-cp:$WORK/shim-ln:$PATH" run_migrate
assert_rc 1 "a copy that differs fails the move"
assert_out "result=refused"
assert_out "refused: move failed"
assert_body .marvin/runs/AOS-1/20260101T000000Z-developer.md "developer report" "the source is kept when cmp fails"
L=$(legacy_dirs)
assert_gone ".marvin/runs/$L/AOS-1/20260101T000000Z-developer.md" "the differing copy is removed"
assert_eq "$(find .marvin/runs -name '.marvin-runs-migrate.*' | wc -l | tr -d ' ')" "0" "no temp file left behind"
assert_report_wellformed "failed copy"

fi  # end SUITE runs

# ═════════════════════════════════════════════════════════════════════════════════════════════
hd "T28 the suite refuses to run without a scratch directory"
selftest=$( (WORK=""; require_workdir; echo "GUARD DID NOT FIRE") 2>&1 )
selftest_rc=$?
assert_eq "$selftest_rc" "2" "require_workdir aborts when mktemp failed"
printf '%s' "$selftest" | grep -Fq "refusing to run at the filesystem root"
chk $? "and says why"
require_workdir   # the real one is still intact

# ═════════════════════════════════════════════════════════════════════════════════════════════
cd "$SCRIPT_DIR" || exit 1
printf '\n----\ntest-migrations: %d passed, %d failed  [filesystem: %s — %s]\n' \
  "$PASSED" "$FAILED" "$FS_KIND" "$FS_NOTE"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
