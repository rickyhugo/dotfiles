vim.pack.add({ "https://github.com/stevearc/conform.nvim" })

local project_tools = require("config.project-tools")

require("conform").setup({
	formatters_by_ft = project_tools.setup_formatters({
		javascript = { "biome-check" },
		typescript = { "biome-check" },
		javascriptreact = { "biome-check" },
		typescriptreact = { "biome-check" },
		css = { "prettierd" },
		html = { "prettierd" },
		astro = { "prettierd" },
		svelte = { "prettierd" },
		graphql = { "prettierd" },
		json = { "prettierd" },
		json5 = { "prettierd" },
		yaml = { "prettierd" },
		markdown = { "prettierd" },
		lua = { "stylua" },
		python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
		sh = { "shfmt", "shellharden" },
		toml = { "taplo" },
		rust = {},
		go = { "goimports", "gofumpt", "golines" },
		zig = { "zigfmt" },
		terraform = { "terraform_fmt" },
	}),
	default_format_opts = { lsp_format = "fallback" },
	format_on_save = project_tools.format_on_save,
})
