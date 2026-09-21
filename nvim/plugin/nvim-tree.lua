vim.pack.add({
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/nvim-tree/nvim-tree.lua",
})

require("nvim-tree").setup({
	sync_root_with_cwd = true,
	filters = { custom = { "^\\.git$" } },
	renderer = {
		indent_markers = { enable = true },
		icons = {
			padding = "  ",
			git_placement = "after",
		},
	},
	view = {
		side = "right",
		signcolumn = "yes",
		width = 40,
		relativenumber = true,
	},
})
vim.keymap.set("n", "<leader>tt", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file tree" })
