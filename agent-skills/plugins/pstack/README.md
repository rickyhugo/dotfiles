# pstack adapter

Engineering workflows entered through `poteto-mode`, with `poteto-agent` workers
and the report-only `comment-sicko` reviewer. The shared installer and update
schedule live at the [agent-skills root](../../README.md).

- `compat.md`: pstack-specific delegation and model-role semantics.
- `setup.md`: portable replacement for Cursor's `setup-pstack` workflow.
- `models.json`: versioned per-host role choices, globally linked at
  `~/.config/pstack/models.json`. Missing roles inherit the parent model; panels
  default to two independent workers, not necessarily different model families.
  The `t3` object applies inside T3 Code, whatever the harness, and takes
  provider-qualified roles such as `"codex:gpt-6.1-sol"`, run through T3's
  `delegate_task`. Roles it omits, and every role outside T3, use the host's object.
  Set `t3.active_profile` to `claudeAgent` or `claudeAgentDelfi` to select the
  subscription. Profiles remap Claude's provider ID while sharing role models
  and effort settings; Codex panel members stay unchanged. Agents validate the
  selected provider's availability in T3 before delegating.
- `plugin.json`: skill overrides, model-file link, and native agent policies.
- `agents/`: local worker prompts; the comment reviewer also keeps its upstream rubric.

Use `@poteto-mode` in OpenCode, `/poteto-mode` in Claude Code, or `$poteto-mode`
in Codex. Invoke `setup-pstack` to configure per-host model roles; this does not
change the host's global model settings. See the [usage guide](../../docs/usage.md).
