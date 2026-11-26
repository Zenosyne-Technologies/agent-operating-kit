#!/usr/bin/env bash
# test-build-docs.sh — behavioural tests for scripts/lib/build_docs.py, the docs-site generator (AOS-299).
# AOS-300 pins the markdown subset renderer: headings with stable ids, inline markup, nested lists, tables, fences,
# blockquotes and rules; HTML in a source is escaped, never passed through; any construct outside the subset fails with
# file:line; a YAML header never leaks into a page; every real release note, upgrade note and the CHANGELOG renders;
# CRLF input renders byte-identically.
# AOS-301 adds the site build and the --check gate: pages wrapped in the shell, links relative from nested pages, the
# nav, determinism, stale/missing/orphan reporting that never touches docs/images|release-notes|decisions|superpowers|
# .nojekyll, CRLF sources, registry validation. Mutations at the end: each `# GUARD:<name>` line in the module is neutralised in a
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
OUT=$(python3 "$MOD" --bogus 2>&1); RC=$?; rc 2; has "usage"

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

# ---------------------------------------------------------------- site fixtures (AOS-301)
# mkrepo <dir>: a minimal repo tree - the real shell, a Home page and a nested concepts page - built into <dir>/docs.
mkrepo() {
  local d="$1"; rm -rf "$d"; mkdir -p "$d/site/assets" "$d/site/concepts"
  cp "$ROOT/site/_shell.html" "$d/site/_shell.html"
  printf 'body{}\n' > "$d/site/assets/site.css"; printf 'void 0;\n' > "$d/site/assets/site.js"
  printf '<h1>Home body</h1>\n' > "$d/site/index.html"
  printf '<h1>Lifecycle body</h1>\n' > "$d/site/concepts/x.html"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "concepts/x.html", "title": "Concept X", "section": "concepts", "order": 1, "source": "hand"}
]
JSON
}
sbuild() { python3 "$MOD" --root "$1" >/dev/null 2>&1; }          # sbuild <repo>: plain build
scheck() { OUT=$(python3 "$MOD" --root "$1" --check 2>&1); RC=$?; } # scheck <repo>: sets OUT, RC
fx_stale() {
  local d="$WORK/fx-stale"; mkrepo "$d"; sbuild "$d" || return 1
  printf '<h1>Changed</h1>\n' > "$d/site/index.html"
  scheck "$d"; [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -Fq 'STALE docs/index.html'
}
fx_missing() {
  local d="$WORK/fx-missing"; mkrepo "$d"; sbuild "$d" || return 1
  rm "$d/docs/concepts/x.html"
  scheck "$d"; [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -Fq 'MISSING docs/concepts/x.html'
}
fx_orphan() {
  local d="$WORK/fx-orphan"; mkrepo "$d"; sbuild "$d" || return 1
  printf 'x' > "$d/docs/old.html"; mkdir -p "$d/docs/assets/fonts"; printf 'x' > "$d/docs/assets/fonts/OFL.txt"
  scheck "$d"; [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -Fq 'ORPHAN docs/old.html' && printf '%s' "$OUT" | grep -Fq 'ORPHAN docs/assets/fonts/OFL.txt'
}
fx_abs_link() {
  local d="$WORK/fx-abs"; mkrepo "$d"
  printf '<p><a href="/elsewhere.html">x</a></p>\n' > "$d/site/index.html"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ] || return 1
  printf '<img src="/a.png" alt="">\n' > "$d/site/index.html"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_registry_dup() {
  local d="$WORK/fx-dup"; mkrepo "$d"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "index.html", "title": "Again", "section": "home", "order": 1, "source": "hand"}
]
JSON
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_registry_section() {
  local d="$WORK/fx-sec"; mkrepo "$d"
  sed -i.bak 's/"section": "concepts"/"section": "nonsense"/' "$d/site/pages.json"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_registry_protected() {
  local d="$WORK/fx-prot" p
  for p in images/keep.png release-notes/v1.html decisions/d.html superpowers/s.html .nojekyll; do
    mkrepo "$d"; mkdir -p "$d/docs/$(dirname "$p")" "$d/site/$(dirname "$p")"
    printf 'keep' > "$d/docs/$p"; printf '<p>x</p>\n' > "$d/site/$p"
    cat > "$d/site/pages.json" <<JSON
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "$p", "title": "P", "section": "concepts", "order": 1, "source": "hand"}
]
JSON
    python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ] || return 1
    [ "$(cat "$d/docs/$p")" = keep ] || return 1
  done
}
# fx_path_bypass: aliases of a protected path (dot segment, other case) and a generator path with '..' all exit 2 and leave
# the protected file alone. Registry entries go through the CLI; generator paths through the module, as build() calls it.
fx_path_bypass() {
  local d="$WORK/fx-bypass" p
  for p in ./images/keep.png Images/keep.png IMAGES/keep.png ./.nojekyll .NOJEKYLL a/../images/keep.png images//keep.png 'x\\y.html' /abs.html C:/x.html; do
    mkrepo "$d"; mkdir -p "$d/docs/images"; printf 'keep' > "$d/docs/images/keep.png"; printf 'keep' > "$d/docs/.nojekyll"
    mkdir -p "$d/site/images"; printf '<p>x</p>\n' > "$d/site/images/keep.png"; printf '<p>x</p>\n' > "$d/site/Images.html"
    cat > "$d/site/pages.json" <<JSON
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "$p", "title": "P", "section": "concepts", "order": 1, "source": "hand"}
]
JSON
    python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ] || return 1
    [ "$(cat "$d/docs/images/keep.png")" = keep ] && [ "$(cat "$d/docs/.nojekyll")" = keep ] || return 1
  done
  for p in a/../images/keep.png ./images/keep.png Images/keep.png ./.nojekyll; do
    mkrepo "$d"; mkdir -p "$d/docs/images"; printf 'keep' > "$d/docs/images/keep.png"; printf 'keep' > "$d/docs/.nojekyll"
    cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "gen", "title": "G", "section": "concepts", "order": 1, "source": "generated:t"}
]
JSON
    PYTHONDONTWRITEBYTECODE=1 python3 -c "
