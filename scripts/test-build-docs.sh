#!/usr/bin/env bash
# test-build-docs.sh — behavioural tests for scripts/lib/build_docs.py, the docs-site generator (AOS-299).
# AOS-300 pins the markdown subset renderer: headings with stable ids, inline markup, nested lists, tables, fences,
# blockquotes and rules; HTML in a source is escaped, never passed through; any construct outside the subset fails with
# file:line; a YAML header never leaks into a page; every real release note, upgrade note and the CHANGELOG renders;
# CRLF input renders byte-identically.
# AOS-306 adds the concept pages: tier marking, the inspector's data, the old-anchor redirect, the sidebar's in-page headings.
# AOS-307 adds Home (links, the 30-second map, the wireframe grid), Getting started, the slim README (its anchors,
# suite list and counts), rules 8/10/11 naming the site in CLAUDE.md and AGENTS.md, and the widened marketplace scan.
# AOS-305 adds the rule-11 galleries (docs/images/<feature>/captions.md -> a See it in Claude Code section, inline shot markers) and the Mods page.
# AOS-301 adds the site build and the --check gate: pages wrapped in the shell, links relative from nested pages, the
# nav, determinism, stale/missing/orphan reporting that never touches docs/images|release-notes|decisions|superpowers|
# .nojekyll, CRLF sources, registry validation. The whole-branch review adds: OS metadata ignored, a build that prunes
# only its own output and fails on any other orphan, every page reachable, the registry schema, wrapped settings bullets
# and unparseable CHANGELOG headings failing loud. Mutations at the end: each `# GUARD:<name>` line in the module is neutralised in a
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
  for p in images/README.md release-notes/v1.html decisions/d.html superpowers/s.html .nojekyll; do
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
  for p in ./images/README.md Images/README.md IMAGES/README.md ./.nojekyll .NOJEKYLL a/../images/README.md images//README.md 'x\\y.html' /abs.html C:/x.html; do
    mkrepo "$d"; mkdir -p "$d/docs/images"; printf 'keep' > "$d/docs/images/README.md"; printf 'keep' > "$d/docs/.nojekyll"
    mkdir -p "$d/site/images"; printf '<p>x</p>\n' > "$d/site/images/README.md"; printf '<p>x</p>\n' > "$d/site/Images.html"
    cat > "$d/site/pages.json" <<JSON
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "$p", "title": "P", "section": "concepts", "order": 1, "source": "hand"}
]
JSON
    python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ] || return 1
    [ "$(cat "$d/docs/images/README.md")" = keep ] && [ "$(cat "$d/docs/.nojekyll")" = keep ] || return 1
  done
  for p in a/../images/README.md ./images/README.md Images/README.md ./.nojekyll; do
    mkrepo "$d"; mkdir -p "$d/docs/images"; printf 'keep' > "$d/docs/images/README.md"; printf 'keep' > "$d/docs/.nojekyll"
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
    [ "$(cat "$d/docs/images/README.md")" = keep ] && [ "$(cat "$d/docs/.nojekyll")" = keep ] || return 1
  done
}

# fx_build_orphan: a stale page carrying the shell's generator meta and a stale docs/assets/ file are owned, so a plain
# build removes them and prints `removed docs/<rel>`; docs/CNAME and docs/robots.txt are not, so they survive, are
# printed as ORPHAN and the build exits 1. A rebuild with them gone is clean again.
fx_build_orphan() {
  local d="$WORK/fx-borph"; mkrepo "$d"; sbuild "$d" || return 1
  cp "$d/docs/concepts/x.html" "$d/docs/concepts/old.html"; printf 'x' > "$d/docs/assets/old.css"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 0 ] || return 1
  printf '%s' "$OUT" | grep -Fq 'removed docs/concepts/old.html' && printf '%s' "$OUT" | grep -Fq 'removed docs/assets/old.css' || return 1
  [ ! -e "$d/docs/concepts/old.html" ] && [ ! -e "$d/docs/assets/old.css" ] || return 1
  printf 'docs.example.com\n' > "$d/docs/CNAME"; printf 'User-agent: *\n' > "$d/docs/robots.txt"; printf '<p>hand</p>\n' > "$d/docs/hand.html"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 1 ] || return 1
  printf '%s' "$OUT" | grep -Fq 'ORPHAN docs/CNAME' && printf '%s' "$OUT" | grep -Fq 'ORPHAN docs/robots.txt' && printf '%s' "$OUT" | grep -Fq 'ORPHAN docs/hand.html' || return 1
  [ -f "$d/docs/CNAME" ] && [ -f "$d/docs/robots.txt" ] && [ -f "$d/docs/hand.html" ] || return 1
  rm "$d/docs/CNAME" "$d/docs/robots.txt" "$d/docs/hand.html"; sbuild "$d"
}
# fx_os_junk: .DS_Store / Thumbs.db / desktop.ini / ._* under docs/, docs/assets/, docs/images/ and a feature folder (and
# under site/assets/) are not content: --check and a build both exit 0, nothing is deleted, nothing junk is published.
fx_os_junk() {
  local d="$WORK/fx-junk" f; mkrepo "$d"; mkdir -p "$d/site/mods" "$d/docs/images/demo"
  printf '<h1>Demo</h1>\n' > "$d/site/mods/demo.html"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "mods/demo.html", "title": "Demo", "section": "mods", "order": 0, "source": "hand", "feature": "demo"}
]
JSON
  sbuild "$d" || return 1
  for f in .DS_Store Thumbs.db desktop.ini ._index.html assets/.DS_Store images/.DS_Store images/demo/.DS_Store images/demo/._x.png images/demo/Thumbs.db; do printf 'junk' > "$d/docs/$f"; done
  printf 'junk' > "$d/site/assets/.DS_Store"; printf 'junk' > "$d/site/assets/._site.css"
  scheck "$d"; [ "$RC" = 0 ] || return 1
  sbuild "$d" || return 1
  for f in .DS_Store Thumbs.db desktop.ini ._index.html assets/.DS_Store images/.DS_Store images/demo/.DS_Store images/demo/._x.png images/demo/Thumbs.db; do [ "$(cat "$d/docs/$f" 2>/dev/null)" = junk ] || return 1; done
  [ ! -e "$d/docs/assets/._site.css" ]
}
# fx_unreachable: a registered page nothing links to (not in the nav, not in a sidebar section, not linked from a body)
# fails the build naming it; linking it from Home makes it reachable.
fx_unreachable() {
  local d="$WORK/fx-unreach"; mkrepo "$d"; printf '<h1>Other</h1>\n' > "$d/site/other.html"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "concepts/x.html", "title": "Concept X", "section": "concepts", "order": 1, "source": "hand"},
  {"path": "other.html", "title": "Other", "section": "home", "order": 5, "source": "hand"}
]
JSON
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'other.html: no other page links to it' || return 1
  printf '<h1>Home</h1>\n<p><a href="other.html#top">other</a></p>\n' > "$d/site/index.html"
  sbuild "$d"
}
# regfail <name> <pages.json text> <message>: the registry exits 2 with that message (each schema guard has its own).
regfail() {
  local d="$WORK/fx-reg-$1"; mkrepo "$d"; printf '%s\n' "$2" > "$d/site/pages.json"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq -- "$3"
}
REG_HOME='{"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"}'
fx_registry_json() { regfail json '[{"path": ' 'site/pages.json: '; }
fx_registry_list() { regfail list '{"path": "index.html"}' 'top level must be a list'; }
fx_registry_entry() { regfail entry "[$REG_HOME, \"concepts/x.html\"]" 'site/pages.json[1]: entry must be an object'; }
fx_registry_key() { regfail key "[$REG_HOME, {\"path\": \"concepts/x.html\", \"title\": \"X\", \"section\": \"concepts\", \"source\": \"hand\"}]" "site/pages.json[1]: missing 'order'"; }
fx_registry_types() {
  regfail types "[$REG_HOME, {\"path\": \"concepts/x.html\", \"title\": 7, \"section\": \"concepts\", \"order\": 1, \"source\": \"hand\"}]" 'must be non-empty strings and order an integer' || return 1
  regfail types "[$REG_HOME, {\"path\": \"concepts/x.html\", \"title\": \"X\", \"section\": \"concepts\", \"order\": \"1\", \"source\": \"hand\"}]" 'must be non-empty strings and order an integer'
}
fx_registry_path() { regfail path "[$REG_HOME, {\"path\": \"../x.html\", \"title\": \"X\", \"section\": \"concepts\", \"order\": 1, \"source\": \"hand\"}]" 'path must be relative and stay inside docs/'; }
fx_registry_feature_type() { regfail ftype "[$REG_HOME, {\"path\": \"concepts/x.html\", \"title\": \"X\", \"section\": \"concepts\", \"order\": 1, \"source\": \"hand\", \"feature\": 5}]" 'feature must be a string'; }
fx_registry_generator() { regfail gen "[$REG_HOME, {\"path\": \"g\", \"title\": \"G\", \"section\": \"concepts\", \"order\": 1, \"source\": \"generated:nope\"}]" "no generator named 'nope'"; }
fx_registry_source() { regfail src "[$REG_HOME, {\"path\": \"concepts/x.html\", \"title\": \"X\", \"section\": \"concepts\", \"order\": 1, \"source\": \"handmade\"}]" "source must be 'hand' or 'generated:<name>'"; }

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
mkdir -p "$R2/docs/images" "$R2/docs/release-notes" "$R2/docs/decisions" "$R2/docs/superpowers/specs"
for f in images/README.md release-notes/v1.md decisions/d.md superpowers/specs/s.md .nojekyll; do printf 'keep' > "$R2/docs/$f"; done
scheck "$R2"; rc 0; lacks ORPHAN
fx_build_orphan && ok "a plain build removes (and prints) only stale output it owns; an unowned file survives and fails the build (exit 1)" || bad "fx_build_orphan"
n=0; for f in images/README.md release-notes/v1.md decisions/d.md superpowers/specs/s.md .nojekyll; do [ "$(cat "$R2/docs/$f" 2>/dev/null)" = keep ] && n=$((n+1)); done
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
hd "registry: schema"
fx_registry_json && ok "a registry that is not JSON exits 2" || bad "fx_registry_json"
fx_registry_list && ok "a top level that is not a list exits 2" || bad "fx_registry_list"
fx_registry_entry && ok "an entry that is not an object exits 2" || bad "fx_registry_entry"
fx_registry_key && ok "an entry missing a key exits 2 naming it" || bad "fx_registry_key"
fx_registry_types && ok "a non-string title or a non-integer order exits 2" || bad "fx_registry_types"
fx_registry_path && ok "a path that leaves docs/ exits 2 with the registry's own message" || bad "fx_registry_path"
fx_registry_feature_type && ok "a non-string feature exits 2" || bad "fx_registry_feature_type"
fx_registry_generator && ok "an unknown generator exits 2 naming it" || bad "fx_registry_generator"
fx_registry_source && ok "a source that is neither hand nor generated:<name> exits 2" || bad "fx_registry_source"

hd "build: OS metadata is not content"
fx_os_junk && ok ".DS_Store, Thumbs.db, desktop.ini and ._* are ignored by --check, kept by the build, never published" || bad "fx_os_junk"

hd "build: every page is reachable"
fx_unreachable && ok "a page no other page links to exits 2 naming it" || bad "fx_unreachable"
R7="$WORK/r7"; mkrepo "$R7"; mkdir -p "$R7/site/mods"; printf '<h1>Mods</h1>\n' > "$R7/site/mods/index.html"; printf '<h1>Late mod</h1>\n' > "$R7/site/mods/late.html"
cat > "$R7/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "concepts/x.html", "title": "Concept X", "section": "concepts", "order": 1, "source": "hand"},
  {"path": "mods/index.html", "title": "Mods", "section": "mods", "order": 0, "source": "hand"},
  {"path": "mods/late.html", "title": "Late mod", "section": "mods", "order": 10, "source": "hand"}
]
JSON
OUT=$(python3 "$MOD" --root "$R7" 2>&1); RC=$?; rc 0
OUT=$(cat "$R7/docs/mods/index.html" 2>/dev/null); has '<aside class="sidebar">'; has '<a href="../mods/late.html">Late mod</a>'
OUT=$(cat "$R7/docs/index.html" 2>/dev/null); has 'content="marvin build-docs"'

# ---------------------------------------------------------------- theme (AOS-302)
# The Emprove dark theme in site/assets/site.css, the self-hosted fonts and the scoped diagram palette. One python
# checker (THEME_PY) parses the CSS (comments stripped, @media/@supports recursed) and runs one mode per test.
CSS="$ROOT/site/assets/site.css"
THEME_PY='
import colorsys, re, sys
mode, path = sys.argv[1], sys.argv[2]
raw = open(path, encoding="utf-8").read()
css = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
def parse(s, chain, out):
    i = 0
    while True:
        j = s.find("{", i)
        if j < 0:
            return out
        pre = s[i:j].split(";")[-1].strip()
        depth, k = 1, j + 1
        while k < len(s) and depth:
            depth += {"{": 1, "}": -1}.get(s[k], 0); k += 1
        body = s[j + 1:k - 1]
        if re.match(r"@(media|supports)\b", pre):
            parse(body, chain + [pre], out)
        else:
            out.append((chain, pre, body))
        i = k
RULES = parse(css, [], [])
def decls(body):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r"(--[\w-]+)\s*:\s*([^;]+)", body)}
root = {}
for chain, sel, body in RULES:
    if sel == ":root" and not chain:
        root.update(decls(body))
TIERS = ("orch", "heavy", "small", "micro", "frontier")
SCOPE = re.compile(r"^\.(diagram|tier-legend)(?![\w-])")
bad = []
def tier_values():
    vals = {}
    for chain, sel, body in RULES:
        for k, v in decls(body).items():
            if k.startswith("--tier-"):
                vals[k[len("--tier-"):]] = v
    return vals
