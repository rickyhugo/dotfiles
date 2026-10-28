## Pstack compatibility

Before following this skill, read `~/.config/pstack/models.json`. Choose the
current host's `opencode`, `claude`, or `codex` object; when T3 Code tools are
present, look up each role in the `t3` object first and fall back to the host's
object for roles `t3` omits. `roles` maps upstream role labels to model IDs, or
lists for panels. Missing roles, `auto`, and
`inherit-parent` mean inherit the parent, NOT an upstream Cursor model default.
Missing panel roles use two independent inherited-model workers. Preserve panel
size, but do not claim model diversity when workers use the same model.

Use only model IDs and effort settings confirmed available in this host, or for
`t3` roles, in T3 Code's catalog. If a configured choice is unavailable,
disclose it and inherit the parent instead of retrying an upstream default. `setup-pstack` configures this JSON file, not Cursor
rules; ignore `pstack-models.mdc` and `~/.cursor/rules/` references.

A host value, alone or in a panel, may also be
`{ "model": "opus", "options": { "effort": "high" } }`. Pass each option as the
native agent tool's parameter of the same name, such as Claude Code's `Agent`
`effort`; the entry is the user's explicit request for that setting. If the tool
has no such parameter or rejects the value, disclose it and run without it.

Every configured role states its effort, and that effort is binding: it overrides
any upstream instruction to pick a reasoning level per job. A configured role
with no effort is a configuration gap; disclose it and use `high`.

### T3 Code roles

This extends the shared rule that models are native choices. T3 Code tools are
present when `orchestrator_capabilities` is callable, after one bounded direct
attempt if the tool catalog does not list it, or when `T3_ACP_MCP_NODE` is set.
Without them, ignore the `t3` object and use only the host's object, so the same
file serves T3 Code and the plain host.

Every `t3` value is provider-qualified, because a T3 thread can run on any
harness. `"<provider>:<model>"`, such as `"codex:gpt-6.1-sol"`, names a T3
provider instance and a model in its catalog; split on the first `:`. The object
form `{ "target": "codex:gpt-6.1-sol", "options": { "reasoningEffort": "high" } }`
adds model options. Host objects hold only native values; disclose a qualified
value found there and inherit the parent for that role.

Run a `t3` role with the native agent tool only when it names the current
harness's provider instance, the native tool accepts the model or an alias that
resolves to it (`claude-opus-5-5` is `opus`), and every option is a native tool
parameter of the same name, such as `effort` on Claude Code's `Agent`; otherwise
use T3's `delegate_task` (or its documented ACP fallback).
Before the first delegation, call `orchestrator_capabilities` (pass `search` for
unlisted models) and confirm the provider instance can run child tasks and has
the model. Pass `options` as `target.options`, checked against the model's
descriptors. Without them the child uses the model's defaults: parent options do
not cross providers. If the provider is disabled or the model or an option is
missing, disclose it and use the host's object for that role.

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
