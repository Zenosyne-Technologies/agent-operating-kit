#!/usr/bin/env python3
"""build_docs.py - the Marvin docs-site generator (AOS-299). Stdlib only, Python 3.10+.

This module owns (AOS-300) the markdown SUBSET renderer: RenderError, split_front_matter, render_markdown,
and (AOS-301) the site build: Page, load_registry, build, check, the generator dispatch table GENERATORS and
the CLI `[--check] [--root DIR] [--render FILE]`.

The subset: ATX headings, paragraphs (hard-wrapped), **bold**, *italic*, `code`, links, fenced code,
unordered (`-`) and ordered (`1.`) lists nested to any depth, GFM pipe tables, blockquotes, horizontal rules.
HTML in a source is escaped, never passed through. Anything the renderer cannot classify FAILS with
`file:line: message` - it never degrades silently. Output is LF, UTF-8, deterministic.

Every rule that raises carries a trailing `# GUARD:<name>` comment; scripts/test-build-docs.sh copies this
module with that line neutralised and asserts the named fixture then fails.
"""
from __future__ import annotations

import html
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


class RenderError(Exception):
    """A source line the renderer will not guess at. str() is `src:line: msg`."""

    def __init__(self, src: str, line: int, msg: str) -> None:
        super().__init__(f"{src}:{line}: {msg}")
        self.src, self.line, self.msg = src, line, msg


# ---------------------------------------------------------------- front matter

_HDR_KEY = re.compile(r"^[A-Za-z_][\w-]*:(?:\s.*)?$")
_HDR_CONT = re.compile(r"^(?:\s+\S.*|- .*)$")
_HDR_PARSE = re.compile(r"^([A-Za-z_][\w-]*):\s*(.*)$")


def _norm(text: str) -> str:
    if text.startswith("﻿"):
        text = text[1:]
    return text.replace("\r\n", "\n").replace("\r", "\n")


def split_front_matter(text: str) -> tuple[dict[str, str], str]:
    """Split a leading `---` ... `---` YAML header (document-standard) from the body.

    The header must open on the very first line and every line in it must be `key: value`, an indented
    continuation or a `- item`; anything else means the opening `---` was a horizontal rule, not a header.
    No header -> ({}, text) (text returned unchanged). Keys map to their raw string values.
    """
    t = _norm(text)
    if not t.startswith("---\n"):
        return {}, text
    lines = t.split("\n")
    for end in range(1, len(lines)):
        if lines[end].rstrip() == "---":
            break
    else:
        return {}, text
    keys: dict[str, str] = {}
    for ln in lines[1:end]:
        if not ln.strip():
            continue
        m = _HDR_PARSE.match(ln)
        if m and _HDR_KEY.match(ln):
            keys[m.group(1)] = m.group(2).strip()
        elif _HDR_CONT.match(ln):
            continue
        else:
            return {}, text
    return keys, "\n".join(lines[end + 1:])


# ---------------------------------------------------------------- guards

def _unknown(src: str, line: int, msg: str) -> None:
    raise RenderError(src, line, msg)  # GUARD:md-unknown


def _raw_html(src: str, line: int, msg: str) -> None:
    raise RenderError(src, line, msg)  # GUARD:md-raw-html


def _bad_scheme(src: str, line: int, href: str) -> None:
    raise RenderError(src, line, f"link scheme not allowed: {href}")  # GUARD:md-link-scheme


# ---------------------------------------------------------------- inline pass

_INLINE = re.compile(
    r"""
    (?P<code>(?<!`)(?P<tick>`+)(?!`)(?P<c>.+?)(?<!`)(?P=tick)(?!`))
  | (?P<esc>\\(?P<ch>[\\`*_{}\[\]()#+\-.!|<>~]))
  | (?P<link>\[(?P<lt>[^\[\]]+)\]\((?P<href>[^()\s]*(?:\([^()\s]*\)[^()\s]*)*)(?:\s+"(?P<title>[^"]*)")?\))
  | (?P<bold>\*\*(?=\S)(?P<b>.+?)(?<=\S)\*\*)
  | (?P<ital>\*(?=[^\s*])(?P<i>.+?)(?<=[^\s*])\*)
  | (?P<ubold>(?<!\w)__(?=\S)(?P<ub>.+?)(?<=\S)__(?!\w))
  | (?P<uital>(?<!\w)_(?=[^\s_])(?P<ui>.+?)(?<=[^\s_])_(?!\w))
    """,
    re.X | re.S,
)
_CTRL = re.compile(r"[\x00-\x20\x7f]")
_OK_SCHEMES = ("http:", "https:", "mailto:")


