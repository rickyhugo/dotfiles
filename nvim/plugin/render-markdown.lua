vim.pack.add({
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/MeanderingProgrammer/render-markdown.nvim",
})

require("render-markdown").setup()
