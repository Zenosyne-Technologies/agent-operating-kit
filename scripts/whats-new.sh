#!/usr/bin/env bash
# whats-new.sh — aggregate CHANGELOG.md briefs over a version range (AOS-184).
#
#   whats-new.sh <to>            → v<to>'s own section
#   whats-new.sh <from> <to>     → every section with from < version <= to
#
# Bullets merge by category in a fixed order — Action needed first, since it is what the user must
# do — newest version first inside a category, each tagged (vX.Y.Z). WHATS_NEW_CHANGELOG overrides
# the file (tests). Deterministic and read-only: never writes a file.
# Exit 0 ok (incl. "No changes") · 1 <to> has no section · 2 usage error or malformed in-range content.
set -u

FLOOR="0.22.0"   # the first version the CHANGELOG carries briefs for
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CL="${WHATS_NEW_CHANGELOG:-$SCRIPT_DIR/../CHANGELOG.md}"
TAB=$(printf '\t')

die() { printf 'whats-new: %s\n' "$2" >&2; exit "$1"; }

is_semver() {  # bounded first, so a hostile argument never reaches the regex at length
  [ "${#1}" -le 20 ] || return 1
  case $1 in *[!0-9.]*) return 1 ;; esac  # grep matches per line, so a newline must never reach it
  printf '%s' "$1" | grep -Eq '^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$'
}

key() {  # key <X.Y.Z> → one comparable integer (each component ≤ 4 digits, checked by is_semver)
  local a="${1%%.*}" r="${1#*.}"
  local b="${r%%.*}" c="${r#*.}"
  echo $(( 10#$a * 100000000 + 10#$b * 10000 + 10#$c ))
}

case $# in
  1) MODE=one;   FROM="";   TO="$1" ;;
  2) MODE=range; FROM="$1"; TO="$2" ;;
  *) die 2 "usage: whats-new.sh [<from>] <to>" ;;
esac
[ "$MODE" = one ] || is_semver "$FROM" || die 2 "not a version: $FROM"
is_semver "$TO" || die 2 "not a version: $TO"
[ -f "$CL" ] && [ -r "$CL" ] || die 2 "no readable CHANGELOG at $CL"

SECTIONS=$(awk '/^## \[[0-9]+\.[0-9]+\.[0-9]+\]/ { v = $2; gsub(/[][]/, "", v); print v }' "$CL")
printf '%s\n' "$SECTIONS" | grep -Fxq -- "$TO" || die 1 "no CHANGELOG section for v$TO"
TK=$(key "$TO")

if [ "$MODE" = one ]; then  # the nearest older section is the lower bound
  FROM="0.0.0"
  for v in $SECTIONS; do
    k=$(key "$v")
    if [ "$k" -lt "$TK" ] && [ "$k" -gt "$(key "$FROM")" ]; then FROM="$v"; fi
  done
fi
FK=$(key "$FROM")
if [ "$FK" -ge "$TK" ]; then
  printf 'No changes: v%s is not older than v%s.\n' "$FROM" "$TO"
  exit 0
fi

# One record per in-range bullet: <category> TAB <sort key> TAB <version> TAB <text>.
# A malformed line instead prints one "!<message>" line and exits 3 (stdout, so no temp file is needed).
# The sort key is zero-padded text, so mawk never formats a large integer.
RECS=$(awk -v fk="$FK" -v tk="$TK" '
  BEGIN { ok["Action needed"] = 1; ok["Added"] = 1; ok["Changed"] = 1; ok["Fixed"] = 1; ok["Removed"] = 1; ok["Security"] = 1 }
  /^## / {
    in_r = 0; v = ""; cat = ""
    if (match($0, /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/)) {
      v = substr($0, 5, RLENGTH - 5); split(v, p, ".")
      k = p[1] * 100000000 + p[2] * 10000 + p[3]
      in_r = (k > fk && k <= tk); sk = sprintf("%04d%04d%04d", p[1], p[2], p[3])
    }
    next
  }
  !in_r { next }
  /^### / { cat = substr($0, 5); if (!(cat in ok)) { print "!unknown category \"" cat "\" in v" v; exit 3 } next }
  /^- / { if (cat == "") { print "!bullet before any category in v" v; exit 3 }
          t = substr($0, 3); gsub(/\t/, " ", t)
          print cat "\t" sk "\t" v "\t" t; next }
  /^[ \t]*$/ { next }
  { print "!unexpected line in v" v ": " $0; exit 3 }
' "$CL")
rc=$?
[ "$rc" -eq 0 ] || die 2 "malformed CHANGELOG — $(printf '%s\n' "$RECS" | grep -m1 '^!' | cut -c2-)"

if [ "$MODE" = one ]; then printf 'What changed in v%s\n' "$TO"; else printf 'What changed from v%s to v%s\n' "$FROM" "$TO"; fi
if [ -z "$RECS" ]; then
  printf '\nNo briefs in this range.\n'
else
  for c in "Action needed" "Added" "Changed" "Fixed" "Removed" "Security"; do
    lines=$(printf '%s\n' "$RECS" | awk -F'\t' -v c="$c" '$1 == c' | sort -s -t"$TAB" -k2,2r)
    [ -n "$lines" ] || continue
    printf '\n### %s\n' "$c"
    printf '%s\n' "$lines" | awk -F'\t' '{ print "- " $4 " (v" $3 ")" }'
  done
fi
if [ "$MODE" = range ] && [ "$FK" -lt "$(key "$FLOOR")" ]; then
  printf '\nNote: briefs start at v%s — for older changes, see the git history.\n' "$FLOOR"
fi
exit 0
