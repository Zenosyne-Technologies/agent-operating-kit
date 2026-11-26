#!/usr/bin/env bash
# test-codeguard.sh — behavioural tests for scripts/marvin-codeguard.sh (AOS-257).
# Pins: install lookup by plugin id (user vs project scope, physical-path match), effective enabledPlugins
# (user < project < local, managed over all), the validated-version advisory, usage/lib failures, never writes.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/marvin-codeguard.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-cgtest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
WORK=$(cd "$WORK" && pwd -P)
CFG="$WORK/cfg"; P="$WORK/p"; MANAGED="$WORK/managed.json"; DOC="$WORK/codeguard.md"
export CLAUDE_CONFIG_DIR="$CFG" MARVIN_MANAGED_SETTINGS="$MANAGED" MARVIN_CODEGUARD_DOC="$DOC"

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0; ROOT=""
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
eq()  { if [ "$OUT" = "$1" ]; then ok "= $(printf '%s' "$1" | tr '\n' '|')"; else bad "got '$OUT', want '$1'"; fi; }
rc()  { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1"; fi; }
snap() { ( cd "$WORK" && find . -exec ls -ld {} + 2>/dev/null | cksum; find "$WORK" -type f -exec cksum {} + 2>/dev/null | cksum ); }
run() {  # run [args...]  (default: check "$ROOT")
  local before after; [ "$#" -gt 0 ] || set -- check "${ROOT:-$P}"
  before=$(snap); OUT=$(bash "${S:-$SCRIPT}" "$@" 2>&1); RC=$?; after=$(snap)
  [ "$before" = "$after" ] || bad "the script wrote something"
}
reset() { rm -rf "$CFG" "$P" "$MANAGED" "$WORK/link"; mkdir -p "$CFG/plugins" "$P/.claude"; ROOT="$P"
  printf 'Intro\nValidated version: `1.5.0`\n' > "$DOC"; }
ID=codeguard-security@project-codeguard; OTHER=pinecone@claude-plugins-official
ep() { printf '{"enabledPlugins":{%s}}\n' "$2" > "$1"; }   # ep <file> <members>
entry() { # entry <scope> <version> [projectPath]
  printf '{"scope":"%s","installPath":"/x/%s","version":"%s","installedAt":"t","lastUpdated":"t","gitCommitSha":"abc"%s}' \
    "$1" "$2" "$2" "${3:+,\"projectPath\":\"$3\"}"; }
inst() { # inst <codeguard entries, comma separated>  (always with another plugin alongside, listed on both sides)
  printf '{"version":2,"plugins":{"%s":[%s],"%s":[%s],"zz@m":[%s]}}\n' "$OTHER" "$(entry user 9.9.9)" "$ID" "$1" "$(entry project 7.7.7 "$P")" > "$CFG/plugins/installed_plugins.json"; }
EN="\"$OTHER\":true"

hd "C1 no installed_plugins.json"
reset; ep "$CFG/settings.json" "$EN,\"$ID\":true"; run; eq "not-installed"; rc 4

hd "C2 user entry, enabled in user settings"
reset; inst "$(entry user 1.5.0)"; ep "$CFG/settings.json" "$EN,\"$ID\":true"; run; eq "ready 1.5.0 user"; rc 0

hd "C3 project entry for this root, enabled in project settings"
reset; inst "$(entry project 1.5.0 "$P")"; ep "$P/.claude/settings.json" "$EN,\"$ID\":true"; run; eq "ready 1.5.0 project"; rc 0

hd "C4 project entry for another path only"
reset; inst "$(entry project 1.5.0 /elsewhere)"; ep "$CFG/settings.json" "\"$ID\":true"; run; eq "not-installed"; rc 4

hd "C5 user true, local false"
reset; inst "$(entry user 1.5.0)"; ep "$CFG/settings.json" "\"$ID\":true"; ep "$P/.claude/settings.local.json" "\"$ID\":false"; run; eq "disabled 1.5.0"; rc 4

hd "C6 installed, id absent from every enabledPlugins (another id enabled)"
reset; inst "$(entry user 1.5.0)"; ep "$CFG/settings.json" "$EN"; run; eq "disabled 1.5.0"; rc 4

hd "C7 installed_plugins.json is malformed"
reset; printf '{bad' > "$CFG/plugins/installed_plugins.json"; run; eq "error unreadable installed_plugins.json"; rc 4
reset; printf '{"version":2,"plugins":{"%s":[{"scope":"user"' "$ID" > "$CFG/plugins/installed_plugins.json"; run; eq "error unreadable installed_plugins.json"; rc 4

hd "C8 managed false over user true"
reset; inst "$(entry user 1.5.0)"; ep "$CFG/settings.json" "\"$ID\":true"; ep "$MANAGED" "\"$ID\":false"; run; eq "disabled 1.5.0"; rc 4

hd "C9 installed newer than validated"
reset; inst "$(entry user 1.6.0)"; ep "$CFG/settings.json" "\"$ID\":true"; run; eq "ready 1.6.0 user
validated: 1.5.0"; rc 0

hd "C10 usage errors"
reset; run check a b; eq "$(printf 'usage: marvin-codeguard.sh check [<project-root>]')"; rc 2
run bogus; rc 2; [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && ok "one line" || bad "not one line: $OUT"

hd "C12 root reached through a symlink, project entry with the physical path"
reset; ln -s "$P" "$WORK/link"; inst "$(entry project 1.5.0 "$P")"; ep "$P/.claude/settings.json" "\"$ID\":true"; ROOT="$WORK/link" run; eq "ready 1.5.0 project"; rc 0

hd "C14 both user and project entries — the project one for this root wins"
reset; inst "$(entry user 1.4.0),$(entry project 1.5.0 "$P")"; ep "$CFG/settings.json" "\"$ID\":true"; run; eq "ready 1.5.0 project"; rc 0
reset; inst "$(entry user 1.4.0),$(entry project 1.5.0 /elsewhere)"; ep "$CFG/settings.json" "\"$ID\":true"; run; eq "ready 1.4.0 user
validated: 1.5.0"; rc 0

hd "C15 validated-version doc missing, unreadable or without the line — no validated line, exit unchanged"
reset; inst "$(entry user 1.6.0)"; ep "$CFG/settings.json" "\"$ID\":true"
rm -f "$DOC"; run; eq "ready 1.6.0 user"; rc 0
printf 'no version here\n' > "$DOC"; run; eq "ready 1.6.0 user"; rc 0
printf 'Validated version: `1.5.0`\n' > "$DOC"; chmod 000 "$DOC"; run; chmod 644 "$DOC"
if [ "$(id -u)" = 0 ]; then ok "root can read it; skipped"; else eq "ready 1.6.0 user"; fi

hd "C16 CLAUDE_PROJECT_DIR is the default root"
reset; inst "$(entry project 1.5.0 "$P")"; ep "$P/.claude/settings.json" "\"$ID\":true"
OUT=$(CLAUDE_PROJECT_DIR="$P" bash "$SCRIPT" check 2>&1); RC=$?; eq "ready 1.5.0 project"; rc 0

hd "C17 lib missing — exit 2, one stderr line, empty stdout"
d="$WORK/nolib"; mkdir -p "$d"; cp "$SCRIPT" "$d/s.sh"; reset
so=$(bash "$d/s.sh" check "$P" 2>"$WORK/nolib.err"); RC=$?; se=$(cat "$WORK/nolib.err")
rc 2; [ -z "$so" ] && ok "stdout empty" || bad "stdout '$so'"; [ -n "$se" ] && ok "stderr non-empty" || bad "stderr empty"

hd "C13 mutation: precedence reverted (first source wins) — C5 must FAIL against it"
d="$WORK/m1"; mkdir -p "$d/lib"; cp "$SCRIPT" "$d/s.sh"
A=' || $1 >= r[$2]' awk '{ i = index($0, ENVIRON["A"]); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(ENVIRON["A"])); print }' "$LIB" > "$d/lib/marvin-hook-lib.sh"
if cmp -s "$d/lib/marvin-hook-lib.sh" "$LIB"; then bad "mutation: target line not found — harness is stale"; else
  reset; inst "$(entry user 1.5.0)"; ep "$CFG/settings.json" "\"$ID\":true"; ep "$P/.claude/settings.local.json" "\"$ID\":false"
  S="$d/s.sh" run
  if [ "$OUT" = "disabled 1.5.0" ]; then bad "mutation survived"; elif [ -z "$OUT" ] || [ "$RC" = 2 ]; then bad "mutant crashed — harness is stale: $OUT"; else ok "mutation caught ($OUT)"; fi; fi

printf '\n----\ntest-codeguard: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
