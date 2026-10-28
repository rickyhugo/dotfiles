# Configure pstack for this host

1. Read `~/.config/pstack/models.json`. Preserve other hosts and existing role
   choices. Determine whether this session runs in OpenCode, Claude Code, or Codex,
   and whether T3 Code tools are present. Inside T3, offer to configure both the
   `t3` object and the host's object, which applies outside T3.
2. Discover which native model IDs and reasoning controls this host actually
   supports. When T3 Code tools are present, also call `orchestrator_capabilities`
   and list each provider instance that can run child tasks, with its models and
   options; these are the choices for the `t3` object. If discovery is
   unavailable, offer `inherit-parent` or ask the user for a confirmed model ID.
   Do not use Cursor model slugs as defaults.
3. Ask which roles the user wants to change and show the proposed choices before
   writing. The default for every role is `inherit-parent`. Use these upstream
   labels verbatim:
   - `feature, refactoring`, `bug-fix`, `perf-issue`, `hillclimb`
   - `judgment and prose`, `hardest tasks`
   - `how explorer`, `how explainer`, `why investigators`, `why synthesizer`
   - `reflect tooling`, `reflect judgment, divergent, synthesizer`
   - `arena runners`, `arena cross-judge pool`, `swarm workers`
   - `architect runners`, `interrogate reviewers`
4. Store choices in the current host's `roles` object. Panel values are nonempty
   arrays of model IDs/aliases; other values are strings. Example:
   `"codex": { "roles": { "bug-fix": "inherit-parent", "interrogate reviewers": ["inherit-parent", "inherit-parent"] } }`.
   Host objects hold only native values; with options, write
   `{ "model": "opus", "options": { "effort": "high" } }`, naming the native
   agent tool's parameters. Store T3 choices in the top-level `t3`
   object's `roles`, always provider-qualified with the T3 provider instance ID,
   such as `"claudeAgent:claude-fable-5-1"` or `"codex:gpt-6.1-sol"`, or as
   `{ "target": "codex:gpt-6.1-sol", "options": { "reasoningEffort": "high" } }`
   when the user picks options. Roles `t3` omits use the host's object.
   Every role, including each panel seat, states its effort in `options`; ask
   for it with the model rather than leaving it to a default.
   Do not promise a mixed-model panel when both entries inherit one parent model.
5. Write through the existing symlink (do not replace it). This intentionally edits
   `.dotfiles/agent-skills/plugins/pstack/models.json`, so choices can be versioned. Keep
   valid JSON and preserve unknown keys. Do not edit any host's global model,
   permission, or provider settings. Effort is stored in `options` using the
   option name the model's tool takes (`effort` for Claude, `reasoningEffort`
   for Codex). Do not encode effort or speed into invented model IDs.
6. Report what changed. Adapted skills read this file on invocation; this is not
   an always-applied Cursor rule. It affects pstack delegation only, and the host's
   native agent model configuration may take precedence.
