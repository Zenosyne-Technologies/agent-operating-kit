#!/usr/bin/env bash
# test-ticket-lint.sh — behavioural tests for scripts/marvin-ticket-lint.sh (PreToolUse, v0.39.0).
# Pins: scope to the project's own tracker (pm_tool / project_key / tracker_coordinates); every payload shape (Jira create/edit, Linear save_issue, GitHub create_issue/update_issue/
# issue_write, gh issue create|edit, Local Write) × C1–C6; Jira Epic and Local children: exempt from C4;
# label-less edits never denied; C5 prose positives and ordinary-prose negatives; registry parse
# (resolved areas vs placeholders, sev4 vs sev4-low, milestone/release patterns, registry absent); modes
# block (explicit, invalid value, # comment) / advise (absent, empty) / off; no echo of prose or odd labels; valid JSON; sub-agent
# calls fire; non-Marvin, other tools and malformed input silent; never writes; exit 0.
# bash 3.2 + POSIX awk; python3 optional.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
HOOK="$SCRIPT_DIR/marvin-ticket-lint.sh"; LIB="$SCRIPT_DIR/lib/marvin-hook-lib.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-tltest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
assert_rc0()   { if [ "$RC" = 0 ]; then ok "exit 0"; else bad "exit $RC, want 0"; fi; }
assert_out()   { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "out has: $1"; else bad "out lacks: $1"; fi; }
assert_no()    { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "out must not have: $1"; else ok "out free of: $1"; fi; }
assert_empty() { if [ -z "$OUT" ]; then ok "no output"; else bad "expected no output, got: $(printf '%s' "$OUT" | head -c 200)"; fi; }
assert_json()  {  # python3 when present; else the hook lib's strict walker must read the keys back
  local v
  if command -v python3 >/dev/null 2>&1; then
    v=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])' 2>/dev/null)
  else
    v=$(. "$LIB"; { printf '%s' "$OUT" | mh_get hookSpecificOutput.additionalContext >/dev/null || printf '%s' "$OUT" | mh_get hookSpecificOutput.permissionDecisionReason >/dev/null; } && printf '%s' "$OUT" | mh_get hookSpecificOutput.hookEventName)
  fi
  if [ "$v" = PreToolUse ]; then ok "valid JSON"; else bad "not valid JSON: $(printf '%s' "$OUT" | head -c 200)"; fi
}
jstr() {  # JSON string literal of $1 (no python): escapes \ " tab, joins lines with \n
  printf '%s' "$1" | LC_ALL=C awk 'BEGIN { printf "\"" }
    { if (NR > 1) printf "\\n"; o = ""
      for (i = 1; i <= length($0); i++) { c = substr($0, i, 1)
        if (c == "\\") c = "\\\\"; else if (c == "\"") c = "\\\""; else if (c == "\t") c = "\\t"; o = o c }
      printf "%s", o }
    END { printf "\"" }'
}
REGSRC="$ROOT/templates/marvin/agents/label-syntax.md"
mk_project() {  # mk_project <dir> <frontmatter-line|""=ticket_lint: block|"-"=no mode key at all> <registry: resolved|placeholder|absent> [pm_tool, default jira|- for none] [coordinates]
  rm -rf "$1"; mkdir -p "$1/.marvin/agents"
  { printf -- '---\nkit_version: 0.39.0\n'; [ "${4:-jira}" != - ] && printf 'pm_tool: %s\n' "${4:-jira}"
    printf 'project_key: AOS\ntracker_coordinates: %s\n' "${5:-https://example.atlassian.net AOS}"
    case "$2" in -) ;; "") printf 'ticket_lint: block\n' ;; *) printf '%s\n' "$2" ;; esac; printf -- '---\nFacts.\n'; } > "$1/.marvin/PROJECT-INFO.md"
  case "$3" in
    resolved) sed 's/{{AREA_1}} · {{AREA_2}} · {{AREA_3}}/ui · core · api/' "$REGSRC" > "$1/.marvin/agents/label-syntax.md" ;;
    placeholder) cp "$REGSRC" "$1/.marvin/agents/label-syntax.md" ;;
  esac
}
P="$WORK/p"; mk_project "$P" "" resolved                                   # Jira, key AOS
PLN="$WORK/pln"; mk_project "$PLN" "" resolved linear
PGH="$WORK/pgh"; mk_project "$PGH" "" resolved github 'https://github.com/O/R.git'
PLO="$WORK/plo"; mk_project "$PLO" "" resolved local '.docs/project-management/ AOS'
pfor() { case "$1" in *JiraIssue) printf '%s' "$P" ;; *save_issue) printf '%s' "$PLN" ;; Write) printf '%s' "$PLO" ;; *) printf '%s' "$PGH" ;; esac; }
pre_in() {  # pre_in <tool> <tool_input-json> [prefix-fields]
  printf '{"session_id":"s"%s,"transcript_path":"%s/t.jsonl","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' \
    "${3:-}" "$WORK" "$P" "$1" "$2"
}
run() { OUT=$(printf '%s' "$2" | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1); RC=$?; }
J=mcp__f7d513a3-2df9-4ad9-9dff-08df9965a541__createJiraIssue; JE=mcp__atl__editJiraIssue; LN=mcp__fa0230fe-2401__save_issue
GW=mcp__github__issue_write; GC=mcp__plugin_github_github__create_issue; GU=mcp__GitHub__update_issue
DENY='"permissionDecision":"deny"'; CTX='"additionalContext"'
GOODL='"type:feature","area:ui","origin:roadmap","size:m"'
jira() {  # jira <labels-json-inner> [summary] [description] [issueType] — a Jira create
  printf '{"cloudId":"c","projectKey":"AOS","issueTypeName":"%s","summary":%s,"description":%s,"additional_fields":{"labels":[%s]}}' \
    "${4:-Task}" "$(jstr "${2:-Fix the cache}")" "$(jstr "${3:-Rows drop.}")" "$1"
}
lint() { run "${3:-$(pfor "$1")}" "$(pre_in "$1" "$2")"; }
gh_in() { pre_in Bash "{\"command\":$(jstr "$1"),\"description\":\"d\"}"; }
ghl() { run "${2:-$PGH}" "$(gh_in "$1")"; }
loc_in() {  # loc_in <content> [path] — braces built in a variable: bash 3.2 brace-expands "{…,…}" nested in $(…)
  local ti; ti="{\"file_path\":\"${2:-/r/.docs/project-management/issues/AOS-1.md}\",\"content\":$(jstr "$1")}"; pre_in Write "$ti"; }
