vim.pack.add({ "https://github.com/folke/zen-mode.nvim" })

require("zen-mode").setup({
	plugins = {
		twilight = { enabled = false },
	},
})
vim.keymap.set("n", "<leader>z", "<cmd>ZenMode<cr>", { desc = "Toggle Zen Mode" })
