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
  printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
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
stdin_json=""
if [ ! -t 0 ]; then
  stdin_json=$(cat 2>/dev/null || true)
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
if [ ! -L "$project_info" ] && [ -f "$project_info" ]; then
  raw=$(grep -m1 '^kit_version:' "$project_info" 2>/dev/null | sed -E 's/^kit_version:[[:space:]]*//')
  kit_version=$(printf '%s' "$raw" | sed -E 's/^[[:space:]"'"'"']+//; s/[[:space:]"'"'"']+$//')
fi
is_semver "$kit_version" || kit_version=""

# ── 5. one status line, at most ──────────────────────────────────────────────────────────────
status=""
if [ -z "$kit_version" ]; then
  status="Marvin: couldn't read this project's kit_version — run /marvin:upgrade-agent-os to check the install."
elif [ -n "$plugin_version" ] && [ "$kit_version" != "$plugin_version" ]; then
  status="Marvin: this project's install is v${kit_version} but the plugin is v${plugin_version} — run /marvin:upgrade-agent-os before other work."
fi
if [ -n "$status" ]; then
  printf '%s\n\n' "$status"
fi

# ── 6. the always-on user-update rules block (constant; nothing from the project flows in) ───
cat <<'RULES'
Marvin user-update rules (full formats: .marvin/agents/user-updates.md; these take precedence over any output style):
- Say only what changed, once, in plain words.
- Shipped/done items: one table (item | result | where) with the emoji legend (✅ ❌ ⚠️ ⏳ ⏭️).
- Any issue/blocker: a callout — What / Impact / Cause / Fix / Needs you? — in that order.
- Link to agent reports and tickets; never paste their content into chat.
- End every message with Next / Open questions; drop an empty heading.
RULES

exit 0
