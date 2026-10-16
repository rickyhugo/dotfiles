## Local host compatibility

This is an adapted pstack copy for OpenCode, Claude Code, and Codex, not Cursor.
For host-specific instructions below, use this section instead of incompatible
Cursor assumptions in the upstream text. It does not override system instructions,
permissions, user scope, or approval requirements. A skill is not authorization to
publish, merge, message people, delete data, or perform other external actions.

Before following this skill, read `~/.config/pstack/models.json`. Choose the current
host's `opencode`, `claude`, or `codex` object. `roles` maps the upstream role labels
to native model IDs or lists of IDs for panels. A missing role, `auto`, or
`inherit-parent` means inherit the parent model, NOT the upstream Cursor default.
Missing panel roles use two independent inherited-model workers. Do not claim
model diversity when those workers use the same model. Use only model IDs and
effort settings confirmed available to the current host; never manufacture Cursor
slugs or retry an unavailable model with an upstream default. If a configured model
is unavailable, disclose it and inherit the parent. Preserve requested panel size.

Translate upstream `Task` calls into the host's actual delegation tool:

| Host        | Worker selection                                    | General-purpose selection          |
| ----------- | --------------------------------------------------- | ---------------------------------- |
| OpenCode    | `subagent` with `agent: "poteto-agent"`             | `agent: "general"`                 |
| Claude Code | `Agent` with `subagent_type: "poteto-agent"`        | `subagent_type: "general-purpose"` |
| Codex       | native spawn tool with `agent_type: "poteto-agent"` | `agent_type: "default"`            |

`comment-sicko` is registered on each host as a read-only reviewer. Pass native
model/background parameters only when the tool supports them. Omit Cursor-only
`environment`, `readonly`, and `run_in_background` arguments when unsupported;
express read-only scope in the task prompt and enforce permissions where possible.
Do not turn a requested cloud execution into local execution without disclosure.
When delegation is unavailable or disallowed, explain the limitation; a serial
self-review is not an independent review. Tell every worker the absolute path to
the installed `poteto-mode/SKILL.md`, and let the parent own the playbook.

Resolve bundled skills relative to this installed skill tree. Use the host's skill
loader or read the file directly; Cursor slash-command spelling is not a tool API.
OpenCode uses path-derived skill IDs, Claude Code uses slash commands, and Codex
uses `$skill-name`. Host permissions and invocation restrictions still apply.

`setup-pstack` in this tree configures the shared JSON file, not Cursor rules.
Ignore all references to `pstack-models.mdc` and `~/.cursor/rules/`. Do not edit the
pristine upstream download or generated skill files to capture lessons: propose
changes to the compatibility sources in `.dotfiles/agent-skills/pstack` instead.

The external `cursor-team-kit` skills (`deslop`, `control-cli`, `control-ui`) and
Cursor's `create-skill`, cloud agents, chat history, loops, and UI features are NOT
provided by this layer. Use an installed equivalent only after checking its
capabilities. For `create-skill`, use the host's skill-creator if available. For
`deslop`, perform a normal diff/code-quality review and identify the substitution.
For UI/CLI proof, use actual available browser/terminal tools; if no equivalent
exists, report the missing verification rather than claiming the gate passed.

## Upstream instructions