loc() { run "${3:-$PLO}" "$(loc_in "$1" "${2:-}")"; }
denied()  { if printf '%s\n' "$OUT" | grep -Fq "$DENY" && printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "deny [$1]"; else bad "no deny [$1]: $(printf '%s' "$OUT" | head -c 200)"; fi; [ "$RC" = 0 ] || bad "exit $RC"; }
advised() { if printf '%s\n' "$OUT" | grep -Fq "$CTX" && ! printf '%s\n' "$OUT" | grep -Fq "$DENY" && printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "advise [$1]"; else bad "no advice-only [$1]: $(printf '%s' "$OUT" | head -c 200)"; fi; [ "$RC" = 0 ] || bad "exit $RC"; }
lacks()   { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "has [$1]"; else ok "free of [$1]"; fi; }
silent()  { if [ -z "$OUT" ] && [ "$RC" = 0 ]; then ok "silent${1:+: $1}"; else bad "not silent${1:+ ($1)}: $(printf '%s' "$OUT" | head -c 200)"; fi; }

hd "T1 fast paths and silence"
lint "$J" "$(jira "$GOODL")"; silent "a valid Jira create"; assert_rc0
ghl 'ls -la && git status'; silent "Bash without gh issue"
ghl 'gh issue list -l bug'; silent "gh issue list"
ghl 'gh pr create -l foo'; silent "gh pr create"
ghl 'echo gh issue create -t x'; silent "gh not in command position"
ghl '# gh issue create'; silent "commented out"
run "$PLO" "$(pre_in Write '{"file_path":"/r/src/issue.md","content":"x"}')"; silent "Write outside issues/"
run "$P" "$(pre_in Read '{"file_path":"/r/.docs/project-management/issues/AOS-1.md"}')"; silent "other tool"
run "$P" "$(pre_in mcp__atl__getJiraIssue '{"issueIdOrKey":"AOS-1"}')"; silent "read-only MCP tool"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"AOS-1","fields":{"assignee":"x"}}'; silent "edit with neither labels nor prose"
lint "$JE" "{\"cloudId\":\"c\",\"issueIdOrKey\":\"AOS-1\",\"fields\":{\"description\":$(jstr 'Rows drop on save.')}}"; silent "edit with plain prose, no labels"
mkdir -p "$WORK/plain"; run "$WORK/plain" "$(pre_in "$J" "$(jira '')")"; silent "non-Marvin project"
ln -s "$P/.marvin" "$WORK/plain/.marvin"; run "$WORK/plain" "$(pre_in "$J" "$(jira '')")"; silent "symlinked .marvin"; rm -f "$WORK/plain/.marvin"
run "$P" '{"tool_name":"mcp__atl__createJiraIssue","tool_input":{"summary":"x","additional_fields":{"labels":["a"'; silent "malformed JSON"
run "$P" 'createJiraIssue issue'; silent "not JSON"
run "$P" ''; silent "empty stdin"

hd "T2 Jira create × C1–C6"
lint "$J" "$(jira '')"; denied "C1 a create with no labels"; assert_json; lacks "C4"
lint "$J" "$(jira '"type:feature","size:m"')"; denied "C2 missing required dimension(s): area: origin:"
lint "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s"')"; denied "C3 type:bug without a severity label"
lint "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s","sev3-medium"')"; silent "bug with severity"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap"')"; denied "C4 a non-epic create without a size: label"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap"' 'An epic' 'x' Epic)"; silent "Jira Epic exempt from C4"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap"' 'An epic' 'x' epic)"; silent "epic, any case"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap"' 'Fix' 'Size: m')"; denied "C5 the size is stated only in the title/description"
lint "$J" "$(jira "$GOODL" 'Fix' 'Size: m')"; advised "C5 the title/description states the size"
lint "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s"' 'Fix' 'Severity: sev3')"; denied "C5 the severity is stated only"
lint "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s","sev3-medium"' 'Fix' 'Severity: sev3')"; advised "C5 the title/description states the severity"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:huge"')"; denied "C6 label size:huge is not a registry value of size:"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:m","needs-triage"')"; advised "C6 label needs-triage has no registry dimension"
lint "$J" "{\"cloudId\":\"c\",\"projectKey\":\"AOS\",\"issueTypeName\":\"Task\",\"summary\":\"x\",\"description\":{\"type\":\"doc\",\"content\":[{\"type\":\"paragraph\",\"content\":[{\"type\":\"text\",\"text\":\"T-shirt: L\"}]}]},\"additional_fields\":{\"labels\":[\"type:feature\",\"area:ui\",\"origin:roadmap\"]}}"
denied "C5 the size is stated only"; denied "C4"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:m"' 'Size: m')"; advised "C5 the title/description states the size"

hd "T3 Jira edit"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"AOS-1","fields":{"labels":["type:feature","origin:roadmap","size:m"]}}'; denied "C2 missing required dimension(s): area:"; lacks "C4"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"AOS-1","fields":{"labels":["type:feature","area:ui","origin:roadmap"]}}'; silent "edit with full set, no size (C4 is create-only)"
lint "$JE" "{\"cloudId\":\"c\",\"issueIdOrKey\":\"AOS-1\",\"fields\":{\"description\":$(jstr 'Repro below.
Size: m')}}"; advised "C5 the title/description states the size"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"AOS-1","fields":{"labels":["type:feature","area:ui","origin:roadmap","sev4"]}}'; denied "C6 label sev4 is not a registry value of severity"

hd "T4 Linear save_issue"
lint "$LN" '{"team":"T","title":"x","labels":["type:feature","area:ui","origin:roadmap"]}'; advised "C4 no size: label"
lint "$LN" '{"team":"T","title":"x"}'; denied "C1 a create with no labels"
lint "$LN" '{"team":"T","title":"x","labels":["type:feature","area:ui","origin:roadmap","size:m"]}'; silent "Linear valid create"
lint "$LN" '{"id":"LIN-1","labels":["type:feature","size:m"]}'; denied "C2 missing required dimension(s): area: origin:"; lacks "C4"
lint "$LN" '{"id":"LIN-1","addLabels":["size:huge"]}'; denied "C6 label size:huge"; lacks "C2"
lint "$LN" '{"id":"LIN-1","addLabels":["size:s"]}'; silent "additive edit, registry value"
lint "$LN" "{\"id\":\"LIN-1\",\"description\":$(jstr '**Size:** M')}"; advised "C5 the title/description states the size"

