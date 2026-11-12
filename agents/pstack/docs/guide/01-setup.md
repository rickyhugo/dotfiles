# Set up pstack

Expose pstack's skills, choose models, and run your first task.

## Expose the skills

Follow the [README installation steps](../../README.md#install): keep one source
tree, link skill directories into your harness's discovery path, and add one
instruction pointer to [pstack/AGENTS.md](../../AGENTS.md). That file owns the
shared runtime rules and selects one [harness adapter](../../harnesses/).
Skills themselves contain no adapter loading. No plugin or generated tree is used.

## Pick your models

Run:

```text
/setup-pstack
```

[`/setup-pstack`](../../skills/setup-pstack/SKILL.md) shows current roles and the active harness's supported model controls. Choose models for your use cases and exact native reasoning options where supported. Save shared defaults in XDG `pstack/config.json`, or this machine's overrides in `pstack/config.local.json`.

Defaults inherit the session model. No vendor model or reasoning tier is assumed. Named profiles carry explicit native targets per harness; a harness with no target inherits and reports that gap. A harness without per-call model control can run the workflow but cannot honor independent model routing.

Override only the roles you care about. Roles merge by key, lists replace, and each named model profile replaces the whole lower-precedence profile. Setup preserves unrelated choices. Removing an override restores the lower-precedence value. Read [configuration](../configuration.md) for the format and examples. The agent reads and checks the JSON directly.

The built-in `inherit` profile omits model overrides. A panel list runs one attempt per entry, including duplicate or inherited entries. Defaults use two inherited seats. `arena-judges` is an ordered cross-family pool, empty by default, rather than a fan-out count. `swarm-worker` sets ordinary swarm worker models; a requested model race must verify each arm's actual model.

## Accept the verification offers, or don't

At the end of setup, `/setup-pstack` looks for a way to prove app behavior in your project, either a `verify-*` skill or an existing harness. If it finds neither, it offers once to generate one with [`/create-verification-skill`](../../skills/create-verification-skill/SKILL.md).

Say yes and it writes `verify-<app>/` under the project's discovered skill directory. It proves the skill works once before handing it over. Say no and setup moves on. You can run `/create-verification-skill` yourself any time. [Verify and ship](./06-verify-and-ship.md#create-a-project-verification-skill) covers it in depth.

If you're new to pstack, say yes. An agent that can check its own work keeps going until the check passes. An agent that can't hands every result back to you to check by hand. Of everything in this guide, the verification skill pays off the most.

Then setup offers once to generate a formal verification skill with [`/create-formal-verification-skill`](../../skills/create-formal-verification-skill/SKILL.md), unless the project already has one. Tests check the cases someone thought to write. A formal verification skill checks one key property of your code, such as "a job never runs twice at once", in every case within a stated scope. Say yes when your code has concurrency, retries, a state machine, or a parser, where a bug is costly and tests rarely reach the case that breaks. Otherwise say no, and run it later if that changes. [Verify and ship](./06-verify-and-ship.md#prove-a-property-with-a-formal-verification-skill) covers it.

Changes apply on the next model resolution. No new chat or restart is needed.

## Keep the cost in check

pstack spends extra tokens on subagents and review panels. That's the price of the rigor. To spend fewer:

- Rerun `/setup-pstack` and choose cheaper models or lower native reasoning settings where supported.
- Set a role to `inherit` so it runs on the chat's own model.
- Shorten a panel list. Each entry runs one subagent.
- Save `/poteto-mode` for work that needs rigor. A small, obvious edit doesn't.

## Run your first task

Pick something real but small, and describe it the way you'd describe it to a colleague:

```text
/poteto-mode add a --json flag to this command. text output stays byte-identical. verify both.
```

Watch the todo list. Its first items are the matched playbook's steps copied in, the Feature playbook for this prompt. If `/poteto-mode` skips a step, the step stays in the list with `skip: <reason>`, so you can see what it chose not to do.

From here you can type normal follow-ups. To keep `/poteto-mode` on for the whole chat, pick it from the `/` menu with Option+Enter (Mac) or Alt+Enter (Windows) instead of Enter. That makes it a [Custom Mode](https://cursor.com/docs/skills#using-a-skill-as-a-custom-mode), which stays in context on every turn until you exit it. Custom Modes are available in the Agents Window and the CLI. Plain Enter attaches the skill to one message, and it fades as the chat moves on.

Next: [Route work through `/poteto-mode`](./02-poteto-mode.md).
