vim.pack.add({
	"https://github.com/nvim-lua/plenary.nvim",
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/nvim-telescope/telescope-fzf-native.nvim",
	"https://github.com/nvim-telescope/telescope.nvim",
})

require("telescope").setup({
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
		file_ignore_patterns = { "%.git/" },
		mappings = {
			i = {
				["<esc>"] = "close", -- close explorer with <esc>
			},
		},
	},
	extensions = {
		fzf = {},
	},
})
require("telescope").load_extension("fzf")
vim.keymap.set("n", "<leader>ps", function()
	require("config.telescope-multigrep").live_multigrep()
end, { desc = "Telescope project-wide multigrep" })
vim.keymap.set("n", "<C-p>", function()
	require("telescope.builtin").find_files()
end, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fg", function()
	require("telescope.builtin").live_grep()
end, { desc = "Telescope live grep" })
vim.keymap.set("n", "<C-b>", function()
	require("telescope.builtin").buffers()
end, { desc = "Telescope buffers" })
vim.keymap.set("n", "<leader>fh", function()
	require("telescope.builtin").help_tags()
end, { desc = "Telescope help tags" })
vim.keymap.set("n", "<leader>en", function()
	require("telescope.builtin").find_files({
		cwd = vim.fn.stdpath("config"),
	})
end, { desc = "Open neovim config" })
