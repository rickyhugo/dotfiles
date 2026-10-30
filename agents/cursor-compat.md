# Running Cursor skills on Claude Code, Codex, and OpenCode

pstack and Team Kit skills use Cursor's tools, agents, models, and paths. Map
each Cursor name below to the current host. When a field or value has no row,
drop it and say so in one line.

## Claude Code

Follow pstack's own adapter, `~/.external-skills/cursor-plugins/pstack/docs/harness/claude-code.md`,
with three changes for this install:

- Skills: invoke another skill with the `Skill` tool under its installed name,
  such as `pstack-poteto-mode`, and write `/pstack-<name>` when you tell the user
  to type it. The adapter's `/pstack:<name>` names a plugin install this machine
  does not use.
- Agents: `poteto-agent`, `comment-sicko`, `ci-watcher`, and
  `thermo-nuclear-code-quality-review` are registered without a prefix.
- Models: use the shared model rule in [Models](#models), not `~/.claude/rules/`.

## Codex and OpenCode

| Cursor                          | Codex                                                         | OpenCode                                      |
| ------------------------------- | ------------------------------------------------------------- | --------------------------------------------- |
| `Task` with a named agent       | spawn tool with `agent_type: "<id>"`                          | `subagent` with `agent: "<id>"`               |
| `subagent_type: generalPurpose` | `agent_type: "default"`                                       | `agent: "general"`                            |
| `readonly: true`                | `default`, with "report only, do not edit files" in the brief | `agent: "explore"`                            |
| `AskQuestion`                   | ask in plain text                                             | `question` tool when offered, else plain text |
| A todolist                      | the plan tool when offered, else a list in your reply         | `todowrite`                                   |
| Run another skill               | `$<installed-name>` or read its `SKILL.md`                    | the `skill` tool with the installed name      |

On both hosts, omit `run_in_background`, `resume`, and `environment: "local"`.
Map `environment: "cloud"` to a separate git worktree and name its base branch.
Pass `file_attachments` as paths in the brief.

## Models

`setup-pstack` writes one rule for every host: `~/.cursor/rules/pstack-models.mdc`,
exactly as its steps say. Detect models from the current host's agent tool and
write each as a slug ending in its effort, such as `claude-opus-5-5-xhigh`.
Before choosing a subagent model on any host, read that file and map each slug:

- Claude Code: `model` is the family (`opus`, `sonnet`, `haiku`, `fable`) and
  `effort` is the last token.
- Codex: the model ID, with the last token as `reasoning_effort`.
- OpenCode: the matching `provider/model` from the host's model list.
- T3 Code (when `orchestrator_capabilities` is callable): `delegate_task` with
  the provider instance that serves the model, the model ID, and the effort in
  `target.options` (`effort` for Claude, `reasoningEffort` for Codex). Validate
  each against `orchestrator_capabilities` first.

`inherit-parent`, `auto`, a missing file, a missing role, and a slug the host
cannot run all mean the same thing: omit the model so the agent inherits the
parent, and say so when a configured slug was unavailable.

## Delegates

The four named agents above are registered natively on each host. A T3
`delegate_task` child has none of them, so its brief carries the role. A
worker reads `~/.external-skills/cursor-plugins/pstack/skills/poteto-mode/SKILL.md`
in full before any work, and a reviewer reports findings only.

## Paths

| Cursor                                               | Here                                                                                                                                     |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `~/.cursor/skills/`, `.cursor/skills/`               | `~/.agents/skills/`, `.agents/skills/`                                                                                                   |
| `<pstack>`, the plugin root                          | `~/.external-skills/cursor-plugins/pstack/`                                                                                              |
| `https://github.com/cursor/plugins/blob/main/<path>` | `~/.external-skills/cursor-plugins/<path>` when it exists                                                                                |
| `.cursor/rules/*.mdc`                                | the repository's `AGENTS.md` or `CLAUDE.md`. The model rule above is the one `.mdc` you read.                                            |
| `~/.cursor/projects/<slug>/agent-transcripts/`       | this host's sessions: `~/.claude/projects/<slug>/` on Claude Code, `~/.codex/sessions/` on Codex. On OpenCode, skip with the line below. |

## Cursor-only features

Cursor Automations, Bugbot setup, cloud agent dashboards, `/loop`, and Cursor's
PR tool have no equivalent here. Write `Skipped on <host>: <step>. <reason>.`
and continue with the next step. Use the forge command the step names, such as
`gh pr create`, wherever Cursor would use its PR tool.
