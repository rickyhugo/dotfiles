return {
	"danymat/neogen",
	dependencies = "nvim-treesitter/nvim-treesitter",
	version = "*",
	config = function()
		require("neogen").setup({
			enabled = true,
			languages = {
				python = {
					template = {
						annotation_convention = "numpydoc",
					},
				},
			},
			snippet_engine = "luasnip",
		})
	end,
	keys = {
		{
			"<leader>nf",
			function()
				require("neogen").generate({})
			end,
			desc = "Generate docstring in current context",
		},
	},
}
