# PM subsystem — selection, sensecheck, project key

Factory-side reference for the `install-agent-os` and `upgrade-agent-os` skills. NOT installed into
consumer projects — the skills read it, resolve it, and install only the selected tool's files.

## 1. Selection

Ask the user which PM tool this project uses, presented as a selection they pick from
(AskUserQuestion where available): **Linear | Jira | GitHub | Local**.

- Always a user selection, NEVER inferred — even when exactly one tracker is connected.
- **Local** is the self-contained markdown tracker (`pm/local/`) — the default answer for projects
  with no external tool. It replaces the old "none" option for new installs; `pm_tool: none` stays
  understood for legacy installs and keeps its file-based issue log.

## 2. Sensecheck (immediately on selection, before anything else)

Prove the tool is actually reachable from THIS session before installing anything for it:

| Selection | Check |
|---|---|
| Linear | its MCP tools resolve (one ToolSearch), then ONE cheap read call — e.g. `list_teams` — to prove auth |
| Jira | its MCP tools resolve (one ToolSearch), then ONE cheap read call — `getVisibleJiraProjects` — to prove auth |
| GitHub | `gh auth status` succeeds AND `gh repo view <owner/repo>` resolves |
| Local | always available — no check |

One read call only; the sensecheck proves reachability, it does not survey the tracker.

**On FAIL** — tell the user plainly what happened ("<tool> is not reachable from this session"),
name the failing check, and offer three ways forward:

1. pick a different tool (re-run selection),
2. connect the tool and re-run the install later,
3. fall back to **Local** now — Marvin continues fully self-contained, and the external tool can be
   adopted later via `upgrade-agent-os` + an intake re-run.

Never silently downgrade: the fallback to Local is the user's choice, not the skill's.

## 3. Project key / coordinates

Externally-hosted tools LIST what exists and let the USER choose — never guess, never create:

- **Linear** — list teams, then that team's projects; user picks both. Coordinates: team + project.
- **Jira** — `getVisibleJiraProjects`; user picks. Coordinates: site URL + project key (+ Confluence
  space, if the guide lands there).
- **GitHub** — confirm `owner/repo` (the repo's own origin is the proposal). Coordinates: owner/repo.
- **Local** — ask for a short uppercase key (2–5 letters), or propose one derived from the project
  name and have the user confirm it. Coordinates: `.docs/project-management/` + project key.

Record the resolved coordinates as today: `.docs/PROJECT-INFO.md` frontmatter (`pm_tool`,
`project_key`, `tracker_coordinates`, `hierarchy_levels`) and `ticket-filing.md`'s coordinates line.
