return {
	"stevearc/oil.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = {
		columns = { "icon" },
		view_options = {
			show_hidden = true,
		},
		delete_to_trash = true,
		keymaps = {
			["<C-h>"] = false,
			["<C-j>"] = false,
			["<C-k>"] = false,
			["<C-l>"] = false,
			["<M-h>"] = "actions.select_split",
			["<esc>"] = { "actions.close", mode = "n" },
		},
	},
	keys = {
		{
			"-",
			"<CMD>Oil<CR>",
			desc = "Open file explorer",
		},
		{
			"<leader>-",
			function()
				require("oil").toggle_float()
			end,
			desc = "Open file explorer in floating window",
		},
	},
}
