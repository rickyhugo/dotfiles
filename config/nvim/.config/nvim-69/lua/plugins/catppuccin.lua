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
			},
		})
		vim.cmd([[colorscheme catppuccin]])
	end,
}
