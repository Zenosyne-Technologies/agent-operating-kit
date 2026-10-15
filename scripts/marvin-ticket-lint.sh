#!/usr/bin/env bash
# marvin-ticket-lint.sh — PreToolUse hook for the marvin plugin (v0.39.0). Matcher:
#   ^mcp__.*__(createJiraIssue|editJiraIssue|save_issue|create_issue|update_issue|issue_write)$|^Bash$|^Write$
# Enforces the PRE-WRITE half of the label check .marvin/agents/ticket-filing.md owns, against the
# registry .marvin/agents/label-syntax.md (the read-back half stays the writer's — this hook never reads
# the tracker). Only writes to the project's OWN tracker (PROJECT-INFO pm_tool / project_key /
# tracker_coordinates) are linted; pm_tool none, absent or unknown → silent:
#   jira   — createJiraIssue whose projectKey is project_key; editJiraIssue whose issueIdOrKey is
#            <project_key>-… or numeric (any MCP server: claude.ai connectors carry opaque server ids)
#   linear — save_issue (Linear's tool name; create when it carries no `id`; a `template`/`templateId`
#            supplies labels server-side, so C1/C2/C4 only advise)
#   github — issue_write on any MCP server (GitHub's own tool name; method "create" = create);
#            create_issue / update_issue only on a server whose name contains "github"; Bash `gh issue
#            create|new|edit` with no -R/--repo or one naming the tracker_coordinates owner/repo
#            (--label/-l repeatable and comma-split, --add-label, --title/-t, --body/-b — a
#            "$(cat <<'EOF' … EOF)" heredoc value is read as prose; --body-file is unreadable, so its
#            prose goes unchecked; a top-level heredoc body is never read as commands or prose)
#   local  — Write of */project-management/issues/*.md (frontmatter `labels:` inline or block list,
#            `children:` marks an epic); a new file is a create, an existing one an edit carrying labels
# Labels = every string in any JSON array keyed `labels` (full set) or `addLabels` (additive), at any
# depth. Prose = strings under summary/title/description/body at any depth (Jira ADF — an object or a
# JSON string of a doc — included); markdown fences and inline code, ADF codeBlock nodes and code marks
# skipped.
# Checks (an edit is checked only when it carries labels or prose; C2/C3 and C5 violations need the
# FULL label set — a create, or an edit that sets `labels`; additive or label-less edits only advise):
#   C1 a create with no labels · C2 missing type:/area:/origin: · C3 type:bug without a severity label ·
#   C4 a create without size: — a violation where the item is known non-epic (Jira issueTypeName not
#      Epic; Local without children:), an advisory elsewhere (and on a Local edit) ·
#   C5 a size stated in the title/description (line- or sentence-anchored: `Size: m`, `**Size:** M`,
#      `Size — m`, `T-shirt: L`) or a label-like severity line (`Severity: sev3`, `Severity: 3`,
#      `**Severity:** high`, `Sev: 2` — the whole line) — a violation without the label, an advisory
#      ("delete the prose") with it ·
#   C6 a dimension:value label whose value is not in the registry's Dimensions table (bare sevN too) —
#      a violation; a label with no registry dimension — an advisory. Area placeholders ({{AREA_1}})
#      unresolved → area values unchecked; registry missing/unparseable → C6 skipped.
# Mode = ticket_lint in .marvin/PROJECT-INFO.md frontmatter (case-insensitive): block (default; absent or
# invalid too) — violations deny, advisories folded into the reason, advisories alone as
# additionalContext · advise — everything as additionalContext · off — nothing.
# Known limits: only the first 64 KiB of a Bash command is parsed; gh run through a variable, alias,
# bash -c or xargs is not seen; a size/severity in a table cell or mid-sentence is not prose-matched;
# Edit-tool writes to Local issue files are not linted; Linear `patch` ops are not read as prose; Jira
# create_issue/update_issue on
# a GitHub MCP server whose name lacks "github" is not linted. A gh command parse is heuristic: it
# denies only when certain (quotes balanced, heredocs terminated, no quote inside a substitution
# outside a heredoc body, no $/backtick expansion in a flag value it reads); otherwise its violations
# only advise.
# Contract: Marvin projects only; fires for sub-agent calls too; never writes; always exits 0; output is
# constant text, dimension names and label values matching ^[A-Za-z0-9:._-]{1,40}$ (else <label>) —
# never prose, never a title.
set -u
[ -t 0 ] && exit 0
RAW=$(head -c 1048576 2>/dev/null) || exit 0
case "$RAW" in *ssue*) ;; *) exit 0 ;; esac
. "$(dirname "$0")/lib/marvin-hook-lib.sh" 2>/dev/null || exit 0
MH_IN=$RAW
tool=$(printf '%s' "$MH_IN" | mh_get tool_name) || exit 0
case "$tool" in
  Bash) src=$(printf '%s' "$MH_IN" | mh_get tool_input.command | head -c 65536) || exit 0
        case "$src" in *gh*issue*) kind=gh ;; *) exit 0 ;; esac ;;
  Write) fp=$(printf '%s' "$MH_IN" | mh_get tool_input.file_path) || exit 0
         case "$fp" in */project-management/issues/*.md|project-management/issues/*.md) kind=local ;; *) exit 0 ;; esac
         src=$(printf '%s' "$MH_IN" | mh_get tool_input.content) || exit 0 ;;
  mcp__*__createJiraIssue|mcp__*__editJiraIssue|mcp__*__save_issue|mcp__*__create_issue|mcp__*__update_issue|mcp__*__issue_write) kind=mcp ;;
  *) exit 0 ;;
esac
root=$(mh_root); mh_is_marvin "$root" || exit 0
fm=$(mh_frontmatter "$root") || fm=""
mode=$(mh_fm_value "$fm" ticket_lint | tr 'A-Z' 'a-z')
case "$mode" in advise|off) ;; *) mode=block ;; esac
[ "$mode" = off ] && exit 0

# Scope: the project's own tracker only
pm=$(mh_fm_value "$fm" pm_tool | tr 'A-Z' 'a-z')
pkey=$(mh_fm_value "$fm" project_key | tr 'a-z' 'A-Z')
srv=${tool#mcp__}; srv=$(printf '%s' "${srv%__*}" | tr 'A-Z' 'a-z')
repo=""
case "$pm" in
  jira)
    case "$tool" in
      *__createJiraIssue)
        k=$(printf '%s' "$MH_IN" | mh_get tool_input.projectKey | tr 'a-z' 'A-Z') || exit 0
        [ -n "$pkey" ] && [ "$k" = "$pkey" ] || exit 0 ;;
      *__editJiraIssue)
        k=$(printf '%s' "$MH_IN" | mh_get tool_input.issueIdOrKey | tr 'a-z' 'A-Z') || exit 0
        case "$k" in "") exit 0 ;; *[!0-9]*) [ -n "$pkey" ] || exit 0; case "$k" in "$pkey"-*) ;; *) exit 0 ;; esac ;; esac ;;
      *) exit 0 ;;
    esac ;;
  linear) case "$tool" in *__save_issue) ;; *) exit 0 ;; esac ;;
  github)
    case "$kind" in
      gh) repo=$(mh_fm_value "$fm" tracker_coordinates | sed -E 's#^.*github\.com[/:]##; s#\.git([^A-Za-z0-9].*)?$##' \
            | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -n 1 | tr 'A-Z' 'a-z') ;;
      mcp) case "$tool" in
             *__issue_write) ;;                                        # GitHub's own tool name: any server
             *__create_issue|*__update_issue) case "$srv" in *github*) ;; *) exit 0 ;; esac ;;
             *) exit 0 ;;
           esac ;;
      *) exit 0 ;;
    esac ;;
  local) [ "$kind" = local ] || exit 0 ;;
  *) exit 0 ;;
esac

# The tool_input walker: one pass, an explicit stack, strings decoded. Prints "K key<TAB>value" for the
# top-level id/method/issueTypeName/template/templateId, "H" when a full `labels` array opens, "L"/"A" per label string
# (labels / addLabels) and "P" per prose line — an ADF text node only when neither it (a code mark) nor an
# ancestor (a codeBlock) is code; "J path" for a prose string that holds a JSON doc (ADF as a string),
# which the shell re-walks. Malformed input → exit 1 (the hook stays silent).
IFS= read -r -d '' TW_AWK <<'AWK' || true
function hx(h,   i, v, d) { v = 0; h = tolower(h)
  for (i = 1; i <= 4; i++) { d = index("0123456789abcdef", substr(h, i, 1)); if (!d) return -1; v = v * 16 + d - 1 }
  return v }
function u8(c) {
  if (c <= 0) return ""
  if (c < 128) return sprintf("%c", c)
  if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
  if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
  return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64) }
function ch(p) { return substr(ck[int((p - 1) / CK) + 1], (p - 1) % CK + 1, 1) }
function sb(p, l,   r, t) { r = ""
  while (l > 0) { t = substr(ck[int((p - 1) / CK) + 1], (p - 1) % CK + 1, l); if (t == "") break; r = r t; p += length(t); l -= length(t) }
  return r }
function emit(p, l,   t) {
  while (l > 0) { t = substr(ck[int((p - 1) / CK) + 1], (p - 1) % CK + 1, l); if (t == "") break; printf "%s", t; p += length(t); l -= length(t) } }
function esc(   c, a, b) {
  c = ch(pos + 1); pos += 2
  if (c == "n") return "\n"
  if (c == "t") return "\t"
  if (c == "r" || c == "b" || c == "f") return ""
  if (c != "u") return c
  a = hx(sb(pos, 4)); if (a < 0) exit 1; pos += 4
  if (a >= 55296 && a <= 56319 && sb(pos, 2) == "\\u") {
    b = hx(sb(pos + 2, 4))
    if (b >= 56320 && b <= 57343) { pos += 6; a = 65536 + (a - 55296) * 1024 + (b - 56320) } }
  return u8(a) }
function run(st, l) { if (l <= 0) return
  if (m == 2) emit(st, l); else if (m == 1 && length(out) < 4096) out = out sb(st, l > 4096 ? 4096 : l) }
function rstr(mm,   c, st, e) {  # mm: 1 collect (capped) · 2 stream as prose lines
  m = mm; out = ""; pos++; st = pos
  if (m == 2) printf "P "
  while (pos <= n) { c = ch(pos)
    if (c == "\"") { run(st, pos - st); pos++; if (m == 2) printf "\n"; return out }
    if (c == "\\") { run(st, pos - st); e = esc()
      if (m == 2) { if (e == "\n") printf "\nP "; else printf "%s", e }
      else if (length(out) < 4096) out = out e
      st = pos; continue }
    pos++ }
  exit 1 }
function prose(   k) { for (k = 2; k <= d; k++) if (T[k] == "{" && K[k] ~ /^(summary|title|description|body)$/) return k
  return 0 }
function path(   k, p) { p = ""; for (k = 2; k <= d; k++) p = p (k > 2 ? "." : "") K[k]; return p }
function incode(e,   k) { for (k = 1; k <= e; k++) if (CB[k]) return 1; return 0 }
BEGIN { CK = 4096 }
{ buf = buf $0 "\n"
  while (length(buf) >= CK) { ck[++nck] = substr(buf, 1, CK); buf = substr(buf, CK + 1) } }
END { if (buf != "") ck[++nck] = buf
  n = nck ? (nck - 1) * CK + length(ck[nck]) : 0; pos = 1; d = 0
  while (pos <= n) { c = ch(pos)
    if (c == "\"") {
      if (d && T[d] == "{" && EK[d]) { K[d] = rstr(1); EK[d] = 0; continue }
      inti = d >= 2 && K[1] == "tool_input"
      if (inti && T[d] == "[" && (K[d - 1] == "labels" || K[d - 1] == "addLabels")) { s = rstr(1); gsub(/[\n\t]/, " ", s); print (K[d - 1] == "labels" ? "L " : "A ") s; continue }
      if (inti && d == 2 && K[2] ~ /^(id|method|issueTypeName|template|templateId)$/) { s = rstr(1); gsub(/[\n\t]/, " ", s); print "K " K[2] "\t" s; continue }
      if (inti && (pl = prose())) {
        if (pl == d || T[d] == "[") {   # the prose value itself; a JSON-string ADF doc is re-walked by the shell
          if (pl == d && ch(pos + 1) == "{") { print "J " path(); rstr(0); continue }
          rstr(2); continue }
        if (T[d] == "{" && K[d] == "text") { s = rstr(1); PT[d] = PT[d] s "\n"; continue }   # an ADF text node, held to its close
        if (T[d] == "{" && K[d] == "type") { s = rstr(1)
          if (s == "codeBlock") CB[d] = 1
          if (s == "code" && d >= 3 && T[d - 1] == "[" && K[d - 2] == "marks") SK[d - 2] = 1   # a code mark
          continue }
        rstr(0); continue }
      rstr(0); continue }
    if (c == "{") { if (++d > 64) exit 1; T[d] = "{"; EK[d] = 1; K[d] = ""; CB[d] = 0; SK[d] = 0; PT[d] = ""; pos++; continue }
    if (c == "[") { if (++d > 64) exit 1; T[d] = "["; K[d] = ""; if (d >= 3 && K[1] == "tool_input" && K[d - 1] == "labels") print "H"; pos++; continue }
    if (c == "}" || c == "]") {
      if (c == "}" && PT[d] != "") { if (!SK[d] && !incode(d)) { s = PT[d]; sub(/\n$/, "", s); gsub(/\n/, "\nP ", s); print "P " s }; PT[d] = "" }
      if (--d < 0) exit 1; pos++; continue }
    if (c == ",") { if (T[d] == "{") EK[d] = 1; pos++; continue }
    pos++ }
  if (d != 0) exit 1 }
AWK

# gh issue create|new|edit — the command split into shell words and simple commands; gh must sit in
# command position (after VAR=value assignments and env/command/sudo/exec). A heredoc (<<X, <<'X', <<"X",
# <<-X) counts only outside quotes or inside a $( … ) — also one nested in double quotes (cs tracks it);
# a top-level body is skipped up to its terminator line, a body inside "$(cat <<'EOF' …)" becomes part
# of that word, so a --body heredoc is read as prose. One
# record per gh call; a call whose -R/--repo is not the tracker's owner/repo (-v repo) is dropped. The parse
# is heuristic: unbalanced quotes or substitutions, an unterminated heredoc, or a quote inside a $( … ) /
# backtick substitution (outside a heredoc body) mark every record "U", and so does a $ or backtick
# expansion in that call's --label/-l/--add-label/--title/--body/--repo value (a "$(cat <<'EOF' … EOF)"
# body excepted) — its violations only advise.
IFS= read -r -d '' GH_AWK <<'AWK' || true
function flush() { if (inw) { tok[++nt] = w; th[nt] = hwt; w = ""; inw = 0; hwt = 0 } }
function brk() { flush(); if (nt && tok[nt] != SEP) tok[++nt] = SEP }
function out(x) { rb = rb x "\n" }
function xv(k,   v, a, b) {  # token k is a flag value: any $ or backtick expansion outside a heredoc body → uncertain
  v = tok[k]
  if (th[k]) { a = index(v, "\n"); b = v; sub(/^.*\n/, "", b)
    if (substr(v, 1, a - 1) ~ /^\$\(cat[ \t]*$/ && b ~ /^[ \t]*\)$/) return v }
  if (index(v, "$") || index(v, "`")) ru = 1
  return v }
function xs(v) { if (index(v, "$") || index(v, "`")) ru = 1; return v }
function lab(v, tag,   p, q, j) { gsub(/[\n\t\r]/, " ", v); q = split(v, p, ","); for (j = 1; j <= q; j++) { gsub(/^[ \t]+|[ \t]+$/, "", p[j]); if (p[j] != "") out(tag " " p[j]) } }
function pr(v) { gsub(/\r/, "", v); gsub(/\n/, "\nP ", v); out("P " v) }
function here(i,   j, c, k, d, st) {  # a heredoc operator at i: queue its terminator, return the index to resume after
  j = i + 2; st = 0
  if (substr($0, j, 1) == "-") { st = 1; j++ }
  while (substr($0, j, 1) == " " || substr($0, j, 1) == "\t") j++
  c = substr($0, j, 1)
  if (c == "'" || c == "\"") { k = index(substr($0, j + 1), c); if (!k) return i; d = substr($0, j + 1, k - 1); j += k + 1 }
  else if (match(substr($0, j), /^[^ \t;&|()<>"'`\\]+/)) { d = substr($0, j, RLENGTH); j += RLENGTH }
  if (d == "") return i
  hd[++nh] = d; hs[nh] = st; hw[nh] = (q == 2); if (q == 2) hwt = 1   # inside "$(…)": the body is part of the current word
  return j - 1 }
function seg(s, e,   k, t, b, op, tag, rv) {
  k = s
  while (k <= e && (tok[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || tok[k] ~ /^(env|command|sudo|exec)$/)) k++
  if (k > e) return
  b = tok[k]; sub(/.*\//, "", b); if (b != "gh") return
  k++; if (k > e || tok[k] != "issue") return
  rv = ""; ru = 0
  for (k++; k <= e && tok[k] ~ /^-/; k++) {
    if (tok[k] == "-R" || tok[k] == "--repo") { rv = xv(k + 1); k++ }
    else if (tok[k] ~ /^--repo=/) rv = xs(substr(tok[k], 8))
    else if (tok[k] ~ /^-R./) rv = xs(substr(tok[k], 3)) }
  if (k > e) return
  if (tok[k] == "create" || tok[k] == "new") op = "create"; else if (tok[k] == "edit") op = "edit"; else return
  tag = op == "create" ? "L" : "A"; rb = ""
  out("R"); out("OP " op); out("E unknown"); if (op == "create") out("H")
  for (k++; k <= e; k++) { t = tok[k]
    if (t == "--label" || t == "-l" || t == "--add-label") { if (k < e) lab(xv(++k), tag); continue }
    if (t ~ /^--(add-)?label=/) { lab(xs(substr(t, index(t, "=") + 1)), tag); continue }
    if (t ~ /^-l./) { lab(xs(substr(t, 3)), tag); continue }
    if (t == "--title" || t == "-t" || t == "--body" || t == "-b") { if (k < e) pr(xv(++k)); continue }
    if (t ~ /^--(title|body)=/) { pr(xs(substr(t, index(t, "=") + 1))); continue }
    if (t ~ /^-[tb]./) { pr(xs(substr(t, 3))); continue }
    if (t == "-R" || t == "--repo") { if (k < e) rv = xv(++k); continue }
    if (t ~ /^--repo=/) { rv = xs(substr(t, 8)); continue }
    if (t ~ /^-R./) { rv = xs(substr(t, 3)); continue }
    if (t ~ /^(-a|--assignee|-m|--milestone|-p|--project|-T|--template|--recover|--remove-label|--add-assignee|--remove-assignee|--add-project|--remove-project|-F|--body-file)$/) k++ }
  if (rv != "") { rv = tolower(rv); sub(/^.*github\.com[\/:]/, "", rv); sub(/\.git$/, "", rv); if (repo == "" || rv != repo) return }
  if (sx[e + 1]) ru = 1   # the call runs into an unquoted substitution: a flag value may be in it
  if (unc || ru) out("U")
  printf "%s", rb }
BEGIN { SEP = "\001"; hi = 1 }
{ if (hi <= nh) { l = $0; if (hs[hi]) sub(/^\t+/, "", l); if (l == hd[hi]) hi++; else if (hw[hi]) w = w $0 "\n"; if (hi > nh) { nh = 0; hi = 1 }; next }
  L = length($0)
  for (i = 1; i <= L; i++) { c = substr($0, i, 1)
    if (!esc && (c == "'" || c == "\"") && (cs || ts || bt || cb)) unc = 1   # a quote inside a substitution: not certain
    if (esc) { esc = 0; w = w c; inw = 1 }
    else if (q == 1) { if (c == "'") q = 0; else w = w c }
    else if (c == "<" && substr($0, i, 2) == "<<" && substr($0, i + 2, 1) != "<" && (!q || cs)) { if (!q) flush(); i = here(i) }
    else if (q == 2) { if (c == "\\") esc = 1; else if (c == "\"") { q = 0; cs = 0; cb = 0 }
      else { if (c == "(" && substr(w, length(w), 1) == "$") cs++; else if (c == ")" && cs) cs--; else if (c == "`") cb = !cb; w = w c } }
    else if (c == "\\") { esc = 1; inw = 1 }
    else if (c == "'") { q = 1; inw = 1 }
    else if (c == "\"") { q = 2; inw = 1 }
    else if (c == " " || c == "\t" || c == "\r") flush()
    else if (c == "#" && !inw) break
    else if (index(";&|()`", c)) { o = 0; if (c == "(" && inw && substr(w, length(w), 1) == "$") { ts++; o = 1 } else if (c == ")" && ts) ts--; else if (c == "`") { bt = !bt; o = bt }
      brk(); if (o) sx[nt] = 1 }   # sx: this separator opens a substitution
    else { w = w c; inw = 1 } }
  if (esc) { esc = 0; if (w == "") inw = 0 }
  else if (q) w = w "\n"
  else brk() }
END { flush(); if (q || esc || ts || bt || hi <= nh) unc = 1   # unbalanced quotes or substitutions, an unterminated heredoc
  for (i = 1; i <= nt; i = j + 1) { for (j = i; j <= nt && tok[j] != SEP; j++); if (j > i) seg(i, j - 1) } }
AWK

# Local tracker file: frontmatter labels (inline [a, b] or a block list), children: → epic, title + body = prose
IFS= read -r -d '' LO_AWK <<'AWK' || true
function val(s) { sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); return s }
function item(s) { gsub(/^[ \t"']+|[ \t"']+$/, "", s); if (s != "") print "L " s }
{ sub(/\r$/, "") }
NR == 1 { if ($0 != "---") exit; fmo = 1; next }
fmo && $0 == "---" { fmo = 0; body = 1; next }
fmo {
  if (bl && $0 ~ /^[ \t]+-/) { s = $0; sub(/^[ \t]+-[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); if (bl == 1) item(s); else ep = 1; next }
  bl = 0
  if ($0 ~ /^labels:/) { print "H"; v = val($0); if (v == "") { bl = 1; next }
    gsub(/^\[|\][ \t]*$/, "", v); q = split(v, p, ","); for (j = 1; j <= q; j++) item(p[j]); next }
  if ($0 ~ /^children:/) { v = val($0); if (v == "") bl = 2; else if (v !~ /^\[[ \t]*\]$/) ep = 1; next }
  if ($0 ~ /^title:/) print "P " val($0)
  next }
body { print "P " $0 }
END { if (body) print "E " (ep ? "yes" : "no") }
AWK

# The registry's Dimensions table → "dim:v1,v2,…|…"; area:? for unresolved placeholders, milestone:* / release:* by pattern
IFS= read -r -d '' RG_AWK <<'AWK' || true
/^## / { ind = ($0 ~ /^## Dimensions/); next }
ind && /^\|/ { if (split($0, c, "|") < 5) next
  dm = c[2]; gsub(/[` \t]/, "", dm)
  if (dm ~ /^sev/) dm = "sev"; else if (dm ~ /^milestone:/) dm = "milestone"; else if (dm ~ /^release:/) dm = "release"; else sub(/:.*/, "", dm)
  if (dm !~ /^[a-z]+$/ || dm == "Dimension") next
  if (dm == "milestone" || dm == "release") { o = o "|" dm ":*"; next }
  v = c[4]; if (index(v, "{{")) { o = o "|" dm ":?"; next }
  gsub(/`/, "", v); while (match(v, /\([^()]*\)/)) v = substr(v, 1, RSTART - 1) " " substr(v, RSTART + RLENGTH)
  q = split(v, p, "\302\267"); l = ""
  for (j = 1; j <= q; j++) { sub(/^[ \t]+/, "", p[j]); split(p[j], w, /[ \t]+/); if (w[1] ~ /^[a-z0-9][a-z0-9-]*$/) l = l "," w[1] }
  o = o "|" dm ":" substr(l, 2) }
END { print substr(o, 2) }
AWK

# The checker: records ("R" … ) → "V<TAB>text" violations and "A<TAB>text" advisories, deduplicated
IFS= read -r -d '' CK_AWK <<'AWK' || true
function sv(x) { return (length(x) <= 40 && x ~ /^[A-Za-z0-9:._-]+$/) ? x : "<label>" }
function note(t, s) { if (t == "V" && un) { t = "A"; uh = 1 }   # an uncertain gh parse never denies
  if (!((t, s) in seen)) { seen[t, s] = 1; msg[++nm] = t "\t" s } }
function norm(f) { f = tolower(f); gsub(/\*\*|__|`/, "", f); sub(/^[ \t>*+#_-]+/, "", f); sub(/^[0-9]+[.)][ \t]*/, "", f); return f }
function prose(l,   q, p, j, f) {
  if (l ~ /^[ \t>]*(```|~~~)/) { fence = !fence; return }
  if (fence) return
  gsub(/`[^`]*`/, "", l)
  if (norm(l) ~ /^(severity|sev)[ \t]*[:=][ \t]*(sev[1-4](-[a-z]+)?|[1-4]|critical|high|medium|low)[ \t.]*$/) psv = 1
  q = split(l, p, /[.;!?][ \t]+/)
  for (j = 1; j <= q; j++) { f = norm(p[j])
    if (f ~ /^(t-shirt size|t-shirt|size)([ \t]*([:=-]|\342\200\224|\342\200\223)[ \t]*|[ \t]+)(xs|s|m|l|xl)([^a-z0-9]|$)/) psz = 1 } }
function fin(   i, x, dm, v, full, miss, n6, c6) {
  if (!rec) return
  full = (op == "create" || hf)
  for (i = 1; i <= nl; i++) { x = lb[i]; dm = ""; v = x
    if (x ~ /^sev[0-9]/) dm = "sev"; else if (index(x, ":") > 1) { dm = substr(x, 1, index(x, ":") - 1); v = substr(x, index(x, ":") + 1) }
    if (dm != "") has[dm] = 1
    if (dm == "type" && v == "bug") bug = 1
    if (!regok) continue
    if (dm == "" || !(dm in DIM)) { c6[++n6] = "A\tC6 label " sv(x) " has no registry dimension"; continue }
    if (dm == "milestone") { if (v !~ /^[a-z0-9][a-z0-9-]*$/) c6[++n6] = "V\tC6 label " sv(x) " is not a valid milestone:<slug>"; continue }
    if (dm == "release") { if (v !~ /^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$/) c6[++n6] = "V\tC6 label " sv(x) " is not a valid release:v<semver>"; continue }
    if ((dm in UNK) || ((dm, (dm == "sev" ? x : v)) in OK)) continue
    c6[++n6] = "V\tC6 label " sv(x) " is not a registry value of " (dm == "sev" ? "severity (sev1-critical..sev4-low)" : dm ":") }
  if (op == "create" && nl == 0) note(tm ? "A" : "V", "C1 a create with no labels — add one label per required dimension")
  else {
    if (full) { miss = ""
      if (!has["type"]) miss = miss " type:"; if (!has["area"]) miss = miss " area:"; if (!has["origin"]) miss = miss " origin:"
      if (miss != "") note(tm ? "A" : "V", "C2 missing required dimension(s):" miss)
      if (bug && !has["sev"]) note("V", "C3 type:bug without a severity label (sev1-critical..sev4-low)") }
    if ((op == "create" || (le && hf)) && !has["size"]) {
      if (ep == "no" && !le && !tm) note("V", "C4 a non-epic create without a size: label (xs..xl, set at filing)")
      else if (ep == "no") note("A", "C4 no size: label — every item except epics and milestones carries one, set at filing")
      else if (ep != "yes") note("A", "C4 no size: label — every item except epics and milestones carries one, set at filing") } }
  if (psz) note((full && !has["size"]) ? "V" : "A", (full && !has["size"]) ? "C5 the size is stated only in the title/description — move it to a size: label and delete the prose" : "C5 the title/description states the size — keep it only in the size: label and delete the prose")
  if (psv) note((full && !has["sev"]) ? "V" : "A", (full && !has["sev"]) ? "C5 the severity is stated only in the title/description — move it to a severity label and delete the prose" : "C5 the title/description states the severity — keep it only in the severity label and delete the prose")
  for (i = 1; i <= n6; i++) note(substr(c6[i], 1, 1), substr(c6[i], 3))
  if (uh) note("A", "the gh command could not be parsed with certainty (unbalanced quotes, an unterminated heredoc or a quote inside a substitution), so these findings only advise — check its labels yourself")
  rec = 0 }
BEGIN { q = split(reg, R, "|")
  for (i = 1; i <= q; i++) { c = index(R[i], ":"); if (!c) continue; dm = substr(R[i], 1, c - 1); v = substr(R[i], c + 1); DIM[dm] = 1
    if (v == "?") UNK[dm] = 1; else { r = split(v, W, ","); for (j = 1; j <= r; j++) OK[dm, W[j]] = 1 } }
  regok = ("type" in DIM) }
$0 == "R" { fin(); rec = 1; op = ""; ep = "unknown"; hf = 0; nl = 0; bug = 0; psz = 0; psv = 0; fence = 0; tm = 0; le = 0; un = 0; uh = 0; split("", has); split("", lseen); next }
$0 == "T" { tm = 1; next }
$0 == "U" { un = 1; next }
$0 == "S" { le = 1; next }
/^OP / { op = substr($0, 4); next }
/^E / { ep = substr($0, 3); next }
$0 == "H" { hf = 1; next }
/^[LA] / { x = substr($0, 3); if (x != "" && !(x in lseen)) { lseen[x] = 1; lb[++nl] = x }; next }
/^P / { prose(substr($0, 3)); next }
END { fin(); for (i = 1; i <= nm; i++) print msg[i] }
AWK

case "$kind" in
  mcp)
    w=$(printf '%s' "$MH_IN" | LC_ALL=C awk "$TW_AWK" 2>/dev/null) || exit 0
    jps=$(printf '%s\n' "$w" | sed -n 's/^J //p' | head -n 8)
    if [ -n "$jps" ]; then   # ADF passed as a JSON string: walk it as an object; not JSON → plain prose
      while IFS= read -r jp; do
        adf=$(printf '%s' "$MH_IN" | mh_get "tool_input.$jp") || continue
        if x=$(printf '{"tool_input":{"description":%s}}' "$adf" | LC_ALL=C awk "$TW_AWK" 2>/dev/null); then x=$(printf '%s\n' "$x" | grep '^P ')
        else x=$(printf '%s\n' "$adf" | sed 's/^/P /'); fi
        w="$w
$x"
      done <<EOF
$jps
EOF
    fi
    kv() { printf '%s\n' "$w" | sed -n "s/^K $1	//p" | head -n 1; }
    op=edit; ep=unknown
    case "$tool" in
      *__createJiraIssue|*__create_issue) op=create ;;
      *__save_issue) printf '%s\n' "$w" | grep -q '^K id	' || op=create ;;
      *__issue_write) [ "$(kv method)" = create ] && op=create ;;
    esac
    tm=""; printf '%s\n' "$w" | grep -q '^K template' && tm=T
    case "$tool" in *__createJiraIssue)
      case "$(kv issueTypeName | tr 'A-Z' 'a-z')" in epic) ep=yes ;; *) ep=no ;; esac ;;
    esac
    recs=$(printf 'R\nOP %s\nE %s\n%s\n%s\n' "$op" "$ep" "$tm" "$w") ;;
  gh) recs=$(printf '%s\n' "$src" | LC_ALL=C awk -v repo="$repo" "$GH_AWK" 2>/dev/null) || exit 0 ;;
  local) lo=$(printf '%s\n' "$src" | LC_ALL=C awk "$LO_AWK" 2>/dev/null) || exit 0
         case "$lo" in *"E "*) ;; *) exit 0 ;; esac
         f=$fp; case "$f" in /*) ;; *) f="$root/$f" ;; esac
         if [ -f "$f" ]; then recs=$(printf 'R\nOP edit\nS\n%s\n' "$lo")   # an existing item: an edit carrying its labels
         else recs=$(printf 'R\nOP create\nH\n%s\n' "$lo"); fi ;;
esac
[ -n "$recs" ] || exit 0

reg=""
rf="$root/.marvin/agents/label-syntax.md"
[ ! -L "$rf" ] && [ -f "$rf" ] && reg=$(head -c 65536 -- "$rf" 2>/dev/null | LC_ALL=C awk "$RG_AWK" 2>/dev/null)
res=$(printf '%s\n' "$recs" | LC_ALL=C awk -v reg="$reg" "$CK_AWK" 2>/dev/null) || exit 0
[ -n "$res" ] || exit 0
vio=$(printf '%s\n' "$res" | sed -n 's/^V	//p' | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')
adv=$(printf '%s\n' "$res" | sed -n 's/^A	//p' | awk '{ printf "%s%s", (NR > 1 ? "; " : ""), $0 }')
REF=".marvin/agents/label-syntax.md and .marvin/agents/ticket-filing.md"
if [ "$mode" = block ] && [ -n "$vio" ]; then
  out="Marvin ticket lint (ticket_lint: block) denied this tracker write — $vio."
  [ -n "$adv" ] && out="$out Also: $adv."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s Fix the labels per %s, then retry the write."}}\n' "$out" "$REF"
  exit 0
fi
all="$vio"; [ -n "$adv" ] && all="${all:+$all; }$adv"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"Marvin ticket lint (%s): %s. Fix the labels per the registry before the next tracker write."}}\n' "$REF" "$all"
exit 0
