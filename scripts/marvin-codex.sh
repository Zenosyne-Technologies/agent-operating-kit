#!/usr/bin/env bash
# marvin-codex.sh — the ONLY place in Marvin that touches OpenAI's Codex companion (codex-companion.mjs, shipped
# by the `codex@openai-codex` Claude Code plugin). Everything Marvin knows about the companion's argv, JSON
# shapes and quirks lives here; the codex handover guides call this script and never the companion.
#
#   marvin-codex.sh check [--json]
#     Is Codex usable from here? Stdout is exactly ONE line:
#       ready · not-installed · no-node · no-codex-cli · not-logged-in · error <reason, <= 80 chars in all>
#     Exit 0 for ready, 4 for anything else, 2 for a usage error. With --json the companion's `setup --json`
#     output passes through byte-for-byte on stdout and the exit code is the same; when there is no such output
#     (no node, not installed, companion failed) stdout stays empty and the status line goes to stderr.
#     Order: node not on PATH -> no-node (the companion is not called) · companion not found -> not-installed ·
#     companion timed out -> `error companion timed out` · rc != 0 or stdout not a JSON object -> error ·
#     node.available false -> no-node · codex.available false -> no-codex-cli · auth.loggedIn false ->
#     not-logged-in · ready true -> ready · else error. Fields are read BY JSON PATH (`available` appears under
#     node, npm, codex, auth, sessionRuntime).
#
#   marvin-codex.sh run <lane> --prompt-file <file> [--model M] [--effort E] [--astra] [--architect]
#                       [--write-evidence] [--wait-max <seconds, default 540>]
#     <lane>: plan|review|security|design|diagnose|build|build-micro, or `astra` (an alias lane, refused
#     without --astra). Model and effort default to the lane's row of the `## Codex profile` table in
#     <toplevel>/.marvin/agents/model-profile.md, else (per lookup) in this kit's templates/ copy; --astra
#     selects the astra row's model and, unless --effort is given, its effort. Guards, in order, each refusing
#     with exit 3 and one stdout line:
#       1. codex_handover (PROJECT-INFO.md frontmatter, lower-cased, `# comment` stripped; missing key/file or
#          any value but ask|auto counts as off) is off and --architect is absent -> refused: codex_handover is off
#       2. the lane is astra, or the resolved model names astra (any case, any dated alias) or equals the astra
#          row of the project copy OR the template, and --astra is absent -> refused: astra needs --astra
#       3. effort max|ultra -> refused: effort above xhigh · not none|minimal|low|medium|high|xhigh ->
#          refused: unknown effort
#       4. --prompt-file not given, missing, empty or unreadable -> exit 2
#       5. `check` is not ready -> exit 4, unavailable: <check status>
#     Then: node <companion> task --background --json --cwd <toplevel> --prompt-file <absolute file>
#     --model <M> --effort <E> [--write]. --model is ALWAYS passed (the user's Codex default may be the costly
#     frontier model); the prompt text never enters argv; --write only for build|build-micro or with
#     --write-evidence. The job id (`jobId`) is polled with `status <id> --json --cwd <toplevel>` every
#     MARVIN_CODEX_POLL seconds until it ends or the budget is spent, then `result <id> --json --cwd <toplevel>`.
#     As soon as the id is known, `submitted <id>` goes to STDERR. A submission that times out prints
#     `unavailable: timeout (job may be queued; check status)`: the job may exist, its id is unknowable.
#
#   marvin-codex.sh result <job-id> [--wait-max S]
#     Resume waiting on a job `run` left pending; run it from the same project (jobs are stored per --cwd).
#
#   run / result stdout and exit: 0 the job completed with a non-empty storedJob.result.rawOutput — stdout is
#     the companion's `result --json` payload, unchanged · 4 one line `unavailable: <status|timeout|empty|
#     error <reason>>` (job failed or cancelled, garbage or non-JSON output, unknown job) · 5 one line
#     `pending <job-id>` (the budget ran out with the job unfinished or its result unfetched; resume with
#     `result`) · 3 refused · 2 usage.
#     --wait-max (whole seconds, 1..999999, default 540) is the TOTAL wall-clock budget, measured from script
#     start: every companion call (setup, task, status, result) is capped at the seconds left, no call starts
#     with under 1 s left, and no poll sleeps into the last second, so a call returns within about --wait-max
#     + 3 s (TERM grace) — the default keeps it under a 10-minute tool limit.
#
# Every companion call runs under a watchdog (MARVIN_CODEX_CALL_TIMEOUT seconds, default 60): a call past it
# is killed (TERM, then KILL 2 s later) and counts as a timeout; no watchdog or sleeper outlives the call. Under
# run/result the limit is also capped by the --wait-max budget (above); a status or result call it cut short
# means pending.
#
# Locating the companion (mc_locate prints its absolute path or returns 1), first hit wins:
#   1. a `scope: project` entry of any `codex@*` key in the plugins file whose projectPath is the git toplevel
#      of the cwd (physical paths compared, so symlinked checkouts match) and whose companion file exists;
#      in a linked git worktree, then an entry whose projectPath is the MAIN checkout's toplevel;
#   2. a `scope: user` entry of a `codex@*` key whose companion file exists;
#   3. the newest existing <cache>/<semver>/scripts/codex-companion.mjs (numeric compare: 1.0.10 > 1.0.9).
# A stale installPath therefore falls through instead of failing. Entries of other plugins are never read.
#
# Env seams (tests): MARVIN_CODEX_PLUGINS_JSON (default $HOME/.claude/plugins/installed_plugins.json),
#   MARVIN_CODEX_CACHE (default $HOME/.claude/plugins/cache/openai-codex/codex), MARVIN_CODEX_POLL (status
#   poll interval in seconds, default 5), MARVIN_CODEX_CALL_TIMEOUT (per-call watchdog, default 60). `node`
#   comes from PATH.
# Contract: never writes outside a mktemp scratch it removes; never runs `codex login`; never touches
# ~/.codex; bash 3.2 + POSIX awk (macOS awk and mawk), no python/jq.
# Exit: 0 ready / finished · 2 usage · 3 refused · 4 not ready / unavailable · 5 pending.
set -u
export LC_ALL=C
MC_HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/marvin-hook-lib.sh
. "$MC_HERE/lib/marvin-hook-lib.sh" 2>/dev/null || { echo "error hook library missing" >&2; exit 4; }

