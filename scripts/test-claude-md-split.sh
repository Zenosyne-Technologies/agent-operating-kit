#!/usr/bin/env bash
# test-claude-md-split.sh — behavioural suite for scripts/plan-claude-md-split.sh (AOS-165).
#
# Each fixture P1–P8 pins one contract point of the read-only CLAUDE.md split planner: a fresh
# stub needs nothing, every shipped kit line classifies `kit` while facts/conventions/attribution
# never do, a customised kit line is `near-kit`, a symlinked CLAUDE.md is refused silently, an
# AGENTS.md-only repo is reported, an import in a code span does not count, the agent's edit is
# idempotent, and the planner never writes.
#
# A green suite proves nothing about a guard it cannot fail without: the mutation section at the
# bottom reverts one classification guard at a time in a throwaway copy of the planner and
# requires its named fixture to fail. A mutation the suite survives is a hole, not a pass
# (CLAUDE.md extension rule 9's discipline; the planner is read-only, not a migration script).
#
# Run from anywhere: bash scripts/test-claude-md-split.sh
# Exit 0 = every fixture and every mutation check passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PLANNER="$SCRIPT_DIR/plan-claude-md-split.sh"
HIST="$SCRIPT_DIR/claude-core-history"
STUB="$REPO_DIR/templates/CLAUDE.project.md"
KITCORE="$REPO_DIR/templates/marvin/CLAUDE.marvin.md"
IMPORT_LINE='@.marvin/CLAUDE.marvin.md'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-splittest.XXXXXX") || WORK=""
if [ -z "${WORK:-}" ] || [ ! -d "${WORK:-}" ]; then
  printf 'test-claude-md-split: FATAL — scratch directory unavailable\n' >&2; exit 2
fi
trap 'rm -rf "$WORK"' EXIT

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }
run() { OUT=$(bash "$1" "$2" 2>/dev/null); RC=$?; }   # run <planner> <repo-dir>
has() { printf '%s\n' "$OUT" | grep -Fxq -- "$1"; chk $? "report has: $1"; }
cls() { printf '%s\n' "$OUT" | awk -v n="$1" '$1=="line:" && $2==n {print $3}'; }  # class of line n
lines_of() { printf '%s\n' "$OUT" | awk -v c="$1" '$1=="line:" && $3==c {print $2}' | tr '\n' ' '; }

