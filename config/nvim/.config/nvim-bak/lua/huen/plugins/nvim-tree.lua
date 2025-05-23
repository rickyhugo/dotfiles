return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
		"antosha417/nvim-lsp-file-operations",
		"echasnovski/mini.base16",
	},
	keys = {
		{
			"<leader>tt",
			"<cmd>NvimTreeToggle<cr>",
			desc = "[T]oggle file [t]ree",
		},
	},
	config = function()
		require("nvim-tree").setup({
			view = {
				side = "right",
				signcolumn = "yes",
				width = 36,
			},
			sync_root_with_cwd = true,
			filters = { custom = { "^\\.git$" } },
			renderer = {
				indent_markers = { enable = true },
				icons = {
					padding = "  ",
					git_placement = "after",
				},
			},
		})
	end,
}
