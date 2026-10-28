# Matt Pocock skills adapter

[Matt Pocock's skills](https://github.com/mattpocock/skills) for engineering
workflows, planning, review, and writing. The source is pinned in
[`sources.json`](../../sources.json) and includes all four published categories:
`engineering`, `productivity`, `misc`, and `in-progress`.

The installer discovers skills in each category, flattens them under
`.generated/plugins/mattpocock-skills/skills/`, and links them into
`~/.agents/skills/` and `~/.claude/skills/`.

`tdd` and `teach` are installed as `matt-tdd` and `matt-teach` because pstack
already provides skills with those IDs. `plugin.json` records the renames and
updates upstream invocation references in the adapted bodies.

`compat.md` covers host translation, the Claude Code-only `claude-handoff` and
`git-guardrails-claude-code` skills, and the experimental status of the
`misc`/`in-progress` sets. Use the [shared commands](../../README.md) to
install or update the plugin. See the [usage guide](../../docs/usage.md) for
example prompts.
