#!/usr/bin/env bash
# marvin-placeholder-check.sh — lists install-time {{PLACEHOLDER}}s still left in a project's installed kit files
# (AOS-221). Read-only; run by the install and upgrade skills as their last mechanical check, so an install that
# skipped a substitution cannot report success. Every hit is a must-fix before the final report.
# Usage: bash marvin-placeholder-check.sh [<project-root>]   (default: $CLAUDE_PROJECT_DIR, else $PWD)
# Scans only what the kit writes: .marvin/ (not runs/, reports/, backups/), the .docs/ files that exist under this
# plugin's own templates/docs/ (derived at run time from the script's location), and the root CLAUDE.md.
# A placeholder is any {{ followed by NAME = [A-Z][A-Z0-9_]* and then a non-name character or the end of the line:
# {{NAME}}, {{NAME: instructions}}, {{NAME + more}}. These stay in installed files by design — they are filled when
# a brief is dispatched (allowed only as {{NAME}} or {{NAME:):
#   PERIOD_DAYS, SCOPE   (the stats-collection brief)
# Output, one line per hit:  unresolved: <path relative to the root>:<line>:{{NAME
# Exit 0 clean (no output); 1 hits found; 2 usage error, no kit files, or a file/dir could not be read (never a
# false clean). Never writes.
set -u
[ "$#" -le 1 ] || { echo "usage: marvin-placeholder-check.sh [<project-root>]" >&2; exit 2; }
plug=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 2
root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -d "$root" ] || { echo "marvin-placeholder-check.sh: no such directory" >&2; exit 2; }
cd "$root" 2>/dev/null || exit 2
[ -d "$plug/templates/docs" ] || { echo "marvin-placeholder-check.sh: no templates/docs under the plugin root" >&2; exit 2; }
seeded=$(cd "$plug/templates/docs" && find . -type f 2>/dev/null | sed 's|^\./||')
set --
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  [ "$#" -eq 0 ] || set -- "$@" -o
  set -- "$@" -path ".docs/$rel"
done <<EOT
$seeded
EOT
# find (no -L) never follows a symlink, on BSD and GNU alike; grep gets plain files only.
files() {
  if [ -d .marvin ] && [ ! -L .marvin ]; then
    find .marvin \( -path .marvin/runs -o -path .marvin/reports -o -path .marvin/backups \) -prune -o -type f -print0
  fi
  if [ -d .docs ] && [ ! -L .docs ] && [ "$#" -gt 0 ]; then find .docs -type f \( "$@" \) -print0; fi
  if [ -f CLAUDE.md ] && [ ! -L CLAUDE.md ]; then printf 'CLAUDE.md\0'; fi
}
{ [ -d .marvin ] && [ ! -L .marvin ]; } || { [ -d .docs ] && [ ! -L .docs ]; } || { [ -f CLAUDE.md ] && [ ! -L CLAUDE.md ]; } \
  || { echo "marvin-placeholder-check.sh: no .marvin, .docs or CLAUDE.md under the root" >&2; exit 2; }
HIT=':[0-9]+:\{\{[A-Z][A-Z0-9_]*([^A-Za-z0-9_])?$'
# stderr is merged in on purpose: any line that is not a hit line is a read failure, never a clean result.
raw=$(files "$@" 2>&1 \
  | LC_ALL=C xargs -0 grep -noE '\{\{[A-Z][A-Z0-9_]*([^A-Za-z0-9_]|$)' /dev/null 2>&1 \
  | LC_ALL=C grep -vE ':[0-9]+:\{\{(PERIOD_DAYS|SCOPE)(\}|:)$' \
  | LC_ALL=C tr -c '[:print:]\n' '?')
bad=$(printf '%s\n' "$raw" | LC_ALL=C grep -vE "$HIT" | LC_ALL=C grep -v '^$' | head -n 1)
if [ -n "$bad" ]; then echo "marvin-placeholder-check.sh: could not read all files: $bad" >&2; exit 2; fi
hits=$(printf '%s\n' "$raw" | LC_ALL=C grep -E "$HIT" | LC_ALL=C sed -E 's/(\{\{[A-Z][A-Z0-9_]*)[^A-Za-z0-9_]?$/\1/')
[ -n "$hits" ] || exit 0
printf '%s\n' "$hits" | head -n 200 | sed 's/^/unresolved: /'
n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
[ "$n" -le 200 ] || echo "unresolved: … $((n - 200)) more"
exit 1
