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
			"<leader>fh",
			require("telescope.builtin").help_tags,
			desc = "Open help tags explorer",
		},
		{
			"<leader>en",
			function()
				require("telescope.builtin").find_files({
					cwd = vim.fn.stdpath("config"),
				})
			end,
			desc = "Open neovim config",
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
	config = function(_, opts)
		require("telescope").setup(opts)
		require("core.telescope-multigrep").setup()
	end,
}