hd "T5 GitHub MCP"
lint "$GW" '{"method":"create","owner":"o","repo":"r","title":"x","body":"y"}'; denied "C1 a create with no labels"
lint "$GW" '{"method":"create","owner":"o","repo":"r","title":"x","labels":["type:feature","area:ui","origin:roadmap"]}'; advised "C4 no size: label"
lint "$GW" '{"method":"update","owner":"o","repo":"r","issue_number":3,"labels":["type:bug","area:ui","origin:agent-dev"]}'; denied "C3 type:bug without a severity label"; lacks "C4"
lint "$GW" '{"method":"update","owner":"o","repo":"r","issue_number":3,"state":"closed"}'; silent "issue_write update, nothing to check"
lint "$GC" '{"owner":"o","repo":"r","title":"x","body":"Sev: 2","labels":["type:bug","area:ui","origin:agent-qa","size:s"]}'; denied "C3"; denied "C5 the severity is stated only"
lint "$GU" '{"owner":"o","repo":"r","issue_number":3,"labels":["type:feature","area:nope","origin:roadmap"]}'; denied "C6 label area:nope is not a registry value of area:"

hd "T6 gh issue create|edit"
ghl 'gh issue create -t "Fix" -b "Rows drop." -l type:feature,area:ui --label origin:roadmap --label=size:m'; silent "gh create, comma + repeat + ="
ghl 'gh issue create -t "Fix" -b "Rows drop." -ltype:feature -l area:ui -l origin:roadmap'; advised "C4 no size: label"; [ -z "$(printf '%s' "$OUT" | grep -F 'C2')" ] && ok "-lVALUE read" || bad "-lVALUE not read"
ghl 'gh issue create -t "Fix" -b "Rows drop."'; denied "C1 a create with no labels"
ghl 'cd /r && gh issue create --title "Fix" --body "Size **m**" -l type:feature,area:ui,origin:roadmap'; denied "C5 the size is stated only"
ghl 'gh issue create --title "Fix" --body-file notes.md -l type:feature,area:ui,origin:roadmap,size:m'; silent "--body-file: prose unchecked"
ghl 'gh issue new -R o/r -t x -l type:bug,area:ui,origin:agent-qa,size:s'; denied "C3"
ghl 'gh issue edit 12 --add-label sev4'; denied "C6 label sev4"; lacks "C2"
ghl 'gh issue edit 12 --add-label sev4-low --remove-label sev4'; silent "edit, add valid, remove ignored"
ghl 'gh issue edit 12 --title "Severity: high"'; advised "C5 the title/description states the severity"
ghl 'gh issue create -t a -l type:feature,area:ui,origin:roadmap,size:m && gh issue create -t b'; denied "C1"
ghl 'GH_REPO=o/r gh issue create -t x -l type:feature,area:ui,origin:roadmap'; advised "C4 no size: label"

hd "T7 Local Write"
FM='---
key: AOS-1
title: Fix the cache
type: feature
status: todo'
loc "$FM
labels: [type:feature, area:core, origin:roadmap, size:m]   # inline
---
## Scope
Rows drop."; silent "Local valid inline labels"
loc "$FM
labels:
  - type:feature
  - \"area:core\"
  - origin:roadmap
  - size:s
---
x"; silent "Local block-list labels"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
---
x"; denied "C4 a non-epic create without a size: label"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
children: [AOS-2, AOS-3]
---
x"; silent "Local epic (children:) exempt from C4"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
children:
  - AOS-2
---
x"; silent "Local epic, block children"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
children: []
---
x"; denied "C4"
loc "$FM
labels: []
---
x"; denied "C1 a create with no labels"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
---
## Scope
- **T-shirt size:** xl"; denied "C5 the size is stated only"
loc "no frontmatter here"; silent "no frontmatter"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
---
x" "/r/notes/issues/AOS-1.md"; silent "not a project-management path"

hd "T8 C5 prose: positives fire, ordinary prose stays quiet"
L3='"type:feature","area:ui","origin:roadmap"'
for t in 'Size **m**' 'Size: m' '**Size:** M' 'Size — m' 'Size – m' 'T-shirt: L' 'T-shirt size: xl' 'size = s' '- Size: XS' '> **Size**: l' 'Done. Size: m.' '1. size: m'; do
  lint "$J" "$(jira "$L3" 'Fix' "$t")"; if printf '%s' "$OUT" | grep -Fq "C5 the size"; then ok "size prose: $t"; else bad "missed size prose: $t"; fi; done
for t in 'Severity: sev3' 'Sev: 2' 'severity: high' '**Severity:** sev1-critical' 'Severity: 3' '**Severity:** high' '- Sev: 2'; do
  lint "$J" "$(jira "$L3,\"size:m\"" 'Fix' "$t")"; if printf '%s' "$OUT" | grep -Fq "C5 the severity"; then ok "sev prose: $t"; else bad "missed sev prose: $t"; fi; done
for t in 'the size of the buffer' 'image size: 2 MB' 'Size matters here' 'Size: small' 'Sizes vary' 'the severity of this is unclear' 'Sev1 outage last week' 'Sev 1 outage last week showed we need retries.' 'Severity: high memory use is the motivation.' 'Repro first; sev 1 today' '`Size: m` is the old format' 'Severity: sev3 and more text' 'resize: m' 'The page size: m is ignored' 'set size:m later'; do
  lint "$J" "$(jira "$L3,\"size:m\"" 'Fix' "$t")"; if printf '%s' "$OUT" | grep -Fq "C5"; then bad "false positive: $t"; else ok "ordinary prose: $t"; fi; done

