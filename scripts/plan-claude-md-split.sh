#!/usr/bin/env bash
# plan-claude-md-split.sh — READ-ONLY planner for the one-time CLAUDE.md split (v0.33.0, AOS-165).
#
# From v0.33.0 the kit's core rules live in the kit-owned `.marvin/CLAUDE.marvin.md`, and the
# consumer's `CLAUDE.md` keeps only project content plus the bare import line
# `@.marvin/CLAUDE.marvin.md`. An install that predates that split carries the kit's rules
# INSIDE `CLAUDE.md`. This script classifies every line of that `CLAUDE.md` so the upgrading
# agent knows exactly which lines are the kit's (and may go) and which are the project's (and
# must stay) — and, re-run after the agent's edit, proves the edit is complete
# (`result=nothing-to-do`).
#
# WHAT THIS SCRIPT DOES NOT DO: it writes nothing, stages nothing, moves nothing. Editing
# `CLAUDE.md` is the agent's half (CLAUDE.md extension rule 9: a script never edits content);
# this script is the code half that drives that edit and checks its result.
#
# Reference set: every `CLAUDE.core.md` the kit shipped at a tag (scripts/claude-core-history/,
# v0.22.0 .. v0.32.0) plus the current kit core template. Each reference line becomes an
# ANCHORED pattern — literal text, each `{{…}}` a non-greedy capture. Never a pattern: blank
# lines, a line that is nothing but placeholders (the facts paragraph, the conventions bullet —
# as patterns they would match every line), the title (`{{PROJECT_NAME}}`) and the attribution
# line in every variant (consumer content, install step 6).
#
# Classes, one per non-blank line (the import line itself is reported by `import:` instead):
#   kit          exact match of a reference line
#   near-kit     same heading, same leading bold rule label, or same `- <label> →` bullet label
#                as a reference line, but no exact match — the agent judges it; unsure → keep
#   review       no label match, but its content words overlap a reference line closely (below):
#                a customised UNLABELLED kit rule — shown to the user at the split gate to keep or
#                drop, never silently kept or dropped
#   attribution  a `**Attribution…**` rule line (any variant) — always kept
#   title        the first H1 — always kept
#   project      everything else, including every line inside a fenced block — always kept
#
# `review` threshold: content words = lowercase alphanumeric runs of 3+ characters minus a short
# stopword list; for each reference line, shared = |line ∩ ref| and the overlap coefficient
# shared / min(|line|, |ref|). A line is `review` when some reference line gives shared >= 4 AND
# coefficient >= 0.6. The overlap coefficient (not Jaccard) because a customised kit rule is
# usually the kit line TRUNCATED or EXTENDED, and both keep most of the shorter side's words; 0.6
# means the majority of the shorter side is kit wording; the floor of 4 shared words stops a short
# project line from matching a kit line by one or two common words. Tuned against every fixture's
# project lines (facts, conventions, project rules): none reaches it.
#
# result=split-needed when any `kit` line remains, OR — before the import exists, i.e. before the
# split — any `near-kit` or `review` line does: a file whose kit lines were ALL customised still
# reaches the gate. After the split (import present) kept near-kit/review lines are the user's
# decision, so the re-run is `nothing-to-do`.
#
# THE REPORT IS A MACHINE CONTRACT another agent acts on, and the values it prints (the issue
# log path, model names) come from a consumer-controlled file. Values are ENCODED exactly as
# migrate-v0.21.0.sh encodes paths (its `encoding=` line); no consumer line text is ever
# printed — lines are named by number only.
#
# MODE is explicit, never inferred from content (`--mode`, required):
#   install  the repo has no kit install (no PROJECT-INFO `kit_version`): nothing in it can be a
#            customised kit line, so every line that is not an exact `kit` match is `project` —
#            `near-kit` and `review` do not exist in this mode, and only `kit` lines make
#            `split-needed` (a prior install the install skill hands to upgrade-agent-os)
#   upgrade  a kit install exists (the upgrade and re-install paths): all classes apply
#
# Usage: bash plan-claude-md-split.sh --mode install|upgrade [<repo-root>]   (default root: .)
# Exit codes:
#   0  report printed (result=split-needed or result=nothing-to-do)
#   4  usage error: missing/unknown --mode, unknown flag, extra argument, repo root not a
#      directory, CLAUDE.md not a file
#   5  the reference set is missing (a broken plugin install)
#   6  refused: CLAUDE.md is a symlink — nothing is read, no report record is printed
set -uo pipefail

SELF="plan-claude-md-split"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
HIST_DIR="$SCRIPT_DIR/claude-core-history"
KIT_CORE="$SCRIPT_DIR/../templates/marvin/CLAUDE.marvin.md"

usage() { printf 'usage: bash %s.sh --mode install|upgrade [<repo-root>]\n' "$SELF" >&2; }