if mode == "tokens":
    want = {"--em-black": "#00090C", "--em-green": "#00FF57", "--em-text": "#F4F6FF", "--em-text-2": "#A7ACBF",
            "--em-surface-1": "#0B0D14", "--em-surface-2": "#10131C", "--em-surface-3": "#161A26", "--em-red": "#FF3355"}
    for k, v in want.items():
        if root.get(k, "").upper() != v:
            bad.append(f":root {k} is {root.get(k)!r}, want {v}")
elif mode == "scoped":
    for chain, sel, body in RULES:
        if "--tier-" not in body:
            continue
        if any(not c.startswith(("@media", "@supports")) for c in chain) or sel.startswith("@"):
            bad.append(f"--tier-* inside an at-rule that is not @media/@supports: {chain} {sel}")
            continue
        for part in (p.strip() for p in sel.split(",")):
            if not SCOPE.match(part):
                bad.append(f"--tier-* used in a rule whose selector does not start with .diagram/.tier-legend: {part!r}")
    if "--tier-" in "".join(v for v in root.values()) or any(k.startswith("--tier-") for k in root):
        bad.append("--tier-* declared or used on :root")
    vals = tier_values()
    if sorted(vals) != sorted(TIERS):
        bad.append(f"tier set is {sorted(vals)}, want {sorted(TIERS)}")
    for t in TIERS:
        sels = [sel for _c, sel, body in RULES if re.search(r"--tc\s*:\s*var\(--tier-" + t + r"\)", body)]
        if not any(f"[data-tier=\"{t}\"]" in s for s in sels):
            bad.append(f"no [data-tier=\"{t}\"] rule sets --tc: var(--tier-{t})")
    if "Three Colours Rule" not in raw or "decision 4" not in raw:
        bad.append("the palette exception comment must name the Three Colours Rule and the architect decision 4")
elif mode == "contrast":
    def rgb(h):
        h = h.strip().lstrip("#")
        if not re.fullmatch(r"[0-9A-Fa-f]{6}", h):
            raise SystemExit(f"not a #RRGGBB colour: {h!r}")
        return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    def lum(h): r, g, b = map(lin, rgb(h)); return 0.2126 * r + 0.7152 * g + 0.0722 * b
    def ratio(a, b): x, y = sorted((lum(a), lum(b)), reverse=True); return (x + 0.05) / (y + 0.05)
    def lab(h):
        r, g, b = map(lin, rgb(h))
        X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
        return 116 * f(Y) - 16, 500 * (f(X) - f(Y)), 200 * (f(Y) - f(Z))
    def de(a, b): return sum((p - q) ** 2 for p, q in zip(lab(a), lab(b))) ** 0.5
    def hue(h): return colorsys.rgb_to_hls(*rgb(h))[0] * 360
    def dhue(a, b): d = abs(hue(a) - hue(b)) % 360; return min(d, 360 - d)
    body_r = ratio(root["--em-text-2"], root["--em-black"])
    print("body", root["--em-text-2"], "on", root["--em-black"] + ":", f"{body_r:.2f}")
    if body_r < 4.5:
        bad.append(f"body text contrast {body_r:.2f} < 4.5")
    surf, green = root["--em-surface-1"], root["--em-green"]
    vals = tier_values()
    if sorted(vals) != sorted(TIERS):
        bad.append(f"tier set is {sorted(vals)}, want {sorted(TIERS)}")
    for t, v in sorted(vals.items()):
        r, e, h = ratio(v, surf), de(v, green), dhue(v, green)
        print(f"tier {t} {v}: {r:.2f}:1 on {surf}, dE {e:.1f} and hue {h:.0f} deg from {green}")
        if r < 3.0:
            bad.append(f"tier {t} {v} contrast {r:.2f} < 3.0 on {surf}")
        if not (e >= 20 or h >= 25):
            bad.append(f"tier {t} {v} too close to laser green (dE {e:.1f}, hue {h:.0f} deg)")
for b in bad:
    print("PROBLEM:", b)
sys.exit(1 if bad else 0)
'
theme() { OUT=$(python3 -c "$THEME_PY" "$1" "${2:-$CSS}" 2>&1); RC=$?; }

hd "theme: tokens"
theme tokens; rc 0

hd "theme: dark only"
if grep -rIl 'prefers-color-scheme' "$ROOT/site" >/dev/null 2>&1; then bad "a prefers-color-scheme rule in site/"; else ok "no prefers-color-scheme in site/"; fi
grep -q 'color-scheme: *dark' "$CSS" && ok "site.css declares color-scheme: dark" || bad "site.css lacks color-scheme: dark"

hd "theme: no remote"
# No http(s) URL anywhere in site/ but the repo's own GitHub URL (and paths under it); no protocol-relative
# url(//…) / href="//…" / src="//…" / @import either. The verbatim OFL licence texts (site/assets/fonts/OFL-*.txt)
# are exempt: the licence must ship unmodified and it cites its own FAQ URL. The fonts README writes its source URLs
# scheme-less so it needs no exemption.
OUT=$(python3 - "$ROOT/site" <<'PY' 2>&1
import re, sys
from pathlib import Path
base = Path(sys.argv[1]); bad = []
ALLOW = re.compile(r"https://github\.com/Zenosyne-Technologies/agent-operating-kit(?![\w.-])")
for f in sorted(base.rglob("*")):
    if not f.is_file() or (f.parent.name == "fonts" and re.fullmatch(r"OFL-[\w-]+\.txt", f.name)):
        continue
    try:
        t = f.read_bytes().decode("utf-8")
    except UnicodeDecodeError:
        continue  # binary (woff2): no text URLs to scan
    t = ALLOW.sub("", t)
    for m in re.finditer(r"(?i)\bhttps?://\S*|(?:url\(\s*[\"']?|(?:href|src)\s*=\s*[\"']?)//\S*|@import\b[^;]*", t):
        bad.append(f"{f.relative_to(base)}: {m.group(0)[:80]}")
print("\n".join(bad) or "clean"); sys.exit(1 if bad else 0)
PY
); RC=$?; rc 0
OUT=$(python3 - "$ROOT/docs" <<'PY' 2>&1
import re, sys
from pathlib import Path
base = Path(sys.argv[1]); bad = []; n = 0
SKIP = {"images", "release-notes", "decisions", "superpowers"}
pat = re.compile(r"(?i)(?:url\(\s*[\"']?|(?:href|src)\s*=\s*[\"']?|@import\s+[\"']?)(?:https?:)?//fonts\.(?:googleapis|gstatic)\.com")
for f in sorted(base.rglob("*")):
    rel = f.relative_to(base)
    if not f.is_file() or rel.parts[0] in SKIP or f.suffix not in (".html", ".css", ".js", ".svg"):
        continue
    n += 1
    if pat.search(f.read_bytes().decode("utf-8", "replace")):
        bad.append(str(rel))
print(f"scanned {n} output files; google-fonts refs: {bad or 'none'}"); sys.exit(1 if bad or n == 0 else 0)
PY
); RC=$?; rc 0; has 'google-fonts refs: none'

hd "theme: palette scoped"
theme scoped; rc 0
if grep -rl -- '--tier-' "$ROOT/site" --include='*.html' --include='*.js' >/dev/null 2>&1; then bad "--tier-* used outside site.css"; else ok "--tier-* only in site.css"; fi
printf '.diagram, .tier-legend { --tier-orch:#8E9CF5; --tier-heavy:#4FC4DB; --tier-small:#B4CF6A; --tier-micro:#E9B35C; --tier-frontier:#BB9CF2 }\n.chip { border-color: var(--tier-orch) }\n' > "$WORK/leak.css"
theme scoped "$WORK/leak.css"; [ "$RC" = 1 ] && ok "a --tier-* use outside the scope is caught" || bad "scope leak not caught ($OUT)"

hd "theme: contrast"
theme contrast; rc 0; has 'body #A7ACBF on #00090C'; has 'tier small'
printf ':root { --em-black:#00090C; --em-surface-1:#0B0D14; --em-green:#00FF57; --em-text-2:#A7ACBF }\n.diagram { --tier-orch:#8E9CF5; --tier-heavy:#4FC4DB; --tier-small:#10F060; --tier-micro:#E9B35C; --tier-frontier:#BB9CF2 }\n' > "$WORK/green.css"
theme contrast "$WORK/green.css"; [ "$RC" = 1 ] && ok "a small tier near laser green is caught" || bad "near-green small tier not caught ($OUT)"

hd "theme: fonts self-hosted"
FONTS_SHA="52de70091213c9eab340e2a7ac59e7b6b2b94e089bf69ef38479b22cfde4274c  ibm-plex-mono-latin-400.woff2
f17f51948d10b67d907393ccbac551912f2c2bd2c5af19be3aabe2f456f8fe54  ibm-plex-mono-latin-500.woff2
6438d7b8ea9c7c3992d5e2fd2afdb1ff948570a3ef0bedae76247b51632960ba  montserrat-latin-variable.woff2"
FONTS_SHA="$FONTS_SHA
8b7141c03fa4f8d44e6345d5d4931709290f0f67875e452e95ac1fd3a027802e  OFL-Montserrat.txt
37784b44044a4ffd9256702b7c0982c37e5c8887ba90c6dca0479aea93dc898d  OFL-IBMPlexMono.txt"
for d in site/assets/fonts docs/assets/fonts; do
  if [ -d "$ROOT/$d" ] && (cd "$ROOT/$d" && printf '%s\n' "$FONTS_SHA" | shasum -a 256 -c - >/dev/null 2>&1); then ok "$d woff2 and OFL texts match the recorded sha256"; else bad "$d woff2/OFL missing or sha256 mismatch"; fi
done
OUT=$(cat "$ROOT/site/assets/fonts/README.md"); while read -r sum f; do has "$sum  $f"; done <<< "$FONTS_SHA"
for f in OFL-Montserrat.txt OFL-IBMPlexMono.txt README.md; do
  [ -f "$ROOT/site/assets/fonts/$f" ] && cmp -s "$ROOT/site/assets/fonts/$f" "$ROOT/docs/assets/fonts/$f" && ok "$f shipped" || bad "$f missing or differs in docs/"
done
grep -rIl 'tereo *Gothic\|StereoGothic' "$ROOT/site" "$ROOT/docs/assets" >/dev/null 2>&1 && bad "a Stereo Gothic reference" || ok "no Stereo Gothic"
OUT=$(grep -oE 'url\([^)]*\)' "$CSS" | sort -u)
has 'url(fonts/montserrat-latin-variable.woff2)'; has 'url(fonts/ibm-plex-mono-latin-400.woff2)'; has 'url(fonts/ibm-plex-mono-latin-500.woff2)'
OUT=$(tr '\n' ' ' < "$CSS"); has 'font-weight: 400 700'; has 'font-display: swap'; has 'unicode-range: U+0000-00FF'
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  for p in site/assets/fonts/x.woff2 docs/assets/fonts/x.woff2 docs/images/f/x.png; do
    OUT=$(git -C "$ROOT" check-attr text -- "$p"); case "$OUT" in *": text: unset") ok "$p is binary to git";; *) bad "$p not binary: $OUT";; esac
  done
  OUT=$(git -C "$ROOT" check-attr eol -- site/assets/site.css docs/assets/fonts/OFL-Montserrat.txt docs/assets/fonts/README.md); has 'site/assets/site.css: eol: lf'; has 'OFL-Montserrat.txt: eol: lf'; has 'README.md: eol: lf'
fi

hd "build: binary assets copied byte-for-byte"
# a binary asset carrying a BOM, CRLF and lone CR is copied untouched, and --check compares it byte-for-byte
fx_binary_asset() {
  local d="$WORK/fx-bin"; mkrepo "$d"; mkdir -p "$d/site/assets/fonts"
  printf 'wOF2\357\273\277a\r\nb\rc\000\377' > "$d/site/assets/fonts/t.woff2"
  sbuild "$d" || return 1
  cmp -s "$d/site/assets/fonts/t.woff2" "$d/docs/assets/fonts/t.woff2" || return 1
  scheck "$d"; [ "$RC" = 0 ] || return 1
  printf 'wOF2\357\273\277a\nb\nc\000\377' > "$d/docs/assets/fonts/t.woff2"
  scheck "$d"; [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -Fq 'STALE docs/assets/fonts/t.woff2'
}
fx_binary_asset && ok "woff2 bytes survive the build and a CR-only drift reports STALE" || bad "fx_binary_asset"

hd "theme: site.js scroll-spy"
JS="$ROOT/site/assets/site.js"
OUT=$(cat "$JS"); has 'IntersectionObserver'; has 'function initScrollSpy'; has '.sidebar'
if grep -Eq '\b(import|require)\b|https?:' "$JS"; then bad "site.js pulls a dependency or a URL"; else ok "site.js is dependency-free"; fi

hd "site: the real repo is fresh and hand sources name no model"
OUT=$(python3 "$MOD" --check 2>&1); RC=$?; rc 0
# model_scan <dir>: exit 0 when a hand source (html, json, md, and the site's own js and css) names a model family
model_scan() { grep -rniE '\b(opus|sonnet|haiku|fable|gpt-[0-9])' "$1" --include='*.html' --include='*.json' --include='*.md' --include='*.js' --include='*.css' -l >/dev/null 2>&1; }
if model_scan "$ROOT/site"; then bad "a model name is hand-typed in site/"; else ok "no model name in site/ (html, json, md, js, css)"; fi
MS="$WORK/model-scan"; mkdir -p "$MS"; printf 'var x = "Sonnet 9";\n' > "$MS/a.js"
model_scan "$MS" && ok "negative control: a model name in a .js file is caught" || bad "the model scan misses a .js file"
rm "$MS/a.js"; printf '.x::after { content: "opus"; }\n' > "$MS/b.css"
model_scan "$MS" && ok "negative control: a model name in a .css file is caught" || bad "the model scan misses a .css file"

# ---------------------------------------------------------------- generated Releases (AOS-303)
# mkrel <dir>: mkrepo plus a generated Releases entry and a CHANGELOG / upgrades / release-notes tree:
#   0.42.0 in all three (note + upgrade + changes, with Action needed), 0.30.0 CHANGELOG only (Action needed: None),
#   0.26.1 upgrades only, 0.10.0 and 0.9.0 pre-0.22 (string order would put 0.9.0 above 0.10.0), 0.25.0 in no source.
mkrel() {
  local d="$1"; mkrepo "$d"; mkdir -p "$d/upgrades" "$d/docs/release-notes"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "releases", "title": "Releases", "section": "releases", "order": 0, "source": "generated:releases"}
]
JSON
  cat > "$d/CHANGELOG.md" <<'MD'
