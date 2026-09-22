---
doc: Screen catalog
type: reference
status: active
summary: The index of the product's UI screens — each screen's route, how to reach it, and the breakpoints it must hold — the declared surface source the design/visual review resolves against.
keywords: [screens, ui, surfaces, routes, breakpoints, visual-validation, catalog]
level: project
created: {{INSTALL_DATE}}
updated: {{INSTALL_DATE}}
---

# `.docs/handbooks/developer/screens/` — screen catalog

**Belongs here**: one entry per UI screen — or per distinct state worth reviewing — the product renders: its route (or how a reviewer reaches it), any auth/seed prerequisites, and the breakpoints it must hold. This catalog is the DECLARED surface source for design/visual review — surfaces are declared here, never guessed from a diff. It rides the normal `.docs/` crawl (index → screen → deeper), so a reviewer resolves a changed surface to its entry with one lookup.

**Does NOT belong here**: implementation detail (→ the developer handbook page for that unit), what CHANGED (the tracker and commit history own that), secrets or internal-only URLs — this is a shareable surface.

## Screens

| screen | route · how to reach (auth · seed) | breakpoints | detail |
|---|---|---|---|
<!-- Replace with the project's real screens, one row each. Example:
| Sign-in | `/login` · public, no seed | mobile · desktop | — |
| Dashboard | `/app` · requires auth (seed a user) | mobile · tablet · desktop · dark | [dashboard.md](dashboard.md) |
-->

## Per-screen detail docs

A row is enough for a simple screen. When a screen has flows, states or variants worth their own page, create `<screen>.md` beside this index — carrying the full document header per the document standard, with a `sources:` list of the code paths that render it — and link it from that row's **detail** column. That page may link deeper still (per-state or per-flow docs), so the catalog navigates index → screen → detail. Register every such page with its own row above; a screen doc no row links to cannot be found.
