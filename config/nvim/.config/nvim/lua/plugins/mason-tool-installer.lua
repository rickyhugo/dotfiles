return {
	"WhoIsSethDaniel/mason-tool-installer.nvim",
	dependencies = { "williamboman/mason-lspconfig.nvim" },
	opts = {},
	config = function()
		local utils = require("config.utils")
		local ensure_installed = {}
		vim.list_extend(ensure_installed, utils.tools.lsp)
		vim.list_extend(ensure_installed, utils.tools.lint)
		require("mason-tool-installer").setup({ ensure_installed = ensure_installed })
	end,
}