def _href_ok(href: str) -> bool:
    """Allowlist for the value that lands in the attribute: a fragment, a scheme-less relative URL, http(s), mailto."""
    if _CTRL.search(href):
        return False
    if href.startswith("#"):
        return True
    if ":" in re.split(r"[/?#]", href, maxsplit=1)[0]:  # a scheme (or something that parses like one)
        return href.lower().startswith(_OK_SCHEMES)
    return True


def _esc(s: str) -> str:
    return html.escape(s, quote=False)


def _inline(text: str, src: str, line: int, link_map: Callable[[str], str]) -> str:
    out: list[str] = []
    pos = 0
    for m in _INLINE.finditer(text):
        out.append(_esc(text[pos:m.start()]))
        pos = m.end()
        if m.group("code") is not None:
            c = m.group("c").replace("\n", " ")
            if len(c) > 2 and c[0] == " " and c[-1] == " " and c.strip():
                c = c[1:-1]
            out.append("<code>" + _esc(c) + "</code>")
        elif m.group("esc") is not None:
            out.append(_esc(m.group("ch")))
        elif m.group("link") is not None:
            href = m.group("href")
            mapped = link_map(href)
            if not _href_ok(mapped):
                _bad_scheme(src, line, mapped)
            attrs = html.escape(mapped, quote=True)
            title = m.group("title")
            tattr = f' title="{html.escape(title, quote=True)}"' if title is not None else ""
            out.append(f'<a href="{attrs}"{tattr}>' + _inline(m.group("lt"), src, line, link_map) + "</a>")
        elif m.group("bold") is not None:
            out.append("<strong>" + _inline(m.group("b"), src, line, link_map) + "</strong>")
        elif m.group("ital") is not None:
            out.append("<em>" + _inline(m.group("i"), src, line, link_map) + "</em>")
        elif m.group("ubold") is not None:
            out.append("<strong>" + _inline(m.group("ub"), src, line, link_map) + "</strong>")
        else:
            out.append("<em>" + _inline(m.group("ui"), src, line, link_map) + "</em>")
    out.append(_esc(text[pos:]))
    return "".join(out)


# ---------------------------------------------------------------- block pass

_FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})[ \t]*([^`]*?)[ \t]*$")
_HEADING = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$")
_HR = re.compile(r"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")
_QUOTE = re.compile(r"^ {0,3}>")
_ITEM = re.compile(r"^([ \t]*)(-|\d{1,9}[.)])([ \t]+)(\S.*)$")
_BAD_BULLET = re.compile(r"^[ \t]*[*+][ \t]+\S")
_TABLE_SEP = re.compile(r"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$")
_SETEXT = re.compile(r"^ {0,3}(?:=+|-+)[ \t]*$")
_REFDEF = re.compile(r"^ {0,3}\[[^\]]+\]:[ \t]*\S")
_IMAGE = re.compile(r"!\[[^\]]*\]\(")
_BLOCK_TAGS = (
    "address|article|aside|blockquote|body|br|center|dd|details|dialog|div|dl|dt|fieldset|figcaption|figure|"
    "footer|form|h[1-6]|head|header|hr|html|iframe|img|li|link|main|meta|nav|ol|p|pre|script|section|style|"
    "summary|svg|table|tbody|td|tfoot|th|thead|title|tr|ul|video"
)
_HTML_BLOCK = re.compile(rf"^ {{0,3}}<(?:/?(?:{_BLOCK_TAGS})(?=[\s/>]|$)|!|\?)", re.I)

Line = tuple[int, str]


def _indent(s: str) -> int:
    n = 0
    for ch in s:
        if ch == " ":
            n += 1
        elif ch == "\t":
            n += 4
        else:
            break
    return n


def _dedent(s: str, n: int) -> str:
    cols = 0
    i = 0
    while i < len(s) and cols < n:
        if s[i] == " ":
            cols += 1
        elif s[i] == "\t":
            if cols + 4 > n:
                break
            cols += 4
        else:
            break
        i += 1
    return s[i:]


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "section"


class _Ctx:
    def __init__(self, src: str, link_map: Callable[[str], str]) -> None:
        self.src, self.link_map = src, link_map
        self.ids: set[str] = set()

    def heading_id(self, rendered: str) -> str:
        base = _slug(html.unescape(re.sub(r"<[^>]+>", "", rendered)))
        cand, n = base, 1
        while cand in self.ids:
            n += 1
            cand = f"{base}-{n}"
        self.ids.add(cand)
        return cand

    def inline(self, text: str, line: int) -> str:
        return _inline(text, self.src, line, self.link_map)


def _starts_block(s: str) -> bool:
    """True when a non-blank line opens a block that interrupts a paragraph."""
    return bool(
        _FENCE.match(s) or _HEADING.match(s) or _HR.match(s) or _QUOTE.match(s) or _ITEM.match(s)
        or _HTML_BLOCK.match(s)
    )


def _split_row(s: str) -> list[str]:
    s = s.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s)]


def _table(lines: list[Line], i: int, ctx: _Ctx) -> tuple[str, int]:
    head_no, head = lines[i]
    sep = _split_row(lines[i + 1][1])
    cells = _split_row(head)
    aligns: list[str] = []
    for c in sep:
        left, right = c.startswith(":"), c.endswith(":")
        aligns.append("center" if left and right else "right" if right else "left" if left else "")
    if len(cells) != len(aligns):
        _unknown(ctx.src, head_no, "table header and alignment row differ in column count")
    n = len(cells)

    def row(tag: str, cs: list[str], no: int) -> str:
        if len(cs) > n:
            _unknown(ctx.src, no, f"table row has {len(cs)} cells but the header has {n}")
        cs = cs + [""] * (n - len(cs))
        tds = []
        for k, c in enumerate(cs):
            cls = f' class="align-{aligns[k]}"' if aligns[k] else ""
            tds.append(f"<{tag}{cls}>{ctx.inline(c, no)}</{tag}>")
        return "<tr>" + "".join(tds) + "</tr>"

    parts = ["<table>", "<thead>", row("th", cells, head_no), "</thead>", "<tbody>"]
    j = i + 2
    while j < len(lines) and lines[j][1].strip() and "|" in lines[j][1]:
        parts.append(row("td", _split_row(lines[j][1]), lines[j][0]))
        j += 1
    parts += ["</tbody>", "</table>"]
    return "\n".join(parts), j


def _list(lines: list[Line], i: int, ctx: _Ctx) -> tuple[str, int]:
    m0 = _ITEM.match(lines[i][1])
    assert m0 is not None
    base = _indent(m0.group(1))
    ordered = m0.group(2)[0].isdigit()
    items: list[tuple[int, list[Line]]] = []  # (content offset, lines) per item
    j = i
    n = len(lines)
    while j < n:
        no, s = lines[j]
        if not s.strip():
            k = j
            while k < n and not lines[k][1].strip():
                k += 1
            if k >= n:
                break
            nxt = lines[k][1]
            mi = _ITEM.match(nxt)
            if _indent(nxt) > base or (mi and _indent(mi.group(1)) == base and mi.group(2)[0].isdigit() == ordered):
                if items:
                    items[-1][1].extend((x, "") for x, _ in lines[j:k])
                j = k
                continue
            break
        mi = _ITEM.match(s)
        if mi and _indent(mi.group(1)) == base:
            if mi.group(2)[0].isdigit() != ordered:
                break
            width = base + len(mi.group(2)) + len(mi.group(3).replace("\t", "    "))
            items.append((width, [(no, mi.group(4))]))
            j += 1
            continue
        if mi and _indent(mi.group(1)) < base:
            break
        if not items:
            break
        prev_blank = not lines[j - 1][1].strip()
        if _indent(s) <= base and (prev_blank or _starts_block(s)):
            break
        items[-1][1].append((no, s))
        j += 1
    out = []
    for width, item in items:
        body: list[Line] = [item[0]] + [(no, _dedent(s, width)) for no, s in item[1:]]
        out.append(_item_html(body, ctx))
    tag = "ol" if ordered else "ul"
    start = ""
    if ordered:
        num = int(re.match(r"\d+", m0.group(2)).group(0))  # type: ignore[union-attr]
        start = f' start="{num}"' if num != 1 else ""
    return f"<{tag}{start}>\n" + "\n".join(out) + f"\n</{tag}>", j


def _item_html(body: list[Line], ctx: _Ctx) -> str:
    blocks = _blocks(body, ctx)
    paras = sum(1 for k, _ in blocks if k == "p")
    parts = [(h if paras == 1 else f"<p>{h}</p>") if k == "p" else h for k, h in blocks]
    return "<li>" + "\n".join(parts) + "</li>"


def _blocks(lines: list[Line], ctx: _Ctx) -> list[tuple[str, str]]:
    """Classify and render a block region. Returns (kind, html); kind 'p' html is the bare inline text."""
    out: list[tuple[str, str]] = []
    i, n = 0, len(lines)
    while i < n:
        no, s = lines[i]
        if not s.strip():
            i += 1
            continue
        m = _FENCE.match(s)
        if m:
            fence, info = m.group(1), m.group(2)
            body: list[str] = []
            i += 1
            closed = False
            while i < n:
                t = lines[i][1]
                if re.match(rf"^ {{0,3}}{re.escape(fence[0])}{{{len(fence)},}}[ \t]*$", t):
                    closed = True
                    i += 1
                    break
                body.append(t)
                i += 1
            if not closed:
                _unknown(ctx.src, no, "fenced code block is never closed")
            lang = re.sub(r"[^A-Za-z0-9_+-]", "", info.split()[0]) if info.split() else ""
            cls = f' class="lang-{lang}"' if lang else ""
            out.append(("pre", f"<pre><code{cls}>" + _esc("\n".join(body) + ("\n" if body else "")) + "</code></pre>"))
            continue
        m = _HEADING.match(s)
        if m:
            level = len(m.group(1))
            rendered = ctx.inline(m.group(2), no)
            out.append(("h", f'<h{level} id="{ctx.heading_id(rendered)}">{rendered}</h{level}>'))
            i += 1
            continue
        if _HR.match(s):
            out.append(("hr", "<hr>"))
            i += 1
            continue
        if _QUOTE.match(s):
            inner: list[Line] = []
            while i < n and lines[i][1].strip() and _QUOTE.match(lines[i][1]):
                inner.append((lines[i][0], re.sub(r"^ {0,3}> ?", "", lines[i][1])))
                i += 1
            sub = _blocks(inner, ctx)
            out.append(("quote", "<blockquote>\n" + "\n".join(h if k != "p" else f"<p>{h}</p>" for k, h in sub) + "\n</blockquote>"))
            continue
        if "|" in s and i + 1 < n and _TABLE_SEP.match(lines[i + 1][1]) and "-" in lines[i + 1][1]:
            h, i = _table(lines, i, ctx)
            out.append(("table", h))
            continue
        if s.lstrip().startswith("|"):
            _unknown(ctx.src, no, "table row without an alignment row beneath the header")
        if _ITEM.match(s):
            h, i = _list(lines, i, ctx)
            out.append(("list", h))
            continue
        if _HTML_BLOCK.match(s):
            _raw_html(ctx.src, no, "block-level HTML is not supported (write markdown, or add the construct to the subset)")
        if _BAD_BULLET.match(s):
            _unknown(ctx.src, no, "'*' and '+' bullets are not supported; use '-'")
        if _indent(s) >= 4:
            _unknown(ctx.src, no, "indented code blocks are not supported; use a fence")
        if _REFDEF.match(s):
            _unknown(ctx.src, no, "reference-style link definitions are not supported")
        # paragraph
        para: list[Line] = []
        while i < n and lines[i][1].strip():
            t = lines[i][1]
            if para and _SETEXT.match(t):
                _unknown(ctx.src, lines[i][0], "setext headings are not supported; use '#'")
            if para and _starts_block(t):
                break
            if _IMAGE.search(t):
                _unknown(ctx.src, lines[i][0], "images are not supported")
            para.append(lines[i])
            i += 1
        if not para:  # the line itself is a block start already rejected above; never loop
            para.append(lines[i])
            i += 1
        text = "\n".join(t.strip() for _, t in para)
        out.append(("p", ctx.inline(text, para[0][0])))
    return out


_YAML_LEAK = re.compile(r"(?m)^(?:<p>)?doc: ")
_PRE = re.compile(r"<pre>.*?</pre>", re.S)


def render_markdown(text: str, src: str, link_map: Callable[[str], str]) -> str:
    """Render the markdown subset to an HTML fragment (LF, trailing newline). Raises RenderError."""
    t = _norm(text)
    _, body = split_front_matter(t)
    offset = t.count("\n") - body.count("\n")
    lines = [(offset + k + 1, ln) for k, ln in enumerate(body.split("\n"))]
    ctx = _Ctx(src, link_map)
    parts = [h if k != "p" else f"<p>{h}</p>" for k, h in _blocks(lines, ctx)]
    out = "\n".join(parts) + ("\n" if parts else "")
    if _YAML_LEAK.search(_PRE.sub("", out)):
        raise RenderError(src, 1, "a YAML header leaked into the page (is it the first thing in the file?)")  # GUARD:md-header-leak
    return out


# ---------------------------------------------------------------- site build (AOS-301)

class BuildError(Exception):
    """Any rule violation in the site build; the message names the file."""


SECTIONS = ("home", "start", "concepts", "reference", "mods", "releases")
PROTECTED = ("images", "release-notes", "decisions", "superpowers")  # docs/ dirs the build never writes or removes
PROTECTED_FILES = (".nojekyll",)
TEXT_EXT = (".html", ".css", ".js", ".json", ".svg", ".txt", ".md", ".xml")
_TOKENS = re.compile(r"\{\{(TITLE|ROOT|NAV|SIDEBAR|BODY)\}\}")


@dataclass(frozen=True)
class Page:
    path: str
    title: str
    section: str
    order: int
    source: str
    feature: str | None = None


# Generator dispatch: "generated:<name>" registry entries expand to the pages GENERATORS[name](root) returns,
# {relpath: (title, body_html)}; the generator's own insertion order is the page order inside its section (the
# first entry sorts first, so a generator that returns its index first gets the section's nav link). AOS-303
# registers `releases`; later tasks register `settings`, `skills`, `reference` here.
GENERATORS: dict[str, Callable[[Path], dict[str, tuple[str, str]]]] = {}


def _claim(seen: set[str], path: str) -> None:
    """The one choke point every output path (registry, generated, asset) passes through."""
    segs = path.split("/")
    if not path or "\\" in path or path.startswith("/") or ":" in segs[0] or any(x in ("", ".", "..") for x in segs):
        raise BuildError(f"malformed output path (empty, '.'/'..' segment, backslash, leading '/' or ':'): {path!r}")  # GUARD:path-shape
    if _protected(path):
        raise BuildError(f"output path is under a protected docs/ path (never written by the build): {path}")  # GUARD:registry-protected
    if path in seen:
        raise BuildError(f"duplicate output path: {path}")  # GUARD:registry-dup
    seen.add(path)


def _read_text(p: Path) -> str:
    try:
        return _norm(p.read_bytes().decode("utf-8"))
    except (OSError, UnicodeDecodeError) as exc:
        raise BuildError(f"{p}: {exc}") from exc


def load_registry(root: Path) -> list[Page]:
    """Read site/pages.json: [{path,title,section,order,source,feature?}], validated, in registry order."""
    reg = root / "site" / "pages.json"
    try:
        data = json.loads(_read_text(reg))
    except (BuildError, ValueError) as exc:
        raise BuildError(f"site/pages.json: {exc}") from exc
    if not isinstance(data, list):
        raise BuildError("site/pages.json: top level must be a list")
    pages: list[Page] = []
    seen: set[str] = set()
    for k, e in enumerate(data):
        where = f"site/pages.json[{k}]"
        if not isinstance(e, dict):
            raise BuildError(f"{where}: entry must be an object")
        for key in ("path", "title", "section", "order", "source"):
            if key not in e:
                raise BuildError(f"{where}: missing '{key}'")
        if not all(isinstance(e[x], str) and e[x] for x in ("path", "title", "source")) or not isinstance(e["order"], int):
            raise BuildError(f"{where}: path/title/source must be non-empty strings and order an integer")
        if e["section"] not in SECTIONS:
            raise BuildError(f"{where}: unknown section '{e['section']}' (one of {', '.join(SECTIONS)})")  # GUARD:registry-section
        if e["path"].startswith("/") or ".." in e["path"].split("/"):
            raise BuildError(f"{where}: path must be relative and stay inside docs/: {e['path']}")
        feat = e.get("feature")
        if feat is not None and not isinstance(feat, str):
            raise BuildError(f"{where}: feature must be a string")
        _claim(seen, e["path"])
        pages.append(Page(e["path"], e["title"], e["section"], e["order"], e["source"], feat))
    return pages


def _expand(root: Path) -> list[tuple[Page, str]]:
    """Registry -> concrete (page, body_html) pairs, generated entries expanded, sorted (section, order, path)."""
    out: list[tuple[Page, str]] = []
    seen: set[str] = set()
    for pg in load_registry(root):
        if pg.source == "hand":
            _claim(seen, pg.path)
            out.append((pg, _read_text(root / "site" / pg.path)))
        elif pg.source.startswith("generated:"):
            name = pg.source[len("generated:"):]
            if name not in GENERATORS:
                raise BuildError(f"site/pages.json: no generator named '{name}' ({pg.path})")
            for k, (rel, (title, body)) in enumerate(GENERATORS[name](root).items()):
                _claim(seen, rel)
                out.append((Page(rel, title, pg.section, pg.order + k, pg.source, pg.feature), body))
        else:
            raise BuildError(f"site/pages.json: source must be 'hand' or 'generated:<name>': {pg.source}")
    out.sort(key=lambda t: (SECTIONS.index(t[0].section), t[0].order, t[0].path))
    return out


# top-nav: (label, section, exact page path or None = the section's first page). Items whose target is not
# registered are not rendered.
NAV = (
    ("Home", "home", "index.html"),
    ("Getting started", "start", "start.html"),
    ("Concepts", "concepts", None),
    ("Settings", "reference", "settings.html"),
    ("Skills & commands", "reference", "skills.html"),
    ("Reference", "reference", "reference.html"),
    ("Mods", "mods", None),
    ("Releases", "releases", None),
)


def _nav(pages: list[Page], cur: Page, prefix: str) -> str:
    paths = {p.path for p in pages}
    items: list[tuple[str, str, str]] = []
    for label, sec, path in NAV:
        if path is None:
            first = next((p.path for p in pages if p.section == sec), None)
            path = first or ""
        if path and path in paths:
            items.append((label, sec, path))
    cur_i = next((i for i, it in enumerate(items) if it[2] == cur.path), None)
    if cur_i is None:
        cur_i = next((i for i, it in enumerate(items) if it[1] == cur.section), None)
    rows = []
    for i, (label, _sec, path) in enumerate(items):
        mark = ' aria-current="page"' if i == cur_i else ""
        rows.append(f'<a href="{prefix}{html.escape(path)}"{mark}>{html.escape(label)}</a>')
    return '<nav class="top-nav" aria-label="Primary">' + "".join(rows) + "</nav>"


def _sidebar(pages: list[Page], cur: Page, prefix: str) -> str:
    if cur.section not in ("concepts", "releases"):
        return ""
    rows = []
    for p in pages:
        if p.section != cur.section:
            continue
        mark = ' aria-current="page"' if p.path == cur.path else ""
        label = p.title.split(" — ", 1)[0] if cur.section == "releases" else p.title  # 55 entries: the version, not the headline
        rows.append(f'<li><a href="{prefix}{html.escape(p.path)}"{mark}>{html.escape(label)}</a></li>')
    return '<aside class="sidebar"><nav aria-label="In this section"><ul>' + "".join(rows) + "</ul></nav></aside>"


def _assets(root: Path) -> dict[str, bytes]:
    base = root / "site" / "assets"
    out: dict[str, bytes] = {}
    if not base.is_dir():
        return out
    for f in sorted(base.rglob("*")):
        if not f.is_file():
            continue
        rel = "assets/" + f.relative_to(base).as_posix()
        raw = f.read_bytes()
        if f.suffix.lower() in TEXT_EXT:
            try:
                raw = _norm(raw.decode("utf-8")).encode("utf-8")
            except UnicodeDecodeError as exc:
                raise BuildError(f"{rel}: {exc}") from exc
        out[rel] = raw
    return out


def render_site(root: Path) -> dict[str, bytes]:
    """The whole site as {relpath under docs/: bytes}. Pure and deterministic; writes nothing."""
    shell = _read_text(root / "site" / "_shell.html")
    expanded = _expand(root)
    pages = [p for p, _ in expanded]
    files: dict[str, bytes] = {}
    seen: set[str] = set()
    for pg, body in expanded:
        _claim(seen, pg.path)
        prefix = "../" * pg.path.count("/")
        vals = {"TITLE": html.escape(pg.title), "ROOT": prefix, "NAV": _nav(pages, pg, prefix),
                "SIDEBAR": _sidebar(pages, pg, prefix), "BODY": body}
        page_html = _TOKENS.sub(lambda m: vals[m.group(1)], shell)
        if 'href="/' in page_html or 'src="/' in page_html:
            raise BuildError(f"{pg.path}: root-absolute href/src (the site lives under a project URL; use a relative link)")  # GUARD:abs-link
        files[pg.path] = page_html.encode("utf-8")
    for rel, raw in _assets(root).items():
        _claim(seen, rel)
        files[rel] = raw
    return files


def _protected(rel: str) -> bool:
    first = rel.split("/", 1)[0].casefold()  # case-folded: a case-insensitive filesystem would alias Images/ to images/
    return first in PROTECTED or rel.casefold() in PROTECTED_FILES


def _existing(docs: Path) -> list[str]:
    if not docs.is_dir():
        return []
    return sorted(f.relative_to(docs).as_posix() for f in docs.rglob("*") if f.is_file())


def build(root: Path, out: Path) -> list[str]:
    """Write the site into `out`, removing outputs the registry no longer produces (never the protected paths)."""
    files = render_site(root)
    for rel, raw in sorted(files.items()):
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(raw)
    for rel in _existing(out):
        if rel not in files and not _protected(rel):
            (out / rel).unlink()
    for d in sorted((p for p in out.rglob("*") if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
        if not any(d.iterdir()) and not _protected(d.relative_to(out).as_posix() + "/x"):
            d.rmdir()
    return sorted(files)


def check(root: Path) -> int:
    """0 = docs/ is fresh; 1 = stale/missing/orphan (printed); 2 = BuildError/RenderError (printed)."""
    docs = root / "docs"
    try:
        files = render_site(root)  # in memory: nothing is written, so the comparison cannot touch docs/
    except (BuildError, RenderError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    problems: list[str] = []
    for rel, raw in sorted(files.items()):
        f = docs / rel
        if not f.is_file():
            problems.append(f"MISSING docs/{rel}")  # GUARD:missing
        elif f.read_bytes() != raw:
            problems.append(f"STALE docs/{rel}")  # GUARD:stale
    for rel in _existing(docs):
        if rel not in files and not _protected(rel):
            problems.append(f"ORPHAN docs/{rel}")  # GUARD:orphan-output
    for line in problems:
        print(line)
    if problems:
        print("docs/ is out of date: run `bash scripts/build-docs.sh` and commit the result", file=sys.stderr)
    return 1 if problems else 0


# ---------------------------------------------------------------- generated Releases (AOS-303)
# releases/index.html, releases/v<ver>.html per version found in ANY of docs/release-notes/v<ver>.md (header stripped),
# upgrades/v<ver>.md and the CHANGELOG `## [<ver>]` sections, and releases/earlier.html for the `## [≤0.21.x]` catch-all.

GH_BLOB = "https://github.com/Zenosyne-Technologies/agent-operating-kit/blob/main/"
_REPO_DIRS = ("upgrades/", "templates/", "scripts/", "skills/", "agents/", "commands/", "hooks/", ".claude-plugin/")
_ROOT_FILES = ("CHANGELOG.md", "README.md", "CLAUDE.md", "AGENTS.md", "BOOTSTRAP.md", "LICENSE")
_REL_NOTE = re.compile(r"^docs/release-notes/v(\d+\.\d+\.\d+)\.md(#.*)?$")
_SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
_VER_FILE = re.compile(r"^v(\d+\.\d+\.\d+)\.md$")
_VER = re.compile(r"^\d+\.\d+\.\d+$")
_CL_HEAD = re.compile(r"^## \[([^\]]+)\](?:[ \t]+—[ \t]+(\S.*?))?[ \t]*$")
_EARLIER = "≤0.21.x"
_H1 = re.compile(r'<h1 id="[^"]*">(.*?)</h1>', re.S)


def _semver(v: str) -> tuple[int, int, int]:
    a, b, c = v.split(".")
    return int(a), int(b), int(c)


def _release_link_map(known: set[str], frag_prefix: str) -> Callable[[str], str]:
    """Repo paths -> the GitHub blob on main; a note link -> its sibling page; fragments land on the block's ids."""
    def mapper(href: str) -> str:
        if href.startswith("#"):
            return "#" + frag_prefix + href[1:]
        if not href or _SCHEME.match(href):
            return href
        m = _REL_NOTE.match(href)
        if m and m.group(1) in known:
            return f"v{m.group(1)}.html{m.group(2) or ''}"
        if href.startswith(_REPO_DIRS) or href.split("#", 1)[0] in _ROOT_FILES or m:
            return GH_BLOB + href
        return href
    return mapper


def _scope_ids(h: str, prefix: str) -> str:
    return re.sub(r'(<h[1-6] id=")', lambda m: m.group(1) + prefix, h)


def _changelog(root: Path) -> dict[str, tuple[str | None, str]]:
    """{version-or-'≤0.21.x': (date, body)}; the body is left-padded with blank lines so render errors cite CHANGELOG.md lines."""
    p = root / "CHANGELOG.md"
    if not p.is_file():
        return {}
    out: dict[str, tuple[str | None, str]] = {}
    cur: tuple[str, str | None, int] | None = None
    buf: list[str] = []

    def flush() -> None:
        if cur is not None:
            out[cur[0]] = (cur[1], "\n" * cur[2] + "\n".join(buf))
    for no, line in enumerate(_read_text(p).split("\n")):
        m = _CL_HEAD.match(line)
        if m or line.startswith("## "):
            flush()
            cur, buf = ((m.group(1), m.group(2), no + 1) if m else None), []
        elif cur is not None:
            buf.append(line)
    flush()
    return out


def _action_needed(body: str) -> bool:
    """True when the `### Action needed` category holds something other than a line starting 'None'."""
    lines, on = [], False
    for ln in body.split("\n"):
        if ln.startswith("### "):
            on = ln[4:].strip().lower() == "action needed"
        elif on and ln.strip():
            lines.append(re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+", "", ln).strip())
    return any(not t.startswith("None") for t in lines)


def _strip_h1(text: str) -> str:
    """Blank the leading H1 (the block heading replaces it); line numbers stay put."""
    _, body = split_front_matter(text)
    lines = _norm(text).split("\n")
    start = len(lines) - len(body.split("\n"))
    for k in range(start, len(lines)):
        if lines[k].strip():
            if re.match(r"^# \S", lines[k]):
                lines[k] = ""
            break
    return "\n".join(lines)


def gen_releases(root: Path) -> dict[str, tuple[str, str]]:
    cl = _changelog(root)
    ups: dict[str, Path] = {}
    notes: dict[str, Path] = {}
    for d, into in ((root / "upgrades", ups), (root / "docs" / "release-notes", notes)):
        if d.is_dir():
            for f in sorted(d.iterdir()):
                m = _VER_FILE.match(f.name)
                if m and f.is_file():
                    into[m.group(1)] = f
    versions = {v for v in cl if _VER.match(v)} | set(ups) | set(notes)
    order = sorted(versions, key=_semver, reverse=True)
    pages: dict[str, tuple[str, str]] = {}
    info: dict[str, dict[str, object]] = {}
    known = set(order)
    built: set[str] = set()
    for ver in order:
        date, cbody = cl.get(ver, (None, ""))
        blocks: list[str] = []
        note_h1, note_html = "", ""
        if ver in notes:
            hdr, _ = split_front_matter(_read_text(notes[ver]))
            date = date or hdr.get("date") or hdr.get("created")
            note_html = render_markdown(_read_text(notes[ver]), f"docs/release-notes/{notes[ver].name}", _release_link_map(known, ""))
            m = _H1.search(note_html)
            note_h1 = html.unescape(re.sub(r"<[^>]+>", "", m.group(1))).strip() if m else ""
        if ver in ups:
            up = render_markdown(_strip_h1(_read_text(ups[ver])), f"upgrades/{ups[ver].name}", _release_link_map(known, "upgrade-"))
            if up.strip():
                blocks.append('<section class="release-block release-block--upgrade">\n<h2 id="release-upgrade">Upgrade</h2>\n'
                              + _scope_ids(up, "upgrade-") + "</section>\n")
        if cbody.strip():
            ch = render_markdown(cbody, "CHANGELOG.md", _release_link_map(known, "changes-"))
            if ch.strip():
                blocks.append('<section class="release-block release-block--changes">\n<h2 id="release-changes">Changes</h2>\n'
                              + _scope_ids(ch, "changes-") + "</section>\n")
        if not note_html.strip() and not blocks:
            continue  # nothing to show; the release-missing guard below reports it
        head = "" if _H1.search(note_html) else f"<h1>v{html.escape(ver)}</h1>\n"
        title = f"v{ver}" if not note_h1 else (note_h1 if note_h1.startswith(f"v{ver}") else f"v{ver} — {note_h1}")
        pages[f"releases/v{ver}.html"] = (title, head + note_html + "".join(blocks))
        built.add(ver)
        sub = note_h1[len(f"v{ver}"):].lstrip(" —-:") if note_h1.startswith(f"v{ver}") else note_h1
        info[ver] = {"date": date, "sub": sub, "action": _action_needed(cbody)}
    missing = sorted(versions - built, key=_semver)
    if missing:
        raise BuildError(f"release(s) found in a source but no page could be built: {', '.join(missing)}")  # GUARD:release-missing
    old = [v for v in order if _semver(v) < (0, 22, 0)]
    rows = []
    for ver in order:
        i = info[ver]
        badge = ' <span class="badge badge--action">Action needed</span>' if i["action"] else ""
        rows.append(f'<tr><td><a href="v{ver}.html">v{ver}</a></td><td>{html.escape(str(i["date"] or ""))}</td>'
                    f'<td>{html.escape(str(i["sub"]))}{badge}</td></tr>')
    has_earlier = bool(old) or _EARLIER in cl
    index = ('<h1>Releases</h1>\n<p>Every Marvin release, newest first. A release page carries its release note, the upgrade steps and its '
             'changelog entry. A badge marks a release with an action to take after upgrading.</p>\n'
             '<table>\n<thead><tr><th>Version</th><th>Date</th><th>Release</th></tr></thead>\n<tbody>\n' + "\n".join(rows) + "\n</tbody>\n</table>\n")
    if has_earlier:
        index += '<p><a href="earlier.html">Earlier releases (before v0.22.0)</a></p>\n'
    out = {"releases/index.html": ("Releases", index)}
    out.update(pages)
    if has_earlier:
        body = "<h1>Earlier releases</h1>\n"
        if _EARLIER in cl and cl[_EARLIER][1].strip():
            body += render_markdown(cl[_EARLIER][1], "CHANGELOG.md", _release_link_map(known, ""))
        if old:
            body += "<ul>\n" + "\n".join(f'<li><a href="v{v}.html">v{v}</a></li>' for v in old) + "\n</ul>\n"
        out["releases/earlier.html"] = ("Earlier releases (≤0.21.x)", body)
    return out


GENERATORS["releases"] = gen_releases


# ---------------------------------------------------------------- CLI

def _identity(href: str) -> str:
    return href


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def main(argv: list[str]) -> int:
    args = argv[1:]
    if len(args) == 2 and args[0] == "--render":
        try:
            with open(args[1], "rb") as fh:
                text = fh.read().decode("utf-8")
            out = render_markdown(text, args[1], _identity)
        except (OSError, UnicodeDecodeError) as exc:
            print(f"{args[1]}: {exc}", file=sys.stderr)
            return 2
        except RenderError as exc:
            print(str(exc), file=sys.stderr)
            return 2
        sys.stdout.buffer.write(out.encode("utf-8"))
        return 0
    do_check, root, k = False, _repo_root(), 0
    while k < len(args):
        if args[k] == "--check":
            do_check = True
        elif args[k] == "--root" and k + 1 < len(args):
            k += 1
            root = Path(args[k])
        else:
            print("usage: build_docs.py [--check] [--root DIR] | --render FILE", file=sys.stderr)
            return 2
        k += 1
    if do_check:
        return check(root)
    try:
        written = build(root, root / "docs")
    except (BuildError, RenderError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    print(f"build-docs: wrote {len(written)} files to docs/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
