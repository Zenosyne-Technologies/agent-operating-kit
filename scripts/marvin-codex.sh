#!/usr/bin/env bash
# marvin-codex.sh — the ONLY place in Marvin that touches OpenAI's Codex companion (codex-companion.mjs, shipped
# by the `codex@openai-codex` Claude Code plugin). Everything Marvin knows about the companion's argv, JSON
# shapes and quirks lives here; the codex handover guides call this script and never the companion.
# Subcommands: check (this file, AOS-233); run / result land with AOS-234 in this same file.
#
#   marvin-codex.sh check [--json]
#     Is Codex usable from here? Stdout is exactly ONE line:
#       ready · not-installed · no-node · no-codex-cli · not-logged-in · error <reason, <= 80 chars in all>
#     Exit 0 for ready, 4 for anything else, 2 for a usage error. With --json the companion's `setup --json`
#     output passes through byte-for-byte on stdout and the exit code is the same; when there is no such output
#     (no node, not installed, companion failed) stdout stays empty and the status line goes to stderr.
#     Order: node not on PATH -> no-node (the companion is not called) · companion not found -> not-installed ·
#     companion rc != 0 or stdout not a JSON object -> error · node.available false -> no-node · codex.available
#     false -> no-codex-cli · auth.loggedIn false -> not-logged-in · ready true -> ready · else error.
#     Fields are read BY JSON PATH (`available` appears under node, npm, codex, auth, sessionRuntime).
#
# Locating the companion (mc_locate prints its absolute path or returns 1), first hit wins:
#   1. a `scope: project` entry of any `codex@*` key in the plugins file whose projectPath is the git toplevel
#      of the cwd (physical paths compared, so symlinked checkouts match) and whose companion file exists;
#   2. a `scope: user` entry of a `codex@*` key whose companion file exists;
#   3. the newest existing <cache>/<semver>/scripts/codex-companion.mjs (numeric compare: 1.0.10 > 1.0.9).
# A stale installPath therefore falls through instead of failing. Entries of other plugins are never read.
#
# Env seams (tests): MARVIN_CODEX_PLUGINS_JSON (default $HOME/.claude/plugins/installed_plugins.json),
#   MARVIN_CODEX_CACHE (default $HOME/.claude/plugins/cache/openai-codex/codex). `node` comes from PATH.
# Contract: never writes outside a mktemp scratch it removes; never runs `codex login`; never touches
# ~/.codex; bash 3.2 + POSIX awk (macOS awk and mawk), no python/jq.
# Exit: 0 ready · 2 usage · 4 not ready / not available.
set -u
export LC_ALL=C
MC_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/marvin-hook-lib.sh
. "$MC_HERE/lib/marvin-hook-lib.sh" 2>/dev/null || { echo "error hook library missing" >&2; exit 4; }

MC_US=$(printf '\037')
MC_COMPANION=scripts/codex-companion.mjs

# mc_entries — stdin: installed_plugins.json. One line per entry under any `codex@*` key:
#   <scope> US <projectPath> US <installPath>   (entries without an installPath are dropped)
# A small tokenizer, scoped to the codex@ key; other plugins' scope/installPath keys never reach it.
mc_entries() {
  awk -v US="$MC_US" '
  { s = s $0 "\n" }
  END {
    n = length(s); i = 1; depth = 0; cap = 0; capd = 0; pend = 0; haskey = 0
    while (i <= n) {
      c = substr(s, i, 1)
      if (c == "\"") {
        v = ""; i++
        while (i <= n) {
          c = substr(s, i, 1)
          if (c == "\\") { e = substr(s, i + 1, 1); if (e == "n" || e == "t" || e == "r") e = " "; v = v e; i += 2; continue }
          if (c == "\"") break
          v = v c; i++
        }
        i++
        j = i; while (j <= n && index(" \t\r\n", substr(s, j, 1))) j++
        if (substr(s, j, 1) == ":") {
          key = v; haskey = 1; pend = 0
          if (!cap && v ~ /^codex@/) pend = 1
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
        if (c == "}" && cap && depth == capd + 1 && f["installPath"] != "") print f["scope"] US f["projectPath"] US f["installPath"]
        if (c == "]" && cap && depth == capd) cap = 0
        depth--; pend = 0; haskey = 0
      } else if (!index(" \t\r\n:,", c)) { haskey = 0; pend = 0 }
      i++
    }
  }'
}

mc_phys() { ( cd "$1" 2>/dev/null && pwd -P ); }   # physical path of a directory, or nothing

# mc_vkey <name> — fixed-width sortable key of a x.y.z[-pre] folder name, or rc 1 when it is not a version
mc_vkey() {
  local re='^([0-9]+)\.([0-9]+)\.([0-9]+)([-+].*)?$'
  [[ $1 =~ $re ]] || return 1
  printf '%09d%09d%09d' "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))" "$((10#${BASH_REMATCH[3]}))"
}

mc_locate() {
  local pj=${MARVIN_CODEX_PLUGINS_JSON:-$HOME/.claude/plugins/installed_plugins.json}
  local cache=${MARVIN_CODEX_CACHE:-$HOME/.claude/plugins/cache/openai-codex/codex}
  local top="" scope pp ip entries user_hit="" d name key best="" bestkey=""
  top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(mc_phys "$top") || top=""
  if [ -f "$pj" ] && [ -r "$pj" ]; then
    entries=$(mc_entries < "$pj" 2>/dev/null)
    while IFS="$MC_US" read -r scope pp ip; do
      [ -n "$ip" ] && [ -f "$ip/$MC_COMPANION" ] || continue
      case "$scope" in
        project) if [ -n "$top" ] && [ -n "$pp" ] && [ "$(mc_phys "$pp")" = "$top" ]; then printf '%s\n' "$ip/$MC_COMPANION"; return 0; fi ;;
        user) [ -n "$user_hit" ] || user_hit="$ip/$MC_COMPANION" ;;
      esac
    done <<EOF
