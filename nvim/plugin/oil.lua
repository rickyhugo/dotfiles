vim.pack.add({
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/stevearc/oil.nvim",
})

require("oil").setup()
vim.keymap.set("n", "<leader>ft", "<cmd>Oil<cr>", { desc = "Open file explorer" })
