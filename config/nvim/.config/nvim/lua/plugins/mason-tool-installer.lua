return {
	"WhoIsSethDaniel/mason-tool-installer.nvim",
	dependencies = { "williamboman/mason-lspconfig.nvim" },
	opts = {},
	config = function()
		local tools = require("config.tools")
		local ensure_installed = {}
		vim.list_extend(ensure_installed, tools.lsp)
		vim.list_extend(ensure_installed, tools.lint)
		require("mason-tool-installer").setup({ ensure_installed = ensure_installed })
	end,
}