import sys; from pathlib import Path; sys.path.insert(0, sys.argv[1]); import build_docs as b
b.GENERATORS['t'] = lambda root: {sys.argv[3]: ('T', '<p>x</p>')}
try: b.build(Path(sys.argv[2]), Path(sys.argv[2]) / 'docs')
except b.BuildError: sys.exit(2)
" "$(dirname "$MOD")" "$d" "$p" >/dev/null 2>&1; [ "$?" = 2 ] || return 1
    [ "$(cat "$d/docs/images/keep.png")" = keep ] && [ "$(cat "$d/docs/.nojekyll")" = keep ] || return 1
  done
}

hd "build: wraps pages"
R="$WORK/r1"; mkrepo "$R"; python3 "$MOD" --root "$R" >/dev/null 2>&1; RC=$?; rc 0
OUT=$(cat "$R/docs/index.html"); has '<!doctype html>'; has '<html lang="en">'; has '<title>Home - Marvin</title>'; has '<h1>Home body</h1>'
has '<main id="main">'; has 'class="skip-link"'; has 'href="assets/site.css"'; has 'src="assets/site.js"'; lacks '{{'
[ -f "$R/docs/assets/site.css" ] && ok "assets copied" || bad "assets not copied"

hd "build: links relative from nested pages"
OUT=$(cat "$R/docs/concepts/x.html"); has 'href="../assets/site.css"'; has 'src="../assets/site.js"'; has 'href="../index.html"'; has '<h1>Lifecycle body</h1>'
if grep -rqE '(href|src)="/' "$R/docs"; then bad "a root-absolute href/src in the output"; else ok "no root-absolute href/src anywhere"; fi
fx_abs_link && ok "a root-absolute link in a source is a BuildError (exit 2)" || bad "fx_abs_link"

hd "build: nav active"
OUT=$(cat "$R/docs/index.html"); has '<a href="index.html" aria-current="page">Home</a>'; has '<a href="concepts/x.html">Concepts</a>'; lacks 'Settings'
OUT=$(cat "$R/docs/concepts/x.html"); has '<a href="../concepts/x.html" aria-current="page">Concepts</a>'; has '<a href="../index.html">Home</a>'
has '<aside class="sidebar">'; has '<li><a href="../concepts/x.html" aria-current="page">Concept X</a></li>'
OUT=$(cat "$R/docs/index.html"); lacks '<aside'

