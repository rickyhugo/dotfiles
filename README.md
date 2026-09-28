# dotfiles

## Setup

Run the bootstrap for your OS (installs OS deps, then `setup_mise.sh`).
Set `MISE_ENV` on the same command so it flows through to `mise bootstrap`:

```sh
MISE_ENV=personal ./scripts/bootstrap_archlinux.sh  # Arch Linux
MISE_ENV=work ./scripts/bootstrap_macos.sh          # macOS
```

## Neovim project tools

Each project declares its editor tools in a `.nvim-tools.lua` file at its root
(ignored through `~/.global.gitignore`). The nearest such file above a buffer
decides which tools it gets. **Without that file, nothing runs:** no LSP,
formatter or linter.

```lua
return {
	-- Packages that provide executables; mise tools use mise's own names.
	tools = {
		["lua-language-server"] = { provider = "mise", version = "3.19.1" },
		["npm:bash-language-server"] = { provider = "mise", version = "5.8.0" },
		stylua = { provider = "mise", version = "2.5.2" },
		ruff = { provider = "venv" },
		basedpyright = { provider = "venv", bin = { "basedpyright-langserver" } },
		rustfmt = { provider = "system" },
	},
	lsp = { "lua_ls", "basedpyright" }, -- vim.lsp.config names
	format = { -- conform formatters_by_ft syntax, run in order
		lua = { "stylua" },
		python = { "ruff_organize_imports", "ruff_format" },
		rust = { lsp_format = "prefer" },
	},
	lint = { -- nvim-lint names; "*" applies to every filetype
		python = { "ruff" },
		["*"] = { "typos" },
	},
	format_on_save = true, -- default
	lsp_format = "fallback", -- default: never | fallback | prefer | first | last
}
```

Providers:

| provider | executables from                          | version                         |
| -------- | ----------------------------------------- | ------------------------------- |
| `mise`   | `mise bin-paths <tool>@<version>`         | required (`"latest"` allowed)   |
| `venv`   | `<root>/.venv/bin`                        | from the project's lockfile     |
| `node`   | `<root>/node_modules/.bin`                | from the project's lockfile     |
| `system` | `$PATH`                                   | whatever is installed           |

mise is the default choice: it keeps every version side by side, so pins never
clash between projects. Tools outside its registry use a backend, e.g.
`npm:yaml-language-server`, `pipx:basedpyright`, `go:golang.org/x/tools/gopls`
or `github:owner/repo`. mise tools are looked up by exact version and never
activated in your shell. `system` is the fallback for things mise does not
manage: toolchain tools (`rustfmt`, `clippy`, `zig fmt`), LuaRocks packages
such as `luacheck`, or anything else on `$PATH`.

`bin` limits which executables a tool provides; `venv`, `node` and `system`
default to the tool's name. Every LSP, formatter and linter command is rewritten
to the path of a declared tool, so something that is only on `$PATH` is never
used. An undeclared executable, or a mise version that is not installed, is
skipped with a one-time warning.

The file runs with an empty environment (declarations only) and goes through
Neovim's trust prompt (`:trust`). Saving it from Neovim trusts it and reloads
the project: servers restart and diagnostics refresh.

Commands:

- `:ProjectTools` / `<leader>ct`: health for loaded projects (`:checkhealth project-tools`).
- `:ProjectTools edit` / `<leader>cT`: open the file, creating it from a template.
- `:ProjectTools install`: install missing mise tools at their declared versions.
- `:ProjectTools reload`: re-read files, e.g. after installing tools outside Neovim.

Run the integration checks with installed Conform and nvim-lint plugins and Python 3:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
