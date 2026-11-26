#!/usr/bin/env bash
# test-build-docs.sh — behavioural tests for scripts/lib/build_docs.py, the docs-site generator (AOS-299).
# AOS-300 pins the markdown subset renderer: headings with stable ids, inline markup, nested lists, tables, fences,
# blockquotes and rules; HTML in a source is escaped, never passed through; any construct outside the subset fails with
# file:line; a YAML header never leaks into a page; every real release note, upgrade note and the CHANGELOG renders;
# CRLF input renders byte-identically. Mutations at the end: each `# GUARD:<name>` line in the module is neutralised in a
# copy and the named fixture must then FAIL. Later tasks append `name:fixture` pairs to MUTATIONS.
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd); ROOT="$SCRIPT_DIR/.."
MODULE="$SCRIPT_DIR/lib/build_docs.py"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/marvin-docstest.XXXXXX") || { echo "FATAL: mktemp" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
PASSED=0; FAILED=0; CURRENT=""; OUT=""; RC=0
hd()  { CURRENT="$1"; printf '\n== %s\n' "$1"; }
ok()  { PASSED=$((PASSED+1)); printf '   ok    %s\n' "$1"; }
bad() { FAILED=$((FAILED+1)); printf '   FAIL  [%s] %s\n' "$CURRENT" "$1"; }
rc()  { if [ "$RC" = "$1" ]; then ok "exit $1"; else bad "exit $RC, want $1 ($OUT)"; fi; }
has() { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then ok "has: $1"; else bad "missing: $1 (got: $OUT)"; fi; }
lacks() { if printf '%s\n' "$OUT" | grep -Fq -- "$1"; then bad "unexpected: $1"; else ok "lacks: $1"; fi; }

MOD="$MODULE"   # the module under test; the mutation block repoints it at a mutated copy
# render <markdown text>: writes it to a fixture file, renders it, OUT = stdout+stderr, RC = exit code
render() { printf '%s' "$1" > "$WORK/in.md"; OUT=$(python3 "$MOD" --render "$WORK/in.md" 2>&1); RC=$?; }
# rcode <markdown text> -> prints the exit code only (for fixtures that need several inputs)
rcode() { printf '%s' "$1" > "$WORK/in.md"; python3 "$MOD" --render "$WORK/in.md" >/dev/null 2>&1; echo $?; }

# ---------------------------------------------------------------- fixtures (reused by the mutation block)
# Each fixture returns 0 when the behaviour holds against $MOD. A mutated copy of a guard must make it return non-zero.
fx_md_unknown() {
  local t
  for t in $'* star bullet\n' $'    indented code\n' $'Title\n=====\n' $'![img](a.png)\n' $'[ref]: http://x\n' \
           $'```\nnever closed\n' $'| a | b |\nno alignment row here\n' \
           $'| a |\n|---|\n| x | y | z |\n'; do
    [ "$(rcode "$t")" = 2 ] || return 1
  done
}
fx_md_raw_html() {
  local t
  for t in $'<div>\nx\n</div>\n' $'<details>\n<summary>s</summary>\n</details>\n' $'<!-- c -->\n'; do
    [ "$(rcode "$t")" = 2 ] || return 1
  done
}
fx_md_link_scheme() {
  local t
  for t in $'[x](javascript:alert(1))\n' $'[x](JavaScript:alert(1))\n' $'[x](data:text/html,a)\n' \
           $'[x](java\x01script:alert(1))\n' $'[x](javascript\x7f:a)\n' $'[x](file:///etc/passwd)\n' $'[x](ftp://h/f)\n' \
           $'[x](vbscript:a)\n'; do
    [ "$(rcode "$t")" = 2 ] || return 1
  done
}
fx_md_header_leak() {
  # an opening --- that is not the very first line is a rule, not a header: its keys must not reach the page
  [ "$(rcode $'\n---\ndoc: x\nsummary: y\n---\n\n# T\n')" = 2 ] || return 1
  # an unclosed header leaks too
  [ "$(rcode $'---\ndoc: x\nsummary: y\n\n# T\n')" = 2 ] || return 1
}

