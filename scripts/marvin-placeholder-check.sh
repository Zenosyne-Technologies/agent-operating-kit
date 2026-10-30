#!/usr/bin/env bash
# marvin-placeholder-check.sh — lists install-time {{PLACEHOLDER}}s still left in a project's installed kit files
# (AOS-221). Read-only; run by the install and upgrade skills as their last mechanical check, so an install that
# skipped a substitution cannot report success. Every hit is a must-fix before the final report.
# Usage: bash marvin-placeholder-check.sh [<project-root>]   (default: $CLAUDE_PROJECT_DIR, else $PWD)
# Scans: .marvin/ (not runs/, reports/), .docs/, CLAUDE.md. A placeholder is {{NAME}} or {{NAME: instructions}},
# NAME = [A-Z][A-Z0-9_]*. These stay in installed files by design — they are filled when a brief is dispatched:
#   PERIOD_DAYS, SCOPE   (the stats-collection brief)
# Output, one line per hit:  unresolved: <path relative to the root>:<line>: {{NAME
# Exit 0 clean (no output); 1 hits found; 2 usage error or no kit files under the root. Never writes.
set -u
[ "$#" -le 1 ] || { echo "usage: marvin-placeholder-check.sh [<project-root>]" >&2; exit 2; }
root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -d "$root" ] || { echo "marvin-placeholder-check.sh: no such directory" >&2; exit 2; }
cd "$root" 2>/dev/null || exit 2
targets=""
for t in .marvin .docs CLAUDE.md; do [ -e "$t" ] && [ ! -L "$t" ] && targets="$targets $t"; done
[ -n "$targets" ] || { echo "marvin-placeholder-check.sh: no .marvin, .docs or CLAUDE.md under the root" >&2; exit 2; }
# find (no -L) never follows a symlink, on BSD and GNU alike; grep gets plain files only.
# shellcheck disable=SC2086
hits=$(find $targets \( -path .marvin/runs -o -path .marvin/reports \) -prune -o -type f -print0 2>/dev/null \
  | LC_ALL=C xargs -0 grep -noE '\{\{[A-Z][A-Z0-9_]*(\}\}|:)' /dev/null 2>/dev/null \
  | LC_ALL=C grep -vE ':\{\{(PERIOD_DAYS|SCOPE)(\}\}|:)$' \
  | LC_ALL=C sed -E 's/(\{\{[A-Z][A-Z0-9_]*)(\}\}|:)$/\1/' \
  | LC_ALL=C tr -c '[:print:]\n' '?')
[ -n "$hits" ] || exit 0
printf '%s\n' "$hits" | head -n 200 | sed 's/^/unresolved: /'
n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
[ "$n" -le 200 ] || echo "unresolved: … $((n - 200)) more"
exit 1
