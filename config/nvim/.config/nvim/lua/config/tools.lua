return {
	lsp = {
		-- lua
		"lua_ls",

		-- python
		"basedpyright",
		"ruff",

		-- rust
		"rust_analyzer",
		-- "bacon-ls",

		-- go
		"gopls",

		-- web
		-- "biome",
		-- "astro",
		"eslint",
		"tailwindcss",
		"svelte",
		"vtsls",

		-- shell,
		"bashls",

		-- docker
		"dockerls",
		"docker_compose_language_service",

		-- misc
		"marksman",
		"jsonls",
		"taplo",
		"yamlls",
	},
	lint = {
		-- web
		"prettierd",
		"eslint_d",

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
		"cspell",
		"codespell",

		-- terraform
		"tflint",

		-- github actions
		"actionlint",

		-- makefile
		"checkmake",
	},
}