MC_US=$(printf '\037')
MC_COMPANION=scripts/codex-companion.mjs
MC_JOB_RE='^task-[a-z0-9]+-[a-z0-9]+$'
MC_MODEL_RE='^[A-Za-z0-9][A-Za-z0-9._:-]*$'
MC_TMP=""; MC_COMP=""; MC_STATUS=""; MC_HAVE_JSON=0; MC_CAPPED=0
MC_T0=$SECONDS; MC_DEADLINE=""   # run/result: the wall-clock budget, measured from script start

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

# mc_main_top — in a linked worktree, the MAIN checkout's physical toplevel (the parent of the common .git
# directory); nothing in the main checkout itself, a bare repo or outside git
mc_main_top() {
  local cd_ top
  cd_=$(git rev-parse --git-common-dir 2>/dev/null) || return 0
  cd_=$(mc_phys "$cd_"); [ -n "$cd_" ] && [ "${cd_##*/}" = .git ] || return 0
  top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(mc_phys "$top") || top=""
  [ "${cd_%/*}" != "$top" ] && printf '%s\n' "${cd_%/*}"
  return 0
}

mc_locate() {
  local pj=${MARVIN_CODEX_PLUGINS_JSON:-$HOME/.claude/plugins/installed_plugins.json}
  local cache=${MARVIN_CODEX_CACHE:-$HOME/.claude/plugins/cache/openai-codex/codex}
  local top="" main="" scope pp ip php entries user_hit="" main_hit="" d name key best="" bestkey=""
  top=$(git rev-parse --show-toplevel 2>/dev/null) && top=$(mc_phys "$top") || top=""
  [ -n "$top" ] && main=$(mc_main_top)
  if [ -f "$pj" ] && [ -r "$pj" ]; then
    entries=$(mc_entries < "$pj" 2>/dev/null)
    while IFS="$MC_US" read -r scope pp ip; do
      [ -n "$ip" ] && [ -f "$ip/$MC_COMPANION" ] || continue
      case "$scope" in
        project)
          [ -n "$top" ] && [ -n "$pp" ] || continue
          php=$(mc_phys "$pp")
          if [ "$php" = "$top" ]; then printf '%s\n' "$ip/$MC_COMPANION"; return 0; fi
          if [ -n "$main" ] && [ "$php" = "$main" ] && [ -z "$main_hit" ]; then main_hit="$ip/$MC_COMPANION"; fi ;;
        user) [ -n "$user_hit" ] || user_hit="$ip/$MC_COMPANION" ;;
      esac
    done <<EOF
