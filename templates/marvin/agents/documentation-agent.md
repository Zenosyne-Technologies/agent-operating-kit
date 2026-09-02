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
2. **Code-level docs — the code-documentation convention** (binds whoever writes code: the builder at build time and the documenter when it touches code docs, not only this post-task pass): README/usage snippets where a public contract changed, plus two distinct rules that never override each other —
   - **Contract docblocks**: every NEW public class or method, and every signature you modify, carries a docblock stating its contract — a one-line summary, its parameters, return, and errors/exceptions — in the project's own ecosystem idiom (PHPDoc, JSDoc/TSDoc, Javadoc, Python docstrings per PEP 257, rustdoc, GoDoc, …). Use what the language's ecosystem standardises on, never a kit-invented format. Match a file's existing convention where it already has one; impose the language default only in a file or project with none. A modified signature updates its docblock in the same change, or the docs rot. Skip private one-liners and trivial getters the idiom itself would omit.
   - **Inline comments**: reserved for non-obvious constraints, matching surrounding density, never narrating what the code plainly does — unchanged by the rule above. The two are distinct: a docblock states WHAT the contract is on the API surface; an inline comment explains WHY a non-obvious line is the way it is. Neither overrides the other.
3. **Tracker**: closing comment on the issue — what shipped, commits, where the docs live. When telemetry is available per `.marvin/agents/token-economics.md`, resolve the per-issue recipe AND its control count (this project's total events) before writing a cost line — control 0 → telemetry absent, skip the line silently; control > 0 but the per-issue sum is 0 → the scope did not resolve, so write `Cost: unresolved (telemetry present, no events matched this issue)`, never a `$0.00` figure; control > 0 and sum > 0 → append `Cost: ~$X.XX (N tokens across M commits)`, clearly an estimate. This agent has no `tokens.state` field to lean on — the prose above is its equivalent of the zero rule.
4. **Config surface**: env examples + compose/deploy env blocks for any new variable — env-wiring is part of the feature, and it is the class of gap validators structurally miss.
5. **Project info** (`.marvin/PROJECT-INFO.md`): update any meta fact the change altered — stack, dev command/ports, tracker coordinates, label-syntax version.
6. **Handbooks** (`.docs/handbooks/`): the sole home for how the product now works — architecture, contracts, behavior. Per `handbooks.md` discovery, map the touched paths to pages; amend or create the affected developer/user/admin pages and their index entries; report which pages changed, or state explicitly that none were relevant.

Keep diffs surgical; follow existing doc structure and tone. Attribution policy per core rules.
