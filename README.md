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

Pstack, Cursor Team Kit, and tstack live in [`agents/pstack/`](agents/pstack),
[`agents/cursor-team-kit/`](agents/cursor-team-kit), and [`agents/tstack/`](agents/tstack).
Each has an `UPSTREAM.md` record for selective manual updates. No plugin packaging
or test suites are kept.

Mise links their skills into `~/.agents/skills/` with `pstack-`, `cursor-`, and
`tstack-` prefixes. Matt Pocock's skills still come from a mise-managed checkout
under `~/.external-skills/`, using `mp-`. Claude Code, Codex, and OpenCode share
the directory. Deployment entries live in `~/.config/mise/config.toml`.

[`agents/`](agents) holds the rest, deployed by `mise dot apply`:

- `AGENTS.md`: global instructions for every harness, linked as `~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`, and `~/.config/opencode/AGENTS.md`.
- `pstack/AGENTS.md` and `pstack/harnesses/`: shared execution rules and external
  harness adapters. Team Kit and tstack reuse it through their own `AGENTS.md`.
- `claude/`, `codex/`, `opencode/`: helper agents such as `poteto-agent`, one
  file per host.
- `skills/`: my own skills

Pstack reads model choices directly from `~/.config/pstack/config.json` and
machine-specific `config.local.json`; see its [configuration guide](agents/pstack/docs/configuration.md).

## Neovim project tools

Each project declares its LSP / formatters / linters in `.nvim-tools.lua` at its root; `~/.nvim-tools.lua` is the global base. Nearest project file wins, global fills the gaps. **Without either file, nothing runs** — silence is a feature.

Tools come from `$PATH` via mise shims, so start Neovim inside the project and pin versions in `mise.local.toml`. Try `:ProjectTools show` to see the merged config, `:ProjectTools edit` to tweak it.

CodeLens annotations are disabled by default. Opt in with `lsp = { "tsgo", codelens = true }` in either tools file; a project's `lsp.codelens` overrides the global value. Changes apply automatically.

For LuaLS completion and hover docs, add `---@type ProjectToolsConfig` immediately before `return { ... }`. LazyDev loads the shared types automatically; newly generated configs already include the annotation. LuaLS must be enabled for the buffer.

Verify with:

```sh
nvim --clean --headless -l nvim/tests/project-tools.lua
```
