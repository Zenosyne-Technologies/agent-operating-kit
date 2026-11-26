#!/usr/bin/env python3
"""build_docs.py - the Marvin docs-site generator (AOS-299). Stdlib only, Python 3.10+.

This module owns, so far, the markdown SUBSET renderer (AOS-300):
  RenderError, split_front_matter, render_markdown, and the CLI `--render FILE`.

The subset: ATX headings, paragraphs (hard-wrapped), **bold**, *italic*, `code`, links, fenced code,
unordered (`-`) and ordered (`1.`) lists nested to any depth, GFM pipe tables, blockquotes, horizontal rules.
HTML in a source is escaped, never passed through. Anything the renderer cannot classify FAILS with
`file:line: message` - it never degrades silently. Output is LF, UTF-8, deterministic.

Every rule that raises carries a trailing `# GUARD:<name>` comment; scripts/test-build-docs.sh copies this
module with that line neutralised and asserts the named fixture then fails.
"""
from __future__ import annotations

import html
import re
import sys
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


# ---------------------------------------------------------------- CLI

def _identity(href: str) -> str:
    return href


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
    print("usage: build_docs.py --render FILE", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
