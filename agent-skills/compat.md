## Local host compatibility

These skills are adapted for OpenCode, Claude Code, and Codex, not Cursor.
Use this section and the plugin-specific notes instead of incompatible upstream
assumptions. System instructions, native permissions, user scope, and approvals
take precedence. Loading a skill is not authorization to publish, merge, message
people, delete data, or perform other external actions.

Translate upstream `Task` calls to the host's actual delegation tool and schema:

| Host        | Named agent                                 | General-purpose agent              |
| ----------- | ------------------------------------------- | ---------------------------------- |
| OpenCode    | `subagent` with `agent: "<id>"`             | `agent: "general"`                 |
| Claude Code | `Agent` with `subagent_type: "<id>"`        | `subagent_type: "general-purpose"` |
| Codex       | native spawn tool with `agent_type: "<id>"` | `agent_type: "default"`            |

Use only registered native agent IDs. Translate Cursor's `shell` agent to a
general-purpose worker with explicit scope, and use the host's explorer when
available. Omit unsupported Cursor parameters such as `environment`, `readonly`,
and `run_in_background`. Use native background/model parameters only if supported.
Do not silently substitute local execution for requested cloud execution.
When delegation is unavailable, explain the limitation; self-review is not an
independent review. Models inherit the parent unless plugin-specific notes
configure a supported native choice. Never manufacture Cursor model slugs.

Resolve supporting files within the current plugin tree. For cross-plugin
references, use the skill loader or `~/.agents/skills/<id>/SKILL.md`, not a sibling
path assumption. OpenCode uses `@skill-id`, Claude Code uses `/skill-id`, and
Codex uses `$skill-id`. Host invocation restrictions still apply.

Cursor's persistent modes, cloud agents, history APIs, `/loop`, and UI features
are not provided by this layer. Use an available equivalent only after checking
its capabilities. For `create-skill`, prefer the host's skill-creator. Do not
install dependencies or claim verification without appropriate permission and
actual evidence. Use the host-approved temporary directory, not hard-coded `/tmp`.

Keep changes to adapters in `.dotfiles/agent-skills/plugins/<plugin>/`. Do not
edit pristine cached sources or generated files. Cursor `.mdc` rules are preserved
as reference material, not globally applied instructions.
