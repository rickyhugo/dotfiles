vim.pack.add({
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/nvim-lualine/lualine.nvim",
})

local icons = require("config.icons")

require("lualine").setup({
	options = {
		theme = "auto",
		globalstatus = vim.o.laststatus == 3,
		disabled_filetypes = {
			statusline = { "NvimTree", "alpha" },
			winbar = { "NvimTree", "alpha" },
		},
		section_separators = { left = "", right = "" },
		component_separators = { left = "", right = "" },
	},
	sections = {
		lualine_a = {
			{
				"mode",
				fmt = function(str)
					return str:sub(1, 1)
				end,
			},
		},
		lualine_b = {
			{
				"diagnostics",
				symbols = {
					error = icons.diagnostic.Error,
					warn = icons.diagnostic.Warn,
					info = icons.diagnostic.Info,
					hint = icons.diagnostic.Hint,
				},
			},
		},
		lualine_c = {},
		lualine_x = { "location", "progress" },
		lualine_y = {
			{
				"diff",
				source = function()
					local gitsigns = vim.b.gitsigns_status_dict
					if gitsigns then
						return {
							added = gitsigns.added,
							modified = gitsigns.changed,
							removed = gitsigns.removed,
						}
					end
				end,
			},
		},
		lualine_z = { "branch" },
	},
	inactive_sections = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = {},
		lualine_x = {},
		lualine_y = {},
		lualine_z = {},
	},

	winbar = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = { { "filename", path = 1 } },
		lualine_x = {},
		lualine_y = {},
		lualine_z = {},
	},
	inactive_winbar = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = { { "filename", path = 1 } },
		lualine_x = {},
		lualine_y = {},
		lualine_z = {},
	},

	extensions = { "nvim-tree" },
})
