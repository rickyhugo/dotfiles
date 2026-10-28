# Using agent skills

Start with `poteto-mode` for nontrivial engineering tasks. It chooses a playbook
and invokes the other skills as needed. You do not need to pick every skill or
coordinate the worker agents yourself.

This guide describes our compatibility layer for OpenCode, Claude Code, and
Codex. The [upstream README](https://github.com/cursor/plugins/tree/main/pstack#readme)
describes the original Cursor workflows.

## Invoke a skill

Skills are installed globally for your user, so you can use them in any project.
Invoke them in the agent's chat, not your terminal:

| Host        | Main entry point | Individual skill example |
| ----------- | ---------------- | ------------------------ |
| OpenCode    | `@poteto-mode`   | `@interrogate`           |
| Claude Code | `/poteto-mode`   | `/interrogate`           |
| Codex       | `$poteto-mode`   | `$interrogate`           |

Select the skill from the host's completion menu when available, then add your
task. `poteto-mode` requires explicit invocation; global installation does not
make it always active. Invoke it again when starting a new task or conversation.

## Give it a goal and boundaries

A useful prompt states the outcome, relevant symptoms or files, how success
should be demonstrated, and what the agent must not do. You can leave the
implementation approach open.

Examples below use OpenCode syntax. Replace the prefix for the other hosts.

### Fix a bug

```text
@poteto-mode Fix the intermittent timeout in the import command.
Reproduce it first, fix the root cause, and verify the behavior.
Don't commit or open a PR.
```

### Build a feature

```text
@poteto-mode Add cancellation to background imports.
Follow the existing patterns. Demonstrate that cancellation stops the work
and leaves partial output in a safe state. Keep changes local.
```

### Investigate without editing

```text
@poteto-mode Investigate why startup is slow.
Measure the bottleneck before proposing changes. Read-only for now.
```

### Refactor without changing behavior

```text
@poteto-mode Simplify the configuration loader without changing its behavior.
Keep the public API unchanged and verify existing configuration files still load.
Don't commit, push, or open a PR.
```

Keep publication boundaries explicit. Some upstream playbooks include opening
PRs or shipping changes; loading a skill does not grant permission to do either.

## Choose an individual skill

Use a specific skill when you already know the kind of help you want.

| Goal                       | OpenCode prompt                                              |
| -------------------------- | ------------------------------------------------------------ |
| Pick the right workflow    | `@poteto-help Which skill fits a review of this branch?`     |
| Clarify the task           | `@in-your-own-words Restate the goal before starting.`       |
| Understand implementation  | `@how How does session restoration work?`                    |
| Understand design history  | `@why Why did we choose polling here?`                       |
| Learn a subsystem          | `@teach Explain this module and the reasoning behind it.`    |
| Assess consequences        | `@blast-radius What could changing this API break?`          |
| Settle API and type design | `@architect Design cancellation before implementing it.`     |
| Compare alternatives       | `@arena Compare two approaches to caching this response.`    |
| Divide independent checks  | `@swarm Check every package's test setup. One report.`       |
| Review changes             | `@interrogate Review this branch against main. Report only.` |
| Test before fixing         | `@tdd Write a failing test for this bug, then fix it.`       |
| Clean up prose             | `@unslop Tighten the README without losing information.`     |

Parallel workflows can use more tokens than a single-agent task. Reserve them
for work where independent attempts, coverage, or review justify the cost.

## Cursor Team Kit skills

These skills use the same global links and invocation syntax as pstack:

| Goal                          | OpenCode prompt                                                      |
| ----------------------------- | -------------------------------------------------------------------- |
| Clean up code style           | `@deslop Clean up this branch's diff without changing behavior.`     |
| Diagnose CI failures          | `@fix-ci Investigate failing checks. Don't push or rerun workflows.` |
| Prove a claim                 | `@verify-this Verify whether this change improves startup time.`     |
| Drive a CLI or TUI            | `@control-cli Reproduce the keyboard navigation bug locally.`        |
| Verify a web UI               | `@control-ui Demonstrate the form validation with local test data.`  |
| Strict maintainability review | `@thermo-nuclear-code-quality-review Review this diff. Report only.` |

The control skills build on tools already available in the project or environment;
installation does not provision a browser, Playwright, tmux, or a CDP endpoint.
Some kit workflows include commits, PRs, or shipping, so specify those boundaries.

## Matt Pocock skills

Matt Pocock's skills use the same global links:

| Goal                     | OpenCode prompt                                                          |
| ------------------------ | ------------------------------------------------------------------------ |
| Pick a workflow          | `@ask-matt Which skill fits a tricky refactor?`                          |
| Stress-test a plan       | `@grilling Interview me about this design until the branches are clear.` |
| Diagnose a hard bug      | `@diagnosing-bugs Find the root cause of this intermittent failure.`     |
| Build test-first         | `@matt-tdd Implement this slice one failing test at a time.`             |
| Review a branch          | `@code-review Review this branch against main on standards and spec.`    |
| Turn a plan into tickets | `@to-tickets Break this plan into tracer-bullet tickets.`                |
| Write a PR body          | `@pr Draft the PR body from this diff.`                                  |
| Hand off a session       | `@handoff Summarize this session for the next agent.`                    |

`tdd` and `teach` are installed as `matt-tdd` and `matt-teach` because pstack
already provides skills with those names. Adapting a repo with
`@setup-matt-pocock-skills` is optional; the engineering skills also work without
it, but spec, ticket, and triage workflows read the tracker configuration it
creates. Commit, tracker, and PR actions still require explicit permission.

The `misc` and `in-progress` sets are experimental. `git-guardrails-claude-code`
and `claude-handoff` are Claude Code-specific features and are not emulated on
other hosts.

## Workers and models

The main chat runs `poteto-mode` and owns the playbook. It delegates individual
tasks to `poteto-agent`. Do not ask a worker to run the entire playbook. For
comment review, normally invoke `no-comments` rather than `comment-sicko` directly.

Models inherit the parent by default in our installation. To change pstack's
per-host role choices, invoke `setup-pstack` with your host's prefix, for example:

```text
@setup-pstack Configure the models used for implementation and review.
```

Settings live in `~/.config/pstack/models.json`, linked to the versioned
[`models.json`](../plugins/pstack/models.json) here. These choices affect pstack delegation, not
your host's global model. A review panel with inherited models gives independent
workers, but not different model families.

## Check the installation

From the dotfiles directory, run:

```sh
mise run skills:check
```

For OpenCode's native worker registration:

```sh
opencode debug agents
```

Look for `poteto-agent` and `comment-sicko` with `mode: subagent`. They are workers,
not primary agents in the main-agent picker. Start a fresh host session if a
newly installed skill or agent is missing.

## What does not carry over from Cursor

Cursor's persistent-mode shortcut, `/loop`, cloud agents, history APIs, and
browser/terminal-control runtimes are not supplied by our compatibility layer. Workflows
that need them must use a verified available equivalent or report the missing
capability. Native permissions and approval requirements still apply.

For installation, daily updates, logs, and adapter internals, see the
[compatibility README](../README.md).