# ---------------------------------------------------------------- tests
hd "render: headings"
render $'# A\n\n### B\n\n## A\n\n## A\n'
rc 0; has '<h1 id="a">A</h1>'; has '<h3 id="b">B</h3>'; has '<h2 id="a-2">A</h2>'; has '<h2 id="a-3">A</h2>'
render $'## v0.43.0 — Fable: **bold** `code`\n'; has 'id="v0-43-0-fable-bold-code"'

hd "render: inline"
render $'**b** *i* `c` [t](u)\n'
rc 0; has '<p><strong>b</strong> <em>i</em> <code>c</code> <a href="u">t</a></p>'
render $'a snake_case_name and _em_ and __strong__ and 2*3\n'; has 'snake_case_name'; has '<em>em</em>'; has '<strong>strong</strong>'
render $'[a **b** `c`](https://x.y/z?a=1&b=2 "T")\n'; has '<a href="https://x.y/z?a=1&amp;b=2" title="T">a <strong>b</strong> <code>c</code></a>'
render $'`` a ` b `` and \\*not em\\*\n'; has '<code>a ` b</code>'; has '*not em*'
render $'one\ntwo wrapped\n'; has $'<p>one\ntwo wrapped</p>'

hd "render: lists"
render $'- a\n  wrapped on\n  - nested 1\n  - nested 2\n    1. deep\n- b\n\n1. one\n2. two\n   - under two\n'
rc 0
has $'<ul>\n<li>a\nwrapped on\n<ul>\n<li>nested 1</li>'; has '<li>nested 2'; has '<ol>'; has '<li>deep</li>'
has '<li>b</li>'; has '<li>two'; has '<li>under two</li>'
render $'3. three\n4. four\n'; has '<ol start="3">'
render $'- a\n\n  second para\n- b\n'; has '<li><p>a</p>'; has '<p>second para</p>'
render $'text\n- directly after\n'; has $'<p>text</p>\n<ul>'

hd "render: table"
render $'| a | b \\| c | d |\n|:--|:-:|--:|\n| 1 | `x\\|y` | 3 |\n| only |\n'
rc 0; has '<table>'; has '<thead>'; has '<tbody>'; has '<th class="align-left">a</th>'; has '<th class="align-center">b | c</th>'
has '<td class="align-right">3</td>'; has '<td class="align-center"><code>x|y</code></td>'; has '<td class="align-left">only</td>'
render $'a | b\n--|--\n1 | 2\n\nafter\n'; has '<th>a</th>'; has '<td>2</td>'; has '<p>after</p>'

hd "render: fences"
render $'```bash\n<x> & {{Y}}\n  keep   spacing\n\n- not a list\n```\n~~~\nplain\n~~~\n'
rc 0; has '<pre><code class="lang-bash">&lt;x&gt; &amp; {{Y}}'; has '  keep   spacing'; has '- not a list'; has '<pre><code>plain'
lacks '<ul>'

hd "render: blockquote, hr"
render $'> quoted **b**\n> second\n\n---\n\n***\n'
rc 0; has '<blockquote>'; has '<strong>b</strong>'; has '</blockquote>'; has '<hr>'
[ "$(printf '%s\n' "$OUT" | grep -c '^<hr>$')" = 2 ] && ok "two rules" || bad "want two <hr>: $OUT"

hd "render: escaping"
render $'<b>&{{X}}≤ 🚀\n'
rc 0; has '&lt;b&gt;&amp;{{X}}≤ 🚀'; lacks '<b>'
render $'a <script>x</script> b <https://x.y> c\n'; lacks '<script>'; has '&lt;script&gt;'
render $'- <i>x</i> in a list\n'; has '&lt;i&gt;x&lt;/i&gt;'
render $'[<b>t</b>](u "<i>")\n'; lacks '<b>'; has '&lt;b&gt;t&lt;/b&gt;'