# render <template> <attribution: a|b|c> — a consumer's CLAUDE.md as install step 4/6/7 wrote it
render() {
  local sub_attr
  case "$2" in
    a) sub_attr='/{{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION}}/d' ;;
    b) sub_attr='s/ {{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION}}//' ;;
    c) sub_attr='s/^- \*\*Attribution: none\.\*\*.*{{DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION}}$/- **Attribution: Emprove Marvin (Claude).** Commits and PRs carry the "Emprove Marvin (Claude)" trailer; docs and code comments carry none./' ;;
  esac
  sed -e "$sub_attr" \
      -e 's/{{PROJECT_NAME}}/Acme Shop/g' \
      -e 's/{{ESCALATION_MODEL}}/Model Heavy 9/g; s/{{WORKER_MODEL}}/Model Small 9/g' \
      -e 's/{{MICRO_MODEL}}/Model Micro 9/g; s/{{FRONTIER_MODEL}}/Model Frontier 9/g' \
      -e 's#{{DOCS_ISSUE_LOG_PATH}}#.docs/issue-log.md#g' \
      -e 's/{{ONE_PARAGRAPH_PROJECT_FACTS[^}]*}}/Acme Shop is a Rails 8 monolith; run shell commands via `mise exec --`; dev: `bin\/dev` on :3000./' \
      -e 's/{{CONVENTIONS_THAT_BITE[^}]*}}/**Migrations**: always run `bin\/rails db:migrate` twice in CI (INC-12)./' \
      "$1"
}
# expected kit line numbers of a template rendered with variant b (line-preserving)
expected_kit() {
  awk '{ t=$0; sub(/[ \t]+$/, "", t) }
       t=="" { next }
       t ~ /\{\{(PROJECT_NAME|ONE_PARAGRAPH_PROJECT_FACTS|CONVENTIONS_THAT_BITE|DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION)/ { next }
       { printf "%d ", NR }' "$1"
}
mkrepo() { rm -rf "$1"; mkdir -p "$1"; }

# ── fixtures — each takes the planner under test ───────────────────────────────────────────
P1() {  # a fresh stub (what install step 4 writes) needs nothing
  local p="$1" d="$WORK/p1"; mkrepo "$d"; render "$STUB" b > "$d/CLAUDE.md"
  run "$p" "$d"; chk $([ "$RC" = 0 ]; echo $?) "exit 0"
  has "result=nothing-to-do"; has "import: present"; has "counts: kit=0 near-kit=0 attribution=1 title=1 project=3"
}

P2() {  # every history version rendered: kit lines are kit; facts, conventions, attribution never
  local p="$1" h d v want got
  for h in "$HIST"/v*.md; do
    v=$(basename "$h" .md); d="$WORK/p2-$v"; mkrepo "$d"; render "$h" b > "$d/CLAUDE.md"
    run "$p" "$d"; want=$(expected_kit "$h"); got=$(lines_of kit)
    [ "$want" = "$got" ]; chk $? "$v: exactly the template's kit lines classify kit"
    [ "$(cls 1)" = title ]; chk $? "$v: title line is title"
    [ "$(cls 3)" = project ]; chk $? "$v: facts line is project"
    [ "$(cls "$(wc -l < "$d/CLAUDE.md" | tr -d ' ')")" = project ]; chk $? "$v: conventions line is project"
    [ "$(lines_of attribution)" = "$(grep -n '^- \*\*Attribution' "$d/CLAUDE.md" | cut -d: -f1) " ]; chk $? "$v: attribution line is attribution"
    has "issue-log-path: .docs/issue-log.md"; has "result=split-needed"
  done
  has 'model-values: ESCALATION_MODEL="Model Heavy 9" WORKER_MODEL="Model Small 9" MICRO_MODEL="Model Micro 9" FRONTIER_MODEL="Model Frontier 9"'
  for v in a c; do  # v0.31.0 as installs with attribution (a) deleted and (c) branded rendered it
    d="$WORK/p2-v0.31.0-$v"; mkrepo "$d"; render "$HIST/v0.31.0.md" "$v" > "$d/CLAUDE.md"
    run "$p" "$d"
    printf '%s\n' "$OUT" | grep -q '^counts: kit=34 near-kit=0 ' ; chk $? "v0.31.0 attribution ($v): 34 kit lines, no near-kit"
    for n in $(lines_of kit); do sed -n "${n}p" "$d/CLAUDE.md"; done | grep -qE 'Acme Shop is a Rails|Migrations\*\*|Attribution'
    [ $? -ne 0 ]; chk $? "v0.31.0 attribution ($v): no facts/conventions/attribution text among kit lines"
  done
}

P3() {  # one customised kit line is near-kit — neither kit nor project
  local p="$1" d="$WORK/p3" n; mkrepo "$d"; render "$HIST/v0.31.0.md" b > "$d/CLAUDE.md"
  n=$(grep -n '^- \*\*Autocommit\*\*' "$d/CLAUDE.md" | cut -d: -f1)
  sed -e "${n}s/\$/ Sign every commit with GPG./" "$d/CLAUDE.md" > "$d/x" && mv "$d/x" "$d/CLAUDE.md"
  run "$p" "$d"; [ "$(cls "$n")" = near-kit ]; chk $? "customised Autocommit line (line $n) is near-kit"
}

P4() {  # CLAUDE.md -> AGENTS.md is refused: exit 6 and no report record at all
  local p="$1" d="$WORK/p4"; mkrepo "$d"; printf '# Agents\n\n- **Autocommit**: x\n' > "$d/AGENTS.md"
  ln -s AGENTS.md "$d/CLAUDE.md"; run "$p" "$d"
  [ "$RC" = 6 ]; chk $? "exit 6 on a symlinked CLAUDE.md (got $RC)"
  [ -z "$OUT" ]; chk $? "no output record"
}

P5() {  # AGENTS.md with no CLAUDE.md: install must add @AGENTS.md above the kit import
  local p="$1" d="$WORK/p5"; mkrepo "$d"; printf '# Agents\n' > "$d/AGENTS.md"
  run "$p" "$d"; has "agents-md: present"; has "claude-md: absent"; has "result=nothing-to-do"
}

P6() {  # an import in backticks or inside a fence is inert: in-code-span, never present
  local p="$1" d="$WORK/p6"; mkrepo "$d"
  printf '# X\n\nThe kit core is `%s`.\n' "$IMPORT_LINE" > "$d/CLAUDE.md"
  run "$p" "$d"; has "import: in-code-span"
  printf '# X\n\n```\n%s\n```\n' "$IMPORT_LINE" > "$d/CLAUDE.md"
  run "$p" "$d"; has "import: in-code-span"
  printf '# X\n\n@./.marvin/CLAUDE.marvin.md  \n' > "$d/CLAUDE.md"
  run "$p" "$d"; has "import: present"
}

sim_edit() {  # the agent's edit, as a sed: drop every kit line, append the import if absent
  local p="$1" d="$2" rep dels
  rep=$(bash "$p" "$d" 2>/dev/null)
  dels=$(printf '%s\n' "$rep" | awk '$1=="line:" && $3=="kit" {printf "%sd;", $2}')
  if [ -n "$dels" ]; then sed -e "$dels" "$d/CLAUDE.md" > "$d/x" && mv "$d/x" "$d/CLAUDE.md"; fi
  printf '%s\n' "$rep" | grep -qx 'import: present' || printf '\n%s\n' "$IMPORT_LINE" >> "$d/CLAUDE.md"
}
P7() {  # idempotence: edit, re-plan → nothing-to-do; edit again → byte-identical
  local p="$1" d="$WORK/p7" c1 c2; mkrepo "$d"; render "$HIST/v0.31.0.md" c > "$d/CLAUDE.md"
  sim_edit "$p" "$d"; run "$p" "$d"
  has "result=nothing-to-do"; has "import: present"
  grep -q 'Acme Shop is a Rails' "$d/CLAUDE.md" && grep -q 'Migrations\*\*' "$d/CLAUDE.md" && grep -q 'Attribution: Emprove' "$d/CLAUDE.md"
  chk $? "facts, conventions and attribution survive the edit"
  c1=$(cksum < "$d/CLAUDE.md"); sim_edit "$p" "$d"; c2=$(cksum < "$d/CLAUDE.md")
  [ "$c1" = "$c2" ]; chk $? "second edit leaves CLAUDE.md byte-identical"
}

P8() {  # the planner never writes: whole-tree cksum and git status unchanged, every mode
  local p="$1" d="$WORK/p8" before after; mkrepo "$d"
  render "$HIST/v0.31.0.md" b > "$d/CLAUDE.md"; printf '# Agents\n' > "$d/AGENTS.md"
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm init
  snap() { (cd "$d" && find . -path ./.git -prune -o -print0 | sort -z | xargs -0 perl -MTime::HiRes=lstat -e 'for (@ARGV) { my @s = lstat($_); print "$_ $s[2] $s[7] $s[9]\n" }'; find . -type f -print0 | sort -z | xargs -0 cksum; git status --porcelain); }
  before=$(snap)
  bash "$p" "$d" > /dev/null 2>&1; bash "$p" "$d" --bogus > /dev/null 2>&1
  (cd "$d" && bash "$p" > /dev/null 2>&1)
  after=$(snap); [ "$before" = "$after" ]; chk $? "tree, cksums and git status unchanged (report, usage error, cwd modes)"
  rm "$d/CLAUDE.md"; ln -s AGENTS.md "$d/CLAUDE.md"
  before=$(snap); bash "$p" "$d" > /dev/null 2>&1; after=$(snap)
  [ "$before" = "$after" ]; chk $? "tree, cksums and git status unchanged (symlink refusal)"
}

P0() {  # usage errors exit 4
  local p="$1"
  bash "$p" --bogus > /dev/null 2>&1; [ $? = 4 ]; chk $? "unknown flag exits 4"
  bash "$p" "$WORK" "$WORK" > /dev/null 2>&1; [ $? = 4 ]; chk $? "extra argument exits 4"
  bash "$p" "$WORK/does-not-exist" > /dev/null 2>&1; [ $? = 4 ]; chk $? "missing directory exits 4"
}

for f in P0 P1 P2 P3 P4 P5 P6 P7 P8; do hd "$f"; "$f" "$PLANNER"; done

# ── mutation checks: revert one guard at a time in a throwaway copy, its named fixture must fail
MROOT="$WORK/mut"; mkdir -p "$MROOT/scripts" "$MROOT/templates/marvin"
cp -R "$HIST" "$MROOT/scripts/"; cp "$KITCORE" "$MROOT/templates/marvin/"
# mutate <name> <fixture> <exact line> <replacement line>
mutate() {
  local name="$1" fx="$2" old="$3" new="$4" m="$MROOT/scripts/plan-claude-md-split.sh" res
  hd "mutation $name (must be caught by $fx)"
  OLD="$old" NEW="$new" perl -e 'my ($o,$n)=@ENV{qw(OLD NEW)}; my $c=0; while(<STDIN>){ chomp; if($_ eq $o){$_=$n;$c++} print "$_\n" } exit($c==1?0:1)' < "$PLANNER" > "$m"
  if [ $? -ne 0 ]; then bad "target line not found exactly once — the harness is stale"; return; fi
  res=$( ( PASSED=0; FAILED=0; "$fx" "$m" > /dev/null; echo "$FAILED" ) )
  if [ "${res:-0}" -gt 0 ]; then ok "caught — $fx fails against the mutant"; else bad "NOT caught — $fx still passes against the mutant"; fi
}
mutate full-line-placeholder-as-pattern P2 \
  '    next if $lit =~ /\A[\s#*+-]*\z/;   # full-line placeholder (facts, conventions): never a pattern' \
  '    1;'
mutate unanchored-match P3 \
  '    push @pats, [ qr/^$re$/, [ @names ] ];' \
  '    push @pats, [ qr/$re/, [ @names ] ];'
mutate code-span-blind-import P6 \
  '  elsif ($t =~ /\A$IMP\z/) { $imp = "present"; next; }' \
  '  elsif ($t =~ /$IMP/) { $imp = "present"; next; }'
mutate fence-blind-import P6 \
  '  elsif ($fence) { $code_imp = 1 if $t =~ $IMP; $cls = "project"; }' \
  '  elsif (0) { $code_imp = 1 if $t =~ $IMP; $cls = "project"; }'
mutate symlink-guard-removed P4 \
  "if [ -L \"\$CM\" ]; then printf '%s: refused: CLAUDE.md is a symlink — replace it with a CLAUDE.md that imports @AGENTS.md, then re-run\\n' \"\$SELF\" >&2; exit 6; fi" \
  ':'

printf '\n----\ntest-claude-md-split: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
