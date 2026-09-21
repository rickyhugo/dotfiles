vim.pack.add({
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/folke/trouble.nvim",
})

require("trouble").setup()
vim.keymap.set(
	"n",
	"<leader>xx",
	"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
	{ desc = "Buffer Diagnostics (Trouble)" }
)
