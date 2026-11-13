vim.pack.add({
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/nvim-tree/nvim-tree.lua",
	"https://github.com/nvim-lua/plenary.nvim",
	"https://github.com/antosha417/nvim-lsp-file-operations",
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
-- The integration subscribes only after nvim-tree has been loaded.
require("lsp-file-operations").setup()
vim.lsp.config("*", { capabilities = require("lsp-file-operations").default_capabilities() })
vim.keymap.set("n", "<leader>tt", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file tree" })
