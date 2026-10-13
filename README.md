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

## Neovim project tools

Each project declares its LSP / formatters / linters in `.nvim-tools.lua` at its root; `~/.nvim-tools.lua` is the global base. Nearest project file wins, global fills the gaps. **Without either file, nothing runs** — silence is a feature.

Tools come from `$PATH` via mise shims, so start Neovim inside the project and pin versions in `mise.local.toml`. Try `:ProjectTools show` to see the merged config, `:ProjectTools edit` to tweak it.

Verify with:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
