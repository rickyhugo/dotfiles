## Matt Pocock skills compatibility

These skills come from [`mattpocock/skills`](https://github.com/mattpocock/skills),
which targets Claude Code and Codex. Follow the shared host translation above.
When an upstream skill says to call the Skill tool with a skill name, invoke the
installed skill using this host's syntax.

`tdd` and `teach` are installed as `matt-tdd` and `matt-teach` because pstack
already owns those IDs. Use the `matt-*` names for Matt's workflows; the
unprefixed `tdd` and `teach` skills are different pstack skills. Adapted bodies
already use the renamed references.

`claude-handoff` launches `claude --bg`, and `git-guardrails-claude-code` writes
Claude Code hooks. Use them only on a host that actually provides those features;
otherwise report the limitation or use `handoff`.

The `misc` and `in-progress` skills are experimental and may assume TypeScript
or specific repository tooling. Issue-tracker writes, label changes, commits,
and PR actions need explicit user approval and the repository's configured
tracker.
