---
doc: Documentation agent scope
type: reference
status: active
summary: What a documentation agent covers once a tracker task has passed both validators, and the order it covers it in.
updated: {{INSTALL_DATE}}
---

# Documentation agent (after a tracker task is done)

Dispatch `marvin:documenter` once — and only once — BOTH validators have PASSED; the task is not Done until this step lands, and the tracker issue is never closed before it. Brief the agent with the issue id, commit hashes, and the touched paths. A failed validation goes back to the builder instead: nothing is documented until the work actually holds.

Everything you write under `.docs/` obeys `.marvin/agents/document-standard.md`: enter at `.docs/index.md`, find the existing document by crawling — never by globbing — write the full header on every document (records such as the issue log take none), and update every index row on the path to whatever you touched, in this commit. A loose note at the docs root belongs to no folder and no index, which means it does not exist.

Scope (only what the change affects — skip untouched docs):
1. **Project docs** (`.docs/`): the new behavior or contract is developer-handbook material and is handled at item 6 — do NOT also write a separate architecture note. Here: the result line on the milestone's plan in `plans/` when the change is milestone-relevant, a row in the issue log at `{{DOCS_ISSUE_LOG_PATH}}` for each bug fixed en route, and a `researches/` memo registered in its index only if the task produced findings that outlive it.
2. **Code-level docs**: README/usage snippets where a public contract changed; doc comments only for non-obvious constraints (match surrounding density — no narration).
3. **Tracker**: closing comment on the issue — what shipped, commits, where the docs live. Append, when telemetry is available per `.marvin/agents/token-economics.md`: one line `Cost: ~$X.XX (N tokens across M commits)` via the contract's per-issue recipe — clearly an estimate; skip silently without telemetry.
4. **Config surface**: env examples + compose/deploy env blocks for any new variable — env-wiring is part of the feature, and it is the class of gap validators structurally miss.
5. **Project info** (`.marvin/PROJECT-INFO.md`): update any meta fact the change altered — stack, dev command/ports, tracker coordinates, label-syntax version.
6. **Handbooks** (`.docs/handbooks/`): the sole home for how the product now works — architecture, contracts, behavior. Per `handbooks.md` discovery, map the touched paths to pages; amend or create the affected developer/user/admin pages and their index entries; report which pages changed, or state explicitly that none were relevant.

Keep diffs surgical; follow existing doc structure and tone. Attribution policy per core rules.