MODE=""; ROOT=""; nroot=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --mode) [ "$#" -ge 2 ] || { usage; exit 4; }; MODE="$2"; shift 2;;
    --mode=*) MODE="${1#--mode=}"; shift;;
    -*) usage; exit 4;;
    *) ROOT="$1"; nroot=$((nroot+1)); shift;;
  esac
done
case "$MODE" in install|upgrade) ;; *) usage; exit 4;; esac
[ "$nroot" -le 1 ] || { usage; exit 4; }
ROOT="${ROOT:-.}"
[ -d "$ROOT" ] || { printf '%s: not a directory\n' "$SELF" >&2; exit 4; }
CM="$ROOT/CLAUDE.md"
AG="$ROOT/AGENTS.md"

# Symlink guard: a CLAUDE.md -> AGENTS.md link is refused, never followed (the upgrade skill's
# Symlink precondition). No record is printed, so no caller can act on a half-report.
if [ -L "$CM" ]; then printf '%s: refused: CLAUDE.md is a symlink — replace it with a CLAUDE.md that imports @AGENTS.md, then re-run\n' "$SELF" >&2; exit 6; fi
if [ -e "$CM" ] && [ ! -f "$CM" ]; then printf '%s: CLAUDE.md is not a regular file\n' "$SELF" >&2; exit 4; fi
ls "$HIST_DIR"/v*.md > /dev/null 2>&1 || { printf '%s: reference set missing: %s\n' "$SELF" "$HIST_DIR" >&2; exit 5; }

cm_state=absent; [ -f "$CM" ] && cm_state=present
ag_state=absent; { [ -e "$AG" ] || [ -L "$AG" ]; } && ag_state=present
kit_core=""; [ -f "$KIT_CORE" ] && kit_core="$KIT_CORE"

LC_ALL=C perl -e '
use strict; use warnings;
my ($cm_state, $cm, $ag_state, $hist, $kit_core, $mode) = @ARGV;
my $customised = $mode eq "upgrade";   # mode guard: near-kit/review exist only over a prior install

# ── encoding: migrate-v0.21.0.sh q() exactly (git core.quotePath); named enc — q is a Perl operator
sub enc { my $p = shift;
  return $p if $p =~ /\A[A-Za-z0-9._\/\@+-]+\z/;
  my $o = "\"";
  for my $b (unpack("C*", $p)) {
    if    ($b == 92) { $o .= "\\\\" } elsif ($b == 34) { $o .= "\\\"" }
    elsif ($b == 10) { $o .= "\\n" }  elsif ($b == 9)  { $o .= "\\t" }
    elsif ($b == 13) { $o .= "\\r" }  elsif ($b < 32 || $b > 126) { $o .= sprintf("\\%03o", $b) }
    else { $o .= chr($b) } }
  return $o . "\"";
}

# ── reference set: newest first, so the first capture of a value is the most recent layout ─
sub vkey { my ($a) = $_[0] =~ /v(\d+\.\d+\.\d+)\.md\z/; return join "", map { sprintf "%05d", $_ } split /\./, $a; }
my @refs = sort { vkey($b) cmp vkey($a) } glob("$hist/v*.md");
unshift @refs, $kit_core if $kit_core ne "";