# Changelog

## [0.42.0] — 2026-10-20

### Added
- change-forty-two

### Action needed
- Run the upgrade.

## [0.30.0] — 2026-09-01

### Added
- change-thirty

### Action needed
- None: nothing to do.

## [0.10.0] — 2026-01-02

### Added
- change-ten

## [0.9.0] — 2026-01-01

### Added
- change-nine

## [≤0.21.x]

- Releases before v0.22.0 carry no brief here.
MD
  printf '# Upgrade to v0.42.0\n\nupgrade-forty-two. Back to [why](#why). See `upgrades/v0.42.0.md` and [the script](scripts/migrate-v0.42.0.sh), [prior note](docs/release-notes/v0.41.0.md), [site](https://example.com/x).\n' > "$d/upgrades/v0.42.0.md"
  printf '# Upgrade to v0.26.1\n\nupgrade-twenty-six-one\n' > "$d/upgrades/v0.26.1.md"
  printf '# v0.10.0 - ten\n\nupgrade-ten\n' > "$d/upgrades/v0.10.0.md"
  printf '# v0.9.0 - nine\n\nupgrade-nine\n' > "$d/upgrades/v0.9.0.md"
  printf -- '---\ndoc: v0.42.0 release note\ntype: release-note\nstatus: active\nsummary: header-must-not-leak\ncreated: 2026-10-20\n---\n\n# v0.42.0 — Forty-two headline\n\nnote-forty-two. Next: [release notes](docs/release-notes/v0.42.0.md), [readme](README.md), [guide](#why).\n\n## Why\n\nbecause\n' > "$d/docs/release-notes/v0.42.0.md"
}
rel() { python3 "$MOD" --root "$1" >/dev/null 2>&1; }
page() { cat "$1/docs/releases/$2" 2>/dev/null; }   # page <repo> <name>

hd "releases: union"
R6="$WORK/r6"; mkrel "$R6"; OUT=$(python3 "$MOD" --root "$R6" 2>&1); RC=$?; rc 0
for f in index v0.42.0 v0.30.0 v0.26.1 v0.10.0 v0.9.0 earlier; do [ -f "$R6/docs/releases/$f.html" ] && ok "releases/$f.html exists" || bad "releases/$f.html missing"; done
[ -f "$R6/docs/releases/v0.25.0.html" ] && bad "a version in no source got a page" || ok "no page for a version in no source (0.25.0)"
OUT=$(ls "$R6/docs/releases" | wc -l | tr -d ' '); [ "$OUT" = 7 ] && ok "exactly seven releases pages" || bad "page count $OUT"
OUT=$(python3 "$MOD" --root "$R6" --check 2>&1); RC=$?; rc 0

hd "releases: blocks"
OUT=$(page "$R6" v0.42.0.html)
has 'note-forty-two'; has 'class="release-block release-block--upgrade"'; has 'upgrade-forty-two'
has 'class="release-block release-block--changes"'; has 'change-forty-two'
lacks 'header-must-not-leak'; lacks 'type: release-note'
n=$(printf '%s' "$OUT" | grep -n -e 'note-forty-two' -e 'release-block--upgrade' -e 'release-block--changes' | cut -d: -f1 | tr '\n' ' ')
set -- $n; [ "$#" = 3 ] && [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ] && ok "order: note, upgrade, changes" || bad "block order wrong ($n)"
OUT=$(page "$R6" v0.30.0.html); has 'release-block--changes'; has 'change-thirty'; lacks 'release-block--upgrade'; has '<h1>v0.30.0</h1>'
OUT=$(page "$R6" v0.26.1.html); has 'release-block--upgrade'; lacks 'release-block--changes'; lacks 'upgrade-forty-two'
OUT=$(page "$R6" v0.42.0.html); n=$(printf '%s' "$OUT" | grep -c '<h1')
[ "$n" = 1 ] && ok "one h1 per page" || bad "h1 count $n"
OUT=$(page "$R6" v0.42.0.html); n=$(printf '%s' "$OUT" | grep -o ' id="[^"]*"' | sort | uniq -d | wc -l | tr -d ' ')
[ "$n" = 0 ] && ok "no duplicate ids across the blocks" || bad "$n duplicate ids"
OUT=$(page "$R6" v0.42.0.html); has '<title>v0.42.0 — Forty-two headline'

hd "releases: earlier"
OUT=$(page "$R6" earlier.html | sed -n '/<main/,/<\/main>/p'); has 'carry no brief here'; has 'href="v0.10.0.html"'; has 'href="v0.9.0.html"'; lacks 'v0.26.1.html'; lacks 'v0.30.0.html'
OUT=$(page "$R6" index.html); has 'href="earlier.html"'

hd "releases: index"
OUT=$(page "$R6" index.html)
n=$(printf '%s' "$OUT" | grep -o 'href="v[0-9.]*html"' | sed 's/href="v//; s/.html"//' | tr '\n' ' ')
[ "$n" = "0.42.0 0.30.0 0.26.1 0.10.0 0.9.0 " ] && ok "newest first by semver (0.10.0 above 0.9.0)" || bad "index order: $n"
has '2026-10-20'; has 'Forty-two headline'; has '2026-09-01'
printf '%s' "$OUT" | grep '0.42.0' | grep -q 'badge--action' && ok "Action needed content -> badge" || bad "no badge on 0.42.0"
printf '%s' "$OUT" | grep '0.30.0' | grep -q 'badge--action' && bad "badge on 'None' action" || ok "no badge when Action needed starts with None"
printf '%s' "$OUT" | grep '0.10.0' | grep -q 'badge--action' && bad "badge with no Action needed section" || ok "no badge without an Action needed section"
fx_release_nav() { python3 "$MOD" --root "$R6" >/dev/null 2>&1; local f; f=$(grep -o 'releases/[^"]*' "$R6/docs/index.html" | head -1); [ "$f" = "releases/index.html" ]; }
fx_release_nav && ok "the top-nav Releases item links the index (first page of the section)" || bad "nav does not reach releases/index.html"
OUT=$(grep -o '<aside.*' "$R6/docs/releases/v0.42.0.html" | tr '<' '\n' | grep -o '>v[0-9.]*$' | tr '\n' ' ')
[ "$OUT" = ">v0.42.0 >v0.30.0 >v0.26.1 >v0.10.0 >v0.9.0 " ] && ok "sidebar lists versions newest first, short labels" || bad "sidebar: $OUT"

hd "releases: links"
OUT=$(page "$R6" v0.42.0.html)
has 'href="https://github.com/Zenosyne-Technologies/agent-operating-kit/blob/main/scripts/migrate-v0.42.0.sh"'
has 'href="https://github.com/Zenosyne-Technologies/agent-operating-kit/blob/main/README.md"'
has 'href="https://example.com/x"'
has 'href="#upgrade-why"' ; has 'href="#why"' ; lacks 'docs/release-notes/v0.42.0.md"'
has 'href="v0.42.0.html"'
fx_release_links() {   # the two documented maps, with the sibling page existing for 0.41.0
  local d="$WORK/fx-rl"; mkrel "$d"; printf '# Upgrade\n\n[a](upgrades/v0.42.0.md) [b](docs/release-notes/v0.42.0.md) [c](docs/release-notes/v9.9.9.md) [d](CLAUDE.md) [e](other/page.html)\n' > "$d/upgrades/v0.42.0.md"
  rel "$d" || return 1
  local f="$d/docs/releases/v0.42.0.html"
  grep -Fq 'href="https://github.com/Zenosyne-Technologies/agent-operating-kit/blob/main/upgrades/v0.42.0.md"' "$f" && grep -Fq 'href="v0.42.0.html"' "$f" \
    && grep -Fq 'blob/main/docs/release-notes/v9.9.9.md' "$f" && grep -Fq 'blob/main/CLAUDE.md' "$f" && grep -Fq 'href="other/page.html"' "$f"
}
fx_release_links && ok "upgrades/ -> GitHub blob, docs/release-notes/v<x>.md -> v<x>.html (blob when no page), other relative links unchanged" || bad "fx_release_links"
fx_release_scheme() { local d="$WORK/fx-rs"; mkrel "$d"; printf '# Upgrade\n\n[x](javascript:alert(1))\n' > "$d/upgrades/v0.42.0.md"; python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]; }
fx_release_scheme && ok "the renderer's link allowlist still applies after mapping" || bad "fx_release_scheme"

hd "releases: output hygiene"
OUT=$(grep -rhoE '/(Users|home)/[A-Za-z0-9._-]+' "$R6/docs/releases" | grep -vxE '/Users/me|/home/user' || true); [ -z "$OUT" ] && ok "no local path in releases pages" || bad "local path: $OUT"
OUT=$(grep -rE '(href|src)="/' "$R6/docs/releases" || true); [ -z "$OUT" ] && ok "every link is relative" || bad "absolute link: $OUT"
R6b="$WORK/r6b"; cp -R "$R6" "$R6b"; rel "$R6b"; diff -r "$R6/docs" "$R6b/docs" >/dev/null && ok "deterministic" || bad "two builds differ"

hd "releases: a version no page could be built for"
fx_release_missing() {   # a CHANGELOG header with no body and no other source: nothing to render -> BuildError, never a silent gap
  local d="$WORK/fx-rm"; mkrel "$d"; printf '\n## [0.31.0] — 2026-09-02\n\n## [0.28.0] — 2026-08-01\n\n### Added\n- x\n' >> "$d/CHANGELOG.md"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ] || return 1
  scheck "$d"; [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -Fq '0.31.0'
}
fx_release_missing && ok "release-missing: an empty-source version exits 2 naming it (build and --check)" || bad "fx_release_missing"
fx_changelog_heading() {   # a `## [` heading the parser cannot read (an ASCII hyphen for the em dash) fails loud, never drops its section
  local d="$WORK/fx-ch"; mkrel "$d"; printf '\n## [0.43.0] - 2026-11-26\n\n### Added\n- dropped-silently\n' >> "$d/CHANGELOG.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'CHANGELOG.md:' && printf '%s' "$OUT" | grep -Fq 'unparseable release heading'
}
fx_changelog_heading && ok "an unparseable ## [ heading exits 2 naming CHANGELOG.md:<line>" || bad "fx_changelog_heading"

hd "releases: real repo"
OUT=$(python3 "$MOD" --check 2>&1); RC=$?; rc 0
n_real=0
for src in upgrades docs/release-notes; do for f in "$ROOT/$src"/v*.md; do v=$(basename "$f" .md); [ -f "$ROOT/docs/releases/$v.html" ] || bad "no page for $v ($src)"; done; done
for v in $(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$ROOT/CHANGELOG.md" | tr -d '#[] '); do [ -f "$ROOT/docs/releases/v$v.html" ] || bad "no page for CHANGELOG $v"; done
n_real=$(ls "$ROOT"/docs/releases/v*.html | wc -l | tr -d ' ')
[ "$n_real" -ge 53 ] && ok "$n_real version pages built from the real sources" || bad "only $n_real version pages"
[ -f "$ROOT/docs/releases/index.html" ] && [ -f "$ROOT/docs/releases/earlier.html" ] && ok "index and earlier exist" || bad "index/earlier missing"
[ -f "$ROOT/docs/releases/v0.25.0.html" ] && bad "a page for 0.25.0" || ok "no page for 0.25.0"
OUT=$(grep -rhoE '/(Users|home)/[A-Za-z0-9._-]+' "$ROOT/docs/releases" | grep -vxE '/Users/me|/home/user' || true); [ -z "$OUT" ] && ok "no local path in the real pages" || bad "local path in real pages"
n=$(grep -c 'badge--action' "$ROOT/docs/releases/index.html" || true); [ "$n" -ge 1 ] && ok "index carries Action-needed badges ($n)" || bad "no badge in the real index"

# ---------------------------------------------------------------- generated Settings, Skills, Reference, model data (AOS-304)
# mkgen <dir>: a fixture repo with the three generated pages, a hand page carrying the three markers, and tiny sources.
mkgen() {
  local d="$1"; mkrepo "$d"
  mkdir -p "$d/templates/marvin/agents/codex" "$d/agents" "$d/skills/alpha" "$d/commands"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "concepts/x.html", "title": "Concept X", "section": "concepts", "order": 1, "source": "hand"},
  {"path": "settings", "title": "Settings", "section": "reference", "order": 10, "source": "generated:settings"},
  {"path": "skills", "title": "Skills", "section": "reference", "order": 20, "source": "generated:skills"},
  {"path": "reference", "title": "Reference", "section": "reference", "order": 30, "source": "generated:reference"}
]
JSON
  printf '<h1>Home</h1>\n<!-- data: profiles -->\n' > "$d/site/index.html"
  printf '<h1>X</h1>\n<!-- table: profiles -->\n<!-- table: codex -->\n' > "$d/site/concepts/x.html"
  cat > "$d/templates/marvin/PROJECT-INFO.md" <<'MD'
