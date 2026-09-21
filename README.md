# dotfiles

## Setup

Run the bootstrap for your OS (installs OS deps, then `setup_mise.sh`).
Set `MISE_ENV` on the same command so it flows through to `mise bootstrap`:

```sh
MISE_ENV=personal ./scripts/bootstrap_archlinux.sh  # Arch Linux
MISE_ENV=work ./scripts/bootstrap_macos.sh           # macOS
```

## Neovim project tools

Use `:ProjectTools` or `<leader>ct` to inspect tools for the current buffer's
repository and filetype. The overview has four rows: **Language servers**,
**Formatters**, **Linters**, and **Settings**. Enter opens a category; inside it,
Enter toggles a tool and refreshes the list. **Back to overview** returns to the
summary, and Escape closes the picker.

Only tools listed in `nvim/lua/config/tools.lua` are offered. Enabled tools (`●`)
appear first, followed by installed, relevant alternatives from that list (`○`).
Listed tools with missing executables are collapsed under **Show unavailable tools**;
enabled tools with missing executables always remain visible. Status is evaluated
for the current buffer:

- LSP **running** means attached; **enabled · not attached** distinguishes a
  preference from an actual connection (for example, missing root markers).
- Formatter **ready** means Conform can run it; numbered steps show pipeline order.
  Unavailable formatters show Conform's reason, and LSP fallback/preference is
  reflected in the overview. Formatters run on demand, not continuously.
- Linter **running** means a process is currently active; **ready · on read/save**
  means enabled and executable. This category lists standalone nvim-lint tools;
  LSPs such as Ruff can also publish diagnostics.

- **LSPs:** lists entries from `tools.lsp` matching the current filetype.
  Changes apply immediately to buffers in this repo.
- **Formatters:** toggles the current filetype's ordered pipeline using integrations
  backed by a tool in `tools.lua`; restoring a default formatter preserves its position
  relative to the other defaults. To switch formatters, disable the old one and add
  the replacement.
- **Linters:** toggles allowlisted linter integrations for the current
  filetype, including `typos`.
  A linter toggle applies throughout the repo. Disabling clears its diagnostics;
  subsequent saves and reads respect the selection.
- **Settings → Autoformat on save:** independent of manual `require("conform").format()` calls.
- **Settings → LSP formatting:** controls Conform's LSP fallback (or preferred LSP formatting
  for Rust), independently of whether the language server itself is enabled.
- **Settings → Reset repository to defaults:** removes all personal overrides for this repo.

Filetype and integration-name mappings live in
`nvim/lua/config/project-tool-catalog.lua`, filtered through `tools.lua`.
For example, the `ruff` tool permits `ruff_fix`, `ruff_format`,
`ruff_organize_imports`, and the standalone Ruff linter. `golangci-lint` maps to
`golangcilint`, and `terraform` maps to `terraform_fmt`. Being installed on PATH
or provided by a plugin does not make an unlisted tool eligible. Executable
availability is checked separately against Neovim's environment.

Selections enable tools; install their executables separately through `:Mason` or
the project's environment. Global defaults remain in `nvim/lua/config/tools.lua`,
`nvim/plugin/conform.lua`, and `nvim/plugin/nvim-lint.lua`.

Only overrides are saved in `stdpath("state")/project-tools.json`, normally
`~/.local/state/nvim/project-tools.json`. Keys are canonical absolute Git worktree
roots, so separate worktrees have separate preferences. Outside Git, the file's
directory is used, or the working directory for an unnamed buffer. Moving a repo
gives it a new key. Preferences load on startup; writes preserve other repositories'
changes from concurrent instances (the latest write wins for the same repo).

Run the integration checks with installed Conform, nvim-lint, and Snacks plugins and Python 3:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
