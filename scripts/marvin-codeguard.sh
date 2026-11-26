#!/usr/bin/env bash
# marvin-codeguard.sh — is the third-party CodeGuard plugin (codeguard-security@project-codeguard) installed
# and enabled for this project? Read-only; run by the install and upgrade skills, which ASK before any change.
# Usage: bash marvin-codeguard.sh check [<project-root>]   (default root: $CLAUDE_PROJECT_DIR, else $PWD)
# Stdout, one status line (ids and versions encoded with mh_q):
#   ready <version> <user|project>   installed and the effective enabledPlugins value is exactly true
#   disabled <version>               installed, but the effective value is false or absent
#   not-installed                    no usable entry (no installed_plugins.json, id absent, or only entries for other projects)
#   error unreadable installed_plugins.json   the file exists but is not well-formed JSON
# After `ready`, an advisory `validated: <v>` line when the installed version differs from the version this kit
# was validated against (the line "Validated version: `<v>`" in templates/marvin/agents/codeguard.md); no such
# line when the doc is missing, unreadable or lacks it — advisory only, never an error, never changes the exit.
# Exit: 0 ready · 4 anything else · 2 usage error or the hook lib failed to load (one stderr line, empty stdout).
# Entries: $cfg/plugins/installed_plugins.json, plugins["codeguard-security@project-codeguard"] is an array of
# {scope, installPath, version, projectPath?}. A scope project|local entry counts only when its projectPath equals
# the project root (physical paths compared); a user entry counts everywhere; both present -> the project one wins.
# Effective enabledPlugins: user < project < local settings, managed over all (mh_enabled_plugins).
# Seams: CLAUDE_CONFIG_DIR, MARVIN_MANAGED_SETTINGS, MARVIN_CODEGUARD_DOC (validated-version doc path). Never writes.
set -u
export LC_ALL=C
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || { echo "marvin-codeguard.sh: cannot load lib/marvin-hook-lib.sh" >&2; exit 2; }
[ "${1:-}" = check ] && [ "$#" -le 2 ] || { echo "usage: marvin-codeguard.sh check [<project-root>]" >&2; exit 2; }
root="${2:-${CLAUDE_PROJECT_DIR:-$PWD}}"
cfg="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
file="$cfg/plugins/installed_plugins.json"
ID=codeguard-security@project-codeguard
TAB=$(printf '\t'); US=$(printf '\037')
doc="${MARVIN_CODEGUARD_DOC:-$(dirname "$0")/../templates/marvin/agents/codeguard.md}"

# cg_entries — stdin: installed_plugins.json. Prints `BAD` alone when the JSON is not well-formed (unbalanced,
# unterminated string, or not an object); else one line per entry under the ID key: scope US projectPath US version.
cg_entries() {
  awk -v US="$US" -v ID="$ID" '
  { s = s $0 "\n" }
  END {
    n = length(s); i = 1; depth = 0; cap = 0; capd = 0; pend = 0; haskey = 0; bad = 0; first = 1; out = ""
    while (i <= n) {
      c = substr(s, i, 1)
      if (first && !index(" \t\r\n", c)) { first = 0; if (c != "{") bad = 1 }
      if (c == "\"") {
        v = ""; i++; closed = 0
        while (i <= n) {
          c = substr(s, i, 1)
          if (c == "\\") { e = substr(s, i + 1, 1); if (e == "n" || e == "t" || e == "r") e = " "; v = v e; i += 2; continue }
          if (c == "\"") { closed = 1; break }
          v = v c; i++
        }
        if (!closed) bad = 1
        i++
        j = i; while (j <= n && index(" \t\r\n", substr(s, j, 1))) j++
        if (substr(s, j, 1) == ":") {
          key = v; haskey = 1; pend = 0
          if (!cap && v == ID) pend = 1
        } else {
          if (cap && depth == capd + 1 && haskey) f[key] = v
          haskey = 0; pend = 0
        }
        continue
      }
      if (c == "{" || c == "[") {
        depth++
        if (c == "[" && pend && !cap) { cap = 1; capd = depth }
        else if (c == "{" && cap && depth == capd + 1) { delete f }
        pend = 0; haskey = 0
      } else if (c == "}" || c == "]") {
        if (c == "}" && cap && depth == capd + 1) out = out f["scope"] US f["projectPath"] US f["version"] "\n"
        if (c == "]" && cap && depth == capd) cap = 0
        depth--; if (depth < 0) bad = 1
        pend = 0; haskey = 0
      } else if (!index(" \t\r\n:,", c)) { haskey = 0; pend = 0 }
      i++
    }
    if (depth != 0 || first) bad = 1
    if (bad) print "BAD"; else printf "%s", out
  }'
}

if [ ! -f "$file" ]; then echo "not-installed"; exit 4; fi
ents=$(head -c "$MH_MAX_IN" -- "$file" 2>/dev/null | cg_entries) || ents=BAD
if [ "$ents" = BAD ]; then echo "error unreadable installed_plugins.json"; exit 4; fi

phys=$(cd "$root" 2>/dev/null && pwd -P) || phys=$root
sel_ver=""; sel_scope=""
while IFS="$US" read -r scope pp ver; do
  [ -n "$scope" ] || continue
  case "$scope" in
    user) [ -n "$sel_scope" ] || { sel_scope=user; sel_ver=$ver; } ;;
    project|local)
      [ -n "$pp" ] || continue
      pp=$(cd "$pp" 2>/dev/null && pwd -P) || continue
      [ "$pp" = "$phys" ] && { sel_scope=project; sel_ver=$ver; } ;;
  esac
done <<EOF2
$(printf '%s\n' "$ents" | awk -v US="$US" -F"$US" '$1 == "project" || $1 == "local" { print; next } { u[++n] = $0 } END { for (k = 1; k <= n; k++) print u[k] }')
EOF2
# project entries are listed first above, so a matching project entry is set before any user entry is considered;
# a later user entry must not replace it (guarded by the [ -n "$sel_scope" ] test), and a later project match may.
[ -n "$sel_scope" ] || { echo "not-installed"; exit 4; }
[ -n "$sel_ver" ] || sel_ver=unknown

val=$(mh_enabled_plugins "$root" | awk -F"$TAB" -v id="$ID" '$2 == id { print $3 }')
if [ "$val" != true ]; then echo "disabled $(mh_q "$sel_ver")"; exit 4; fi
echo "ready $(mh_q "$sel_ver") $sel_scope"
vv=""
[ -r "$doc" ] && vv=$(sed -nE 's/^Validated version: `([^`]+)`.*/\1/p' -- "$doc" 2>/dev/null | head -n 1)
[ -z "$vv" ] || [ "$vv" = "$sel_ver" ] || echo "validated: $(mh_q "$vv")"
exit 0
