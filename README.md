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

## Shared agent skills

Install pstack globally for OpenCode, Claude Code, and Codex with
`mise run pstack:install`. Mise deploys the symlinks; the compatibility layer and
model choices live in [`agent-skills/pstack`](agent-skills/pstack/README.md).
Use `mise run pstack:check` to verify the installation and `mise run pstack:test`
to run the adapter tests.

`mise run pstack:update` syncs the latest upstream version. On macOS,
`mise run pstack:daily:enable` enables automatic updates at 09:00 and login;
`mise run pstack:daily:disable` turns them off.

## Neovim project tools

Each project declares its LSP / formatters / linters in `.nvim-tools.lua` at its root; `~/.nvim-tools.lua` is the global base. Nearest project file wins, global fills the gaps. **Without either file, nothing runs** — silence is a feature.

Tools come from `$PATH` via mise shims, so start Neovim inside the project and pin versions in `mise.local.toml`. Try `:ProjectTools show` to see the merged config, `:ProjectTools edit` to tweak it.

CodeLens annotations are disabled by default. Opt in with `lsp = { "tsgo", codelens = true }` in either tools file; a project's `lsp.codelens` overrides the global value. Changes apply automatically.

Verify with:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
