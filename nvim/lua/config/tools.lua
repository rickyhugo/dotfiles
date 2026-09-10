return {
	lsp = {
		-- lua
		"lua_ls",

		-- python
		-- "basedpyright",
		"ty",
		"ruff",

		-- rust
		"rust_analyzer",

		-- go
		"gopls",

		-- web
		-- "biome",
		-- "astro",
		-- "vtsls",
		"eslint",
		"tailwindcss",
		"svelte",

		-- shell,
		"bashls",

		-- docker
		"dockerls",
		"docker_compose_language_service",

		-- zig
		"zls",

		-- misc
		"helm_ls",
		"marksman",
		"jsonls",
		"taplo",
		"yamlls",
		"hyprls",
		"terraform-ls",
	},
	lint = {
		-- web
		"prettierd",
		-- "eslint_d",

		-- shell
		"shfmt",
		"shellharden", -- NOTE: requires rust
		"shellcheck",

		-- docker
		"hadolint",

		-- markdown
		"markdownlint",

		-- json
		"jsonlint",

		-- yaml
		"yamllint",

		-- lua
		"stylua",
		"luacheck",

		-- go
		"gofumpt",
		"goimports",
		"gomodifytags",
		"golangci-lint",
		"golines",
		"impl",

		-- rust
		-- "bacon",

		-- spelling
		"proselint",
		"typos",

		-- terraform
		"tflint",

		-- github actions
		"actionlint",

		-- makefile
		"checkmake",

		--terraform
		"terraform",
	},
}
