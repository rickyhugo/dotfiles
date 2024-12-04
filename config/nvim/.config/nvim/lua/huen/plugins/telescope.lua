return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{
			"nvim-telescope/telescope-fzf-native.nvim",
			build = "make",
			config = function()
				require("telescope").load_extension("fzf")
			end,
		},
	},
	keys = {
		{
			"<C-p>",
			function()
				require("telescope.builtin").find_files()
			end,
			desc = "Open file explorer",
		},
		{
			"<C-b>",
			function()
				require("telescope.builtin").buffers()
			end,
			desc = "Open buffer explorer",
		},
		{
			"<leader>ps",
			function()
				require("telescope.builtin").grep_string({ search = vim.fn.input("rg > ") })
			end,
			desc = "Project-wide search",
		},
	},
	opts = {
		pickers = {
			find_files = {
				hidden = true, -- show hidden files
				theme = "dropdown", -- builtin theme
			},
			buffers = {
				theme = "dropdown", -- builtin theme
			},
		},
		defaults = {
			file_ignore_patterns = { ".git/" },
			mappings = {
				i = {
					["<esc>"] = "close", -- close explorer with <esc>
				},
			},
		},
	},
}
