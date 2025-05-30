return {
	"saghen/blink.cmp",
	dependencies = {
		"rafamadriz/friendly-snippets",
		{
			"saghen/blink.compat",
			optional = true,
			opts = {},
			version = "*",
			enabled = false,
		},
		{ "L3MON4D3/LuaSnip", version = "v2.*" },
		"moyiz/blink-emoji.nvim",
		"fang2hou/blink-copilot",
	},
	version = "1.*",
	opts = {
		snippets = { preset = "luasnip" },

		sources = {
			default = {
				"lsp",
				"path",
				"snippets",
				"buffer",
				"cmdline",
				"omni",
				"emoji",
				"copilot",
			},

			per_filetype = {
				sql = { "snippets", "dadbod", "buffer" },
			},

			providers = {
				dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" },

				emoji = {
					module = "blink-emoji",
					name = "Emoji",
					score_offset = 15, -- Tune by preference
					opts = { insert = true }, -- Insert emoji (default) or complete its name
					should_show_items = function()
						return vim.tbl_contains(
							-- Enable emoji completion only for git commits and markdown.
							-- By default, enabled for all file-types.
							{ "gitcommit", "markdown" },
							vim.o.filetype
						)
					end,
				},

				copilot = {
					name = "copilot",
					module = "blink-copilot",
					score_offset = 100,
					async = true,
				},
			},
		},

		keymap = {
			preset = "default",
		},

		completion = {
			ghost_text = { enabled = true },

			list = { selection = { preselect = false } },

			menu = {
				auto_show = true,

				draw = {
					columns = { { "label", "label_description", gap = 1 }, { "kind_icon", "kind" } },

					components = {
						kind_icon = {
							text = function(ctx)
								return ctx.kind_icon .. ctx.icon_gap .. " "
							end,
						},
					},
				},
			},
		},

		signature = { enabled = true, window = { show_documentation = false } },

		cmdline = {
			enabled = true,

			keymap = {
				preset = "cmdline",
			},

			completion = {
				menu = {
					auto_show = function(_)
						return vim.fn.getcmdtype() == ":" or vim.fn.getcmdtype() == "@"
					end,
				},

				ghost_text = { enabled = true },
			},
		},
	},

	fuzzy = { implementation = "prefer_rust_with_warning" },
}
