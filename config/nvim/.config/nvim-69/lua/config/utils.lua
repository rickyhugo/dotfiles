return {
	tools = {
		mason_ensure_installed = {
			"actionlint",
			"prettierd",
			"eslint_d",
			"biome",
			"shfmt",
			"shellharden", -- NOTE: requires rust
			"shellcheck",
			"hadolint",
			"markdownlint",
			"jsonlint",
			"yamllint",
			"stylua",
			"luacheck",
			"cspell",
			"codespell",
			"tflint",
			"gofumpt",
			"goimports",
			"gomodifytags",
			"golangci-lint",
			"golines",
			"impl",
			"checkmake",
			"bacon",
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
