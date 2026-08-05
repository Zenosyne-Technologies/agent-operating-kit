# Handbooks — developer / user / admin wikis

Three living, Obsidian-compatible wikis under `.docs/handbooks/<audience>/` (`developer`, `user`, `admin`) that document the product as it currently is — not the changelog of *what changed* (that's `documentation-agent.md`'s job), but the current shape of *what exists*. Every consumer of this file — the documentation agent, milestone validation — reads it instead of re-deriving these rules.

## Layout

One page per module or business-logic unit, plain markdown, per-folder `INDEX.md` as the table of contents. Every page MUST be registered in its folder's INDEX with a one-line description — **a page not in INDEX doesn't exist**, even if the file sits on disk.

## Page format

YAML frontmatter:
- `title` — page title
- `audience` — `developer` | `user` | `admin`
- `module` — the module/feature this page covers
- `sources` — list of repo code paths this page documents (the discovery key)
- `updated` — `YYYY-MM-DD`
- `related` — list of `[[Page Name]]` links

Body: Obsidian wikilinks (`[[Page Name]]`) between pages; kebab-case filenames; relative-only references (no absolute paths, no external URLs standing in for internal links).

## Audience voice

- **Developer**: software logic — purpose, the WHY behind nuanced behavior, flows/steps/rules that are NOT common sense, and how this module connects to others (link them). Never restate what clean code already says.
- **User / Admin**: plain language, per module/function — what it does and what to be aware of. Admin covers operation/configuration; user covers usage. No agent/tier internals, no code.

## Discovery rule (MANDATORY, before writing)

1. Read all three INDEX.md files.
2. Grep the handbooks for every touched path: `grep -rl "<path>" .docs/handbooks/`.
3. A match → AMEND that page, never create a near-duplicate.
4. No match → create only when no existing page owns the module.
5. On every create or rename: update `sources`, `updated`, `related`, and the folder's INDEX row. On rename: fix every wikilink that pointed at the old title.

## When triggered

- **Per task**: the documentation agent checks/amends/creates pages — logic changed → developer page; user-visible behavior changed → user page; operational/config surface changed → admin page; nothing relevant changed → say so explicitly, don't force a page.
- **Per milestone**: validation includes a coverage pass — each shipped epic's functionality has current pages in all three audiences.

## Secrets

Handbooks are shareable surfaces (`security.md` applies): no secrets, tokens, or internal-only URLs in any page.
