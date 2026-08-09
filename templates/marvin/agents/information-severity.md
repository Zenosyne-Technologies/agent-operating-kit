---
doc: Information severity
type: reference
status: active
summary: The four severity levels an information file can carry, the reading obligation each one imposes, and how that obligation combines with relevance.
updated: {{INSTALL_DATE}}
---

# Information severity

The four levels below are the ONLY values `severity:` may take. This file owns them — `information-guide.md` and every brief reference it rather than restating it, so a level can be re-tuned here without touching anything else.

| `severity:` | what it means | obligation |
|---|---|---|
| `critical` | ignoring it breaks production, corrupts data, or violates a hard constraint | BLOCKING — must be read before acting in the step it applies to; work does not start until it has been |
| `high` | ignoring it causes rework or walks into a known bug class | MUST be read when relevance matches |
| `normal` | knowing it shortens the work or avoids a detour | SHOULD be read when relevance matches |
| `low` | background, rationale, the history behind a decision | read only when the topic is directly at hand |

Severity is about CONSEQUENCE, not about how interesting the rule is. If ignoring it costs nothing but time, it is not `critical`. When torn, take the lower level and let the rule earn a promotion — a folder where everything is critical routes nothing.

## Severity × relevance

`relevance:` selects WHO (the dispatch personas — see `information-guide.md`). Severity selects WHEN and how binding. They combine:

| `severity:` | your persona is in `relevance:` (or it is `all`) | your persona is not |
|---|---|---|
| `critical` | read it BEFORE you act; state in your final message that you did | read it anyway if your change enters the area it names — a critical rule binds by subject, not by role |
| `high` | read it before you act | skip unless the topic is directly at hand |
| `normal` | read it while planning your approach | skip |
| `low` | read it if the topic is directly at hand | skip |

A rule you cannot satisfy is a FINDING, not a licence to proceed: report the conflict to whoever briefed you and stop at that step.