hd "build: deterministic"
cp -R "$R/docs" "$WORK/r1-first"; sbuild "$R"
diff -r "$WORK/r1-first" "$R/docs" >/dev/null && ok "two builds are byte-identical" || bad "builds differ"
grep -rq $'\r' "$R/docs" && bad "CR in output" || ok "output is LF only"

hd "check: fresh"
scheck "$R"; rc 0

hd "check: stale"
fx_stale && ok "an edited source reports STALE (exit 1)" || bad "fx_stale"

hd "check: missing"
fx_missing && ok "a deleted output reports MISSING (exit 1)" || bad "fx_missing"

hd "check: orphan output"
fx_orphan && ok "an output the build does not write reports ORPHAN (exit 1)" || bad "fx_orphan"
R2="$WORK/r2"; mkrepo "$R2"; sbuild "$R2"
mkdir -p "$R2/docs/images/f" "$R2/docs/release-notes" "$R2/docs/decisions" "$R2/docs/superpowers/specs"
for f in images/f/a.png release-notes/v1.md decisions/d.md superpowers/specs/s.md .nojekyll; do printf 'keep' > "$R2/docs/$f"; done
scheck "$R2"; rc 0; lacks ORPHAN
sbuild "$R2"; printf 'x' > "$R2/docs/old.html"; sbuild "$R2"
[ ! -e "$R2/docs/old.html" ] && ok "a plain build removes its own stale output" || bad "old.html survived a build"
n=0; for f in images/f/a.png release-notes/v1.md decisions/d.md superpowers/specs/s.md .nojekyll; do [ "$(cat "$R2/docs/$f" 2>/dev/null)" = keep ] && n=$((n+1)); done
[ "$n" = 5 ] && ok "protected paths are never written or removed" || bad "protected paths touched ($n/5 intact)"

hd "check: crlf input"
R3="$WORK/r3"; mkrepo "$R3"; sbuild "$R3"
for f in site/_shell.html site/index.html site/concepts/x.html site/pages.json site/assets/site.css; do sed 's/$/\r/' "$R3/$f" > "$R3/$f.tmp"; mv "$R3/$f.tmp" "$R3/$f"; done
scheck "$R3"; rc 0

hd "registry: duplicate path"
fx_registry_dup && ok "a duplicate path exits 2" || bad "fx_registry_dup"
hd "registry: protected path"
fx_registry_protected && ok "an entry under a protected docs/ path exits 2 and the file is untouched" || bad "fx_registry_protected"
fx_path_bypass && ok "dot-segment, case-aliased, '..', backslash and absolute output paths exit 2, protected files untouched" || bad "fx_path_bypass"
hd "registry: unknown section"
fx_registry_section && ok "an unknown section exits 2" || bad "fx_registry_section"
R4="$WORK/r4"; mkrepo "$R4"; sed -i.bak 's/"source": "hand"}$/"source": "generated:nope"}/' "$R4/site/pages.json"
OUT=$(python3 "$MOD" --root "$R4" 2>&1); RC=$?; rc 2; has "no generator named 'nope'"
R5="$WORK/r5"; mkrepo "$R5"; rm "$R5/site/concepts/x.html"
OUT=$(python3 "$MOD" --root "$R5" 2>&1); RC=$?; rc 2; has 'x.html'

hd "site: the real repo is fresh and hand sources name no model"
OUT=$(python3 "$MOD" --check 2>&1); RC=$?; rc 0
if grep -rniE '\b(opus|sonnet|haiku|fable|gpt-[0-9])' "$ROOT/site" --include='*.html' --include='*.json' --include='*.md' -l >/dev/null 2>&1; then bad "a model name is hand-typed in site/"; else ok "no model name in site/"; fi

# ---------------------------------------------------------------- mutations
# Every guard is neutralised in a copy of the module, and its named fixture must then FAIL. A mutation the suite
# survives is a hole, not a pass. Later tasks append "guard-name:fixture_function" pairs.
MUTATIONS=(
  "md-unknown:fx_md_unknown"
  "md-raw-html:fx_md_raw_html"
  "md-link-scheme:fx_md_link_scheme"
  "md-header-leak:fx_md_header_leak"
  "stale:fx_stale"
  "missing:fx_missing"
  "orphan-output:fx_orphan"
  "abs-link:fx_abs_link"
  "registry-dup:fx_registry_dup"
  "registry-section:fx_registry_section"
  "registry-protected:fx_registry_protected"
  "path-shape:fx_path_bypass"
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