$entries
EOF
    if [ -n "$main_hit" ]; then printf '%s\n' "$main_hit"; return 0; fi
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

mc_usage() {
  cat >&2 <<'EOF'
usage: marvin-codex.sh check [--json]
       marvin-codex.sh run <lane> --prompt-file <file> [--model M] [--effort E] [--astra] [--architect]
                           [--write-evidence] [--wait-max S]
       marvin-codex.sh result <job-id> [--wait-max S]
EOF
}
mc_err() { printf 'marvin-codex.sh: %s\n' "$1" >&2; }
mc_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# mc_scratch — one mktemp scratch per process, removed on exit
mc_scratch() {
  [ -n "$MC_TMP" ] && [ -d "$MC_TMP" ] && return 0
  MC_TMP=$(mktemp -d "${TMPDIR:-/tmp}/marvin-codex.XXXXXX") || { MC_TMP=""; return 1; }
  trap 'rm -rf "$MC_TMP"' EXIT
}

# mc_call <tag> <companion args...> — `node $MC_COMP <args>` with stdout in $MC_TMP/<tag>.out and stderr in
# <tag>.err, under a watchdog of MARVIN_CODEX_CALL_TIMEOUT seconds. Returns the companion's rc, or 124 when the
# watchdog fired. The watchdog's own sleeper is killed by its TERM trap; the trap is armed (stop flag first)
# before the sleeper exists, so a TERM at any point leaves no sleeper behind.
#   Under a wall-clock budget (MC_DEADLINE, a $SECONDS value; run/result set it to script start + --wait-max)
# the limit is min(per-call timeout, seconds left), and MC_CAPPED=1 says the budget, not the per-call timeout,
# set it; with under 1 s left the call is not started at all (rc 124, MC_CAPPED=1).
mc_call() {
  local tag=$1 lim=${MARVIN_CODEX_CALL_TIMEOUT:-60} pid wd rc left; shift
  case "$lim" in ''|*[!0-9]*) lim=60 ;; esac
  [ "$lim" -gt 0 ] || lim=60
  MC_CAPPED=0
  if [ -n "$MC_DEADLINE" ]; then
    left=$((MC_DEADLINE - SECONDS))
    if [ "$left" -lt 1 ]; then MC_CAPPED=1; return 124; fi
    if [ "$left" -lt "$lim" ]; then lim=$left; MC_CAPPED=1; fi
  fi
  rm -f "$MC_TMP/$tag.to"
  node "$MC_COMP" "$@" > "$MC_TMP/$tag.out" 2> "$MC_TMP/$tag.err" < /dev/null &
  pid=$!
  (
    stop=""; trap 'stop=1' TERM
    sleep "$lim" & sp=$!
    trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    [ -z "$stop" ] || { kill "$sp" 2>/dev/null; exit 0; }
    wait "$sp"
    : > "$MC_TMP/$tag.to"
    kill -TERM "$pid" 2>/dev/null
    sleep 2 & sp=$!
    wait "$sp"
    kill -KILL "$pid" 2>/dev/null
    exit 0
  ) > /dev/null 2>&1 &
  wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill -TERM "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  [ -f "$MC_TMP/$tag.to" ] && return 124
  return "$rc"
}

