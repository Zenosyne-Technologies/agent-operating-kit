# Screenshots for the GitHub Pages guide

One folder per feature (`docs/images/<feature>/`): PNGs from a real session on the release build, with no secrets or private project content (repo rule 11).

- List the screenshots in `docs/images/<feature>/captions.md`, one per line, in display order: `- <file>.png: <caption>`.
- Register the feature's page in `site/pages.json` with `"feature": "<feature>"` (its hand source lives under `site/mods/`).
- Rebuild with `bash scripts/build-docs.sh`. The page ends with a "See it in Claude Code" gallery; `<!-- shot: <file>.png -->` in the page source also places one inline.

The build only reads this folder. It fails on a PNG with no caption, a caption with no PNG, a folder with no page, a feature with no folder, or any other file type.
