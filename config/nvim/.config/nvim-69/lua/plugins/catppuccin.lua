return {
	"catppuccin/nvim",
	name = "catppuccin",
	lazy = false,
	config = function()
		require("catppuccin").setup({
			flavour = "mocha",
			highlight_overrides = {
				mocha = function(mocha)
					return {
						LineNr = { fg = mocha.text },
						CursorLineNr = { fg = "#8f95aa" },
					}
				end,
			},
			integrations = {
				which_key = true,
				lsp_saga = true,
				mason = true,
				nvimtree = false,
				harpoon = true,
				blink_cmp = true,
				indent_blankline = {
					enabled = true,
					colored_indent_levels = false,
				},
				lsp_trouble = true,
				dadbod_ui = true,
			},
		})
		vim.cmd([[colorscheme catppuccin]])
	end,
}