# mc_reason <tag> <rc> — why a call's output is unusable: "companion exit N: <first line>" or
# "<tag> output is not JSON: <first line>", with "(no output)" / "(empty output)" when there is nothing to show.
# The first non-blank stdout line, else stderr's; printable bytes only.
mc_reason() {
  local first
  first=$(sed -n '/[^[:space:]]/{p;q;}' "$MC_TMP/$1.out" 2>/dev/null)
  [ -n "$first" ] || first=$(sed -n '/[^[:space:]]/{p;q;}' "$MC_TMP/$1.err" 2>/dev/null)
  first=$(printf '%s' "$first" | tr -cd '[:print:]' | sed 's/^ *//')
  if [ "$2" -ne 0 ]; then
    if [ -n "$first" ]; then printf 'companion exit %s: %s' "$2" "$first"; else printf 'companion exit %s (no output)' "$2"; fi
  else
    if [ -n "$first" ]; then printf '%s output is not JSON: %s' "$1" "$first"; else printf '%s output is not JSON (empty output)' "$1"; fi
  fi
}
mc_is_json() { mh_json members "" < "$MC_TMP/$1.out" > /dev/null 2>&1; }   # stdout of <tag> is a JSON object

# mc_status — the `check` verdict: sets MC_STATUS (one status line), MC_COMP (companion path, when found)
# and MC_HAVE_JSON (1 when $MC_TMP/setup.out holds parseable setup JSON). Needs mc_scratch first.
mc_status() {
  local rc v
  MC_STATUS=""; MC_COMP=""; MC_HAVE_JSON=0
  if ! command -v node > /dev/null 2>&1; then MC_STATUS=no-node; return 0; fi
  if ! MC_COMP=$(mc_locate); then MC_COMP=""; MC_STATUS=not-installed; return 0; fi
  mc_call setup setup --json; rc=$?
  if [ "$rc" -eq 124 ]; then MC_STATUS="error companion timed out"; return 0; fi
  if [ "$rc" -ne 0 ] || ! mc_is_json setup; then
    MC_STATUS="error $(mc_reason setup "$rc")"; MC_STATUS=${MC_STATUS:0:80}; return 0
  fi
  MC_HAVE_JSON=1
  v=$(mh_json get node.available < "$MC_TMP/setup.out") || v=""
  if [ "$v" = false ]; then MC_STATUS=no-node; return 0; fi
  v=$(mh_json get codex.available < "$MC_TMP/setup.out") || v=""
  if [ "$v" = false ]; then MC_STATUS=no-codex-cli; return 0; fi
  v=$(mh_json get auth.loggedIn < "$MC_TMP/setup.out") || v=""
  if [ "$v" = false ]; then MC_STATUS=not-logged-in; return 0; fi
  v=$(mh_json get ready < "$MC_TMP/setup.out") || v=""
  if [ "$v" = true ]; then MC_STATUS=ready; else MC_STATUS="error setup reports not ready"; fi
}

# mc_check [--json]
mc_check() {
  local json=0 a
  for a in "$@"; do
    case "$a" in --json) json=1 ;; *) mc_usage; return 2 ;; esac
  done
  mc_scratch || { echo "error cannot create scratch dir"; return 4; }
  mc_status
  if [ "$json" = 1 ]; then
    if [ "$MC_HAVE_JSON" = 1 ]; then cat "$MC_TMP/setup.out"; else printf '%s\n' "$MC_STATUS" >&2; fi
  else
    printf '%s\n' "$MC_STATUS"
  fi
  [ "$MC_STATUS" = ready ] && return 0
  return 4
}

# mc_top — the physical git toplevel of the cwd, else the physical cwd
mc_top() {
  local t
  t=$(git rev-parse --show-toplevel 2>/dev/null) && t=$(mc_phys "$t")
  [ -n "${t:-}" ] || t=$(pwd -P)
  printf '%s\n' "$t"
}

# mc_handover <top> — off|ask|auto from <top>/.marvin/PROJECT-INFO.md frontmatter; anything else is off
mc_handover() {
  local fm v
  fm=$(mh_frontmatter "$1") || fm=""
  v=$(mh_fm_value "$fm" codex_handover)
  v=$(mc_lc "$v")
  case "$v" in ask|auto) printf '%s\n' "$v" ;; *) printf 'off\n' ;; esac
}

