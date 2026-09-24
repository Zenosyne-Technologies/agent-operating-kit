#!/usr/bin/env bash
# marvin-session-start.sh — SessionStart hook for the marvin plugin.
#
# Fires on startup/resume/clear/compact (hooks/hooks.json). For a project the kit is installed
# in (<root>/.marvin exists), it (a) compares the plugin's version against this project's
# installed kit_version and flags drift, and (b) always injects the short user-update format
# rules, since those rules must hold even when an output style would otherwise override them.
#
# Contract: never writes a file, never blocks a session, always exits 0 — including when
# .marvin is absent, plugin.json is missing, or PROJECT-INFO.md is unreadable or hostile.
# Only validated version strings (matching ^[0-9]+\.[0-9]+\.[0-9]+$) ever reach the output;
# no other file content is echoed into context.
set -u

is_semver() {
  # Bound the string BEFORE any regex or numeric work: an unbounded component (e.g. 100,000
  # digits) makes version_gt's O(n^2) substring peeling burn CPU for seconds, and a component of
  # 20+ digits overflows the `[ -ne ]` numeric test in version_gt with "integer expression
  # expected" on stderr. A shell length check runs in constant time regardless of content, so it
  # goes first; the regex (each component capped at 4 digits, well under 10^4-1 — plenty for any
  # real semver) only ever runs against an already-short string.
  local v="$1"
  [ "${#v}" -le 20 ] || return 1
  printf '%s' "$v" | grep -Eq '^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$'
}

# version_gt <a> <b> — true (exit 0) iff a > b, both already-validated X.Y.Z semver strings,
# compared numerically component by component (never as plain strings: "0.9.0" > "0.10.0" as
# text, but must read as older).
version_gt() {
  local a="$1" b="$2"
  local a1="${a%%.*}" a_rest="${a#*.}" b1="${b%%.*}" b_rest="${b#*.}"
  local a2="${a_rest%%.*}" a3="${a_rest#*.}" b2="${b_rest%%.*}" b3="${b_rest#*.}"
  if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
  if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
  [ "$a3" -gt "$b3" ]
}

# Extract the "cwd" field from the hook's stdin JSON without a JSON parser (grep/sed only —
# jq may not be present). Good enough for the plain, unescaped paths Claude Code sends.
extract_cwd() {
  printf '%s' "$1" \
    | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 \
    | sed -E 's/^"cwd"[[:space:]]*:[[:space:]]*"//; s/"$//'
}

# ── 1. resolve the project root: CLAUDE_PROJECT_DIR, else stdin's cwd, else $PWD ─────────────
# Stdin is read only when CLAUDE_PROJECT_DIR is unset (nothing to gain from it otherwise) and
# stdin is not a terminal — and even then the read is bounded, so a hook invocation whose stdin
# pipe is left open with no EOF can never stall the session. Chosen approach: prefer timeout(1)
# (GNU coreutils, present on Linux and installable on macOS) when it's on PATH; fall back to
# bash's own `read -t`, which needs no external tool and works on a stock macOS. The hook's stdin
# JSON from Claude Code is always a single line, so one bounded read is enough either way.
stdin_json=""
if [ -z "${CLAUDE_PROJECT_DIR:-}" ] && [ ! -t 0 ]; then
  if command -v timeout >/dev/null 2>&1; then
    stdin_json=$(timeout 2 cat 2>/dev/null || true)
  else
    read -r -t 2 stdin_json || true
  fi
fi

root="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$root" ]; then
  root=$(extract_cwd "$stdin_json")
fi
if [ -z "$root" ]; then
  root="$PWD"
fi

# ── 2. non-Marvin projects get nothing: .marvin must be a real directory, never a symlink ────
marvin_dir="$root/.marvin"
if [ -L "$marvin_dir" ]; then
  exit 0
fi
if [ ! -d "$marvin_dir" ]; then
  exit 0
fi