hd "T9 registry parse"
PP="$WORK/pp"; mk_project "$PP" "" placeholder
lint "$J" "$(jira '"type:feature","area:anything","origin:roadmap","size:m"')" "$PP"; silent "placeholder areas → area unchecked"
lint "$J" "$(jira '"type:feature","area:anything","origin:roadmap","size:mm"')" "$PP"; denied "C6 label size:mm"
lint "$J" "$(jira '"type:feature","area:bogus","origin:roadmap","size:m"')"; denied "C6 label area:bogus is not a registry value of area:"
for a in ui core api infra docs; do lint "$J" "$(jira "\"type:feature\",\"area:$a\",\"origin:roadmap\",\"size:m\"")"; silent "resolved area:$a"; done
lint "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s","sev4-low"')"; silent "sev4-low"
lint "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s","sev4"')"; denied "C6 label sev4 is not a registry value of severity"
for v in type:change-request type:tech-debt origin:architect-request origin:agent-qa size:xs size:xl finding:visual milestone:m2-launch release:v1.2.0 release:v0.39.0-rc.1; do
  lint "$J" "$(jira "\"type:feature\",\"area:ui\",\"origin:roadmap\",\"size:m\",\"$v\"")"; silent "registry value $v"; done
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:m","milestone:Bad_Slug"')"; denied "C6 label milestone:Bad_Slug is not a valid milestone:<slug>"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:m","release:1.2"')"; denied "C6 label release:1.2 is not a valid release:v<semver>"
lint "$J" "$(jira '"type:Feature","area:ui","origin:roadmap","size:m"')"; denied "C6 label type:Feature"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:m","area-reporting"')"; advised "C6 label area-reporting has no registry dimension"
PA="$WORK/pa"; mk_project "$PA" "" absent
lint "$J" "$(jira '"type:feature","area:bogus","origin:roadmap","size:huge"')" "$PA"; silent "registry absent → C6 skipped"
lint "$J" "$(jira '"type:feature","size:m"')" "$PA"; denied "C2 missing required dimension(s): area: origin:"
PU="$WORK/pu"; mk_project "$PU" "" absent; printf 'not a registry\n' > "$PU/.marvin/agents/label-syntax.md"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:huge","x"')" "$PU"; silent "registry unparseable → C6 skipped"

hd "T10 modes"
V='"type:feature","area:ui","origin:roadmap"'
for m in 'ticket_lint: block' 'ticket_lint: block   # strict' 'ticket_lint: strict' 'ticket_lint: BLOCK' 'ticket_lint: soft mode'; do
  PM="$WORK/pm"; mk_project "$PM" "$m" resolved
  lint "$J" "$(jira "$V")" "$PM"; denied "C4 a non-epic"; assert_json; done
PM="$WORK/pm"; mk_project "$PM" 'ticket_lint: block' resolved
lint "$J" "$(jira "$GOODL,\"oddlabel\"")" "$PM"; advised "C6 label oddlabel"
lint "$J" "$(jira "$V,\"oddlabel\"")" "$PM"; denied "Also: C6 label oddlabel has no registry dimension"
for m in 'ticket_lint: advise' 'ticket_lint: advise # soft' "ticket_lint: 'advise'" 'ticket_lint:' 'ticket_lint: # none' '-'; do
  mk_project "$PM" "$m" resolved
  lint "$J" "$(jira "$V")" "$PM"; advised "C4 a non-epic create without a size: label"; assert_json; done
for m in 'ticket_lint: off' 'ticket_lint: off # quiet'; do
  mk_project "$PM" "$m" resolved; lint "$J" "$(jira '')" "$PM"; silent "$m"; done

hd "T11 output hygiene"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","ZQXL\"AB\\\\EL","size:ZQXSIZE<script>"' 'ZQXSUMMARY "quoted" \ back' 'Size: m ZQXDESC')"
assert_json; assert_no "ZQXSUMMARY"; assert_no "ZQXDESC"; assert_no "ZQXL"; assert_no "ZQXSIZE"; assert_out "<label>"; assert_out "label-syntax.md"; assert_out "ticket-filing.md"
lint "$J" "$(jira '"type:feature","area:ui","origin:roadmap","size:abcdefghijabcdefghijabcdefghijabcdefghij1"')"; assert_out "C6 label <label>"
ghl 'gh issue create -t "ZQXTITLE Size: m" -b "ZQXBODY" -l type:feature'; assert_json; assert_no "ZQX"
loc "$FM
labels: [type:feature]
---
ZQXLOCAL Severity: sev2"; assert_json; assert_no "ZQX"
run "$P" "$(pre_in "$J" "$(jira '')" ',"agent_id":"a1","agent_type":"marvin:ponytail"')"; denied "C1"
assert_no "updatedInput"

hd "T13 scope: only the project's own tracker"
PN="$WORK/pn"; mk_project "$PN" "" resolved -
lint "$J" "$(jira '')" "$PN"; silent "pm_tool absent"
PN2="$WORK/pn2"; mk_project "$PN2" "" resolved none
lint "$J" "$(jira '')" "$PN2"; silent "pm_tool none"
PN3="$WORK/pn3"; mk_project "$PN3" "" resolved youtrack
lint "$J" "$(jira '')" "$PN3"; silent "pm_tool unknown"
lint "$J" '{"cloudId":"c","projectKey":"OTHER","issueTypeName":"Task","summary":"x"}'; silent "Jira create in another project"
lint "$J" '{"cloudId":"c","projectKey":"aos","issueTypeName":"Task","summary":"x"}'; denied "C1"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"OTHER-4","fields":{"labels":["type:feature"]}}'; silent "Jira edit in another project"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"AOSX-4","fields":{"labels":["type:feature"]}}'; silent "Jira key prefix is not the project key"
lint "$JE" '{"cloudId":"c","issueIdOrKey":"10001","fields":{"labels":["type:feature"]}}'; denied "C2"
lint "$J" "$(jira '')" "$PLN"; silent "Jira write under pm_tool linear"
lint "$LN" '{"team":"T","title":"x"}' "$P"; silent "Linear write under pm_tool jira"
lint mcp__sentry__create_issue '{"title":"x"}'; silent "mcp__sentry__create_issue under pm_tool github"
lint mcp__sentry__create_issue '{"title":"x"}' "$P"; silent "mcp__sentry__create_issue under pm_tool jira"
lint mcp__fa0230fe-9999__issue_write '{"method":"create","title":"x"}'; denied "C1"
lint mcp__tracker__update_issue '{"issue_number":3,"labels":["type:feature"]}'; silent "non-github server update_issue"
lint mcp__linear-server__save_issue '{"team":"T","title":"x"}' "$PLN"; denied "C1"
ghl 'gh issue create -R someone/upstream -t Crash -b "it crashed"'; silent "gh -R upstream"
ghl 'gh issue create --repo=someone/upstream -t Crash'; silent "gh --repo= upstream"
ghl 'gh issue -R someone/upstream create -t Crash'; silent "gh issue -R before the subcommand"
ghl 'gh issue create -R o/r -t Crash'; denied "C1"
ghl 'gh issue create --repo github.com/O/R -t Crash'; denied "C1"
ghl 'gh issue create -t Crash' "$P"; silent "gh under pm_tool jira"
PGN="$WORK/pgn"; mk_project "$PGN" "" resolved github 'n/a'
ghl 'gh issue create -R o/r -t Crash' "$PGN"; silent "-R with unreadable coordinates"
ghl 'gh issue create -t Crash' "$PGN"; denied "C1"
loc "---
key: AOS-1
labels: []
---
x" "" "$PGH"; silent "Local Write under pm_tool github"

