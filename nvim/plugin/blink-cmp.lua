vim.pack.add({
	{ src = "https://github.com/L3MON4D3/LuaSnip", version = vim.version.range("2.*") },
	"https://github.com/rafamadriz/friendly-snippets",
	"https://github.com/moyiz/blink-emoji.nvim",
	"https://github.com/saghen/blink.compat",
	"https://github.com/tpope/vim-dadbod",
	"https://github.com/kristijanhusak/vim-dadbod-completion",
	{ src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1.*") },
})

require("blink.cmp").setup({
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
})
