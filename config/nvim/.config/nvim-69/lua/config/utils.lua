return {
	tools = {
		mason_ensure_installed = {
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
			"bacon",

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
	},
	icons = {
		diagnostics = {
			Error = " ",
			Warn = " ",
			Hint = " ",
			Info = " ",
		},
	},
}
