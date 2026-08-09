# Documentation agent (after a tracker task is done)

Dispatch `marvin:documenter` once — and only once — BOTH validators have PASSED; the task is not Done until this step lands, and the tracker issue is never closed before it. Brief the agent with the issue id, commit hashes, and the touched paths. A failed validation goes back to the builder instead: nothing is documented until the work actually holds.

Scope (only what the change affects — skip untouched docs):
1. **Project docs** ({{DOCS_LOCATION}}): update the relevant architecture note(s) with the new behavior/contract; roadmap result line if milestone-relevant; issue-log rows for bugs fixed en route.
2. **Code-level docs**: README/usage snippets where a public contract changed; doc comments only for non-obvious constraints (match surrounding density — no narration).
3. **Tracker**: closing comment on the issue — what shipped, commits, where the docs live. Append, when telemetry is available per `.marvin/agents/token-economics.md`: one line `Cost: ~$X.XX (N tokens across M commits)` via the contract's per-issue recipe — clearly an estimate; skip silently without telemetry.
4. **Config surface**: env examples + compose/deploy env blocks for any new variable — env-wiring is part of the feature, and it is the class of gap validators structurally miss.
5. **Project info** (`.marvin/PROJECT-INFO.md`): update any meta fact the change altered — stack, dev command/ports, tracker coordinates, label-syntax version.
6. **Handbooks** (`.docs/handbooks/`): per `handbooks.md` discovery, map the touched paths to pages; amend or create the affected developer/user/admin pages and their index entries; report which pages changed, or state explicitly that none were relevant.

Keep diffs surgical; follow existing doc structure and tone. Attribution policy per core rules.
