#!/usr/bin/env bash
# test-whats-new.sh — behavioural tests for scripts/whats-new.sh (AOS-184).
# Each fixture pins one contract point: range bounds, category and version ordering, single-version
# mode, empty and inverted ranges, unknown versions, argument validation, the pre-0.22 notice,
# malformed input refusal, numeric (not textual) version order, and read-only behaviour.
# Run from anywhere: bash scripts/test-whats-new.sh — exit 0 = all passed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WN="$SCRIPT_DIR/whats-new.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-wntest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

PASSED=0; FAILED=0; CURRENT=""; OUT=""; ERR=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc()     { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1"; fi; }
assert_out()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_no_out() { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "out must not have: $1"; else ok "out free of: $1"; fi; }
assert_err()    { if printf '%s\n' "$ERR" | grep -Fq -- "$1"; then ok "err has: $1"; else bad "err lacks: $1"; fi; }
assert_before() { # assert_before <first> <second> — both present, first on an earlier line
  local a b; a=$(printf '%s\n' "$OUT" | grep -nF -- "$1" | head -1 | cut -d: -f1)
  b=$(printf '%s\n' "$OUT" | grep -nF -- "$2" | head -1 | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then ok "'$1' before '$2'"; else bad "'$1' (line ${a:-none}) not before '$2' (line ${b:-none})"; fi; }
run() { # run <changelog> <args...>
  local cl="$1"; shift
  OUT=$(WHATS_NEW_CHANGELOG="$cl" bash "$WN" "$@" 2>"$WORK/err"); RC=$?; ERR=$(cat "$WORK/err"); }

CL="$WORK/CHANGELOG.md"
cat > "$CL" <<'EOF'
# Changelog

Intro paragraph.

## [0.36.0] — 2026-10-08

### Added
- New A

### Action needed
- Do X

## [0.35.1] — 2026-10-01

### Fixed
- Fix B

## [0.35.0] — 2026-09-27

### Changed
- Change C

### Action needed
- Do Y

## [0.22.0] — 2026-08-20

### Added
- Old D

## [≤0.21.x]

- See the git history.
EOF

hd "W1 range is (from, to] and categories come in the fixed order"
run "$CL" 0.35.0 0.36.0
assert_rc 0
assert_out "What changed from v0.35.0 to v0.36.0"
assert_out "- Do X (v0.36.0)"
assert_out "- New A (v0.36.0)"
assert_out "- Fix B (v0.35.1)"
assert_no_out "Change C"
assert_before "### Action needed" "### Added"
assert_before "### Added" "### Fixed"

hd "W2 newest version first inside a category"
run "$CL" 0.22.0 0.36.0
assert_rc 0
assert_before "- Do X (v0.36.0)" "- Do Y (v0.35.0)"
assert_no_out "Old D"

hd "W3 lower bound exclusive, upper inclusive"
run "$CL" 0.35.0 0.35.1
assert_rc 0
assert_out "- Fix B (v0.35.1)"
assert_no_out "Do Y"
assert_no_out "Do X"

hd "W4 single-argument mode shows one version's own section"
run "$CL" 0.35.1
assert_rc 0
assert_out "What changed in v0.35.1"
assert_out "- Fix B (v0.35.1)"
assert_no_out "Do Y"
assert_no_out "briefs start at"

hd "W5 empty and inverted ranges"
run "$CL" 0.36.0 0.36.0
assert_rc 0
assert_out "No changes"
run "$CL" 0.36.0 0.35.0
assert_rc 0
assert_out "No changes"

hd "W6 a target version with no section"
run "$CL" 0.35.0 0.40.0
assert_rc 1
assert_err "no CHANGELOG section for v0.40.0"

hd "W7 argument validation"
run "$CL" abc 0.36.0;            assert_rc 2; assert_err "not a version: abc"
run "$CL" 0.35.0 1.2;            assert_rc 2; assert_err "not a version: 1.2"
run "$CL" 0.35.0 12345.0.0;      assert_rc 2
run "$CL";                       assert_rc 2; assert_err "usage"
run "$CL" 0.1.0 0.2.0 0.3.0;     assert_rc 2; assert_err "usage"
run "$WORK/missing.md" 0.36.0;   assert_rc 2; assert_err "no CHANGELOG at"

hd "W8 pre-0.22 notice only when the range starts below v0.22.0"
run "$CL" 0.21.0 0.22.0
assert_rc 0
assert_out "- Old D (v0.22.0)"
assert_out "Note: briefs start at v0.22.0"
run "$CL" 0.35.0 0.36.0
assert_no_out "briefs start at"

hd "W9 malformed in-range content is refused, never dropped"
BADCAT="$WORK/badcat.md"; printf '## [0.36.0] — 2026-10-08\n\n### Misc\n- thing\n' > "$BADCAT"
run "$BADCAT" 0.35.0 0.36.0; assert_rc 2; assert_err "malformed"
NOCAT="$WORK/nocat.md"; printf '## [0.36.0] — 2026-10-08\n\n- orphan bullet\n' > "$NOCAT"
run "$NOCAT" 0.35.0 0.36.0; assert_rc 2; assert_err "malformed"
WRAP="$WORK/wrap.md"; printf '## [0.36.0] — 2026-10-08\n\n### Added\n- first half\n  second half\n' > "$WRAP"
run "$WRAP" 0.35.0 0.36.0; assert_rc 2; assert_err "malformed"

hd "W10 versions compare numerically, not as text"
NUM="$WORK/num.md"
printf '## [0.10.0] — 2026-01-02\n\n### Added\n- Ten\n\n## [0.9.0] — 2026-01-01\n\n### Added\n- Nine\n' > "$NUM"
run "$NUM" 0.9.0 0.10.0
assert_rc 0
assert_out "- Ten (v0.10.0)"
assert_no_out "Nine"

hd "W11 read-only: the changelog and its directory are unchanged"
before=$(cksum < "$CL"); files_before=$(ls "$WORK" | wc -l)
run "$CL" 0.22.0 0.36.0
after=$(cksum < "$CL"); files_after=$(ls "$WORK" | wc -l)
if [ "$before" = "$after" ] && [ "$files_before" = "$files_after" ]; then ok "nothing written"; else bad "the script wrote something"; fi

hd "W12 the real CHANGELOG has a section for the current plugin version"
ver=$(grep -m1 '"version"' "$SCRIPT_DIR/../.claude-plugin/plugin.json" | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
OUT=$(bash "$WN" "$ver" 2>"$WORK/err"); RC=$?; ERR=$(cat "$WORK/err")
assert_rc 0
assert_out "What changed in v$ver"

printf '\n----\ntest-whats-new: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