---
project: "{{PROJECT_NAME}}"
model_profile: {{MODEL_PROFILE}}
update_gate: advise
ticket_lint: block
# Optional: a comment, not a key
# fleet_max_children: 3
kit_version: {{KIT_VERSION}}
---

# {{PROJECT_NAME}}

- `update_gate` sets the update check (`advise` | `block`, `.marvin/agents/fleet.md`)
- `ticket_lint` sets the label check — `.marvin/agents/codex/review.md` and `security.md`; `fleet_max_children` is an optional override
- Label registry: nothing to see
MD
  printf -- '- `project`: The name.\n- `model_profile`: Which profile runs.\n- `kit_version`: The version.\n' > "$d/site/settings-install.md"
  local g
  for g in fleet security; do printf -- '---\ndoc: Guide %s\ntype: rule\nstatus: active\nsummary: Summary of `%s`.\nupdated: {{INSTALL_DATE}}\n---\nbody\n' "$g" "$g" > "$d/templates/marvin/agents/$g.md"; done
  printf -- '---\ndoc: Zed guide\ntype: rule\nstatus: active\nsummary: Zed.\nupdated: 2026-01-02\n---\n' > "$d/templates/marvin/agents/zed.md"
  printf -- '---\ndoc: Codex lane brief — review\ntype: rule\nstatus: active\nsummary: Lane.\nupdated: {{INSTALL_DATE}}\n---\n' > "$d/templates/marvin/agents/codex/review.md"
  printf -- '---\ndoc: Codex lane brief — security\ntype: rule\nstatus: active\nsummary: Lane two.\nupdated: {{INSTALL_DATE}}\n---\n' > "$d/templates/marvin/agents/codex/security.md"
  printf 'Rules: `.marvin/agents/security.md` then `.marvin/agents/fleet.md`.\n' > "$d/templates/marvin/CLAUDE.marvin.md"
  cat > "$d/templates/marvin/agents/model-profile.md" <<'MD'
---
doc: Model profile
type: reference
status: active
summary: x
updated: {{INSTALL_DATE}}
---
## Profile: alpha (default)

| Tier | Model | Window | Default effort | Resolves | Personas |
|---|---|---|---|---|---|
| orchestrator | Mod One | 1M | `medium`; raise | `A` | the main session |
| heavy worker | Mod Two | 1M | `high` (pinned) | `B` | `marvin:dev`, the validators |
| small worker | Mod Three | 1M | `low` | `C` | `marvin:sm` |
| micro | Mod Four | 1M | `low` | `D` | none |
| frontier | Mod Five | 1M | inherits the session's (opt-in) | `E` | `marvin:fr` |

## Profile: beta

| Tier | Model | Window | Default effort | Resolves | Personas |
|---|---|---|---|---|---|
| orchestrator | Mod Nine | 1M | `medium` | `A` | the main session |
| heavy worker | Mod Two | 1M | `high` | `B` | as in `alpha` |
| small worker | Mod Three | 1M | `low` | `C` | as in `alpha` |
| micro | Mod Four | 1M | `low` | `D` | as in `alpha` |
| frontier | none | — | — | `E` | none |
MD
  cat > "$d/templates/marvin/agents/model-profile-codex.md" <<'MD'
---
doc: Codex model profile
type: reference
status: active
summary: x
updated: {{INSTALL_DATE}}
---
| Lane | Tier | Model | Effort | Why |
|---|---|---|---|---|
| build | codex workhorse | codex-model-x | medium | default |
MD
  printf -- '---\nname: dev\ndescription: Builds.\nmodel: opus\neffort: medium\n---\n' > "$d/agents/dev.md"
  printf -- '---\nname: val\ndescription: Validates.\nmodel: opus\neffort: high\n---\n' > "$d/agents/val.md"
  printf -- '---\nname: sm\ndescription: Small.\nmodel: sonnet\neffort: low\n---\n' > "$d/agents/sm.md"
  printf -- '---\nname: fr\ndescription: Frontier.\nmodel: bigone\n---\n' > "$d/agents/fr.md"
  # `bigone` is named only through marvin:fr; `opus` -> heavy through marvin:dev
  printf -- "---\nname: alpha\ndescription: Does alpha.\nargument-hint: '<x|y> [--z]'\n---\nbody\n" > "$d/skills/alpha/SKILL.md"
  printf -- '---\ndescription: A command.\n---\nbody\n' > "$d/commands/beta.md"
}
gp() { python3 -c 'import sys,json; sys.path.insert(0,sys.argv[1]); import importlib.util as u; s=u.spec_from_file_location("bd",sys.argv[1]); m=u.module_from_spec(s); sys.modules["bd"]=m; s.loader.exec_module(m); import pathlib; print(json.dumps(m.profile_data(pathlib.Path(sys.argv[2])),sort_keys=True))' "$MOD" "$1"; }
gpage() { sed -n '/<main/,/<\/main>/p' "$1/docs/$2" 2>/dev/null; }   # gpage <repo> <file>

hd "settings: groups"
G="$WORK/g1"; mkgen "$G"; OUT=$(python3 "$MOD" --root "$G" 2>&1); RC=$?; rc 0
OUT=$(gpage "$G" settings.html)
has '<h2 id="behaviour">Behaviour</h2>'; has '<h2 id="install">Set at install</h2>'
n=$(printf '%s' "$OUT" | grep -n -e 'id="behaviour"' -e 'id="install"' | cut -d: -f1 | tr '\n' ' '); set -- $n; [ "$1" -lt "$2" ] && ok "Behaviour comes first" || bad "group order ($n)"
has '<tr id="update_gate"><td><code>update_gate</code></td><td><code>advise</code></td>'
has 'href="reference.html#fleet"'; has 'href="reference.html#codex-review"'; has 'href="reference.html#security"'
has '<tr id="project"><td><code>project</code></td><td>set at install</td><td>The name.</td></tr>'
has '<tr id="model_profile">'
printf '%s' "$OUT" | grep 'id="fleet_max_children"' | grep -q 'badge badge--optional">optional' && ok "commented key carries the optional badge" || bad "no optional badge"
printf '%s' "$OUT" | grep 'id="ticket_lint"' | grep -q 'optional' && bad "badge on a plain key" || ok "no badge on a plain key"
printf '%s' "$OUT" | grep 'id="update_gate"' | grep -q 'fleet_max' && bad "update_gate row carries another key's clause" || ok "a shared bullet is cut to the clause naming the key"
printf '%s' "$OUT" | grep 'id="fleet_max_children"' | grep -q '<code>3</code>' && ok "optional key shows the template value" || bad "optional default"
lacks 'a comment, not a key'; lacks '<tr id="Optional"'
OUT=$(python3 "$MOD" --root "$G" --check 2>&1); RC=$?; rc 0

hd "settings: bullet text is escaped"
G2="$WORK/g2"; mkgen "$G2"; sed -i.bak 's/^- `ticket_lint` sets the label check/- `ticket_lint` sets <b>x<\/b> {{P}} the label check/' "$G2/templates/marvin/PROJECT-INFO.md"
python3 "$MOD" --root "$G2" >/dev/null 2>&1; OUT=$(gpage "$G2" settings.html); has '&lt;b&gt;x&lt;/b&gt;'; lacks '<b>x'

fx_settings_behaviour() {
  local d="$WORK/fx-sb"; mkgen "$d"; sed -i.bak '/^- `ticket_lint`/d' "$d/templates/marvin/PROJECT-INFO.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'ticket_lint'
}
fx_settings_install_missing() {
  local d="$WORK/fx-sm"; mkgen "$d"; sed -i.bak '/`kit_version`/d' "$d/site/settings-install.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'kit_version'
}
fx_settings_install_extra() {
  local d="$WORK/fx-se"; mkgen "$d"; printf -- '- `ghost_key`: nothing\n' >> "$d/site/settings-install.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'ghost_key'
}
fx_settings_install_dup() {
  local d="$WORK/fx-sd"; mkgen "$d"; printf -- '- `project`: again\n' >> "$d/site/settings-install.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'project'
}
fx_settings_bullet_wrap() {   # a hard-wrapped body bullet (line 14 continues on 15) fails loud naming file:line; a blank line ends a bullet
  local d="$WORK/fx-bw" t; mkgen "$d"; t="$d/templates/marvin/PROJECT-INFO.md"
  awk '{print} /^- `ticket_lint`/{print "  wrapped tail that would be lost"}' "$t" > "$t.new" && mv "$t.new" "$t"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'PROJECT-INFO.md:15: a body bullet continues' || return 1
  mkgen "$d"; printf '\nA closing paragraph after a blank line.\n' >> "$t"; sbuild "$d"
}
hd "settings: guards"
fx_settings_bullet_wrap && ok "a wrapped settings bullet exits 2 naming PROJECT-INFO.md:<line>; prose after a blank line is fine" || bad "fx_settings_bullet_wrap"
fx_settings_behaviour && ok "a behaviour key with no bullet exits 2 naming it" || bad "fx_settings_behaviour"
fx_settings_install_missing && ok "a placeholder key with no install line exits 2 naming it" || bad "fx_settings_install_missing"
fx_settings_install_extra && ok "an install line with no key exits 2 naming it" || bad "fx_settings_install_extra"
fx_settings_install_dup && ok "a key described twice exits 2" || bad "fx_settings_install_dup"

fx_pi_frontmatter_missing() {
  local d="$WORK/fx-pm"; mkgen "$d"; sed -i.bak '1d' "$d/templates/marvin/PROJECT-INFO.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'no YAML frontmatter'
}
fx_pi_frontmatter_unterminated() {
  local d="$WORK/fx-pu"; mkgen "$d"; printf -- '---\nproject: x\n' > "$d/templates/marvin/PROJECT-INFO.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'unterminated'
}
fx_install_file_missing() {
  local d="$WORK/fx-im"; mkgen "$d"; rm "$d/site/settings-install.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'settings-install.md: missing'
}
fx_install_line_shape() {
  local d="$WORK/fx-il"; mkgen "$d"; printf 'not a bullet line\n' >> "$d/site/settings-install.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'expected'
}
fx_table_row_width() {
  local d="$WORK/fx-tw"; mkgen "$d"; sed -i.bak 's/^| micro | Mod Four | 1M | `low` | `D` | none |/| micro | Mod Four | 1M | `low` | `D` | none | extra |/' "$d/templates/marvin/agents/model-profile.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'table row has'
}
hd "settings and profile parsers: structural errors"
fx_pi_frontmatter_missing && ok "PROJECT-INFO without frontmatter exits 2" || bad "fx_pi_frontmatter_missing"
fx_pi_frontmatter_unterminated && ok "unterminated PROJECT-INFO frontmatter exits 2" || bad "fx_pi_frontmatter_unterminated"
fx_install_file_missing && ok "a missing settings-install.md exits 2" || bad "fx_install_file_missing"
fx_install_line_shape && ok "a malformed install line exits 2" || bad "fx_install_line_shape"
fx_table_row_width && ok "a profile table row with the wrong cell count exits 2" || bad "fx_table_row_width"

hd "skills: list"
OUT=$(gpage "$G" skills.html)
has '<code>/marvin:alpha</code>'; has '<code>&lt;x|y&gt; [--z]</code>'; has '<code>/marvin:beta</code>'; has 'A command.'
n=$(printf '%s' "$OUT" | grep -o '/marvin:[a-z-]*' | tr '\n' ' '); [ "$n" = "/marvin:alpha /marvin:beta " ] && ok "sorted by name" || bad "skills order: $n"
fx_skill_description() {
  local d="$WORK/fx-sk"; mkgen "$d"; printf -- '---\nname: nodesc\n---\n' > "$d/commands/nodesc.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'nodesc'
}
fx_skill_description && ok "a skill with no description exits 2" || bad "fx_skill_description"

hd "reference: headers"
OUT=$(gpage "$G" reference.html)
has '<h3 id="fleet">Guide fleet</h3>'; has '<p>Summary of <code>fleet</code>.</p>'
has 'href="https://github.com/Zenosyne-Technologies/agent-operating-kit/blob/main/templates/marvin/agents/fleet.md"'
has '<h3 id="codex-review">Codex lane brief — review</h3>'; has '<h3 id="security">Guide security</h3>'
has 'blob/main/templates/marvin/agents/codex/review.md"'
has 'updated 2026-01-02'; lacks 'INSTALL_DATE'
n=$(printf '%s' "$OUT" | grep -o '<h[23] id="[^"]*"' | sed 's/.*id="//; s/"//' | tr '\n' ' ')
[ "$n" = "group-cascade security fleet group-other model-profile-codex model-profile zed group-codex-lanes codex-review codex-security " ] && ok "cascade order, then other (alphabetical), then Codex lanes" || bad "reference order: $n"
fx_reference_header() {
  local d="$WORK/fx-rh"; mkgen "$d"; printf -- '---\ndoc: No summary\n---\n' > "$d/templates/marvin/agents/bad.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'bad.md'
}
fx_anchor_collision() {   # top-level codex-review.md and codex/review.md both want id codex-review
  local d="$WORK/fx-ac"; mkgen "$d"; printf -- '---\ndoc: Clash\nsummary: s\n---\n' > "$d/templates/marvin/agents/codex-review.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'codex-review'
}
fx_reference_header && ok "a guide without doc:/summary: exits 2 naming it" || bad "fx_reference_header"
fx_anchor_collision && ok "an anchor id collision exits 2" || bad "fx_anchor_collision"

