return {
	"WhoIsSethDaniel/mason-tool-installer.nvim",
	{
		"folke/lazydev.nvim",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},
	{ "j-hui/fidget.nvim", opts = {} },
	"yioneko/nvim-vtsls", -- js/ts lsp
}
