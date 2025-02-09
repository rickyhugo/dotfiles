return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
		"antosha417/nvim-lsp-file-operations",
		"echasnovski/mini.base16",
	},
	opts = {
		view = { side = "right", width = 35, signcolumn = "auto" },
		filters = { custom = { "^\\.git$" } },
		renderer = {
			icons = { padding = " " },
		},
	},
	keys = {
		{
			"<leader>tt",
			"<cmd>NvimTreeToggle<cr>",
			desc = "[T]oggle file [t]ree",
		},
	},
}
