# pstack adapter

Engineering workflows entered through `poteto-mode`, with `poteto-agent` workers
and the report-only `comment-sicko` reviewer. The shared installer and update
schedule live at the [agent-skills root](../../README.md).

- `compat.md`: pstack-specific delegation and model-role semantics.
- `setup.md`: portable replacement for Cursor's `setup-pstack` workflow.
- `models.json`: versioned per-host role choices, globally linked at
  `~/.config/pstack/models.json`. Missing roles inherit the parent model; panels
  default to two independent workers, not necessarily different model families.
  A `"<provider>:<model>"` role, such as `"codex:gpt-6.1-sol"`, runs through T3
  Code's `delegate_task`, so Claude Code can use GPT models; outside T3 it falls
  back to the parent model.
- `plugin.json`: skill overrides, model-file link, and native agent policies.
- `agents/`: local worker prompts; the comment reviewer also keeps its upstream rubric.

Use `@poteto-mode` in OpenCode, `/poteto-mode` in Claude Code, or `$poteto-mode`
in Codex. Invoke `setup-pstack` to configure per-host model roles; this does not
change the host's global model settings. See the [usage guide](../../docs/usage.md).
