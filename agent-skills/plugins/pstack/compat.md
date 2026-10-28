## Pstack compatibility

Before following this skill, read `~/.config/pstack/models.json`. Choose the
current host's `opencode`, `claude`, or `codex` object. `roles` maps upstream role
labels to native model IDs, or lists for panels. Missing roles, `auto`, and
`inherit-parent` mean inherit the parent, NOT an upstream Cursor model default.
Missing panel roles use two independent inherited-model workers. Preserve panel
size, but do not claim model diversity when workers use the same model.

Use only model IDs and effort settings confirmed available in this host, or for
cross-provider roles, in T3 Code's catalog. If a configured choice is unavailable,
disclose it and inherit the parent instead of retrying an upstream default. `setup-pstack` configures this JSON file, not Cursor
rules; ignore `pstack-models.mdc` and `~/.cursor/rules/` references.

### Cross-provider roles

This extends the shared rule that models are native choices. A role value
`"<provider>:<model>"`, such as `"codex:gpt-6.1-sol"`, names a T3 Code provider
instance and a model in its catalog. The object form
`{ "target": "codex:gpt-6.1-sol", "options": { "reasoningEffort": "high" } }`
adds model options. Split on the first `:`. Unqualified values stay native to the
current host. Panel arrays may mix both forms.

Run a qualified role with T3's `delegate_task` (or its documented ACP fallback),
not the native agent tool. The exception is a role that names the current host's
own provider and a model the native tool accepts without options. Before the first
such delegation, call `orchestrator_capabilities` (pass `search` for unlisted
models) and confirm the provider instance can run child tasks and has the model.
Pass `options` as `target.options`, checked against the model's descriptors.
Without them the child uses the model's defaults: parent options do not cross
providers. If T3 tools are absent, the provider is disabled, or the model or an
option is missing, disclose it and run the role on the parent model.

A `delegate_task` child has no `poteto-agent` or `comment-sicko` registration, so
its prompt carries the role. Give a worker the absolute path to
`skills/poteto-mode/SKILL.md`; tell a reviewer to report only, without editing.
Include the full brief, scope, and expected output. Use `isolation: "worktree"`
for parallel editing workers. It starts from the parent's last commit, so commit
or describe any uncommitted state first. Track each `taskId` with `task_status`
and start every later round with a new `delegate_task` and a distinct
`clientRequestId`. The main chat applies child results. A panel is model-diverse
when its entries name different providers or models.

The main chat owns the playbook. Use the native `poteto-agent` for delegates, not
to run the whole playbook. Give workers the absolute path to this plugin's
`skills/poteto-mode/SKILL.md`. `comment-sicko` is a report-only reviewer.
Team Kit skills such as `deslop`, `control-cli`, and `control-ui` are available
through the global skill links, but their tools and dependencies must still be
discovered in the current environment.
