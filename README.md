# dotfiles

## Setup

Run the bootstrap for your OS (installs OS deps, then `setup_mise.sh`).
Set `MISE_ENV` on the same command so it flows through to `mise bootstrap`:

```sh
MISE_ENV=personal ./scripts/bootstrap_archlinux.sh  # Arch Linux
MISE_ENV=work ./scripts/bootstrap_macos.sh          # macOS
```

## Neovim project tools

A project declares which LSP servers, formatters and linters run in
`.nvim-tools.lua` at its root. **Without that file, nothing runs.** The nearest
`.nvim-tools.lua` above a buffer decides.

```lua
return {
	lsp = { "lua_ls", "bashls" }, -- vim.lsp.config names
	format = { -- conform formatters_by_ft syntax, run in order
		lua = { "stylua" },
		rust = { lsp_format = "prefer" },
	},
	lint = { -- nvim-lint names; "*" applies to every filetype
		sh = { "shellcheck" },
		["*"] = { "typos" },
	},
	format_on_save = true, -- default
	lsp_format = "fallback", -- default: never | fallback | prefer | first | last
}
```

Executables come from `$PATH`; the plugin knows nothing about where they come
from. Pin versions in `mise.local.toml` next to it (a warning is shown when it
is missing):

```toml
[tools]
lua-language-server = "latest"
stylua = "latest"
"npm:bash-language-server" = "latest" # any backend: npm:, pipx:, go:, github:
```

`nvim/lua/config/set.lua` puts mise's shims first on `$PATH`, and a shim picks
the version for the directory it runs in. conform, nvim-lint and Neovim's LSP
client run tools from Neovim's working directory, so start Neovim inside the
project. Files you open from another project get the tools of the project you
started in. Run `mise install` in a new project to install its tools, and
`mise upgrade` to move `"latest"` tools forward: `"latest"` means the newest
installed version, not the newest release.

Missing tools are reported by the tools themselves: conform says the formatter
is unavailable, Neovim's LSP client says the server failed to start, and a
linter that isn't on `$PATH` warns once.

Changing `.nvim-tools.lua` or the project's mise config (`mise.local.toml`,
`mise.toml`, `.mise.toml`, `.tool-versions`) reloads the project: servers
restart, so they pick up new versions, and diagnostics refresh. Deleting
`.nvim-tools.lua` unloads the project.

`.nvim-tools.lua` runs with an empty environment, so it can only name tools,
not run code. It isn't checked against Neovim's `:trust` list, so edits from
anywhere (Neovim, another editor, an agent, `git checkout`) apply right away.

Commands:

- `:ProjectTools` / `<leader>ct`: health for loaded projects (`:checkhealth project-tools`).
- `:ProjectTools edit` / `<leader>cT`: open `.nvim-tools.lua`, creating it from a template.
- `:ProjectTools reload`: re-read every loaded project.

Run the integration checks with installed Conform and nvim-lint plugins and Python 3:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
