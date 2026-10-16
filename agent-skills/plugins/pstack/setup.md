# Configure pstack for this host

1. Read `~/.config/pstack/models.json`. Preserve other hosts and existing role
   choices. Determine whether this session runs in OpenCode, Claude Code, or Codex.
2. Discover which native model IDs and reasoning controls this host actually
   supports. If discovery is unavailable, offer `inherit-parent` or ask the user
   for a confirmed model ID. Do not use Cursor model slugs as defaults.
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
   Do not promise a mixed-model panel when both entries inherit one parent model.
5. Write through the existing symlink (do not replace it). This intentionally edits
   `.dotfiles/agent-skills/plugins/pstack/models.json`, so choices can be versioned. Keep
   valid JSON and preserve unknown keys. Do not edit any host's global model,
   permission, or provider settings. Reasoning effort follows the parent unless
   the user separately requests a supported native setting; do not encode effort
   or speed into invented model IDs.
6. Report what changed. Adapted skills read this file on invocation; this is not
   an always-applied Cursor rule. It affects pstack delegation only, and the host's
   native agent model configuration may take precedence.
