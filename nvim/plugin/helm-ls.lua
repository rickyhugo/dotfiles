vim.pack.add({
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
	"https://github.com/qvalentin/helm-ls.nvim",
})

require("helm-ls").setup()
