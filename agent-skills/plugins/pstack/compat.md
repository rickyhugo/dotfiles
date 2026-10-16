## Pstack compatibility

Before following this skill, read `~/.config/pstack/models.json`. Choose the
current host's `opencode`, `claude`, or `codex` object. `roles` maps upstream role
labels to native model IDs, or lists for panels. Missing roles, `auto`, and
`inherit-parent` mean inherit the parent, NOT an upstream Cursor model default.
Missing panel roles use two independent inherited-model workers. Preserve panel
size, but do not claim model diversity when workers use the same model.

Use only model IDs and effort settings confirmed available in this host. If a
configured choice is unavailable, disclose it and inherit the parent instead of
retrying an upstream default. `setup-pstack` configures this JSON file, not Cursor
rules; ignore `pstack-models.mdc` and `~/.cursor/rules/` references.

The main chat owns the playbook. Use the native `poteto-agent` for delegates, not
to run the whole playbook. Give workers the absolute path to this plugin's
`skills/poteto-mode/SKILL.md`. `comment-sicko` is a report-only reviewer.
Team Kit skills such as `deslop`, `control-cli`, and `control-ui` are available
through the global skill links, but their tools and dependencies must still be
discovered in the current environment.
