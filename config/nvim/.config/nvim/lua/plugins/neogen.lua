return {
	"danymat/neogen",
	dependencies = "nvim-treesitter/nvim-treesitter",
	version = "*",
	opts = {
		enabled = true,
		languages = {
			python = {
				template = {
					annotation_convention = "numpydoc",
				},
			},
		},
		snippet_engine = "nvim",
	},
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
