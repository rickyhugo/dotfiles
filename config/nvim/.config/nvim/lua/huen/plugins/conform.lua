return {
	"stevearc/conform.nvim",
	lazy = true,
	event = { "BufReadPre", "BufNewFile" }, -- to disable, comment this out
	opts = {
		formatters_by_ft = {
			javascript = { "prettierd" },
			typescript = { "prettierd" },
			javascriptreact = { "prettierd" },
			typescriptreact = { "prettierd" },
			css = { "prettierd" },
			html = { "prettierd" },
			svelte = { "prettierd" },
			graphql = { "prettierd" },
			json = { "prettierd" },
			json5 = { "prettierd" },
			yaml = { "prettierd" },
			markdown = { "prettierd" },
			lua = { "stylua" },
			python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
			sh = { "shfmt", "shellharden" },
			sql = { "sqruff" },
			toml = { "taplo" },
			rust = { "rustfmt" },
			go = { "goimports", "gofumpt", "golines" },
		},
		format_on_save = {
			lsp_fallback = true,
			async = false,
			timeout_ms = 500,
		},
	},
	config = function(_, opts)
		require("conform").setup(opts)
		require("conform").formatters.golines = {
			prepend_args = { "-m", "80" },
		}
	end,
}
