#!/usr/bin/env bash
# test-style-plugins.sh — behavioural tests for scripts/marvin-style-plugins.sh (v0.38.0).
# Pins: settings precedence user < project < local, managed over all; registry hits; forced styles
# found in the plugin cache; marvin itself never listed; malformed settings tolerated; never writes.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/marvin-style-plugins.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-sptest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
CFG="$WORK/cfg"; P="$WORK/p"; MANAGED="$WORK/managed.json"
export CLAUDE_CONFIG_DIR="$CFG" MARVIN_MANAGED_SETTINGS="$MANAGED"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="" CLAUDE_CODE_DISABLE_1M_CONTEXT="" CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=""

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
eq()  { if [ "$OUT" = "$1" ]; then ok "= $1"; else bad "got '$OUT', want '$1'"; fi; }
run() { OUT=$(bash "${S:-$SCRIPT}" "$P" 2>&1); RC=$?; }
reset() { rm -rf "$CFG" "$P" "$MANAGED"; mkdir -p "$CFG" "$P/.claude"; }
ep() { printf '{"enabledPlugins":{%s}}\n' "$2" > "$1"; }   # ep <file> <members>
EX=explanatory-output-style@claude-plugins-official; LE=learning-output-style@claude-plugins-official
mk_forced() {  # mk_forced <name> <mkt> <style> <force:true|false>
  mkdir -p "$CFG/plugins/cache/$2/$1/1.0.0/output-styles"
  printf -- '---\nname: %s\ndescription: d\nforce-for-plugin: %s\n---\nbody\n' "$3" "$4" > "$CFG/plugins/cache/$2/$1/1.0.0/output-styles/$3.md"
}

hd "P1 nothing enabled — nothing listed"
reset; run; [ "$RC" = 0 ] && ok "exit 0" || bad "exit $RC"; eq ""

hd "P2 a user-enabled registry plugin is listed"
reset; ep "$CFG/settings.json" "\"$EX\":true"; run; eq "registry: $EX"

hd "P3 local false beats user true; P4 project true beats user false"
reset; ep "$CFG/settings.json" "\"$EX\":true"; ep "$P/.claude/settings.local.json" "\"$EX\":false"; run; eq ""
reset; ep "$CFG/settings.json" "\"$EX\":false"; ep "$P/.claude/settings.json" "\"$EX\":true"; run; eq "registry: $EX"

hd "P5 an enabled plugin forcing its style is listed with the style; P6 force false is not"
reset; mk_forced loud mkt loudstyle true; ep "$CFG/settings.json" '"loud@mkt":true'; run; eq "forced-style: loud@mkt loudstyle"
reset; mk_forced calm mkt calmstyle false; ep "$CFG/settings.json" '"calm@mkt":true'; run; eq ""

hd "P7 managed settings forcing a hit on are reported as managed, whatever local says"
reset; ep "$MANAGED" "\"$LE\":true"; ep "$P/.claude/settings.local.json" "\"$LE\":false"; run; eq "managed: $LE"

hd "P8 marvin itself is never listed"
reset; mk_forced marvin emprove marvin true; ep "$CFG/settings.json" '"marvin@emprove":true'; run; eq ""

hd "P9 malformed settings are skipped, the others still read"
reset; printf '{"enabledPlugins":{"%s":tr' "$EX" > "$P/.claude/settings.json"; ep "$CFG/settings.json" "\"$EX\":true"; run; eq "registry: $EX"

hd "P10 path-like ids are ignored; usage error exits 2; never writes"
reset; ep "$CFG/settings.json" '"../x@..":true'; run; eq ""
OUT=$(bash "$SCRIPT" a b 2>&1); RC=$?; [ "$RC" = 2 ] && ok "usage exit 2" || bad "usage exit $RC"
reset; ep "$CFG/settings.json" "\"$EX\":true"; before=$(ls -R "$WORK" | cksum); run; after=$(ls -R "$WORK" | cksum)
[ "$before" = "$after" ] && ok "nothing written" || bad "the script wrote something"

hd "P11 lib missing — exit 2, one stderr line, empty stdout (never \"none found\")"
d="$WORK/nolib"; mkdir -p "$d"; cp "$SCRIPT" "$d/s.sh"; reset
so=$(bash "$d/s.sh" "$P" 2>"$WORK/nolib.err"); RC=$?; se=$(cat "$WORK/nolib.err")
[ "$RC" = 2 ] && ok "exit 2" || bad "exit $RC"
[ -z "$so" ] && ok "stdout empty" || bad "stdout '$so'"
[ -n "$se" ] && ok "stderr non-empty" || bad "stderr empty"

hd "M1 precedence reverted (first source wins) — P3 must catch it"
d="$WORK/m1"; mkdir -p "$d/lib" "$d/../hooks" 2>/dev/null; cp "$LIB" "$d/lib/"; mkdir -p "$WORK/hooks"; cp "$SCRIPT_DIR/../hooks/style-plugins.txt" "$WORK/hooks/"
A="merge='{ if (!(\$2 in r) || \$1 >= r[\$2]) { r[\$2] = \$1; v[\$2] = \$3 } } END { for (k in r) print r[k] \"\t\" k \"\t\" v[k] }'" \
B="merge='{ if (!(\$2 in r)) { r[\$2] = \$1; v[\$2] = \$3 } } END { for (k in r) print r[k] \"\t\" k \"\t\" v[k] }'" \
  awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$SCRIPT" > "$d/s.sh"
if [ ! -f "$SCRIPT" ] || cmp -s "$d/s.sh" "$SCRIPT"; then bad "mutation precedence: target line not found — harness is stale"; else
  reset; ep "$CFG/settings.json" "\"$EX\":true"; ep "$P/.claude/settings.local.json" "\"$EX\":false"
  S="$d/s.sh" run
  if [ "$RC" != 0 ]; then bad "mutation precedence: the mutant crashed (rc $RC) — harness is stale"
  elif [ -n "$OUT" ]; then ok "mutation precedence caught"; else bad "mutation precedence survived"; fi; fi

printf '\n----\ntest-style-plugins: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