hd "render: unknown construct"
printf '%s\n' '# T' '' '<div>' 'x' '</div>' > "$WORK/div.md"
OUT=$(python3 "$MOD" --render "$WORK/div.md" 2>&1); RC=$?; rc 2; has "$WORK/div.md:3:"
printf '%s\n' 'intro' '' '<details>' '<summary>s</summary>' '</details>' > "$WORK/det.md"
OUT=$(python3 "$MOD" --render "$WORK/det.md" 2>&1); RC=$?; rc 2; has "$WORK/det.md:3:"
render $'* star\n'; rc 2; has 'in.md:1:'; has "use '-'"
render $'ok\n\n    indented\n'; rc 2; has 'in.md:3:'
render $'Title\n===\n'; rc 2; has 'setext'
render $'x ![a](b.png) y\n'; rc 2; has 'images'
render $'[x](javascript:alert(1))\n'; rc 2; has 'scheme'
fx_md_unknown && ok "every unclassifiable construct exits 2" || bad "fx_md_unknown"
fx_md_raw_html && ok "block-level HTML exits 2" || bad "fx_md_raw_html"
fx_md_link_scheme && ok "unsafe link schemes exit 2" || bad "fx_md_link_scheme"
printf '%s\n' 'x' > "$WORK/none-ok.md"
OUT=$(python3 "$MOD" --render "$WORK/missing.md" 2>&1); RC=$?; rc 2
OUT=$(python3 "$MOD" 2>&1); RC=$?; rc 2; has "usage"

hd "render: line numbers survive a stripped header"
printf '%s\n' '---' 'doc: x' 'summary: y' '---' '' '# T' '' '<div>' > "$WORK/ln.md"
OUT=$(python3 "$MOD" --render "$WORK/ln.md" 2>&1); RC=$?; rc 2; has "$WORK/ln.md:8:"