hd "profiles: data"
OUT=$(gp "$G" 2>&1); RC=$?; rc 0
has '"default": "alpha"'; has '"beta"'
python3 - "$OUT" <<'PY' && ok "profile_data shape: profiles, personas, codex" || bad "profile_data content"
import json,sys
d=json.loads(sys.argv[1])
assert d["default"]=="alpha" and set(d["profiles"])=={"alpha","beta"}
a=d["profiles"]["alpha"]; b=d["profiles"]["beta"]
assert a["orch"]=={"model":"Mod One","effort":"medium"} and a["heavy"]["effort"]=="high"
assert a["frontier"]["effort"]=="inherits the session's" and b["frontier"]=={"model":"","effort":""} and b["orch"]["model"]=="Mod Nine"
p=d["personas"]
assert p["dev"]["tier"]=="heavy" and p["dev"]["model"]=="Mod Two" and p["dev"]["effort"]=="medium" and p["dev"]["description"]=="Builds."
assert p["val"]["tier"]=="heavy" and p["val"]["effort"]=="high"   # not named: placed by its model alias
assert p["sm"]["tier"]=="small" and p["fr"]["tier"]=="frontier" and p["fr"]["effort"]=="inherits the session's"
assert d["codex"]==[{"lane":"build","tier":"codex workhorse","model":"codex-model-x","effort":"medium"}]
PY
# a third profile table appears with no code change
G3="$WORK/g3"; mkgen "$G3"
printf '\n## Profile: gamma\n\n| Tier | Model | Window | Default effort | Resolves | Personas |\n|---|---|---|---|---|---|\n| orchestrator | Mod Seven | 1M | `high` | `A` | the main session |\n' >> "$G3/templates/marvin/agents/model-profile.md"
OUT=$(gp "$G3" 2>&1); has '"gamma"'; has 'Mod Seven'
fx_profile_parse() {
  local d="$WORK/fx-pp"; mkgen "$d"; sed -i.bak 's/| Tier | Model | Window/| Tier | Engine | Window/' "$d/templates/marvin/agents/model-profile.md"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_profile_tier() {
  local d="$WORK/fx-pt"; mkgen "$d"; sed -i.bak 's/^| micro |/| nano |/' "$d/templates/marvin/agents/model-profile.md"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_profile_default() {
  local d="$WORK/fx-pd"; mkgen "$d"; sed -i.bak 's/ (default)//' "$d/templates/marvin/agents/model-profile.md"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_persona_tier() {   # a persona whose model alias no Personas cell vouches for
  local d="$WORK/fx-ps"; mkgen "$d"; printf -- '---\nname: odd\ndescription: Odd.\nmodel: mystery\n---\n' > "$d/agents/odd.md"
  OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] && printf '%s' "$OUT" | grep -Fq 'odd'
}
fx_persona_alias() {   # two named personas share an alias but sit in different tiers
  local d="$WORK/fx-pa"; mkgen "$d"; printf -- '---\nname: sm2\ndescription: x\nmodel: opus\n---\n' > "$d/agents/sm2.md"
  sed -i.bak 's/`marvin:sm`/`marvin:sm`, `marvin:sm2`/' "$d/templates/marvin/agents/model-profile.md"
  python3 "$MOD" --root "$d" >/dev/null 2>&1; [ "$?" = 2 ]
}
fx_profile_parse && ok "a profile table without a Model column exits 2" || bad "fx_profile_parse"
fx_profile_tier && ok "an unknown tier name exits 2" || bad "fx_profile_tier"
fx_profile_default && ok "no (default) profile exits 2" || bad "fx_profile_default"
fx_persona_tier && ok "a persona that cannot be placed exits 2 naming it" || bad "fx_persona_tier"
fx_persona_alias && ok "one model alias in two tiers exits 2" || bad "fx_persona_alias"

hd "profiles: markers"
OUT=$(cat "$G/docs/index.html"); has '<script type="application/json" id="marvin-data">'; lacks '<!-- data: profiles -->'
python3 - "$G/docs/index.html" <<'PY' && ok "the data block parses as JSON and cannot close its script" || bad "data block"
import re,sys,json
t=open(sys.argv[1]).read()
m=re.search(r'<script type="application/json" id="marvin-data">(.*?)</script>',t,re.S)
d=json.loads(m.group(1)); assert d["default"]=="alpha"
assert "<" not in m.group(1)
PY
OUT=$(cat "$G/docs/concepts/x.html")
has '<div class="tier-legend">'; has '<th>alpha <small>default</small></th><th>beta</th>'; has 'data-tier="orch"'; has 'data-tier="frontier"'
has 'Mod Nine'; has '<td>none</td>'; has 'href="../settings.html#model_profile"'
has 'blob/main/templates/marvin/agents/model-profile.md"'; has 'blob/main/templates/marvin/agents/model-profile-codex.md"'
has '<td><code>build</code></td><td>codex workhorse</td><td>codex-model-x</td><td>medium</td>'
lacks '<!-- table:'
P="$WORK/g4p"; mkgen "$P"; printf '<!-- table: profiles -->\n' > "$P/site/index.html"; python3 "$MOD" --root "$P" >/dev/null 2>&1
grep -Fq 'href="settings.html#model_profile"' "$P/docs/index.html" && ok "a root page links settings.html with no ../" || bad "root-page prefix"
fx_marker_unknown() {
  local d="$WORK/fx-mu" k; mkgen "$d"
  for k in '<!-- table: nope -->' '<!-- data: other -->' '<!--table:profile-->'; do
    printf '%s\n' "$k" > "$d/site/index.html"; OUT=$(python3 "$MOD" --root "$d" 2>&1); [ "$?" = 2 ] || return 1; printf '%s' "$OUT" | grep -Fq 'unknown marker' || return 1
  done
}
fx_marker_unknown && ok "an unknown <!-- table|data: x --> marker exits 2" || bad "fx_marker_unknown"

hd "profiles: no hand model names"
# Every Model cell of both profile tables, read at test time. Whole-word, case-insensitive, over every file under site/
# except the fonts. The bare profile names (`opus`, `fable`) are setting VALUES, not model names, and stay allowed;
# a family word followed by a version number ("Opus 5.5") is a model name and is not.
python3 - "$ROOT" <<'PY' && ok "no file under site/ names a model from the profile tables" || bad "a hand-written file names a model"
import re,sys,pathlib,importlib.util as u
root=pathlib.Path(sys.argv[1]); s=u.spec_from_file_location("bd",root/"scripts/lib/build_docs.py"); m=u.module_from_spec(s); sys.modules["bd"]=m; s.loader.exec_module(m)
d=m.profile_data(root)
names={t["model"] for p in d["profiles"].values() for t in p.values() if t["model"]}|{c["model"] for c in d["codex"]}
assert names, "no models read"
pats=[re.compile(r"(?<![\w.-])"+re.escape(n)+r"(?![\w.-])",re.I) for n in names]
pats.append(re.compile(r"\b(opus|sonnet|haiku|fable|gpt)[ -]?v?\d",re.I))
bad=[]
for f in (root/"site").rglob("*"):
    if f.is_file() and "assets/fonts" not in f.as_posix() and f.suffix in (".html",".md",".css",".js",".json"):
        t=f.read_text(encoding="utf-8")
        for p in pats:
            if p.search(t): bad.append((f.name,p.pattern))
print(bad); sys.exit(1 if bad else 0)
PY

hd "settings, skills, reference: real repo"
OUT=$(python3 "$MOD" --check 2>&1); RC=$?; rc 0
for f in settings skills reference; do [ -f "$ROOT/docs/$f.html" ] && ok "docs/$f.html exists" || bad "docs/$f.html missing"; done
python3 - "$ROOT" <<'PY' && ok "every PROJECT-INFO key has a row; every guide and skill is listed" || bad "real-repo coverage"
import re,sys,pathlib
r=pathlib.Path(sys.argv[1]); s=(r/"docs/settings.html").read_text()
fm=(r/"templates/marvin/PROJECT-INFO.md").read_text().split("---")[1]
keys=re.findall(r"^#?\s*([a-z][a-z0-9_]*):",fm,re.M)
keys=[k for k in keys if k!="optional"]
miss=[k for k in keys if f'<tr id="{k}">' not in s]; assert not miss,miss
ref=(r/"docs/reference.html").read_text()
for f in (r/"templates/marvin/agents").rglob("*.md"):
    a=f.relative_to(r/"templates/marvin/agents").as_posix()[:-3].replace("/","-"); assert f'<h3 id="{a}">' in ref,a
sk=(r/"docs/skills.html").read_text()
for d in (r/"skills").iterdir():
    if (d/"SKILL.md").is_file(): assert f"/marvin:{d.name}</code>" in sk,d.name
for f in (r/"commands").glob("*.md"): assert f"/marvin:{f.stem}</code>" in sk,f.stem
PY
OUT=$(grep -rhoE '/(Users|home)/[A-Za-z0-9._-]+' "$ROOT/docs/settings.html" "$ROOT/docs/skills.html" "$ROOT/docs/reference.html" || true); [ -z "$OUT" ] && ok "no local path in the generated pages" || bad "local path: $OUT"


# ---------------------------------------------------------------- rule-11 galleries and the Mods page (AOS-305)
# mkpng <file> <w> <h>: a minimal valid PNG header (signature + IHDR) with the given size.
mkpng() {
  python3 - "$1" "$2" "$3" <<'PY'
import struct, sys, zlib
f, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
open(f, "wb").write(b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + ihdr + struct.pack(">I", zlib.crc32(b"IHDR" + ihdr)))
PY
}
# mkgal <dir>: mkrepo plus a Mods page carrying feature "demo" (docs/images/demo: a.png 30x20, b.png 64x48 and captions.md)
mkgal() {
  local d="$1"; mkrepo "$d"; mkdir -p "$d/site/mods" "$d/docs/images/demo"
  printf '<h1>Demo</h1>\n<p>Inline:</p>\n<!-- shot: a.png -->\n' > "$d/site/mods/demo.html"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "concepts/x.html", "title": "Concept X", "section": "concepts", "order": 1, "source": "hand"},
  {"path": "mods/demo.html", "title": "Demo", "section": "mods", "order": 0, "source": "hand", "feature": "demo"}
]
JSON
  mkpng "$d/docs/images/demo/a.png" 30 20; mkpng "$d/docs/images/demo/b.png" 64 48
  printf -- '- a.png: First shot\n\n- b.png: Second & <third>\n' > "$d/docs/images/demo/captions.md"
}
# grc <repo>: build, print the exit code only
grc() { python3 "$MOD" --root "$1" >"$WORK/grc.out" 2>&1; echo $?; }
fx_png_no_caption() { local d="$WORK/fx-pnc"; mkgal "$d"; mkpng "$d/docs/images/demo/c.png" 5 5; [ "$(grc "$d")" = 2 ] && grep -Fq 'c.png' "$WORK/grc.out"; }
fx_caption_no_png() { local d="$WORK/fx-cnp"; mkgal "$d"; printf -- '- ghost.png: Not there\n' >> "$d/docs/images/demo/captions.md"; [ "$(grc "$d")" = 2 ] && grep -Fq 'ghost.png' "$WORK/grc.out"; }
fx_folder_no_page() { local d="$WORK/fx-fnp"; mkgal "$d"; mkdir "$d/docs/images/orphan"; mkpng "$d/docs/images/orphan/o.png" 5 5; [ "$(grc "$d")" = 2 ] && grep -Fq 'orphan' "$WORK/grc.out"; }
fx_feature_no_folder() {
  local d="$WORK/fx-fnf"; mkgal "$d"; rm -r "$d/docs/images/demo"
  [ "$(grc "$d")" = 2 ] && grep -Fq "no folder docs/images/demo/" "$WORK/grc.out"
}
fx_non_png() {
  local d="$WORK/fx-np"
  mkgal "$d"; printf 'x' > "$d/docs/images/demo/notes.txt"; [ "$(grc "$d")" = 2 ] || return 1
  mkgal "$d"; printf 'not a png' > "$d/docs/images/demo/c.png"; printf -- '- c.png: C\n' >> "$d/docs/images/demo/captions.md"; [ "$(grc "$d")" = 2 ] || return 1
  mkgal "$d"; printf 'x' > "$d/docs/images/stray.gif"; [ "$(grc "$d")" = 2 ] || return 1
  mkgal "$d"; mkdir "$d/docs/images/demo/sub"; [ "$(grc "$d")" = 2 ] || return 1
  mkgal "$d"; printf '# readme\n' > "$d/docs/images/README.md"; printf '# readme\n' > "$d/docs/images/demo/README.md"; [ "$(grc "$d")" = 0 ]
}
fx_folder_two_pages() {
  local d="$WORK/fx-ftp"; mkgal "$d"; printf '<h1>Two</h1>\n' > "$d/site/mods/two.html"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "mods/demo.html", "title": "Demo", "section": "mods", "order": 0, "source": "hand", "feature": "demo"},
  {"path": "mods/two.html", "title": "Two", "section": "mods", "order": 1, "source": "hand", "feature": "demo"}
]
JSON
  [ "$(grc "$d")" = 2 ] && grep -Fq 'mods/two.html' "$WORK/grc.out"
}
fx_caption_shape() { local d="$WORK/fx-csh"; mkgal "$d"; printf 'b.png - missing the dash form\n' >> "$d/docs/images/demo/captions.md"; [ "$(grc "$d")" = 2 ] && grep -Fq 'captions.md:' "$WORK/grc.out"; }
fx_caption_dup() { local d="$WORK/fx-cdup"; mkgal "$d"; printf -- '- a.png: Again\n' >> "$d/docs/images/demo/captions.md"; [ "$(grc "$d")" = 2 ] && grep -Fq 'twice' "$WORK/grc.out"; }
fx_shot_unknown() { local d="$WORK/fx-su"; mkgal "$d"; printf '<!-- shot: nope.png -->\n' >> "$d/site/mods/demo.html"; [ "$(grc "$d")" = 2 ] && grep -Fq 'nope.png' "$WORK/grc.out"; }
fx_shot_no_feature() { local d="$WORK/fx-snf"; mkgal "$d"; printf '<!-- shot: a.png -->\n' >> "$d/site/concepts/x.html"; [ "$(grc "$d")" = 2 ] && grep -Fq 'no `feature`' "$WORK/grc.out"; }
fx_feature_name() {
  local d="$WORK/fx-fn" f
  for f in 'Demo' 'a_b' 'a b' '.hid'; do   # each folder exists, so only the name rule can stop the build
    mkgal "$d"; mv "$d/docs/images/demo" "$d/docs/images/$f"; sed -i.bak "s#\"feature\": \"demo\"#\"feature\": \"$f\"#" "$d/site/pages.json"
    [ "$(grc "$d")" = 2 ] || return 1
  done
  mkgal "$d"; sed -i.bak 's#"feature": "demo"#"feature": "../x"#' "$d/site/pages.json"; [ "$(grc "$d")" = 2 ]
}

