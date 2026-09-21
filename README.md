# dotfiles

## Setup

Run the bootstrap for your OS (installs OS deps, then `setup_mise.sh`).
Set `MISE_ENV` on the same command so it flows through to `mise bootstrap`:

```sh
MISE_ENV=personal ./scripts/bootstrap_archlinux.sh  # Arch Linux
MISE_ENV=work ./scripts/bootstrap_macos.sh           # macOS
```

## Neovim project tools

Use `:ProjectTools` or `<leader>ct` to configure tools for the current buffer's
repository. Select an entry with Enter to toggle it; the picker reopens with the
updated state. Escape closes it.

- **LSPs:** lists configurations matching the current filetype, including alternatives
  supplied by nvim-lspconfig. Changes apply immediately to buffers in this repo.
- **Formatters:** toggles the current filetype's ordered pipeline. **Add formatter**
  appends a Conform formatter; restoring a default formatter preserves its position
  relative to the other defaults. To switch formatters, disable the old one and add
  the replacement.
- **Linters:** toggles configured linters for the current filetype, including `typos`.
  A linter toggle applies throughout the repo. Disabling clears its diagnostics;
  subsequent saves and reads respect the selection.
- **Autoformat on save:** independent of manual `require("conform").format()` calls.
- **LSP formatting:** controls Conform's LSP fallback (or preferred LSP formatting
  for Rust), independently of whether the language server itself is enabled.
- **Reset repository to defaults:** removes all personal overrides for this repo.

Selections enable tools; install their executables separately through `:Mason` or
the project's environment. Global defaults remain in `nvim/lua/config/tools.lua`,
`nvim/plugin/conform.lua`, and `nvim/plugin/nvim-lint.lua`.

Only overrides are saved in `stdpath("state")/project-tools.json`, normally
`~/.local/state/nvim/project-tools.json`. Keys are canonical absolute Git worktree
roots, so separate worktrees have separate preferences. Outside Git, the file's
directory is used, or the working directory for an unnamed buffer. Moving a repo
gives it a new key. Preferences load on startup; writes preserve other repositories'
changes from concurrent instances (the latest write wins for the same repo).

Run the integration checks with installed Conform and nvim-lint plugins and Python 3:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
