return {
	"nvim-telescope/telescope.nvim",
	tag = "0.1.8",
	dependencies = {
		"nvim-lua/plenary.nvim",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
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
			"<leader>fh",
			function()
				require("telescope.builtin").help_tags()
			end,
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
		require("telescope").load_extension("fzf")
		require("config.telescope-multigrep").setup()
	end,
}