# ── 3. plugin version, from ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json (grep/sed) ──────
plugin_version=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  plugin_json="$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json"
  if [ -f "$plugin_json" ]; then
    plugin_version=$(grep -m1 '"version"' "$plugin_json" 2>/dev/null \
      | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  fi
fi
is_semver "$plugin_version" || plugin_version=""

# ── 4. this project's kit_version, from .marvin/PROJECT-INFO.md frontmatter ──────────────────
# A symlinked PROJECT-INFO.md is refused (treated as unknown) before it is ever read.
kit_version=""
project_info="$marvin_dir/PROJECT-INFO.md"
# [ -f ] alone accepts only a regular file (never a FIFO, device, or directory); combined with the
# ! -L check above it also rejects a symlink, so only a genuine on-disk regular file is read.
if [ ! -L "$project_info" ] && [ -f "$project_info" ]; then
  # Only the YAML frontmatter — between the first two literal "---" lines — is trusted; a
  # "kit_version:" string appearing later in the document body must never be read as the value.
  # The read is bounded two ways: at most the first 40 lines (a hostile file with a huge body and
  # no closing "---" must not stream unbounded content into a shell variable), and time-bounded
  # against TOCTOU — the -f check above and the open below are two different moments, and a FIFO
  # swapped in between them must not block the hook. Same choice as the stdin read above: prefer
  # timeout(1) when present. Fallback (macOS bash 3.2, no timeout(1) on PATH, exercised here):
  # re-check the path is a regular file immediately before a READ-ONLY open (never `<>`, which can
  # create a file), then bound every line read with `read -t`, the same builtin the stdin fallback
  # uses.
  frontmatter=""
  if command -v timeout >/dev/null 2>&1; then
    frontmatter=$(timeout 2 head -n 40 -- "$project_info" 2>/dev/null \
      | awk '{ sub(/\r$/, "") } NR==1 && $0=="---" { f=1; next } f && $0=="---" { exit } f')
  elif [ -f "$project_info" ] && { exec 3<"$project_info"; } 2>/dev/null; then
    # Read-only open only, never `<>`: a read-write open can create a file (O_CREAT) if a symlink
    # is swapped in, which would break the hook's never-writes contract. The regular-file re-check
    # sits immediately before the open; the residual FIFO-swap race between them needs a live local
    # process and is bounded by the host's hook timeout (sev4, accepted).
    # `-n 200` caps a single read at 200 bytes even short of a newline: bash's `read -t` reads a
    # byte at a time (to support the timeout/select), so one real line of ~1,000,000 bytes with no
    # newline costs ~1,000,000 syscalls (seconds) even though the line count is bounded to 40. A
    # line this long is never a real "kit_version:" value, so truncating it is safe — worst case
    # it is later rejected by is_semver, same as today.
    line_no=0
    in_fm=0
    while [ "$line_no" -lt 40 ] && IFS= read -r -t 2 -u 3 -n 200 line; do
      line_no=$((line_no + 1))
      line="${line%$'\r'}"
      if [ "$line_no" -eq 1 ]; then
        [ "$line" = "---" ] || break
        in_fm=1
        continue
      fi
      if [ "$in_fm" -eq 1 ]; then
        [ "$line" = "---" ] && break
        frontmatter="$frontmatter$line
"
      fi
    done
    exec 3<&-
  fi
  raw=$(printf '%s\n' "$frontmatter" | grep -m1 '^kit_version:' | sed -E 's/^kit_version:[[:space:]]*//')
  kit_version=$(printf '%s' "$raw" | sed -E 's/^[[:space:]"'"'"']+//; s/[[:space:]"'"'"']+$//')
fi
is_semver "$kit_version" || kit_version=""

# ── 5. one status line, at most ──────────────────────────────────────────────────────────────
status=""
if [ -z "$kit_version" ]; then
  status="Marvin: couldn't read this project's kit_version — run /marvin:upgrade-agent-os to check the install."
elif [ -n "$plugin_version" ] && [ "$kit_version" != "$plugin_version" ]; then
  if version_gt "$kit_version" "$plugin_version"; then
    status="Marvin: this project's install is v${kit_version}, newer than the plugin (v${plugin_version}) — update the plugin (claude plugin update marvin), don't run the upgrade skill."
  else
    status="Marvin: this project's install is v${kit_version} but the plugin is v${plugin_version} — run /marvin:upgrade-agent-os before other work."
  fi
fi
if [ -n "$status" ]; then
  printf '%s\n\n' "$status"
fi

# ── 6. the always-on user-update rules block (constant; nothing from the project flows in) ───
cat <<'RULES'
Marvin user-update rules (full formats: .marvin/agents/user-updates.md; these take precedence over any output style):
- Say only what changed, once, in plain words.
- One event gets one plain line; use a table for two or more items.
- Shipped/done items: a table (item | result | where) with the emoji legend (✅ ❌ ⚠️ ⏳ ⏭️).
- Any issue/blocker: a callout — What / Impact / Cause / Fix / Needs you? — in that order.
- Link to agent reports and tickets; never paste their content into chat.
- End every message with Next / Open questions; drop an empty heading.
RULES

exit 0