# mc_profile <lane> model|effort [top] — the lane's cell from the `## Codex profile` table: the project copy
# (<top>/.marvin/agents/model-profile.md) first, then this kit's template. Only that section is read (up to
# the next `## ` heading); column 1 is matched trimmed of spaces and backticks; the cell comes back trimmed.
# rc 1 when no non-empty cell is found, 2 for a bad field name.
mc_profile() {
  local lane=$1 col f top
  case "${2:-}" in model) col=4 ;; effort) col=5 ;; *) mc_err "mc_profile: field is model or effort"; return 2 ;; esac
  top=${3:-$(mc_top)}
  for f in "$top/.marvin/agents/model-profile.md" "$MC_HERE/../templates/marvin/agents/model-profile.md"; do
    mc_profile_in "$f" "$lane" "$col" && return 0
  done
  return 1
}
# mc_profile_in <file> <lane> <column> — one profile file's cell (see mc_profile); rc 1 when absent
mc_profile_in() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  awk -F'|' -v lane="$2" -v col="$3" '
    function trim(s) { gsub(/^[ \t`]+/, "", s); gsub(/[ \t`]+$/, "", s); return s }
    { sub(/\r$/, "") }
    /^## / { insec = ($0 ~ /^## Codex profile[ \t]*$/); next }
    insec && /^[ \t]*\|/ && trim($2) == lane { v = trim($col); if (v != "") { print v; found = 1; exit } }
    END { exit !found }' "$1"
}

# mc_is_astra <model> <top> — the model is the frontier model: it names astra (any case, any dated alias), or
# equals the astra row of the project copy OR of the kit template (a project edit cannot launder it)
mc_is_astra() {
  local m f a
  m=$(mc_lc "$1")
  case "$m" in *astra*) return 0 ;; esac
  for f in "$2/.marvin/agents/model-profile.md" "$MC_HERE/../templates/marvin/agents/model-profile.md"; do
    a=$(mc_profile_in "$f" astra 4) || continue
    [ "$m" = "$(mc_lc "$a")" ] && return 0
  done
  return 1
}

mc_unavail() { local s="$1"; printf 'unavailable: %s\n' "${s:0:80}"; }

# mc_job_why — ": <reason>" for a failed/cancelled job from status.out's job.summary (its "message" when the
# summary is an escaped JSON error), or nothing
mc_job_why() {
  local s m
  s=$(mh_json get job.summary < "$MC_TMP/status.out" 2>/dev/null) || return 0
  m=$(printf '%s\n' "$s" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p' | head -n 1)
  [ -n "$m" ] || m=$(printf '%s\n' "$s" | head -n 1)
  m=$(printf '%s' "$m" | tr -cd '[:print:]')
  [ -z "$m" ] || printf ': %s' "$m"
}

# mc_wait <job> <top> — poll until the job ends or the budget (MC_DEADLINE) is spent; print per the run/result
# contract. Every call is capped by the budget; a call the budget cut short, or a poll whose sleep would leave
# under 1 s for the next status call, ends in `pending <job>`.
mc_wait() {
  local job=$1 top=$2 poll=${MARVIN_CODEX_POLL:-5} pint rc st sst raw
  [[ $poll =~ ^[0-9]+(\.[0-9]+)?$ ]] || poll=5
  pint=${poll%%.*}; [ "$pint" = "$poll" ] || pint=$((pint + 1))   # the poll interval rounded up
  while :; do
    mc_call status status "$job" --json --cwd "$top"; rc=$?
    if [ "$rc" -eq 124 ]; then
      if [ "$MC_CAPPED" = 1 ]; then printf 'pending %s\n' "$job"; return 5; fi
      mc_unavail timeout; return 4
    fi
    if [ "$rc" -ne 0 ] || ! mc_is_json status; then mc_unavail "error $(mc_reason status "$rc")"; return 4; fi
    st=$(mh_json get job.status < "$MC_TMP/status.out") || st=""
    case "$st" in
      completed) break ;;
      queued|running) ;;
      failed|cancelled) mc_unavail "error job $st$(mc_job_why)"; return 4 ;;
      *) mc_unavail "error unknown job status${st:+ $st}"; return 4 ;;
    esac
    if [ $((MC_DEADLINE - SECONDS - pint)) -lt 1 ]; then printf 'pending %s\n' "$job"; return 5; fi
    sleep "$poll"
  done
  mc_call result result "$job" --json --cwd "$top"; rc=$?
  if [ "$rc" -eq 124 ]; then
    if [ "$MC_CAPPED" = 1 ]; then printf 'pending %s\n' "$job"; return 5; fi
    mc_unavail timeout; return 4
  fi
  if [ "$rc" -ne 0 ] || ! mc_is_json result; then mc_unavail "error $(mc_reason result "$rc")"; return 4; fi
  st=$(mh_json get job.status < "$MC_TMP/result.out") || st=""
  sst=$(mh_json get storedJob.status < "$MC_TMP/result.out") || sst=""
  if [ "$st" != completed ] || { [ -n "$sst" ] && [ "$sst" != completed ]; }; then
    mc_unavail "error result says job ${sst:-${st:-unknown}}"; return 4
  fi
  raw=$(mh_json get storedJob.result.rawOutput < "$MC_TMP/result.out" | tr -d '[:space:]' | head -c 1)
  if [ -z "$raw" ]; then mc_unavail empty; return 4; fi
  cat "$MC_TMP/result.out"
  return 0
}

