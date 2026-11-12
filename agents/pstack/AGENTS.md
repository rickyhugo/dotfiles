# Running pstack

Read this file once when using pstack. It owns execution guidance; `skills/`
owns the workflows and principles. Session permissions and user scope come first.

Read only the adapter for the active harness:

- [Cursor](harnesses/cursor.md)
- [Claude Code](harnesses/claude-code.md)
- [Codex](harnesses/codex.md)
- [OpenCode](harnesses/opencode.md)
- [T3 Code](harnesses/t3-code.md)

On another harness, use its exposed native tools under the rules below. Report
unsupported capabilities rather than inventing equivalents.

## Paths and roles

`<pstack>` is the real directory containing this file. Resolve symlinks before
following paths. A pstack sibling is `<pstack>/skills/<name>/SKILL.md`; read that
file when its catalog ID is hidden or ambiguous. Use registered IDs in commands
shown to the user. No plugin namespace or cache search is required.

Give delegates absolute reference paths and self-contained briefs. Use the bundled
`agents/poteto-agent.md` for playbook helpers and `agents/comment-sicko.md` for
comment review. A native agent from this installation can supply that role;
otherwise give the role file to a general agent. The parent owns the playbook.

Create new skills in an established, discovered skill directory. Use the host's
skill-authoring workflow when available, otherwise the standard SKILL.md layout.
Keep installed sources and unrelated work untouched unless authorized to edit them.

## Models

Before a delegation batch, read [model configuration](docs/configuration.md) and
the existing shared and machine-local config files. Apply the role's exact native
settings for the active harness. Read the files directly; no resolver, generated
rules, plugin, or background service is required.

Treat model IDs and reasoning/speed options as opaque values. Validate configured
choices against native schemas or available model listings. Missing choices
inherit the session model. Unmapped or unavailable choices inherit with a visible
note. Do not substitute an unchosen model or rewrite model-name suffixes.

Preserve panel order and count, including duplicates. Different attempts on one
model are not a multi-model panel. A cross-family judge must actually run on a
configured, usable family distinct from the known parent family. Otherwise report
that cross-family review could not run. Independent verification remains open
when only self-review is possible.

## Capabilities

Use only parameters accepted by the active tool. Keep investigative agents
report-only while retaining access to required MCP services. Use completion
notifications and parallel work when supported. Give concurrent writers separate
worktrees at explicit base SHAs; otherwise serialize writes.

Use native session history or explicitly exposed transcript paths, scoped to the
authorized conversation/workspace. If unavailable, use a digest and label the gap.
Use native plan/question tools when offered, otherwise a short list/plain text.
Discover MCPs through the session's tool catalog. Use the forge CLI when there is
no native PR tool. Provider-only automations, dashboards, persistent loops, and
subscriptions remain optional host features. Report missing features and block
dependent steps rather than claiming success.

When orchestration has no persistent workers or event delivery, run only a bounded
unit the session can supervise. A cross-family verification gate remains open
when no distinct-family verifier is usable. A missing companion skill is a named
gap, not permission to silently skip its quality gate.
