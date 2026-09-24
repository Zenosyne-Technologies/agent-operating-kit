---
doc: Planning research
type: reference
status: active
summary: The size-gated planning passes — size:m build decomposition, the size:m+ brief falsifier, size:l/xl plan-validation and solution research — who runs each and where findings land.
updated: {{INSTALL_DATE}}
---

# Planning research (decomposition, brief falsifier, plan validation + solution research)

The research passes below apply when planning sizes a task `size:l` or `size:xl` (per `label-syntax.md`). Tasks `size:m` and below get NO dedicated research pass — a `size:m` goes through build decomposition, and every `size:m`+ task through the brief falsifier, before its build.

For each qualifying task, the planner dispatches two research passes, in order, BEFORE the build brief:

1. **Plan-validation research** — a fresh agent adversarially checks the plan against the actual codebase: hidden dependencies, breaking-change surface, wrong assumptions, missing acceptance criteria, sequencing risks.
2. **Solution research** — after validation findings are reconciled into the plan: research implementation approaches — viable options with trade-offs, a recommended approach with reasons, and references (code, docs, prior art).

Both passes search the CODE and the PM TOOL: `git log`/`git blame` the touched files and methods for issue keys in earlier commits (commit messages start with their key), fetch those issues, and read their comments — prior findings and solutions often answer current questions. Cite the relevant issues in Refs.

Tier routing (mandatory — by the task's `size:` label):

| Size | Researcher tier |
|---|---|
| `size:xl` (very complex) | {{ESCALATION_MODEL}} |
| `size:l` (mid complexity) | {{ESCALATION_MODEL}} |
| `size:m` and below | no research pass |

Reporting — findings live where the plan lives, both passes alike:
- Issue-tracked plan → a comment on the issue: `## Findings / ## Risks / ## Recommendation / ## Refs`.
- Otherwise → an md doc at `.docs/researches/<issue-key-or-slug>-{validation|solution}.md` with a full header, registered as a row in `.docs/researches/index.md` (`document-standard.md`) — an unindexed memo cannot be found again — and linked from the tracker issue if one exists.

Briefs follow `briefing.md`; FINAL MESSAGE (machine-consumed): verdict (`plan-ok` | `plan-gaps: <n>` for validation; `recommendation: <one line>` for solution) + the comment URL or doc path. The planner reconciles findings into the plan before dispatching the build — research that isn't folded back in is waste.

## Build decomposition (`size:m`)

The planner splits a `size:m` task into ONE design-bearing core plus zero or more peripheral pieces — ONLY when a design-bearing core exists; a task with nothing design-bearing is not split, and routes by its `size:m` label as before (whole, to `marvin:developer`):
- **Design-bearing** — finishing the work requires a choice the brief and DoD do not fix: an interface, signature or data shape; an algorithm or control flow; the behavior on an error or edge case; a module boundary; a trade-off between approaches. Test: two competent builders given the same brief could deliver materially different results that both meet the DoD. Design-bearing work is the core → `marvin:developer`.
- **Peripheral** — work fully determined by the core's committed interface plus a spec the orchestrator writes: tests from listed cases, docs from the landed diff, wiring a named entry point, fixtures, index rows. Size each by `label-syntax.md`'s rubric: `s` → `marvin:developer-small`, `xs` → `marvin:ponytail` (`ponytail.md`). A piece that fails this definition belongs to the core — never split a guess off to a cheaper tier. A piece that adds or changes a dependency also belongs to the core (`security.md`).
- **Shape** — pieces are dispatches under the ONE tracker issue (no new tracker items; commits carry its key). Each brief lists the DoD lines it owns; every DoD line is owned by exactly one piece.
- **Sequence** — the core builds first; peripherals dispatch once the core has committed (its interface is then fixed), in parallel when their paths are disjoint (`briefing.md` item 7).
- **Validation** — ONE unit, the core-rules lifecycle unchanged: one completion, one security (and, for UI, one visual) pass over the core and every piece together, heavy tier, full scope; then one documenter pass. Why: the DoD belongs to the `size:m` task and a piece only means something against it (a test is right when it tests the core's DoD); per-piece gates would multiply validation spend, the larger cost. A finding names its piece and returns to the persona that built it; the attempt itself counts against the TASK, never the piece (`escalation.md`).
- No clean split (all of it is design-bearing, or a piece is too small to brief) → build it whole on `marvin:developer`; the brief says so in one line.

## Brief falsifier (`size:m`+)

Before the FIRST build dispatch of every `size:m`, `size:l` or `size:xl` task — after research is reconciled and the decomposition is drawn — `marvin:developer-small` reads the build brief, the DoD and (for a `size:m`) the piece list, plus only the files the brief scopes, writes no code and commits nothing, and lists: **undefined terms** (a word the brief or DoD relies on with no definition a builder could apply), **unhandled cases** (an input, state or failure the DoD is silent on), **contradictions** (two statements, or a statement and the code, that cannot both hold). Why this persona: it is spec reading, not design, so it needs no heavy tier (`marvin:researcher` is heavy and memo-shaped for `l`/`xl` plans); the small tier's own STOP rule — the brief leaves discretion — is this very check, run deliberately before the build; reuse keeps the persona inventory and its telemetry role unchanged. Its run report carries the slice `-falsifier` (`briefing.md` item 11).

FINAL MESSAGE, within `briefing.md` item 11's cap: `VERDICT: brief-ok` | `VERDICT: brief-gaps: <n>`; one line per finding, `F<n> <undefined|unhandled|contradiction> <brief item or DoD line> — <what is missing>`; `REPORT: <run report path>`; then item 11's reserved lines.

`brief-gaps` BLOCKS the build until the orchestrator has resolved every finding — amended the brief, or the DoD on the tracker issue (via `marvin:ponytail`; an amendment that narrows the DoD's reach is a descope and needs the user's yes, `escalation.md`) — or recorded why not, one line per declined finding in the build brief (`Falsifier F<n> declined: <reason>`). Every such declined-finding line is also copied into both the completion validator's and the security validator's briefs, so neither gate is blind to a gap that was left open deliberately. Resolving a finding never re-runs the falsifier UNLESS it changed the brief's DoD or scope, in which case the falsifier runs again on the amended brief before build. A falsifier with no usable verdict is never a failed attempt, whatever persona runs it (`escalation.md`'s read-only definition): re-run fresh once, then the orchestrator falsifies inline. Correction dispatches skip it — validator findings are their spec.
