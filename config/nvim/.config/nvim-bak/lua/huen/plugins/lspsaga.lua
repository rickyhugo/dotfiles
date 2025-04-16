return {
	"glepnir/lspsaga.nvim",
	event = "LspAttach",
	opts = {
		lightbulb = { enable = false },
		ui = { border = "rounded" },
		symbol_in_winbar = { enable = false },
	},
	dependencies = {
		{ "nvim-tree/nvim-web-devicons" },
		--Please make sure you install markdown and markdown_inline parser
		{ "nvim-treesitter/nvim-treesitter" },
	},
}
