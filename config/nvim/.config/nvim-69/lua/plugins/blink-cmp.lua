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
		"moyiz/blink-emoji.nvim",
		"fang2hou/blink-copilot",
	},
	event = "InsertEnter",
	version = "*",
	opts = {
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

			per_filetype = { sql = { "dadbod" } },

			providers = {
				dadbod = { module = "vim_dadbod_completion.blink" },

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
			preset = "enter",
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
}