$entries
EOF
    if [ -n "$user_hit" ]; then printf '%s\n' "$user_hit"; return 0; fi
  fi
  for d in "$cache"/*/; do
    d=${d%/}; name=${d##*/}
    [ -f "$d/$MC_COMPANION" ] || continue
    key=$(mc_vkey "$name") || continue
    if [ -z "$bestkey" ] || [[ "$key" > "$bestkey" ]]; then bestkey=$key; best="$d/$MC_COMPANION"; fi
  done
  [ -n "$best" ] || return 1
  printf '%s\n' "$best"
}

mc_usage() { printf 'usage: marvin-codex.sh check [--json]\n' >&2; }

# mc_check [--json]
mc_check() {
  local json=0 a
  for a in "$@"; do
    case "$a" in --json) json=1 ;; *) mc_usage; return 2 ;; esac
  done
  local tmp comp rc first reason status="" out="" have_json=0 v
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/marvin-codex.XXXXXX") || { echo "error cannot create scratch dir"; return 4; }
  if ! command -v node >/dev/null 2>&1; then status=no-node
  elif ! comp=$(mc_locate); then status=not-installed
  else
    node "$comp" setup --json > "$tmp/out" 2> "$tmp/err"; rc=$?
    out=$(cat "$tmp/out")
    if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | mh_json members "" >/dev/null 2>&1; then
      first=$(printf '%s\n' "$out" | sed -n '/[^[:space:]]/{p;q;}')
      [ -n "$first" ] || first=$(sed -n '/[^[:space:]]/{p;q;}' "$tmp/err")
      first=$(printf '%s' "$first" | tr -cd '[:print:]' | sed 's/^ *//')
      if [ "$rc" -ne 0 ]; then reason="companion exit $rc: $first"; else reason="setup output is not JSON: $first"; fi
      status="error $reason"; status=${status:0:80}
    else
      have_json=1
      v=$(printf '%s' "$out" | mh_json get node.available) || v=""
      if [ "$v" = false ]; then status=no-node; else
        v=$(printf '%s' "$out" | mh_json get codex.available) || v=""
        if [ "$v" = false ]; then status=no-codex-cli; else
          v=$(printf '%s' "$out" | mh_json get auth.loggedIn) || v=""
          if [ "$v" = false ]; then status=not-logged-in; else
            v=$(printf '%s' "$out" | mh_json get ready) || v=""
            if [ "$v" = true ]; then status=ready; else status="error setup reports not ready"; fi
          fi
        fi
      fi
    fi
  fi
  if [ "$json" = 1 ]; then
    if [ "$have_json" = 1 ]; then cat "$tmp/out"; else printf '%s\n' "$status" >&2; fi
  else
    printf '%s\n' "$status"
  fi
  rm -rf "$tmp"
  [ "$status" = ready ] && return 0
  return 4
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    check) shift; mc_check "$@"; exit $? ;;
    *) mc_usage; exit 2 ;;
  esac
fi
