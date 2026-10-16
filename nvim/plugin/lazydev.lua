vim.pack.add({ "https://github.com/folke/lazydev.nvim" })

-- Types for Neovim's API and the plugins a Lua file requires, loaded on demand.
require("lazydev").setup({
	library = {
		{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
		{
			path = vim.fn.stdpath("config") .. "/lua/project-tools/types",
			words = { "ProjectToolsConfig" },
			files = { ".nvim-tools.lua" },
		},
	},
})
