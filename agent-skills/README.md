# Agent skills

Global skills and native helper agents for OpenCode V2, Claude Code, and Codex.
The shared installer handles Git sources, host compatibility, mise deployment,
verification, and daily updates. Plugin-specific behavior lives in `plugins/`.

See the [usage guide](docs/usage.md) for invocation examples and choosing skills.

## Commands

From the dotfiles directory:

```sh
mise run skills:install
mise run skills:check
mise run skills:update
```

Requires uv, Git, and mise with `dotfiles` support. The installer declares Python
3.11+ in inline metadata; uv selects or downloads a compatible interpreter.
`install` uses pinned commits; `update` resolves each source's branch, installs
the result, verifies it, and then records the new pins. It never pulls, commits,
or pushes this dotfiles repository.

## Structure

```text
agent-skills/
├── sources.json                # Repositories, branches, pins, plugin paths
├── compat.md                   # Shared host/tool translation
├── plugins/
│   ├── pstack/                 # Model settings, setup override, agent prompts
│   └── cursor-team-kit/        # Agent prompts and harness compatibility notes
├── docs/usage.md
├── .cache/                     # Pristine sources and archived migration data
└── .generated/                 # Adapted plugins, native agents, mise config
```

`scripts/setup_skills.py` is the shared uv entry point. Cache and generated
directories are ignored by Git. Each generated plugin retains its own supporting
files, license, and relative paths under `.generated/plugins/<plugin>/`.

## Add a source or plugin

Declare it in [`sources.json`](sources.json). Source IDs and plugin IDs must be
unique lowercase kebab-case names. Each plugin path is relative to its repository
and must contain `skills/<skill-id>/SKILL.md`:

```json
{
  "example-source": {
    "repository": "https://github.com/example/skills.git",
    "branch": "main",
    "revision": "<full 40-character commit SHA>",
    "plugins": { "example-plugin": "path/to/plugin" }
  }
}
```

Skills-only plugins need no installer changes. For host adaptations, add an
optional `plugins/<plugin>/compat.md` and `plugin.json`. The latter can declare:

- `skills`: per-skill `body` file and/or `description` overrides.
- `agents`: native agent descriptions and prompt files; `include_upstream`
  defaults to true, `read_only` to false, and `shell` to true. Prompts can use
  `{{plugin_root}}` for the absolute generated plugin directory.
- `links`: additional `~/...` destinations pointing to files in the local adapter.

See [pstack's adapter](plugins/pstack/plugin.json) for an example. Duplicate skill
or agent IDs fail rather than silently overriding another plugin. Other Markdown
skill layouts or vendor-specific features need adaptation before use.

For offline installation, point each source ID at a checkout containing its
configured plugin paths; the caller must verify the checkout's revision:

```sh
uv run --script scripts/setup_skills.py --source cursor-plugins=/path/to/plugins --install
```

## Global deployment

The installer generates `.generated/mise.toml`, then invokes `mise dotfiles apply`
for only its declared targets. Definitions are not stored in the global mise
config. Per-skill links are installed in `~/.agents/skills/` for OpenCode/Codex
and `~/.claude/skills/` for Claude Code. Native agents go in the respective global
`~/.config/opencode/agents/`, `~/.claude/agents/`, and `~/.codex/agents/` directories.

Existing managed links are migrated to the new layout; unrelated files and links
are never overwritten. The old pstack cache/generated tree is archived under
`.cache/legacy-pstack/` after deployment. Model settings remain at
`~/.config/pstack/models.json`, now linked to `plugins/pstack/models.json`.
Removed installed skills or links stop updates for manual review rather than
silently pruning files. Edit adapter sources, not cached or generated files.

## Daily updates (macOS)

```sh
mise run skills:daily:enable
mise run skills:daily:status
mise run skills:daily:disable
```

Mise deploys a LaunchAgent that runs `mise run skills:update` at **09:00 local
time** and login. A calendar run missed during sleep runs on wake. It runs as the
logged-in user; offline failures retry at the next run. Logs are at
`~/Library/Logs/agent-skills/sync.log` and `sync-error.log`. Manual and scheduled
installs and checks share a lock. Generated files are replaced atomically.
Disabling removes only the managed job, not the skills.
Installation migrates an enabled legacy pstack job to this schedule. The old
`pstack:*` tasks have been replaced with `skills:*` tasks.

Auto-updates trust new upstream instructions. Verification checks links, file
hashes, and adapter structure, not future model behavior. Missing capabilities
must be reported, not claimed as completed. Native permissions and user approval
requirements always apply; no permission bypasses are installed.

## Included plugins

- [pstack](plugins/pstack/README.md): engineering workflows and role-based models.
- [Cursor Team Kit](plugins/cursor-team-kit/README.md): CI, review, and local verification.

The control skills describe harnesses; they do not install browsers, Playwright,
tmux, or CDP tools. Cursor cloud agents, persistent modes, history APIs, and `/loop`
are not supplied. Cursor `.mdc` rules remain reference files, not global policy.