mc_waitmax_ok() { [[ $1 =~ ^[0-9]{1,6}$ ]] && [ "$((10#$1))" -ge 1 ]; }

# mc_run <lane> [options] — see the header
mc_run() {
  local lane="" pf="" have_pf=0 model="" effort="" astra=0 architect=0 wev=0 wmax=540
  local top amodel rmodel reffort write=0 rc job
  [ $# -ge 1 ] || { mc_usage; return 2; }
  lane=$1; shift
  case "$lane" in plan|review|security|design|diagnose|build|build-micro|astra) ;; *) mc_err "unknown lane: $lane"; mc_usage; return 2 ;; esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt-file|--model|--effort|--wait-max)
        [ $# -ge 2 ] || { mc_err "$1 needs a value"; mc_usage; return 2; }
        case "$1" in
          --prompt-file) pf=$2; have_pf=1 ;;
          --model) model=$2 ;;
          --effort) effort=$2 ;;
          --wait-max) wmax=$2 ;;
        esac
        shift 2 ;;
      --astra) astra=1; shift ;;
      --architect) architect=1; shift ;;
      --write-evidence) wev=1; shift ;;
      *) mc_err "unknown option: $1"; mc_usage; return 2 ;;
    esac
  done
  mc_waitmax_ok "$wmax" || { mc_err "--wait-max takes whole seconds, at least 1"; return 2; }
  MC_DEADLINE=$((MC_T0 + 10#$wmax))
  if [ -n "$model" ] && ! [[ $model =~ $MC_MODEL_RE ]]; then mc_err "not a model name: $model"; return 2; fi
  top=$(mc_top)

  # guard 1 — the project opted in (or the architect asked explicitly)
  if [ "$(mc_handover "$top")" = off ] && [ "$architect" = 0 ]; then echo "refused: codex_handover is off"; return 3; fi

  # resolve model and effort from the profile; never call Codex with an empty or unchecked model
  amodel=$(mc_profile astra model "$top") || { mc_err "no astra row in the Codex profile"; return 2; }
  if [ "$astra" = 1 ]; then
    if [ -n "$model" ] && [ "$(mc_lc "$model")" != "$(mc_lc "$amodel")" ]; then mc_err "--model conflicts with --astra"; return 2; fi
    rmodel=$amodel
    [ -n "$effort" ] || effort=$(mc_profile astra effort "$top") || { mc_err "no astra effort in the Codex profile"; return 2; }
  else
    if [ -n "$model" ]; then rmodel=$model; else rmodel=$(mc_profile "$lane" model "$top") || { mc_err "no $lane row in the Codex profile"; return 2; }; fi
    [ -n "$effort" ] || effort=$(mc_profile "$lane" effort "$top") || { mc_err "no $lane effort in the Codex profile"; return 2; }
  fi
  [[ $rmodel =~ $MC_MODEL_RE ]] || { mc_err "the Codex profile's model is not a model name: $rmodel"; return 2; }

  # guard 2 — the frontier model only on the architect's explicit --astra
  if [ "$astra" = 0 ] && { [ "$lane" = astra ] || mc_is_astra "$rmodel" "$top"; }; then
    echo "refused: astra needs --astra"; return 3
  fi

  # guard 3 — the companion's effort ceiling
  reffort=$(mc_lc "$effort")
  case "$reffort" in
    none|minimal|low|medium|high|xhigh) ;;
    max|ultra) echo "refused: effort above xhigh"; return 3 ;;
    *) echo "refused: unknown effort"; return 3 ;;
  esac

  # guard 4 — a readable prompt file, passed by absolute path (the companion resolves it against --cwd)
  [ "$have_pf" = 1 ] && [ -n "$pf" ] || { mc_err "--prompt-file is required"; mc_usage; return 2; }
  case "$pf" in /*) ;; *) pf="$PWD/$pf" ;; esac
  [ -f "$pf" ] && [ -r "$pf" ] && [ -s "$pf" ] || { mc_err "prompt file missing, empty or unreadable: $pf"; return 2; }

  # guard 5 — Codex is usable from here
  mc_scratch || { mc_unavail "error cannot create scratch dir"; return 4; }
  mc_status
  [ "$MC_STATUS" = ready ] || { mc_unavail "$MC_STATUS"; return 4; }

  case "$lane" in build|build-micro) write=1 ;; esac
  [ "$wev" = 1 ] && write=1
  if [ "$write" = 1 ]; then
    mc_call task task --background --json --cwd "$top" --prompt-file "$pf" --model "$rmodel" --effort "$reffort" --write; rc=$?
  else
    mc_call task task --background --json --cwd "$top" --prompt-file "$pf" --model "$rmodel" --effort "$reffort"; rc=$?
  fi
  # A submission that timed out may still have queued the job; the id is unknowable here, so say so. A job id
  # in parseable output is trusted even when rc != 0 (the job exists; status decides), and is announced on
  # stderr at once so a caller can resume with `result <id>` whatever happens next.
  if [ "$rc" -eq 124 ]; then mc_unavail "timeout (job may be queued; check status)"; return 4; fi
  job=""
  if mc_is_json task; then job=$(mh_json get jobId < "$MC_TMP/task.out") || job=""; fi
  if ! [[ $job =~ $MC_JOB_RE ]]; then
    if [ "$rc" -ne 0 ] || ! mc_is_json task; then mc_unavail "error $(mc_reason task "$rc")"; else mc_unavail "error task output has no job id"; fi
    return 4
  fi
  printf 'submitted %s\n' "$job" >&2
  mc_wait "$job" "$top"
}

# mc_result <job-id> [--wait-max S]
mc_result() {
  local job wmax=540
  [ $# -ge 1 ] || { mc_usage; return 2; }
  job=$1; shift
  [[ $job =~ $MC_JOB_RE ]] || { mc_err "not a job id: $job"; return 2; }
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait-max) [ $# -ge 2 ] || { mc_err "--wait-max needs a value"; return 2; }; wmax=$2; shift 2 ;;
      *) mc_err "unknown option: $1"; mc_usage; return 2 ;;
    esac
  done
  mc_waitmax_ok "$wmax" || { mc_err "--wait-max takes whole seconds, at least 1"; return 2; }
  MC_DEADLINE=$((MC_T0 + 10#$wmax))
  mc_scratch || { mc_unavail "error cannot create scratch dir"; return 4; }
  if ! command -v node > /dev/null 2>&1; then mc_unavail no-node; return 4; fi
  MC_COMP=$(mc_locate) || { mc_unavail not-installed; return 4; }
  mc_wait "$job" "$(mc_top)"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    check) shift; mc_check "$@"; exit $? ;;
    run) shift; mc_run "$@"; exit $? ;;
    result) shift; mc_result "$@"; exit $? ;;
    *) mc_usage; exit 2 ;;
  esac
fi
