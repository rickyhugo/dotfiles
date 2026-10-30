# dotfiles

My machines, but make it reproducible. Configs for `nvim`, `kitty`, `starship`, `btop`, `k9s`, `lazygit`, `lazydocker`, `vscode`, `opencode`, `ccmux`, `fsh`, `worktrunk` — plus `wallpapers` so it looks good while breaking.

No snowflakes here: one bootstrap to rule both OSes, powered by `mise`.

## Setup

Pick your fighter (sets `MISE_ENV` all the way through to `mise bootstrap`):

```sh
MISE_ENV=personal ./scripts/bootstrap_archlinux.sh  # Arch Linux
MISE_ENV=work ./scripts/bootstrap_macos.sh          # macOS
```

Re-runnable and idempotent. Running as root is rejected — even the scripts have boundaries.

## Agent skills

Mise clones pstack, Cursor Team Kit, Matt Pocock's skills, and tstack into
`~/.external-skills/`, then links each skill into `~/.agents/skills/` with a
prefix naming its source (`pstack-`, `cursor-`, `mp-`, `tstack-`). Claude Code,
Codex, and OpenCode all read that directory. The entries live in the
`[dotfiles]` and `[bootstrap.repos]` sections of `~/.config/mise/config.toml`.

[`agents/`](agents) holds the rest, deployed by `mise dot apply`:

- `AGENTS.md`: global instructions for every harness, linked as `~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`, and `~/.config/opencode/AGENTS.md`.
- `cursor-compat.md`: how pstack and Team Kit skills map Cursor's tools, agents,
  and models onto each harness.
- `claude/`, `codex/`, `opencode/`: helper agents such as `poteto-agent`, one
  file per host.
- `skills/`: my own skills, such as `gh-auth`.

## Neovim project tools

Each project declares its LSP / formatters / linters in `.nvim-tools.lua` at its root; `~/.nvim-tools.lua` is the global base. Nearest project file wins, global fills the gaps. **Without either file, nothing runs** — silence is a feature.

Tools come from `$PATH` via mise shims, so start Neovim inside the project and pin versions in `mise.local.toml`. Try `:ProjectTools show` to see the merged config, `:ProjectTools edit` to tweak it.

CodeLens annotations are disabled by default. Opt in with `lsp = { "tsgo", codelens = true }` in either tools file; a project's `lsp.codelens` overrides the global value. Changes apply automatically.

For LuaLS completion and hover docs, add `---@type ProjectToolsConfig` immediately before `return { ... }`. LazyDev loads the shared types automatically; newly generated configs already include the annotation. LuaLS must be enabled for the buffer.

Verify with:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