hd "gallery: renders"
G="$WORK/gal"; mkgal "$G"; printf '<h1>Demo</h1>\n' > "$G/site/mods/demo.html"
RC=$(grc "$G"); OUT=$(cat "$WORK/grc.out"); rc 0
python3 - "$G/docs/mods/demo.html" <<'PY' && ok "ends with a See it in Claude Code section: two figures, captions order, IHDR sizes, escaped captions, ids and :target links" || bad "gallery markup"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
body = h.split("<main", 1)[1]
i = body.index("See it in Claude Code")
assert body.index("</main>") > i and "<h2" in body[max(0, i - 60):i]
sec = body[i:]
figs = re.findall(r'<figure class="shot" id="([^"]+)">(.*?)</figure>', sec, re.S)
assert [f[0] for f in figs] == ["demo-a", "demo-b"], figs
assert '<div class="gallery" id="g-demo">' in sec
a, b = figs[0][1], figs[1][1]
assert '<a class="shot__open" href="#demo-a"><img loading="lazy" src="../images/demo/a.png" width="30" height="20" alt="First shot"></a>' in a, a
assert '<figcaption>First shot</figcaption>' in a and '<a class="shot__close" href="#g-demo">Close</a>' in a
assert 'src="../images/demo/b.png" width="64" height="48" alt="Second &amp; &lt;third&gt;"' in b and '<figcaption>Second &amp; &lt;third&gt;</figcaption>' in b
ids = re.findall(r'\sid="([^"]+)"', h)
assert len(ids) == len(set(ids)), ids
PY
sbuild "$G"; scheck "$G"; rc 0
# the wrapper page is not claimed: the gallery sits at the page end even when the body has no trailing newline
printf '<h1>Demo</h1>' > "$G/site/mods/demo.html"; sbuild "$G"; has_g=$(grep -c 'class="gallery"' "$G/docs/mods/demo.html"); [ "$has_g" = 1 ] && ok "one gallery" || bad "gallery count $has_g"
# docs/images is read, never written: files, captions and the README survive a build byte-for-byte
before=$(find "$G/docs/images" -type f | sort | xargs cat | cksum); sbuild "$G"; after=$(find "$G/docs/images" -type f | sort | xargs cat | cksum)
[ "$before" = "$after" ] && ok "docs/images untouched by the build" || bad "docs/images changed"
# a CRLF captions.md renders the same
cp "$G/docs/mods/demo.html" "$WORK/gal-lf.html"; sed -i.bak 's/$/\r/' "$G/docs/images/demo/captions.md"; sbuild "$G"
cmp -s "$G/docs/mods/demo.html" "$WORK/gal-lf.html" && ok "CRLF captions render identically" || bad "CRLF captions differ"

hd "gallery: inline shot"
G2="$WORK/gal2"; mkgal "$G2"; grc "$G2" >/dev/null
python3 - "$G2/docs/mods/demo.html" <<'PY' && ok "inline figure at the marker (own id, links to the gallery copy) and the gallery keeps it" || bad "inline markup"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
assert "<!--" not in h.split("<main", 1)[1], "marker left behind"
inline = '<figure class="shot" id="demo-a-inline"><a class="shot__open" href="#demo-a"><img loading="lazy" src="../images/demo/a.png" width="30" height="20" alt="First shot"></a><figcaption>First shot</figcaption></figure>'
assert inline in h
assert h.index("Inline:") < h.index(inline) < h.index("See it in Claude Code")
assert h.count('id="demo-a"') == 1 and h.count('id="demo-a-inline"') == 1
ids = re.findall(r'\sid="([^"]+)"', h)
assert len(ids) == len(set(ids)), ids
PY
hd "gallery: functions"
OUT=$(python3 - "$G2" "$MOD" <<'PY' 2>&1
import os, sys
from pathlib import Path
sys.path.insert(0, os.path.dirname(sys.argv[2])); import build_docs as m
root = Path(sys.argv[1])
g = m.gallery(root, "demo", "../")
assert 'src="../images/demo/a.png"' in g and g.count("<figure") == 2
assert m.gallery(root, "nothing") == ""
pgs = m.load_registry(root)
assert m.image_errors(root, pgs) == []
print("fns ok")
PY
); RC=$?; rc 0; has "fns ok"

hd "gallery: errors"
fx_png_no_caption && ok "a PNG with no caption exits 2" || bad "fx_png_no_caption"
fx_caption_no_png && ok "a caption with no PNG exits 2" || bad "fx_caption_no_png"
fx_folder_no_page && ok "a folder with no page exits 2" || bad "fx_folder_no_page"
fx_feature_no_folder && ok "a feature with no folder exits 2" || bad "fx_feature_no_folder"
fx_non_png && ok "a non-PNG (and a fake .png, a stray file, a subfolder) exits 2; README.md is allowed" || bad "fx_non_png"
fx_folder_two_pages && ok "two pages claiming one folder exits 2" || bad "fx_folder_two_pages"
fx_caption_shape && ok "a malformed caption line exits 2" || bad "fx_caption_shape"
fx_caption_dup && ok "a file captioned twice exits 2" || bad "fx_caption_dup"
fx_shot_unknown && ok "a shot marker naming an uncaptioned PNG exits 2" || bad "fx_shot_unknown"
fx_shot_no_feature && ok "a shot marker on a page with no feature exits 2" || bad "fx_shot_no_feature"
fx_feature_name && ok "an unsafe feature name exits 2" || bad "fx_feature_name"
# an unknown data/table marker is still an error, and the shot marker did not widen that rule
mkgal "$WORK/gal3"; printf '<!-- table: nope -->\n' >> "$WORK/gal3/site/concepts/x.html"; [ "$(grc "$WORK/gal3")" = 2 ] && ok "unknown <!-- table: x --> still exits 2" || bad "marker rule widened"

