return {
	"saghen/blink.cmp",
	dependencies = {
		"rafamadriz/friendly-snippets",
		{
			"saghen/blink.compat",
			optional = true, -- make optional so it's only enabled if any extras need it
			opts = {},
			version = "*",
			enabled = false,
		},
	},
	event = "InsertEnter",
	version = "*",
	opts = {
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},

		-- TODO: fix keymaps
		keymap = {
			preset = "enter",
		},

		cmdline = {
			enabled = true,
			keymap = {
				preset = "cmdline",
			},
			completion = {
				menu = { auto_show = true },
			},
		},
	},
}
