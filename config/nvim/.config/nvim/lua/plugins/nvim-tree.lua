return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
		"antosha417/nvim-lsp-file-operations",
		"echasnovski/mini.base16",
	},
	opts = {
		sync_root_with_cwd = true,
		filters = { custom = { "^\\.git$" } },
		renderer = {
			indent_markers = { enable = true },
			icons = {
				padding = " ",
				git_placement = "after",
			},
		},
		view = {
			side = "right",
			signcolumn = "yes",
			width = 40,
			relativenumber = true,
		},
		-- INFO: floating tree
		-- view = {
		-- 	signcolumn = "no",
		-- 	float = {
		-- 		enable = true,
		-- 		open_win_config = function()
		-- 			local screen_w = vim.opt.columns:get()
		-- 			local screen_h = vim.opt.lines:get() - vim.opt.cmdheight:get()
		-- 			local window_w = screen_w * 0.25
		-- 			local window_h = screen_h * 0.8
		-- 			local window_w_int = math.floor(window_w)
		-- 			local window_h_int = math.floor(window_h)
		-- 			local center_x = (screen_w - window_w) / 2
		-- 			local center_y = ((vim.opt.lines:get() - window_h) / 2) - vim.opt.cmdheight:get()
		-- 			return {
		-- 				border = "rounded",
		-- 				relative = "editor",
		-- 				row = center_y,
		-- 				col = center_x,
		-- 				width = window_w_int,
		-- 				height = window_h_int,
		-- 			}
		-- 		end,
		-- 	},
		-- 	width = function()
		-- 		return math.floor(vim.opt.columns:get() * 0.25)
		-- 	end,
		-- },
	},
	keys = {
		{
			"<leader>tt",
			"<cmd>NvimTreeToggle<cr>",
			desc = "Toggle file tree",
		},
	},
}
