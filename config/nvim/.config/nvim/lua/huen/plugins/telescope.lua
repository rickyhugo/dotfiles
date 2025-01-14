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
			require("telescope.builtin").find_files,
			desc = "Open file explorer",
		},
		{
			"<C-b>",
			require("telescope.builtin").buffers,
			desc = "Open buffer explorer",
		},
		{
			"<leader>ps",
			function()
				require("telescope.builtin").grep_string({ search = vim.fn.input("rg > ") })
			end,
			desc = "Project-wide search",
		},
		{
			"<leader>fh",
			require("telescope.builtin").help_tags,
			desc = "List help tags",
		},
	},
	opts = {
		pickers = {
			find_files = {
				hidden = true, -- show hidden files
				theme = "ivy",
			},
			buffers = {
				theme = "ivy",
			},
			grep_string = {
				theme = "dropdown",
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
		extensions = {
			fzf = {},
		},
	},
}
