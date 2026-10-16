# Cursor Team Kit adapter

CI, code review, shipping, and local-verification skills, including `deslop`,
`fix-ci`, `verify-this`, `control-cli`, and `control-ui`.

`plugin.json` registers `ci-watcher` and `thermo-nuclear-code-quality-review` as
native report-only helpers. Models inherit the parent instead of Cursor's `fast`
alias. `compat.md` explains the runtime and permission boundaries.

The control skills are instructions for building a local harness, not bundled
browser or terminal-control tools. The upstream `.mdc` rules are not globally
applied. OpenCode/Claude restrict reviewer tools; Codex inherits the parent sandbox,
so read-only scope there is instructional, not a separate security boundary.

Use the [shared commands](../../README.md) to install/update both plugins.
See the [usage guide](../../docs/usage.md) for example prompts.
