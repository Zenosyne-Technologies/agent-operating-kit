---
doc: CodeGuard security rules
type: reference
status: active
summary: How the security advisor, builders, the security validator and the Codex security lane use the third-party CodeGuard skill when `security_rules: codeguard` — added on top of the kit checklist, never replacing it.
updated: {{INSTALL_DATE}}
---

# CodeGuard security rules

Validated version: `1.5.0` (Project CodeGuard, plugin `codeguard-security@project-codeguard`, skill `codeguard-security:codeguard`). The one owner of how the kit uses CodeGuard; other files cite this file and never restate it.

## Applies when

- `.marvin/PROJECT-INFO.md` reads `security_rules: codeguard`. Absent, empty, `kit` or any other value: every rule below is inert, and `security.md` runs alone, as it always has.

## Availability

- At task start the orchestrator checks its OWN session's skill list for `codeguard-security:codeguard`. Present: the rules below apply.
- Missing: tell the user ONCE per session, with the fix — `claude plugin install codeguard-security@project-codeguard -s project`, preceded by `claude plugin marketplace add 'cosai-oasis/project-codeguard#v1.5.0' --scope project` only when `.claude/settings.json` does not already declare `project-codeguard`; active from the next session. The install is recorded per checkout path, so a copied or moved checkout reads as unavailable until the plugin is reinstalled there (the same fix command). Then run with the kit checklist only, and write `CodeGuard: unavailable` in the brief's security-surface item (`briefing.md` item 4).
- Absence is never a FAIL and never blocks a task, a validator or a release.

## Rule selection (advisor, at brief time)

- The project's `stack` plus the task's changed files select a row of the skill's language table; that row only NARROWS the candidates, since one row can hold most of the topic rules. From within it, the orchestrator names in brief item 4 only the topic rules whose tags match the brief's security surface (the skill's tag table) — never the whole row.
- Always add the three always-apply rules: `codeguard-1-hardcoded-credentials`, `codeguard-1-crypto-algorithms`, `codeguard-1-digital-certificates`. Topic rules are the `codeguard-0-*` IDs that tag match selects.
- Cite the skill's own tables; never copy them into the kit or a brief — they change upstream.
- Name rules, never paste them: loading is the builder's job, so context grows only by what the task touches.

## Builders

- Load the `codeguard` skill and read ONLY the rules the brief names. Treat them as constraints, the same as the surfaces `security.md` lists, never as commentary.

## Security validator

- Load the skill and check the change against the rules the brief names and the three always-apply rules. It MAY also scan the rest of the language row; an extra hit there is a `[note]` in its run report, unless it is itself an exploitable defect — then it is an ordinary finding, graded as below.
- A violated rule is a finding, graded by the kit's severity scale (impact if exploited), never by CodeGuard's own wording.
- A CodeGuard rule violation is FAIL only when it is itself an exploitable security defect at this stage's must-fix bar; a hygiene-only violation is a note.
- The rule ID goes in the finding's prose and in the run report ("violates `codeguard-1-hardcoded-credentials`"); the tag format in `validation-agent.md` *Reporting* is unchanged.
- A rule the brief should have named but did not goes in the run report only, never in the finding ledger: the builder cannot fix the brief, so a ledger entry would recur every round. Code that actually violates it is an ordinary finding against the code.

## Codex security lane

- Codex cannot load Claude skills. The orchestrator writes the text of the rule files, read from the loaded skill's base directory, as the forwarder brief's `rules` DATA (`codex.md` *Brief*), which the forwarder renders as `### Rules` in the lane prompt (`codex/security.md`): the rules the brief names and the three always-apply rules, never the rest of the language row. The asymmetry with *Security validator*'s optional row scan is deliberate: the rule texts would bloat the lane prompt.
- That rules file and the prompt are transient, never committed, never filed.

## Precedence

- CodeGuard adds checks only. Every kit checklist item, safety gate and severity rule stays in force; a CodeGuard rule never softens, overrides or removes one.
- A CodeGuard rule that conflicts with a project rule in `CLAUDE.md`: the project rule wins and the conflict is named to the user once — the kit core's *Precedence* rule.

## License

- CodeGuard is CC BY 4.0 (CoSAI / OASIS). Never copy its rule files into the repo, the tracker or the docs. A rule quoted in a run report carries the line "Project CodeGuard (CoSAI), CC BY 4.0".
