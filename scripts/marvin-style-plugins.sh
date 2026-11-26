#!/usr/bin/env bash
# marvin-style-plugins.sh — lists the enabled plugins that compete with Marvin's output style (v0.38.0).
# Read-only; run by the install and upgrade skills, which ASK before any change — never a silent disable.
# Usage: bash marvin-style-plugins.sh [<project-root>]   (default: $CLAUDE_PROJECT_DIR, else $PWD)
# Effective enabledPlugins: user < project < local settings (later wins); managed settings win over all.
# One line per hit, ids encoded with git's core.quotePath convention (mh_q):
#   registry: <id>              enabled and listed in hooks/style-plugins.txt (SessionStart style injectors)
#   forced-style: <id> <style>  enabled and ships an output style with force-for-plugin: true
#   managed: <id>               a hit that managed settings force on — report it; it cannot be disabled here
# Exit 0 (also when nothing is found or a settings file is unreadable); 2 on a usage error or when the hook lib
# fails to load (one stderr line, no stdout — a failure to report, never "none found"). Never writes.
# MARVIN_MANAGED_SETTINGS overrides the managed-settings path (a test seam).
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || { echo "marvin-style-plugins.sh: cannot load lib/marvin-hook-lib.sh" >&2; exit 2; }
[ "$#" -le 1 ] || { echo "usage: marvin-style-plugins.sh [<project-root>]" >&2; exit 2; }
root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
cfg="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
registry="$(dirname "$0")/../hooks/style-plugins.txt"
TAB=$(printf '\t')

eff=$(mh_enabled_plugins "$root")

printf '%s\n' "$eff" | while IFS="$TAB" read -r rank id val; do
  [ -n "$id" ] && [ "$val" = true ] || continue
  case "$id" in marvin@*|*/*|*..*) continue ;; esac
  hit=""
  if [ -f "$registry" ] && grep -vE '^[[:space:]]*(#|$)' "$registry" | grep -Fxq -- "$id"; then
    hit="registry: $(mh_q "$id")"
  else
    name=${id%@*}; mkt=${id#*@}
    for f in "$cfg/plugins/cache/$mkt/$name"/*/output-styles/*.md; do
      [ -f "$f" ] || continue
      fmo=$(head -n 20 -- "$f" | awk 'NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f')
      printf '%s\n' "$fmo" | grep -Eq '^force-for-plugin:[[:space:]]*true[[:space:]]*$' || continue
      sty=$(printf '%s\n' "$fmo" | sed -nE 's/^name:[[:space:]]*//p' | head -n 1)
      [ -n "$sty" ] || { sty=${f##*/}; sty=${sty%.md}; }
      hit="forced-style: $(mh_q "$id") $(mh_q "$sty")"; break
    done
  fi
  [ -n "$hit" ] || continue
  if [ "$rank" = 9 ]; then echo "managed: $(mh_q "$id")"; else echo "$hit"; fi
done
exit 0
