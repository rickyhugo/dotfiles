vim.pack.add({ "https://github.com/stevearc/conform.nvim" })

require("conform").setup({
	formatters_by_ft = {
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
		rust = { lsp_fallback = "prefer" },
		go = { "goimports", "gofumpt", "golines" },
		zig = { "zigfmt" },
		terraform = { "terraform_fmt" },
	},
	format_on_save = {
		lsp_fallback = true,
		async = false,
		timeout_ms = 500,
	},
})