hd "mods: real page and no jira"
python3 - "$ROOT/site/pages.json" <<'PY' && ok "Mods registered as mods/index.html with no feature" || bad "Mods registry entry"
import json, sys
e = [p for p in json.load(open(sys.argv[1])) if p["path"] == "mods/index.html"]
assert len(e) == 1 and e[0]["section"] == "mods" and e[0]["order"] == 0 and e[0]["source"] == "hand" and "feature" not in e[0], e
PY
M="$ROOT/site/mods/index.html"
[ -f "$M" ] && grep -q 'questions sidebar' <(tr 'A-Z' 'a-z' < "$M") && grep -Fq 'v0.45.0' "$M" && grep -q 'progress panel' <(tr 'A-Z' 'a-z' < "$M") && grep -Fq 'v0.46.0' "$M" && ok "empty state names both planned mods" || bad "Mods empty state text"
if grep -REq 'https?://|/Users/|/home/' "$M"; then bad "Mods page carries a link or local path"; else ok "Mods page has no links or local paths"; fi
MR="$WORK/modsreal"; mkdir -p "$MR"; cp -R "$ROOT/site" "$MR/site"; cp -R "$ROOT/templates" "$MR/templates"; mkdir -p "$MR/docs"; for x in upgrades agents skills commands; do [ -d "$ROOT/$x" ] && cp -R "$ROOT/$x" "$MR/$x"; done
cp "$ROOT/CHANGELOG.md" "$MR/" 2>/dev/null; mkdir -p "$MR/docs/release-notes"; cp "$ROOT"/docs/release-notes/*.md "$MR/docs/release-notes/"
cp -R "$ROOT/docs/images" "$MR/docs/images"
python3 "$MOD" --root "$MR" >/dev/null 2>&1; [ "$?" = 0 ] && ok "the real tree builds" || bad "the real tree does not build"
if grep -rl 'atlassian.net' "$MR/docs" "$ROOT/site" 2>/dev/null | grep -q .; then bad "atlassian.net found in the output or site/"; else ok "no output file or site source contains atlassian.net"; fi
grep -Fq 'class="gallery"' "$MR/docs/mods/index.html" && bad "the real Mods page renders a gallery" || ok "the real Mods page renders no gallery (no feature folder yet)"
grep -Fq 'href="../mods/index.html"' "$MR/docs/index.html" 2>/dev/null; grep -Fq 'mods/index.html' "$MR/docs/index.html" && ok "the nav links Mods" || bad "nav lacks Mods"

# ---------------------------------------------------------------- concept pages (AOS-306)
# The five Concepts pages are hand bodies in site/concepts/. Every tiered node in a diagram carries data-tier and a
# mono tier chip (tier is never colour alone), the persona inspector reads #marvin-data (no model typed by hand), the
# old single page's anchors redirect from the root, the sidebar lists the current concept page's h2s (so the
# scroll-spy has targets), and every Around-the-loop card cites its guide on the Reference page.
CONCEPTS="lifecycle sizing escalation around-the-loop fleet"
hd "concepts: pages"
python3 - "$ROOT/site/pages.json" <<'PY' && ok "the five concept pages are registered in order, hand-written" || bad "concept registry entries"
import json, sys
want = ["concepts/lifecycle.html", "concepts/sizing.html", "concepts/escalation.html", "concepts/around-the-loop.html", "concepts/fleet.html"]
e = sorted((p for p in json.load(open(sys.argv[1])) if p["section"] == "concepts"), key=lambda p: p["order"])
assert [p["path"] for p in e] == want, [p["path"] for p in e]
assert all(p["source"] == "hand" and "feature" not in p for p in e), e
assert len({p["order"] for p in e}) == 5, "orders must be distinct"
PY
for c in $CONCEPTS; do
  [ -f "$ROOT/site/concepts/$c.html" ] && ok "site/concepts/$c.html exists" || bad "site/concepts/$c.html missing"
  [ -f "$ROOT/docs/concepts/$c.html" ] && ok "docs/concepts/$c.html built" || bad "docs/concepts/$c.html not built"
done
OUT=$(cat "$ROOT/docs/settings.html" 2>/dev/null); has '<a href="concepts/lifecycle.html">Concepts</a>'
OUT=$(cat "$ROOT/docs/concepts/sizing.html" 2>/dev/null); has '<a href="../concepts/lifecycle.html" aria-current="page">Concepts</a>'
if grep -REq 'https?://[^"]*atlassian|/Users/|/home/' "$ROOT"/site/concepts/*.html 2>/dev/null; then bad "a concept page carries a tracker link or a local path"; else ok "no tracker link or local path in site/concepts/"; fi

# TIERS_PY <built page>...: every tiered node is marked and chipped, every chip is scoped, every persona's hand-marked
# tier is the generated one, and every interactive SVG node is keyboard-reachable.
TIERS_PY='
import sys, pathlib, importlib.util as u
from html.parser import HTMLParser
root = pathlib.Path(sys.argv[1]); pages = sys.argv[2:]
s = u.spec_from_file_location("bd", root / "scripts/lib/build_docs.py"); m = u.module_from_spec(s); sys.modules["bd"] = m; s.loader.exec_module(m)
d = m.profile_data(root)
TIER = {k: v["tier"] for k, v in d["personas"].items()}; TIER["marvin"] = "orch"
NAME = {"orch": "orchestrator", "heavy": "heavy", "small": "small", "micro": "micro", "frontier": "frontier"}
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
class Tree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True); self.stack = []; self.nodes = []
    def node(self, tag, attrs):
        a = dict(attrs); n = {"tag": tag, "a": a, "cls": set((a.get("class") or "").split()), "up": self.stack[-1] if self.stack else None, "text": [], "kids": []}
        if n["up"]: n["up"]["kids"].append(n)
        self.nodes.append(n); return n
    def handle_starttag(self, tag, attrs):
        n = self.node(tag, attrs)
        if tag not in VOID: self.stack.append(n)
    def handle_startendtag(self, tag, attrs): self.node(tag, attrs)
    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i]["tag"] == tag: del self.stack[i:]; break
    def handle_data(self, t):
        for n in self.stack: n["text"].append(t)
def up(n):
    while n: yield n; n = n["up"]
def down(n):
    for k in n["kids"]: yield k; yield from down(k)
def tier_of(n): return next((x["a"]["data-tier"] for x in up(n) if "data-tier" in x["a"]), None)
def text(n): return "".join(n["text"]).strip().lower()
bad = []; counts = {}
for p in pages:
    t = Tree(); t.feed(open(p, encoding="utf-8").read()); name = pathlib.Path(p).name; c = counts[name] = {"chips": 0, "nodes": 0}
    for n in t.nodes:
        a, cls = n["a"], n["cls"]
        indiag = any("diagram" in x["cls"] for x in up(n))
        tag, pid0 = n["tag"], a.get("data-p")
        if "data-t" in a: bad.append(f"{name}: old data-t attribute on <{tag}>")
        if "chip" in cls:
            c["chips"] += 1
            if not any(x["cls"] & {"diagram", "tier-legend"} for x in up(n)): bad.append(f"{name}: a .chip outside .diagram/.tier-legend (its hue would not apply)")
            tr = tier_of(n)
            if tr not in NAME: bad.append(f"{name}: a .chip with no data-tier on it or an ancestor: {a}")
            elif not any("tier" in k["cls"] and text(k) == NAME[tr] for k in down(n)): bad.append(f"{name}: a {tr} chip whose .tier text is not {NAME[tr]!r}")
        if indiag and "data-tier" in a and "diagram" not in cls:
            tr = a["data-tier"]
            if tr not in NAME: bad.append(f"{name}: unknown data-tier {tr!r}")
            elif "chip" not in cls and not any("chip" in k["cls"] and tier_of(k) == tr for k in down(n)): bad.append(f"{name}: a data-tier={tr} node with no {tr} chip inside: {a}")
        if indiag and "p" in cls and n["tag"] == "g":
            c["nodes"] += 1
            for k, v in (("tabindex", "0"), ("role", "button")):
                if a.get(k) != v: bad.append(f"{name}: SVG persona node {pid0} lacks {k}={v}")
            if not a.get("aria-label"): bad.append(f"{name}: SVG persona node without aria-label")
            if "data-tier" not in a: bad.append(f"{name}: SVG persona node without data-tier")
        if n["tag"] == "button" and "chip" in cls and a.get("type") != "button": bad.append(f"{name}: chip button without type=button")
        if "data-p" in a:
            pid = a["data-p"]
            if pid not in TIER: bad.append(f"{name}: data-p={pid!r} is not a shipped persona (or marvin)")
            elif tier_of(n) != TIER[pid]: bad.append(f"{name}: {pid} is marked {tier_of(n)!r}, the generated tier is {TIER[pid]!r}")
for k, v in sorted(counts.items()): print(k, v)
for b in bad: print("PROBLEM:", b)
sys.exit(1 if bad else 0)
'
hd "concepts: tiers marked"
OUT=$(python3 -c "$TIERS_PY" "$ROOT" "$ROOT"/docs/concepts/*.html 2>&1); RC=$?; rc 0
has 'lifecycle.html {'; has 'sizing.html {'; has 'escalation.html {'; has 'around-the-loop.html {'
python3 - "$ROOT" <<'PY' && ok "lifecycle has >=10 keyboard SVG nodes; sizing, escalation, around have chips" || bad "concept pages lost their persona nodes"
import re, sys, pathlib
r = pathlib.Path(sys.argv[1]) / "docs/concepts"
lc = (r / "lifecycle.html").read_text()
assert len(re.findall(r'<g class="p"[^>]*tabindex="0"', lc)) >= 10
for f in ("sizing", "escalation", "around-the-loop"):
    assert len(re.findall(r'<button type="button" class="chip"', (r / f"{f}.html").read_text())) >= 3, f
PY
# the checker itself catches each defect shape
mkdir -p "$WORK/tiers"
printf '<div class="diagram"><button type="button" class="chip" data-p="developer" data-tier="heavy"><span class="tier">small</span></button></div>\n' > "$WORK/tiers/a.html"
printf '<div class="diagram"><div class="rung" data-tier="small"><p>no chip</p></div></div>\n' > "$WORK/tiers/b.html"
printf '<p><button type="button" class="chip" data-p="ponytail" data-tier="micro"><span class="tier">micro</span></button></p>\n' > "$WORK/tiers/c.html"
printf '<div class="diagram"><button type="button" class="chip" data-p="developer" data-tier="small"><span class="tier">small</span></button></div>\n' > "$WORK/tiers/d.html"
printf '<div class="diagram"><svg><g class="p" data-p="ponytail" data-tier="micro"><g class="chip"><text class="tier">micro</text></g></g></svg></div>\n' > "$WORK/tiers/e.html"
printf '<div class="diagram"><span class="lg" data-t="heavy">x</span></div>\n' > "$WORK/tiers/f.html"
for f in a b c d e f; do OUT=$(python3 -c "$TIERS_PY" "$ROOT" "$WORK/tiers/$f.html" 2>&1); [ "$?" = 1 ] && ok "defect $f caught" || bad "defect $f not caught ($OUT)"; done
printf '<div class="diagram"><svg><g class="p" data-p="ponytail" data-tier="micro" tabindex="0" role="button" aria-label="ponytail"><g class="chip"><text class="tier">micro</text></g></g></svg><button type="button" class="chip" data-p="marvin" data-tier="orch"><span class="tier">orchestrator</span></button></div>\n' > "$WORK/tiers/good.html"
OUT=$(python3 -c "$TIERS_PY" "$ROOT" "$WORK/tiers/good.html" 2>&1); [ "$?" = 0 ] && ok "a well-marked fragment passes" || bad "good fragment rejected ($OUT)"

hd "concepts: inspector data"
OUT=$(cat "$ROOT/docs/concepts/lifecycle.html" 2>/dev/null)
has '<script type="application/json" id="marvin-data">'; has 'id="insp"'; has 'aria-live="polite"'; has '<div class="tier-legend">'; has 'settings.html#model_profile'
for f in lifecycle sizing escalation around-the-loop; do grep -Fq '<!-- data: profiles -->' "$ROOT/site/concepts/$f.html" 2>/dev/null && ok "$f carries the data marker" || bad "$f lacks <!-- data: profiles -->"; done
grep -Fq '<!-- table: profiles -->' "$ROOT/site/concepts/lifecycle.html" 2>/dev/null && ok "lifecycle carries the profiles table" || bad "lifecycle lacks <!-- table: profiles -->"
grep -Fq '<!-- table: codex -->' "$ROOT/site/concepts/around-the-loop.html" 2>/dev/null && ok "around the loop carries the codex table" || bad "around-the-loop lacks <!-- table: codex -->"
OUT=$(cat "$JS"); has 'function initInspector'; has 'getElementById("marvin-data")'; has 'JSON.parse'
python3 - "$ROOT" <<'PY' && ok "site.js persona notes cover exactly the shipped personas plus marvin" || bad "site.js NOTES drifted from agents/"
import re, sys, pathlib, importlib.util as u
root = pathlib.Path(sys.argv[1])
s = u.spec_from_file_location("bd", root / "scripts/lib/build_docs.py"); m = u.module_from_spec(s); sys.modules["bd"] = m; s.loader.exec_module(m)
js = (root / "site/assets/site.js").read_text()
blk = re.search(r"var NOTES = \{\n(.*?)\n  \};", js, re.S)
assert blk, "no NOTES block"
keys = set(re.findall(r'^    "([a-z-]+)": \{', blk.group(1), re.M))
want = set(m.profile_data(root)["personas"]) | {"marvin"}
assert keys == want, ("site/assets/site.js NOTES block drifted from agents/: add a note there for each persona in 'missing', "
                      "remove the note for each in 'extra'", {"extra": sorted(keys - want), "missing": sorted(want - keys)})
for stem in re.findall(r'rules: "([a-z-]+)"', blk.group(1)):
    assert (root / "templates/marvin/agents" / f"{stem}.md").is_file(), stem
PY

hd "redirect: old anchors"
python3 - "$ROOT" <<'PY' && ok "site.js maps the old page's six anchors to the concept page that carries each id" || bad "old-anchor map"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); js = (root / "site/assets/site.js").read_text()
blk = re.search(r"var OLD_ANCHORS = \{(.*?)\};", js, re.S)
assert blk, "no OLD_ANCHORS block"
got = dict(re.findall(r'"(#[a-z]+)": "(concepts/[a-z-]+\.html)"', blk.group(1)))
want = {"#ladder": "concepts/escalation.html", "#stair": "concepts/escalation.html", "#signals": "concepts/escalation.html",
        "#lanes": "concepts/sizing.html", "#around": "concepts/around-the-loop.html", "#insp": "concepts/lifecycle.html"}
assert got == want, got
for h, t in want.items():
    assert f'id="{h[1:]}"' in (root / "docs" / t).read_text(), (h, t)
assert "location.replace(" in js
PY
OUT=$(sed -n '/function initOldAnchors/,/^});/p' "$JS"); has 'location.replace('; has 'rootPrefix() !== ""'; has 'index\.html'

hd "sidebar: in-page headings"
fx_toc() {
  local d="$WORK/fx-toc"; mkrepo "$d"
  printf '<h1>X</h1>\n<h2 id="alpha">Alpha <code>b</code> &amp; c</h2>\n<p>t</p>\n<h2 id="beta">Beta</h2>\n<h3 id="gamma">Gamma</h3>\n' > "$d/site/concepts/x.html"
  printf '<h1>Y</h1>\n<h2 id="why">Why</h2>\n' > "$d/site/concepts/y.html"
  cat > "$d/site/pages.json" <<'JSON'
[
  {"path": "index.html", "title": "Home", "section": "home", "order": 0, "source": "hand"},
  {"path": "concepts/x.html", "title": "Concept X", "section": "concepts", "order": 1, "source": "hand"},
  {"path": "concepts/y.html", "title": "Concept Y", "section": "concepts", "order": 2, "source": "hand"}
]
JSON
  sbuild "$d" || return 1
  OUT=$(cat "$d/docs/concepts/x.html")
  printf '%s' "$OUT" | grep -Fq '<li><a href="../concepts/x.html" aria-current="page">Concept X</a><ul><li><a href="#alpha">Alpha b &amp; c</a></li><li><a href="#beta">Beta</a></li></ul></li><li><a href="../concepts/y.html">Concept Y</a></li>' || return 1
  printf '%s' "$OUT" | grep -Fq 'href="#gamma"' && return 1
  grep -Fq '<li><a href="../concepts/x.html">Concept X</a></li><li><a href="../concepts/y.html" aria-current="page">Concept Y</a><ul><li><a href="#why">Why</a></li></ul></li>' "$d/docs/concepts/y.html"
}
fx_toc && ok "the current concept page's h2s nest under its sidebar entry, other entries stay flat" || bad "fx_toc"
OUT=$(cat "$ROOT/docs/concepts/lifecycle.html" 2>/dev/null); has 'aria-current="page">Lifecycle</a><ul><li><a href="#'
OUT=$(cat "$ROOT/docs/releases/index.html" 2>/dev/null); lacks '<ul><li><a href="#'

hd "concepts: guide links resolve"
python3 - "$ROOT" <<'PY' && ok "every Around-the-loop card cites its guide, and every ../reference.html# link on a concept page resolves" || bad "a concept page cites a missing guide anchor"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); docs = root / "docs"
ids = set(re.findall(r'\bid="([^"]+)"', (docs / "reference.html").read_text()))
sids = set(re.findall(r'\bid="([^"]+)"', (docs / "settings.html").read_text())) | set(re.findall(r'\bid="([^"]+)"', (docs / "skills.html").read_text()))
missing = []
for f in sorted((docs / "concepts").glob("*.html")):
    t = f.read_text()
    for a in re.findall(r'href="\.\./reference\.html#([^"]+)"', t):
        if a not in ids: missing.append((f.name, "reference", a))
    for page, a in re.findall(r'href="\.\./(settings|skills)\.html#([^"]+)"', t):
        if a not in sids: missing.append((f.name, page, a))
assert not missing, missing
around = (docs / "concepts/around-the-loop.html").read_text()
cards = re.findall(r'<article class="card">(.*?)</article>', around, re.S)
assert len(cards) >= 8, len(cards)
nolink = [c[:60] for c in cards if not re.search(r'href="\.\./reference\.html#[a-z-]+"', c)]
assert not nolink, nolink
fl = (docs / "concepts/fleet.html").read_text()
for need in ('href="../reference.html#fleet"', 'href="../reference.html#fleet-child"', "<svg", "/marvin:fleet stop"):
    assert need in fl, need
PY

# ---------------------------------------------------------------- Home, Getting started, the slim README, the rules (AOS-307)
# Home links every top section and carries the 30-second map and the wireframe grid (off under reduced motion).
# Getting started holds what README used to explain. README keeps the pitch, the install one-liner, a Documentation
# block, Contributing, the Inventory and the License, and every README.md#<anchor> link in the repo still resolves.
# CLAUDE.md and AGENTS.md carry rules 8, 10 and 11 identically, and those rules name the site.
SITE_URL="https://zenosyne-technologies.github.io/agent-operating-kit/"
HOME_SRC="$ROOT/site/index.html"
hd "home: links"
for t in start.html concepts/lifecycle.html concepts/sizing.html concepts/escalation.html concepts/around-the-loop.html concepts/fleet.html settings.html skills.html reference.html mods/index.html releases/index.html; do
  grep -Fq "href=\"$t\"" "$HOME_SRC" 2>/dev/null && ok "the Home body links $t" || bad "the Home body does not link $t"
done
OUT=$(cat "$ROOT/docs/index.html" 2>/dev/null); has '<title>Home - Marvin</title>'; lacks 'Marvin - Marvin'; lacks 'being rebuilt'

hd "home: the 30-second map and the grid"
python3 - "$HOME_SRC" <<'PY' && ok "the map is a .diagram (id=map) of stages with tier chips, linked to the lifecycle page" || bad "Home map"
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<(div|section) class="diagram[^"]*" id="map"[^>]*>(.*?)<!-- /map -->', t, re.S)
assert m, "no .diagram#map ... <!-- /map --> block"
body = m.group(2)
assert len(re.findall(r'class="chip"[^>]*data-tier="', body)) >= 6, "fewer than six tier chips in the map"
assert 'href="concepts/lifecycle.html"' in body, "the map does not link the lifecycle page"
assert len(re.findall(r'class="st"', body)) >= 5, "fewer than five stages"
PY
OUT=$(python3 -c "$TIERS_PY" "$ROOT" "$ROOT/docs/index.html" 2>&1); RC=$?; rc 0; has 'index.html {'
grep -Eq 'class="[^"]*\bwire-grid\b' "$HOME_SRC" 2>/dev/null && ok "Home paints the wireframe grid" || bad "Home has no .wire-grid band"
python3 - "$CSS" <<'PY' && ok "the grid is drawn by .wire-grid::before and removed under prefers-reduced-motion: reduce" || bad "wire-grid CSS"
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
assert re.search(r"\.wire-grid::before\s*\{[^}]*background-image", css), "no grid drawing"
i = css.index("@media (prefers-reduced-motion: reduce)")
depth, j = 0, css.index("{", i)
for k in range(j, len(css)):
    depth += {"{": 1, "}": -1}.get(css[k], 0)
    if depth == 0: block = css[j:k]; break
assert re.search(r"\.wire-grid::before\s*\{\s*display:\s*none", block), "grid not removed under reduced motion"
PY

hd "start: page"
python3 - "$ROOT/site/pages.json" <<'PY' && ok "start.html is registered, hand-written, in the start section" || bad "start.html registry entry"
import json, sys
e = [p for p in json.load(open(sys.argv[1])) if p["path"] == "start.html"]
assert len(e) == 1 and e[0]["section"] == "start" and e[0]["source"] == "hand" and "feature" not in e[0], e
h = [p for p in json.load(open(sys.argv[1])) if p["path"] == "index.html"]
assert h and h[0]["title"] == "Home", h
PY
OUT=$(cat "$ROOT/docs/start.html" 2>/dev/null)
has '<a href="start.html" aria-current="page">Getting started</a>'
has 'claude plugin marketplace add Zenosyne-Technologies/emprove-marketplace'; has 'claude plugin install marvin@emprove'
has 'claude plugin update marvin@emprove'; has '/marvin:install-agent-os'; has '/marvin:upgrade-agent-os'; has '/marvin:whats-new'
for id in install first-session pm-tools manual-install upgrading hooks windows portability; do has "id=\"$id\""; done
for t in Linear Jira 'GitHub Issues' Local; do has "<td><strong>$t</strong></td>"; done
has 'href="settings.html#model_profile"'
if grep -REq 'https?://[^"]*atlassian|/Users/|/home/' "$ROOT/site/start.html" "$HOME_SRC" 2>/dev/null; then bad "Home or Getting started carries a tracker link or a local path"; else ok "no tracker link or local path on Home or Getting started"; fi

hd "readme: slim"
python3 - "$ROOT/README.md" "$SITE_URL" <<'PY' && ok "README keeps the pitch, install, docs block, contributing, inventory and licence, and nothing else" || bad "README is not slim"
import re, sys
t = open(sys.argv[1], encoding="utf-8").read(); url = sys.argv[2]
heads, fence = [], False
for line in t.splitlines():
    if line.startswith("```"): fence = not fence; continue
    if not fence and re.match(r"#{1,6} ", line): heads.append(line.split(" ", 1)[1].strip())
for need in ("At a glance", "Documentation", "Contributing", "Inventory", "License"):
    assert any(h.endswith(need) for h in heads), f"missing heading {need!r}: {heads}"
for gone in ("How it works", "PM tools", "Skills and commands", "The discipline stack", "What you get", "Quickstart",
             "Manual install", "Updating and migrating", "Marvin himself", "SessionStart hook", "Windows", "Portability notes"):
    assert gone not in heads, f"README still has ## {gone}"
d = t.split("## Documentation", 1)[1].split("\n## ", 1)[0]
assert url in d, "the Documentation block does not link the site"
for p in ("start.html", "concepts/lifecycle.html", "concepts/fleet.html", "settings.html", "skills.html", "reference.html", "mods/index.html", "releases/index.html"):
    assert url + p in d, f"the Documentation block lacks {p}"
assert "claude plugin marketplace add Zenosyne-Technologies/emprove-marketplace" in t and "claude plugin install marvin@emprove" in t, "no install one-liner"
assert "```mermaid" not in t, "a mermaid diagram is left in README"
PY

# ANCHORS_PY <root> [file...]: every README.md#<anchor> link (in the given files, else in every tracked file outside
# docs/superpowers/ and .superpowers/, and this suite, whose fixtures dangle on purpose) and every in-page #<anchor> link inside README itself names a heading README still
# has, under GitHub's slug rule. `--slug <text>` prints one slug.
ANCHORS_PY='
import re, sys, subprocess, unicodedata, pathlib
def slug(text):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text).strip().lower()
    keep = "".join(c for c in text if c in " -" or unicodedata.category(c)[0] in "LMN" or unicodedata.category(c) == "Pc")
    return keep.replace(" ", "-")
if sys.argv[1] == "--slug": print(slug(sys.argv[2])); sys.exit(0)
root = pathlib.Path(sys.argv[1]); files = sys.argv[2:]
readme = (root / "README.md").read_text(encoding="utf-8")
seen, slugs, fence = {}, set(), False
for line in readme.splitlines():
    if line.startswith("```"): fence = not fence; continue
    m = None if fence else re.match(r"#{1,6} (.+)", line)
    if m:
        s = slug(m.group(1)); n = seen.get(s, 0); seen[s] = n + 1
        slugs.add(s if n == 0 else f"{s}-{n}")
if not files:
    out = subprocess.run(["git", "-C", str(root), "ls-files"], capture_output=True, text=True, check=True).stdout.split()
    files = [f for f in out if not f.startswith(("docs/superpowers/", ".superpowers/")) and f != "scripts/test-build-docs.sh"]
bad = []
for f in files:
    p = root / f
    try: t = p.read_text(encoding="utf-8")
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError): continue
    for a in re.findall(r"(?:\]\(|href=\")[^)\"\s]*README\.md#([A-Za-z0-9_%-]+)", t):
        if a not in slugs: bad.append(f"{f}: README.md#{a}")
    if f == "README.md":
        for a in re.findall(r"\]\(#([^)\s]+)\)", t):
            if a not in slugs: bad.append(f"README.md: #{a}")
for b in bad: print("DANGLING:", b)
sys.exit(1 if bad else 0)
'
hd "readme: anchors"
OUT=$(python3 -c "$ANCHORS_PY" --slug "✨ At a glance"); [ "$OUT" = "-at-a-glance" ] && ok "slug: ✨ At a glance -> -at-a-glance" || bad "slug of the At a glance heading is '$OUT'"
OUT=$(python3 -c "$ANCHORS_PY" --slug "Marvin himself: \`MEMORY.md\` & [the hook](x.md)"); [ "$OUT" = "marvin-himself-memorymd--the-hook" ] && ok "slug strips punctuation, code ticks and link targets" || bad "slug rule: '$OUT'"
OUT=$(python3 -c "$ANCHORS_PY" "$ROOT" 2>&1); RC=$?; rc 0
AF="$WORK/anchors"; mkdir -p "$AF"
printf '# T\n\n- [k](#kept)\n\n## Kept\n\n## Kept\n' > "$AF/README.md"
printf 'see [x](README.md#kept) and [y](README.md#kept-1)\n' > "$AF/ok.md"
printf 'see [x](README.md#gone)\n' > "$AF/dangling.md"
printf '# T\n\n- [n](#nope)\n' > "$AF/README2.md"
OUT=$(python3 -c "$ANCHORS_PY" "$AF" ok.md README.md 2>&1); [ "$?" = 0 ] && ok "a live anchor (and a duplicate heading's -1) passes" || bad "a live anchor was rejected ($OUT)"
OUT=$(python3 -c "$ANCHORS_PY" "$AF" ok.md dangling.md 2>&1); RC=$?; rc 1; has 'DANGLING: dangling.md: README.md#gone'
mv "$AF/README2.md" "$AF/README.md"; OUT=$(python3 -c "$ANCHORS_PY" "$AF" README.md 2>&1); RC=$?; rc 1; has 'DANGLING: README.md: #nope'

hd "readme: suites and gates"
python3 - "$ROOT" <<'PY' && ok "README lists every suite, spells their number, and counts the gate's checks right" || bad "README suite list or counts"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); t = (root / "README.md").read_text(encoding="utf-8")
W = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty".split()
W += ["twenty-" + w for w in W[1:10]] + ["thirty"]
suites = sorted(p.name for p in (root / "scripts").glob("test-*.sh"))
listed = sorted(re.findall(r"^bash scripts/(test-[a-z0-9-]+\.sh)$", t, re.M))
assert listed == suites, (listed, suites)
m = re.search(r"the static release gate and the ([a-z-]+) test suites", t); assert m and W.index(m.group(1)) == len(suites), m and m.group(1)
checks = len(re.findall(r"^# ── [0-9]+\. ", (root / "scripts/validate-kit.sh").read_text(encoding="utf-8"), re.M))
m = re.search(r"The static gate's ([a-z-]+) checks", t); assert m and W.index(m.group(1)) == checks, (m and m.group(1), checks)
PY

hd "rules: 8, 10 and 11 name the site"
python3 - "$ROOT" <<'PY' && ok "CLAUDE.md and AGENTS.md carry the same rules 8/10/11, and they name site/, the build and its check" || bad "rules 8/10/11"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
def rules(f):
    return {m.group(1): m.group(0) for m in re.finditer(r"^(8|10|11)\. .*$", (root / f).read_text(encoding="utf-8"), re.M)}
c, a = rules("CLAUDE.md"), rules("AGENTS.md")
assert set(c) == {"8", "10", "11"}, sorted(c)
for k in c: assert c[k] == a.get(k), f"rule {k} differs between CLAUDE.md and AGENTS.md"
r8 = c["8"]
assert "docs-site build" in r8, "rule 8 does not list the docs-site build suite"
items = r8.split("suite** (", 1)[1].split(" — CI runs them all", 1)[0].split(", ")
assert len(items) == len(list((root / "scripts").glob("test-*.sh"))), (len(items), items)
r10 = c["10"]
for need in ("the README (the inventory row for every file added, renamed or removed; the gate and suite counts and lists)",
             "the site page under `site/` that covers the changed area, regenerated with `scripts/build-docs.sh`"):
    assert need in r10, f"rule 10 lacks: {need}"
for gone in ("the skills and commands table", "the section that describes a consumer-visible behaviour", "`docs/index.html` where it describes"):
    assert gone not in r10, f"rule 10 still says: {gone}"
r11 = c["11"]
for need in ("`site/`", "`site/concepts/`", "`site/mods/<feature>.html`", '`"feature": "<feature>"`', "`site/pages.json`",
             "`docs/images/<feature>/`", "`captions.md`", "`scripts/build-docs.sh --check`", "`docs-site`"):
    assert need in r11, f"rule 11 lacks {need}"
assert "(`docs/index.html`)" not in r11, "rule 11 still names docs/index.html as the guide"
PY

hd "validate-kit: marketplace scans the whole site"
# Runs the check's own scan lines (between its header and its verdict) in a fixture tree.
MK_SCAN=$(sed -n '/^# ── 25\. marketplace/,/^\[ -z "\$mk" \]/p' "$ROOT/scripts/validate-kit.sh" | grep -vE '^#|^\[ -z')
MKF="$WORK/mkt"; mkdir -p "$MKF/docs/releases" "$MKF/docs/concepts" "$MKF/site/concepts" "$MKF/skills" "$MKF/templates" "$MKF/commands"
printf 'claude plugin marketplace add Zenosyne-Technologies/emprove-marketplace\n' > "$MKF/docs/index.html"
printf 'claude plugin marketplace add Zenosyne-Technologies/agent-operating-kit\n' > "$MKF/docs/releases/v1.html"
printf 'claude plugin marketplace add Zenosyne-Technologies/agent-operating-kit\n' > "$MKF/site/concepts/x.html"
printf 'claude plugin marketplace add Zenosyne-Technologies/emprove-marketplace\n' > "$MKF/README.md"; : > "$MKF/BOOTSTRAP.md"
OUT=$(cd "$MKF" && { eval "$MK_SCAN"; printf '%s' "$mk"; }); has 'docs/releases/v1.html'; has 'site/concepts/x.html'; lacks 'docs/index.html'
rm "$MKF/docs/releases/v1.html" "$MKF/site/concepts/x.html"; OUT=$(cd "$MKF" && { eval "$MK_SCAN"; printf '[%s]' "$mk"; }); has '[]'

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
  "release-missing:fx_release_missing"
  "settings-behaviour:fx_settings_behaviour"
  "settings-install-missing:fx_settings_install_missing"
  "settings-install-extra:fx_settings_install_extra"
  "settings-install-dup:fx_settings_install_dup"
  "skill-description:fx_skill_description"
  "reference-header:fx_reference_header"
  "anchor-collision:fx_anchor_collision"
  "profile-parse:fx_profile_parse"
  "profile-tier:fx_profile_tier"
  "profile-default:fx_profile_default"
  "persona-tier:fx_persona_tier"
  "persona-alias:fx_persona_alias"
  "marker-unknown:fx_marker_unknown"
  "pi-frontmatter-missing:fx_pi_frontmatter_missing"
  "pi-frontmatter-unterminated:fx_pi_frontmatter_unterminated"
  "install-file-missing:fx_install_file_missing"
  "install-line-shape:fx_install_line_shape"
  "table-row-width:fx_table_row_width"
  "png-no-caption:fx_png_no_caption"
  "caption-no-png:fx_caption_no_png"
  "folder-no-page:fx_folder_no_page"
  "feature-no-folder:fx_feature_no_folder"
  "non-png:fx_non_png"
  "folder-two-pages:fx_folder_two_pages"
  "caption-shape:fx_caption_shape"
  "caption-dup:fx_caption_dup"
  "shot-unknown:fx_shot_unknown"
  "shot-no-feature:fx_shot_no_feature"
  "feature-name:fx_feature_name"
  "registry-json:fx_registry_json"
  "registry-list:fx_registry_list"
  "registry-entry:fx_registry_entry"
  "registry-key:fx_registry_key"
  "registry-types:fx_registry_types"
  "registry-path:fx_registry_path"
  "registry-feature-type:fx_registry_feature_type"
  "registry-generator:fx_registry_generator"
  "registry-source:fx_registry_source"
  "build-orphan:fx_build_orphan"
  "page-unreachable:fx_unreachable"
  "settings-bullet-wrap:fx_settings_bullet_wrap"
  "changelog-heading:fx_changelog_heading"
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