hd "T14 heredoc bodies are not commands"
ghl "$(printf 'cat > HOWTO.md <<%s\n## Filing\ngh issue create --title X --body Y\nEOF' "'EOF'")"; silent "HOWTO heredoc"
ghl "$(printf 'cat > H.md <<EOF\ngh issue create -t X\nEOF')"; silent "bare terminator"
ghl "$(printf 'cat > H.md <<"EOF"\ngh issue create -t X\nEOF')"; silent "double-quoted terminator"
ghl "$(printf 'cat > H.md <<-EOF\ngh issue create -t X\n\tEOF')"; silent "<<- with a tab-indented terminator"
ghl "$(printf 'cat > H.md <<EOF\ngh issue create -t X\nEOF\ngh issue create -t Real')"; denied "C1"
ghl "$(printf 'gh issue create --title Fix --body "$(cat <<%s\nIt has an odd " quote and Size: m\nEOF\n)" -l type:feature,area:ui,origin:roadmap,size:m' "'EOF'")"; silent "labelled create, odd quote in a heredoc body (size mid-sentence is not prose-matched)"
ghl "$(printf 'gh issue create --title Fix --body "$(cat <<%s\nbody\nEOF\n)" -l type:feature' "'EOF'")"; denied "C2"
ghl 'cat <<< "gh issue create -t X"'; silent "here-string"
CPP="$(printf 'gh issue create -t "Fix stream" -b "Repro:\nstd::cout << value;\nprints nothing." -l type:bug,area:docs,origin:agent-qa,size:s,sev3-medium')"
ghl "$CPP"; silent "<< inside a double-quoted body is not a heredoc"
ghl "$(printf 'gh issue create -t "Fix" -b "Ruby:\nitems << item\nworks." -l type:feature,area:ui,origin:roadmap,size:m')"; silent "Ruby << in a quoted body"
ghl "$(printf "gh issue create -t 'a << b' -b 'x' -l type:feature,area:ui,origin:roadmap,size:m")"; silent "<< inside single quotes"
HB="$(printf 'gh issue create --title Fix --body "$(cat <<%s\nRows drop.\nSize **m**.\nEOF\n)" -l type:feature,area:ui,origin:roadmap' "'EOF'")"
ghl "$HB"; denied "C5 the size is stated only in the title/description"
ghl "$(printf 'gh issue create --title Fix --body "$(cat <<%s\ngh issue create -t inner\nEOF\n)" -l type:feature,area:ui,origin:roadmap,size:m' "'EOF'")"; silent "a gh line inside a --body heredoc is prose, not a command"

hd "T15 code is not prose"
lint "$J" "$(jira "$V" 'Epic' '```
size = s.length
Size: m
```' Epic)"; silent "fenced code"
lint "$J" "$(jira "$GOODL" 'Fix' '~~~
Severity: sev3
~~~')"; silent "tilde fence"
lint "$J" "$(jira "$V" 'Fix' 'Use `Size: m` in the label' Epic)"; silent "inline code"
lint "$J" "$(jira "$V" 'Fix' '```
x
```
Size: m')"; denied "C5 the size is stated only"
ADFCB='{"type":"doc","version":1,"content":[{"type":"codeBlock","attrs":{"language":"js"},"content":[{"type":"text","text":"size = s"}]},{"type":"paragraph","content":[{"type":"text","text":"Rows drop."}]}]}'
ADFCM='{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Size: m","marks":[{"type":"code"}]}]}]}'
ADFCB2='{"type":"doc","content":[{"type":"codeBlock","content":[{"type":"text","text":"Done. Size: m"}]}]}'
ADFTX='{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Size: m"}]}]}'
adf() { printf '{"cloudId":"c","projectKey":"AOS","issueTypeName":"%s","summary":"x","description":%s,"additional_fields":{"labels":[%s]}}' "$1" "$2" "$3"; }
lint "$J" "$(adf Epic "$ADFCB" "$V")"; silent "ADF codeBlock in an Epic"
lint "$J" "$(adf Epic "$ADFCM" "$V")"; silent "ADF code mark"
lint "$J" "$(adf Epic "$ADFTX" "$V")"; denied "C5 the size is stated only"
lint "$J" "$(adf Epic "$(jstr "$ADFCB")" "$V")"; silent "ADF codeBlock passed as a JSON string"
lint "$J" "$(adf Epic "$(jstr "$ADFCB2")" "$V")"; silent "ADF codeBlock with a sentence-anchored size, as a JSON string"
lint "$J" "$(adf Epic "$(jstr "$ADFTX")" "$V")"; denied "C5 the size is stated only"
lint "$J" "$(adf Epic "$(jstr '{not json
Size: m')" "$V")"; denied "C5 the size is stated only"
lint "$JE" "{\"cloudId\":\"c\",\"issueIdOrKey\":\"AOS-1\",\"fields\":{\"labels\":[$V],\"description\":$ADFCB}}"; silent "ADF codeBlock on an edit"

hd "T16 Linear templates and Local edits"
lint "$LN" '{"team":"T","title":"x","template":"Bug report"}'; advised "C1 a create with no labels"
lint "$LN" '{"team":"T","title":"x","templateId":"t1","labels":["type:feature"]}'; advised "C2 missing"
lint "$LN" '{"team":"T","title":"x","template":"Bug report","labels":["size:huge"]}'; denied "C6 label size:huge"
EX="$WORK/r/.docs/project-management/issues"; mkdir -p "$EX"; printf -- '---\nkey: AOS-9\n---\nold\n' > "$EX/AOS-9.md"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
---
x" "$EX/AOS-9.md"; advised "C4 no size: label"
loc "$FM
labels: [type:feature, origin:roadmap, size:m]
---
x" "$EX/AOS-9.md"; denied "C2 missing required dimension(s): area:"; lacks "C4"
loc "$FM
status: done
---
x" "$EX/AOS-9.md"; silent "legacy item rewritten without labels"
loc "$FM
---
Size: m" "$EX/AOS-9.md"; advised "C5 the title/description states the size"
loc "$FM
labels: [type:feature, area:core, origin:roadmap]
children: [AOS-2]
---
x" "$EX/AOS-9.md"; silent "existing epic"

hd "T17 a gh parse denies only when certain"
UNC="could not be parsed with certainty"
SUBQ='gh issue create -t x -b "$(printf "%s" x)" -l type:bug,area:ui,origin:agent-qa,size:s,sev3-medium'
ghl "$SUBQ"; lacks "$DENY"; lacks "C1"
ghl 'gh issue create -t x -b "$(printf "%s" x)" -l type:bug,area:ui'; advised "C2 missing"; advised "$UNC"
ghl 'gh issue create -t x -b y'; denied "C1 a create with no labels"; lacks "$UNC"
ghl 'gh issue create -t x -b "$(date)" -l type:feature'; advised "C2 missing"; advised "$UNC"
ghl 'LBL=type:feature,area:docs,origin:roadmap,size:m; gh issue create -t Fix -b x -l "$LBL"'; lacks "$DENY"; advised "$UNC"
ghl 'gh issue create -t Fix -b x -l "$LBL"'; lacks "$DENY"; advised "$UNC"
ghl 'gh issue create -t Fix -b x -l `cat labels.txt`'; lacks "$DENY"; advised "$UNC"
ghl 'gh issue create -t "Fix `date`" -b x'; advised "C1"; advised "$UNC"
ghl 'gh issue create -t Fix -b x --label=$L'; lacks "$DENY"
ghl 'gh issue create -t Fix -b x -l type:bug,area:ui,origin:agent-qa,size:s,sev2-high'; silent "literal labels, nothing missing"
ghl 'gh issue create -t Fix -b x -l type:bug'; denied "C2 missing"; lacks "$UNC"
ghl 'gh issue create -t Fix -b x -l $(cat labels.txt)'; lacks "$DENY"; advised "$UNC"
ghl 'cd "$(git rev-parse --show-toplevel)" && gh issue create -t Fix -b x'; denied "C1"
ghl "$(printf 'gh issue create -t x <<EOF\nbody without a terminator')"; advised "C1 a create with no labels"; advised "$UNC"
ghl 'gh issue create -t "x -b y'; advised "C1"; advised "$UNC"
ghl 'gh issue create -t `echo "x"` -b y'; advised "C1"; advised "$UNC"
ghl 'X=$(echo "a") gh issue create -t x'; advised "C1"; advised "$UNC"

hd "T12 never writes"
snap() { find "$WORK" -exec ls -ldn {} + 2>/dev/null | sort | cksum; }   # $WORK only — `ls -laR` also lists `..`, the shared temp dir, which any concurrent mktemp changes
before=$(snap); lint "$J" "$(jira '"type:bug"' 'x' 'Size: m')"
after=$(snap); if [ "$before" = "$after" ]; then ok "nothing written"; else bad "the hook wrote something"; fi

# ── mutations: the fixture must hold on the real hook and break on the mutant ─────────────────────────
check() {  # check <expect> — "silent", "has:<text>", "no:<text>", "deny", "nodeny"
  case "$1" in
    silent) [ -z "$OUT" ] ;;
    deny) printf '%s\n' "$OUT" | grep -Fq "$DENY" ;;
    nodeny) [ -n "$OUT" ] && ! printf '%s\n' "$OUT" | grep -Fq "$DENY" ;;
    has:*) printf '%s\n' "$OUT" | grep -Fq -- "${1#has:}" ;;
    no:*) ! printf '%s\n' "$OUT" | grep -Fq -- "${1#no:}" ;;
  esac
}
mutation() {  # mutation <name> <exact line> <replacement> <expect> <project> <stdin>
  local d="$WORK/m-$1"
  rm -rf "$d"; mkdir -p "$d/lib"; cp "$LIB" "$d/lib/"
  A="$2" B="$3" awk '$0 == ENVIRON["A"] { print ENVIRON["B"]; next } { print }' "$HOOK" > "$d/hook.sh"   # ENVIRON: no escape processing
  if [ ! -f "$HOOK" ] || cmp -s "$d/hook.sh" "$HOOK"; then bad "mutation $1: target line not found — harness is stale"; return; fi
  run "$5" "$6"; if [ "$RC" != 0 ] || ! check "$4"; then bad "mutation $1: fixture fails on the real hook — harness is stale: $(printf "%s" "$OUT" | head -c 160)"; return; fi
  OUT=$(printf '%s' "$6" | CLAUDE_PROJECT_DIR="$5" bash "$d/hook.sh" 2>&1); RC=$?
  if [ "$RC" != 0 ]; then bad "mutation $1: run failed (exit $RC)"; return; fi
  if check "$4"; then bad "mutation $1 survived ($4 still holds)"; else ok "mutation $1 caught"; fi
}
hd "M1 C1 removed — T2 no-label create must catch it"
mutation c1 '  if (op == "create" && nl == 0) note(tm ? "A" : "V", "C1 a create with no labels — add one label per required dimension")' '  if (0) note("V", "x")' "has:C1 a create" "$P" "$(pre_in "$J" "$(jira '')")"
hd "M2 C2 origin: not required — T2 must catch it"
mutation c2 '      if (!has["type"]) miss = miss " type:"; if (!has["area"]) miss = miss " area:"; if (!has["origin"]) miss = miss " origin:"' '      if (!has["type"]) miss = miss " type:"; if (!has["area"]) miss = miss " area:"' "has:C2" "$P" "$(pre_in "$J" "$(jira '"type:feature","area:ui","size:m"')")"
hd "M3 C3 removed — T2 bug without severity must catch it"
mutation c3 '      if (bug && !has["sev"]) note("V", "C3 type:bug without a severity label (sev1-critical..sev4-low)") }' '      }' "has:C3" "$P" "$(pre_in "$J" "$(jira '"type:bug","area:ui","origin:agent-qa","size:s"')")"
hd "M4 Jira Epic not exempt — T2 Epic must catch it"
mutation epic '      case "$(kv issueTypeName | tr '"'A-Z' 'a-z'"')" in epic) ep=yes ;; *) ep=no ;; esac ;;' '      ep=no ;;' silent "$P" "$(pre_in "$J" "$(jira "$V" 'E' 'x' Epic)")"
hd "M5 C4 never denies — T2 non-epic without size must catch it"
mutation c4 '      if (ep == "no" && !le && !tm) note("V", "C4 a non-epic create without a size: label (xs..xl, set at filing)")' '      if (0) note("V", "x")' deny "$P" "$(pre_in "$J" "$(jira "$V")")"
hd "M6 Local children: not read — T7 epic must catch it"
mutation children '  if ($0 ~ /^children:/) { v = val($0); if (v == "") bl = 2; else if (v !~ /^\[[ \t]*\]$/) ep = 1; next }' '  if ($0 ~ /^children:/) next' silent "$PLO" "$(loc_in "$FM
labels: [type:feature, area:core, origin:roadmap]
children: [AOS-2]
---
x")"
hd "M7 C5 size prose not anchored — T8 'the size of the buffer'-style prose must catch it"
mutation anchor '    if (f ~ /^(t-shirt size|t-shirt|size)([ \t]*([:=-]|\342\200\224|\342\200\223)[ \t]*|[ \t]+)(xs|s|m|l|xl)([^a-z0-9]|$)/) psz = 1 } }' '    if (f ~ /(t-shirt size|t-shirt|size)([ \t]*([:=-]|\342\200\224|\342\200\223)[ \t]*|[ \t]+)(xs|s|m|l|xl)([^a-z0-9]|$)/) psz = 1 } }' silent "$P" "$(pre_in "$J" "$(jira "$GOODL" 'Fix' 'The page size: m is ignored')")"
hd "M8 bold not stripped — T8 **Size:** M must catch it"
mutation bold 'function norm(f) { f = tolower(f); gsub(/\*\*|__|`/, "", f); sub(/^[ \t>*+#_-]+/, "", f); sub(/^[0-9]+[.)][ \t]*/, "", f); return f }' 'function norm(f) { f = tolower(f); return f }' "has:C5" "$P" "$(pre_in "$J" "$(jira "$V" 'Fix' '**Size:** M')")"
hd "M9 C6 value check removed — T9 size:huge must catch it"
mutation c6 '    if ((dm in UNK) || ((dm, (dm == "sev" ? x : v)) in OK)) continue' '    continue' "has:C6" "$P" "$(pre_in "$J" "$(jira "$GOODL,\"size:huge\"")")"
hd "M10 placeholder areas checked — T9 placeholder registry must catch it"
mutation placeholder '  v = c[4]; if (index(v, "{{")) { o = o "|" dm ":?"; next }' '  v = c[4]' silent "$PP" "$(pre_in "$J" "$(jira '"type:feature","area:anything","origin:roadmap","size:m"')")"
hd "M11 absent mode defaults to block instead of advise — T10 must catch it"
PABS="$WORK/pabs"; mk_project "$PABS" - resolved; PSTR="$WORK/pstr"; mk_project "$PSTR" 'ticket_lint: strict' resolved
mutation mode 'mh_mode "$fm" ticket_lint "block advise off" advise >/dev/null; mode=$MH_MODE' 'mh_mode "$fm" ticket_lint "block advise off" block >/dev/null; mode=$MH_MODE' nodeny "$PABS" "$(pre_in "$J" "$(jira "$V")")"
hd "M11b an unknown explicit value no longer fails closed — T10 must catch it"
mutation modebad '[ -n "$MH_MODE_INVALID" ] && mode=block' ':' deny "$PSTR" "$(pre_in "$J" "$(jira "$V")")"
EDIT_SIZE="{\"cloudId\":\"c\",\"issueIdOrKey\":\"AOS-1\",\"fields\":{\"description\":$(jstr 'Size: m')}}"
hd "M12 label-less edits treated as full sets — T3 description-only edit must catch it"
mutation full '  full = (op == "create" || hf)' '  full = 1' nodeny "$P" "$(pre_in "$JE" "$EDIT_SIZE")"
hd "M13 label sanitiser removed — T11 must catch it"
mutation sv 'function sv(x) { return (length(x) <= 40 && x ~ /^[A-Za-z0-9:._-]+$/) ? x : "<label>" }' 'function sv(x) { return x }' "no:ZQX" "$P" "$(pre_in "$J" "$(jira "$GOODL,\"ZQX<b>\"")")"
hd "M14 Linear id not read (every save_issue a create) — T4 edit must catch it"
mutation linid '      *__save_issue) printf '"'%s\n'"' "$w" | grep -q '"'^K id	'"' || op=create ;;' '      *__save_issue) op=create ;;' silent "$PLN" "$(pre_in "$LN" '{"id":"LIN-1","addLabels":["size:s"]}')"
hd "M15 sub-agent calls skipped — T11 must catch it"
mutation subagent 'MH_IN=$RAW' 'MH_IN=$RAW; mh_is_subagent_call && exit 0' deny "$P" "$(pre_in "$J" "$(jira '')" ',"agent_id":"a1"')"

hd "M16 severity prose widened — T8 'Sev 1 outage …' must catch it"
mutation sevre '  if (norm(l) ~ /^(severity|sev)[ \t]*[:=][ \t]*(sev[1-4](-[a-z]+)?|[1-4]|critical|high|medium|low)[ \t.]*$/) psv = 1' '  if (norm(l) ~ /^(severity|sev)([ \t]*[:=-][ \t]*|[ \t]+)(sev[1-4][a-z-]*|[1-4]|critical|high|medium|low)([^a-z0-9]|$)/) psv = 1' silent "$P" "$(pre_in "$J" "$(jira "$GOODL" 'Fix' 'Sev 1 outage last week showed we need retries.')")"
hd "M17 gh command position dropped — T1 echo must catch it"
mutation ghpos '  b = tok[k]; sub(/.*\//, "", b); if (b != "gh") return' '  for (k = s; k <= e && tok[k] != "gh"; k++); if (k > e) return' silent "$PGH" "$(gh_in 'echo gh issue create -t x')"
hd "M18 issue_write method ignored (every call a create) — T5 update must catch it"
mutation method '      *__issue_write) [ "$(kv method)" = create ] && op=create ;;' '      *__issue_write) op=create ;;' silent "$PGH" "$(pre_in "$GW" '{"method":"update","owner":"o","repo":"r","issue_number":3,"state":"closed"}')"
hd "M19 Local path filter widened — T7 notes/issues must catch it"
mutation pathfilter '         case "$fp" in */project-management/issues/*.md|project-management/issues/*.md) kind=local ;; *) exit 0 ;; esac' '         case "$fp" in *.md) kind=local ;; *) exit 0 ;; esac' silent "$PLO" "$(loc_in "$FM
labels: [type:feature]
---
x" /r/notes/issues/AOS-1.md)"
hd "M20 fast path narrowed to Bash payloads — T2 Jira create must catch it"
mutation fastpath 'case "$RAW" in *ssue*) ;; *) exit 0 ;; esac' 'case "$RAW" in *\"command\"*issue*) ;; *) exit 0 ;; esac' deny "$P" "$(pre_in "$J" '{"cloudId":"c","projectKey":"AOS","issueTypeName":"Task","summary":"x"}')"
hd "M21 tracker scope dropped (any Jira project) — T13 must catch it"
mutation scope '        [ -n "$pkey" ] && [ "$k" = "$pkey" ] || exit 0 ;;' '        : ;;' silent "$P" "$(pre_in "$J" '{"cloudId":"c","projectKey":"OTHER","issueTypeName":"Task","summary":"x"}')"
hd "M22 gh -R not compared — T13 upstream must catch it"
mutation ghrepo '  if (rv != "") { rv = tolower(rv); sub(/^.*github\.com[\/:]/, "", rv); sub(/\.git$/, "", rv); if (repo == "" || rv != repo) return }' '' silent "$PGH" "$(gh_in 'gh issue create -R someone/upstream -t Crash')"
hd "M23 heredoc bodies read as commands — T14 HOWTO must catch it"
mutation heredoc '    else if (c == "<" && substr($0, i, 2) == "<<" && substr($0, i + 2, 1) != "<" && (!q || cs)) { if (!q) flush(); i = here(i) }' '    else if (0) i = i' silent "$PGH" "$(gh_in "$(printf 'cat > HOWTO.md <<%s\n## Filing\ngh issue create --title X --body Y\nEOF' "'EOF'")")"
hd "M24 fences read as prose — T15 must catch it"
mutation fence '  if (fence) return' '  fence = 0' silent "$P" "$(pre_in "$J" "$(jira "$V" 'Epic' '```
Size: m
```' Epic)")"
hd "M25 Linear template not honoured — T16 must catch it"
mutation template '    tm=""; printf '"'%s\n'"' "$w" | grep -q '"'^K template'"' && tm=T' '    tm=""' nodeny "$PLN" "$(pre_in "$LN" '{"team":"T","title":"x","template":"Bug report"}')"
hd "M26 existing Local file treated as a create — T16 must catch it"
mutation localedit '         if [ -f "$f" ]; then recs=$(printf '"'R\nOP edit\nS\n%s\n'"' "$lo")   # an existing item: an edit carrying its labels' '         if false; then :' nodeny "$PLO" "$(loc_in "$FM
labels: [type:feature, area:core, origin:roadmap]
---
x" "$EX/AOS-9.md")"

hd "M27 heredoc detector ignores quote state — T14 C++ body must catch it"
mutation quotestate '    else if (c == "<" && substr($0, i, 2) == "<<" && substr($0, i + 2, 1) != "<" && (!q || cs)) { if (!q) flush(); i = here(i) }' '    else if (c == "<" && substr($0, i, 2) == "<<" && substr($0, i + 2, 1) != "<") { if (!q) flush(); i = here(i) }' silent "$PGH" "$(gh_in "$CPP")"
hd "M28 --body heredoc not read as prose — T14 Size **m** body must catch it"
mutation bodyprose '{ if (hi <= nh) { l = $0; if (hs[hi]) sub(/^\t+/, "", l); if (l == hd[hi]) hi++; else if (hw[hi]) w = w $0 "\n"; if (hi > nh) { nh = 0; hi = 1 }; next }' '{ if (hi <= nh) { l = $0; if (hs[hi]) sub(/^\t+/, "", l); if (l == hd[hi]) hi++; if (hi > nh) { nh = 0; hi = 1 }; next }' "has:C5" "$PGH" "$(gh_in "$HB")"
hd "M29 issue_write gated on a github server name — T13 must catch it"
mutation anyserver '             *__issue_write) ;;                                        # GitHub'"'"'s own tool name: any server' '             *__issue_write) case "$srv" in *github*) ;; *) exit 0 ;; esac ;;' deny "$PGH" "$(pre_in mcp__fa0230fe-9999__issue_write '{"method":"create","title":"x"}')"

hd "M30 certainty flag dropped — T17 quote-in-substitution must catch it"
mutation certain '  if (unc || ru) out("U")' '  :' nodeny "$PGH" "$(gh_in 'gh issue create -t x -b "$(printf "%s" x)" -l type:bug,area:ui')"

hd "M31 expanded gh values counted as certain — T17 -l \"\$LBL\" must catch it"
mutation expand '  if (index(v, "$") || index(v, "`")) ru = 1' '  ru = ru' nodeny "$PGH" "$(gh_in 'LBL=type:feature,area:docs,origin:roadmap,size:m; gh issue create -t Fix -b x -l "$LBL"')"
hd "M32 ADF codeBlock read as prose — T15 must catch it"
mutation adfcb '          if (s == "codeBlock") CB[d] = 1' '          CB[d] = 0' silent "$P" "$(pre_in "$J" "$(adf Epic "$ADFCB" "$V")")"
hd "M33 ADF code mark read as prose — T15 must catch it"
mutation adfcm '          if (s == "code" && d >= 3 && T[d - 1] == "[" && K[d - 2] == "marks") SK[d - 2] = 1   # a code mark' '          SK[d] = 0' silent "$P" "$(pre_in "$J" "$(adf Epic "$ADFCM" "$V")")"
hd "M34 JSON-string ADF not re-walked — T15 must catch it"
mutation adfstr '          if (pl == d && ch(pos + 1) == "{") { print "J " path(); rstr(0); continue }' '          pl = pl' silent "$P" "$(pre_in "$J" "$(adf Epic "$(jstr "$ADFCB2")" "$V")")"

printf '\n----\ntest-ticket-lint: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