hd "render: header stripped"
printf '%s\n' '---' 'doc: v9 note' 'type: release-note' 'summary: a long summary' 'keywords: [a, b]' 'scope: [AOS-1]' '---' '' '# Body' '' 'text' > "$WORK/hdr.md"
OUT=$(python3 "$MOD" --render "$WORK/hdr.md" 2>&1); RC=$?
rc 0; lacks 'doc:'; lacks 'summary:'; lacks '<hr>'; has '<h1 id="body">Body</h1>'
printf '%s\n' 'intro' '' '---' '' 'after the rule' > "$WORK/rule.md"
OUT=$(python3 "$MOD" --render "$WORK/rule.md" 2>&1); RC=$?; rc 0; has '<hr>'
printf '%s\n' '---' '' 'a rule first, then prose' '' '---' > "$WORK/rule2.md"
OUT=$(python3 "$MOD" --render "$WORK/rule2.md" 2>&1); RC=$?; rc 0; has 'a rule first'
PYC='import sys; sys.path.insert(0, sys.argv[1]); import build_docs as b'
OUT=$(python3 -c "$PYC
print(b.split_front_matter('---\ndoc: a\nsummary: b: c\n---\nbody\n'))
print(b.split_front_matter('no header\n'))
print(b.split_front_matter('---\nprose\n---\nx\n'))" "$(dirname "$MOD")" 2>&1)
has "({'doc': 'a', 'summary': 'b: c'}, 'body\n')"; has "({}, 'no header\n')"; has "({}, '---\nprose\n---\nx\n')"

hd "render: header leak"
fx_md_header_leak && ok "a header that is not first, or unclosed, is refused" || bad "fx_md_header_leak"
render $'```\ndoc: example of a header line\n```\n'; rc 0; has 'doc: example'

hd "render: every real source"
for f in "$ROOT"/docs/release-notes/*.md "$ROOT"/upgrades/*.md "$ROOT/CHANGELOG.md"; do
  OUT=$(python3 "$MOD" --render "$f" 2>&1 >/dev/null); RC=$?
  if [ "$RC" = 0 ]; then PASSED=$((PASSED+1)); else bad "$(basename "$f"): $OUT"; fi
done
n=$(ls "$ROOT"/docs/release-notes/*.md "$ROOT"/upgrades/*.md | wc -l | tr -d ' ')
[ "$n" -ge 40 ] && ok "rendered $n notes plus CHANGELOG.md" || bad "only $n real sources found"
OUT=$(python3 "$MOD" --render "$ROOT/CHANGELOG.md" 2>&1); has '<h2 id="0-43-0-2026-11-26">'; lacks 'doc:'

hd "render: crlf"
printf '%s\n' '---' 'doc: x' '---' '' '# T' '' '- a' '  - b' '' '| h | i |' '|---|---|' '| 1 | 2 |' '' '```' 'code' '```' > "$WORK/lf.md"
sed 's/$/\r/' "$WORK/lf.md" > "$WORK/crlf.md"; tr '\n' '\r' < "$WORK/lf.md" > "$WORK/cr.md"
python3 "$MOD" --render "$WORK/lf.md" > "$WORK/lf.out" 2>&1; python3 "$MOD" --render "$WORK/crlf.md" > "$WORK/crlf.out" 2>&1
python3 "$MOD" --render "$WORK/cr.md" > "$WORK/cr.out" 2>&1
cmp -s "$WORK/lf.out" "$WORK/crlf.out" && ok "CRLF output is byte-identical" || bad "CRLF differs"
cmp -s "$WORK/lf.out" "$WORK/cr.out" && ok "lone CR output is byte-identical" || bad "CR differs"
grep -q $'\r' "$WORK/crlf.out" && bad "CR in output" || ok "output is LF only"
python3 "$MOD" --render "$WORK/lf.md" > "$WORK/lf.out2"; python3 "$MOD" --render "$WORK/lf.md" > "$WORK/lf.out3"
cmp -s "$WORK/lf.out2" "$WORK/lf.out3" && ok "deterministic" || bad "two runs differ"

# ---------------------------------------------------------------- mutations
# Every guard is neutralised in a copy of the module, and its named fixture must then FAIL. A mutation the suite
# survives is a hole, not a pass. Later tasks append "guard-name:fixture_function" pairs.
MUTATIONS=(
  "md-unknown:fx_md_unknown"
  "md-raw-html:fx_md_raw_html"
  "md-link-scheme:fx_md_link_scheme"
  "md-header-leak:fx_md_header_leak"
)
mutate() {  # mutate <guard> <fixture>
  local g="$1" fx="$2" d="$WORK/mut-$1"
  mkdir -p "$d"
  local n; n=$(grep -cE "# GUARD:$g[[:space:]]*\$" "$MODULE")
  [ "$n" -ge 1 ] || { bad "guard '$g' has no marker in the module"; return; }
  sed -E "s/^([[:space:]]*).*# GUARD:$g[[:space:]]*\$/\1pass  # mutated/" "$MODULE" > "$d/build_docs.py"
  grep -qE "# GUARD:$g[[:space:]]*\$" "$d/build_docs.py" && { bad "mutation of '$g' did not apply"; return; }
  MOD="$d/build_docs.py"
  if "$fx" >/dev/null 2>&1; then bad "mutation survived: $g ($fx still passes)"; else ok "mutation caught: $g"; fi
  MOD="$MODULE"
}
for pair in "${MUTATIONS[@]}"; do hd "M ${pair%%:*} reverted — ${pair##*:} must fail"; mutate "${pair%%:*}" "${pair##*:}"; done
# every guard in the module must be listed above (a new guard without a mutation row is a hole)
hd "M every GUARD marker has a mutation row"
for g in $(grep -oE '# GUARD:[a-z0-9-]+' "$MODULE" | sed 's/# GUARD://' | sort -u); do
  case " ${MUTATIONS[*]} " in *" $g:"*) ok "listed: $g";; *) bad "guard '$g' has no mutation row";; esac
done

printf '\n----\ntest-build-docs: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
