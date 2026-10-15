#!/usr/bin/env bash
# marvin-update-gate.sh — UserPromptSubmit + Stop hook for the marvin plugin (v0.38.0).
# Checks the orchestrator's messages to the user against .marvin/agents/user-updates.md:
#   U1 a <details> fold · U2 a pictographic emoji outside the legend (✅ ❌ ⚠️ ⏳ ⏭️) · U3 a ⚠️/❌ issue
#   callout without What / Impact / Cause / Fix / Needs you? in that order · U4 a status update (a table
#   row carrying a legend emoji, or a callout) with no Next / Open questions heading after it.
# Fenced and inline code is ignored. Mode = update_gate in .marvin/PROJECT-INFO.md frontmatter:
#   advise (default) — on UserPromptSubmit, check the PREVIOUS assistant text in the transcript and
#                      inject one note with the prompt: passive, no extra turn. Stop stays silent.
#   block            — on Stop, send a message failing U1–U3 back once (never when stop_hook_active,
#                      never while a background task runs). U4 only ever advises: an empty tail is legal.
#   off              — nothing.
# Advice is never given at Stop: Stop additionalContext forces an immediate continuation and loops (spec H11).
# Contract: Marvin projects only; sub-agent invocations skipped; never writes; always exits 0; the output
# is constant text — nothing from the message is echoed back.
set -u
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0
mh_read_stdin || exit 0
mh_is_subagent_call && exit 0
event=$(printf '%s' "$MH_IN" | mh_get hook_event_name) || exit 0
case "$event" in UserPromptSubmit|Stop) ;; *) exit 0 ;; esac
root=$(mh_root); mh_is_marvin "$root" || exit 0
fm=$(mh_frontmatter "$root") || fm=""
mode=$(mh_fm_value "$fm" update_gate)
case "$mode" in block|off) ;; *) mode=advise ;; esac
[ "$mode" = off ] && exit 0

# Byte-level (LC_ALL=C): ✅ \342\234\205 · ❌ \342\235\214 · ⚠ \342\232\240 · ⏳ \342\217\263 · ⏭ \342\217\255.
# "Pictographic" = U+1F000–1FAFF (\360\237[\200-\253]) or U+2600–27BF, U+2B00–2BFF (\342[\230-\236\254-\257]).
IFS= read -r -d '' UG_AWK <<'AWK' || true
function inorder(c,   k, p, q, r) {
  split("**What**|**Impact**|**Cause**|**Fix**|**Needs you?**", k, "|"); p = 0
  for (q = 1; q <= 5; q++) { r = index(substr(c, p + 1), k[q]); if (!r) return 0; p += r }
  return 1 }
{ l = $0; sub(/\r$/, "", l)
  if (l ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
  if (fence) next
  gsub(/`[^`]*`/, "", l)
  L[++n] = l }
END {
  ck = "\342\234\205"; cx = "\342\235\214"; wn = "\342\232\240"; hg = "\342\217\263"; sk = "\342\217\255"
  for (i = 1; i <= n; i++) { l = L[i]
    if (tolower(l) ~ /<details/) u1 = 1
    t = l; gsub(ck, "", t); gsub(cx, "", t); gsub(wn, "", t)
    if (t ~ /\360\237[\200-\253]/ || t ~ /\342[\230-\236\254-\257]/) u2 = 1
    if (l ~ /^[ \t]*>[ \t]*\*\*[ \t]*(\342\232\240|\342\235\214)/) {
      c = ""; for (j = i + 1; j <= n && L[j] ~ /^[ \t]*>/; j++) c = c "\n" L[j]
      if (!inorder(c)) u3 = 1
      st = i }
    if (l ~ /^[ \t]*\|/ && (index(l, ck) || index(l, cx) || index(l, wn) || index(l, hg) || index(l, sk))) st = i
    if (l ~ /^[ \t]*(\*\*(Next|Open questions)\*\*|#+[ \t]+(Next|Open questions))[ \t:]*$/) tl = i }
  if (u1) print "U1"
  if (u2) print "U2"
  if (u3) print "U3"
  if (st && tl <= st) print "U4" }
AWK

note() {  # note <ids> — the constant advice for the failed checks
  local s="" id
  for id in $1; do
    case "$id" in
      U1) s="$s; U1 a <details> fold — never fold, link the report or ticket instead" ;;
      U2) s="$s; U2 a status emoji outside the legend — use only ✅ ❌ ⚠️ ⏳ ⏭️" ;;
      U3) s="$s; U3 an issue callout without What / Impact / Cause / Fix / Needs you? in that order" ;;
      U4) s="$s; U4 a status update with no Next / Open questions tail — end with it whenever anything is next or open" ;;
    esac
  done
  printf '%s' "${s#; }"
}

if [ "$event" = Stop ]; then
  [ "$mode" = block ] || exit 0
  [ "$(printf '%s' "$MH_IN" | mh_get stop_hook_active)" = true ] && exit 0
  i=0
  while st=$(printf '%s' "$MH_IN" | mh_get "background_tasks.$i.status"); do
    [ "$st" = running ] && exit 0
    i=$((i + 1)); [ "$i" -lt 32 ] || break
  done
  text=$(printf '%s' "$MH_IN" | mh_get last_assistant_message) || exit 0
  ids=$(printf '%s\n' "$text" | LC_ALL=C awk "$UG_AWK" | grep -v U4)
  [ -n "$ids" ] || exit 0
  printf '{"decision":"block","reason":"Marvin update gate (block mode): rewrite your last message to the user so it passes — %s. Formats: .marvin/agents/user-updates.md. Send only the corrected message, with no remark about the correction."}\n' "$(note "$ids")"
  exit 0
fi

tp=$(printf '%s' "$MH_IN" | mh_get transcript_path) || exit 0
text=$(mh_last_text "$tp") || exit 0
ids=$(printf '%s\n' "$text" | LC_ALL=C awk "$UG_AWK")
[ "$mode" = block ] && ids=$(printf '%s\n' "$ids" | grep U4)
[ -n "$ids" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Marvin update check — your previous message to the user broke the format (.marvin/agents/user-updates.md): %s. Apply the formats from this reply on; do not re-send or apologise for the earlier message."}}\n' "$(note "$ids")"
exit 0
