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
})
require("telescope").load_extension("fzf")
require("config.telescope-multigrep").setup()
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<C-p>", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<C-b>", builtin.buffers, { desc = "Telescope buffers" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope help tags" })
vim.keymap.set("n", "<leader>en", function()
	builtin.find_files({
		cwd = vim.fn.stdpath("config"),
	})
end, { desc = "Open neovim config" })