my $PH = qr/\{\{([A-Z_0-9]+)(?::[^}]*)?\}\}/;
sub norm { my $s = lc shift; $s =~ s/\s+/ /g; $s =~ s/\A\s+|\s+\z//g; $s =~ s/[.:]+\z//; return $s; }
sub label_of { my $l = shift;
  return ("h", norm($1)) if $l =~ /\A\s{0,3}#{1,6}\s+(.*?)\s*#*\s*\z/;
  return ("b", norm($1)) if $l =~ /\A\s*(?:[-*+]\s+)?\*\*(.+?)\*\*/;
  return ("a", norm($1)) if $l =~ /\A\s*[-*+]\s+(.+?)\s+\xe2\x86\x92\s/;
  return (); }
my $ATTR = qr/\A\s*(?:[-*+]\s+)?\*\*Attribution\b/;

my %STOP = map { $_ => 1 } qw(the and for with you are its any from this that per into was has have may can when then than they them their our out also not but all one);
sub words { my %w; $w{$_} = 1 for grep { length($_) >= 3 && !$STOP{$_} } split /[^a-z0-9]+/, lc shift; return \%w; }
my (@pats, %labels, @refwords);
for my $ref (@refs) {
  open(my $fh, "<", $ref) or die "cannot read reference $ref\n";
  while (my $t = <$fh>) {
    chomp $t; $t =~ s/\r\z//; $t =~ s/\s+\z//;
    next if $t eq "";
    (my $lit = $t) =~ s/$PH//g;
    next if $lit =~ /\A[\s#*+-]*\z/;   # full-line placeholder (facts, conventions): never a pattern
    next if $t =~ /\{\{(?:PROJECT_NAME|DELETE_THIS_LINE_TO_KEEP_DEFAULT_ATTRIBUTION)\b/;
    next if $t =~ $ATTR;
    my ($re, $pos, @names) = ("", 0);
    while ($t =~ /$PH/g) {
      $re .= quotemeta(substr($t, $pos, $-[0] - $pos)) . "(.+?)"; push @names, $1; $pos = $+[0];
    }
    $re .= quotemeta(substr($t, $pos));
    push @pats, [ qr/^$re$/, [ @names ] ];
    push @refwords, words($lit);
    my @lab = label_of($t); $labels{"$lab[0]:$lab[1]"} = 1 if @lab;
  }
  close $fh;
}

my (@rec, %mv, $logpath);
my %cnt = map { $_ => 0 } qw(kit near-kit review attribution title project);
sub close_to_kit { my $a = words(shift); my $na = keys %$a; return 0 unless $na;
  for my $b (@refwords) { my $nb = keys %$b; next unless $nb;
    my $shared = grep { $b->{$_} } keys %$a; my $min = $na < $nb ? $na : $nb;
    return 1 if $shared >= 4 && $shared / $min >= 0.6; }
  return 0; }
my ($imp, $code_imp, $fence, $title_seen, $n) = ("absent", 0, 0, 0, 0);
my $IMP = qr/\@(?:\.\/)?\.marvin\/CLAUDE\.marvin\.md/;
my @lines;
if ($cm_state eq "present") { open(my $c, "<", $cm) or die "cannot read CLAUDE.md\n"; @lines = <$c>; close $c; }
for my $l (@lines) {
  $n++; chomp $l; $l =~ s/\r\z//; (my $t = $l) =~ s/\s+\z//;
  my $cls;
  if ($t =~ /\A\s{0,3}(?:```|~~~)/) { $fence = !$fence; $cls = "project"; }
  elsif ($fence) { $code_imp = 1 if $t =~ $IMP; $cls = "project"; }
  elsif ($t =~ /\A$IMP\z/) { $imp = "present"; next; }
  elsif ($t eq "") { next; }
  else {
    $code_imp = 1 if $t =~ /`[^`]*$IMP[^`]*`/;
    if ($t =~ $ATTR) { $cls = "attribution"; }
    else {
      for my $p (@pats) {
        my @cap = ($t =~ $p->[0]) or next;
        $cls = "kit";
        for my $i (0 .. $#{ $p->[1] }) {
          my $name = $p->[1][$i];
          $mv{$name} //= $cap[$i];
          $logpath //= $cap[$i] if $name eq "DOCS_ISSUE_LOG_PATH";
        }
        last;
      }
      if (!defined $cls && !$title_seen && $t =~ /\A#\s+\S/) { $cls = "title"; }
      if (!defined $cls && $customised) { my @lab = label_of($t); $cls = "near-kit" if @lab && $labels{"$lab[0]:$lab[1]"}; }
      if (!defined $cls && $customised) { $cls = "review" if close_to_kit($t); }
      $cls //= "project";
    }
    if (!defined $logpath && $cls ne "kit" && $t =~ /(?:A real bug|Real bugs)\s*\xe2\x86\x92\s*`([^`]+)`/) { $logpath = $1; }
  }
  $title_seen = 1 if $t =~ /\A#\s+\S/ && !$fence;
  $cnt{$cls}++; push @rec, "line: $n $cls";
}
$imp = "in-code-span" if $imp eq "absent" && $code_imp;

print "plan-claude-md-split: read-only planner report — it changed nothing\n";
print "encoding=values are printed raw when they match [A-Za-z0-9._/\@+-]+, otherwise C-quoted in double quotes with \\n \\t \\r \\\" \\\\ and \\ooo escapes (git core.quotePath convention); exactly one record per line; no CLAUDE.md line text is ever printed\n";
print "reference=", join(",", map { (my $b = $_) =~ s{.*/}{}; $b } @refs), "\n";
print "mode=$mode\n";
print "claude-md: $cm_state\n";
print "$_\n" for @rec;
print "counts: ", join(" ", map { "$_=$cnt{$_}" } qw(kit near-kit review attribution title project)), "\n";
print "import: $imp\n";
print "agents-md: $ag_state\n";
print "issue-log-path: ", (defined $logpath ? enc($logpath) : "not-found"), "\n";
print "model-values: ", join(" ", map { "$_=" . (defined $mv{$_} ? enc($mv{$_}) : "not-found") } qw(ESCALATION_MODEL WORKER_MODEL MICRO_MODEL FRONTIER_MODEL)), "\n";
my $split = $cnt{kit} > 0 || ($imp ne "present" && $cnt{"near-kit"} + $cnt{review} > 0);
print "result=", ($split ? "split-needed" : "nothing-to-do"), "\n";
' "$cm_state" "$CM" "$ag_state" "$HIST_DIR" "$kit_core" "$MODE"
