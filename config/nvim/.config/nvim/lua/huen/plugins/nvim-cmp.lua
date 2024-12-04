return {
	"hrsh7th/nvim-cmp",
	event = "InsertEnter",
	dependencies = {
		{
			"L3MON4D3/LuaSnip",
			dependencies = "rafamadriz/friendly-snippets",
			opts = { history = true, updateevents = "TextChanged,TextChangedI" },
			version = "v2.*", -- Replace <CurrentMajor> by the latest released major (first number of latest release)
			build = "make install_jsregexp",
			config = function(_, opts)
				local luasnip = require("luasnip")
				luasnip.config.set_config(opts)
				luasnip.filetype_extend("typescriptreact", { "html" })
				luasnip.filetype_extend("javascriptreact", { "html" })
				require("luasnip.loaders.from_vscode").lazy_load()
			end,
		},
		{
			"saadparwaiz1/cmp_luasnip",
			"hrsh7th/cmp-nvim-lua",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-nvim-lsp-signature-help",
			"hrsh7th/cmp-cmdline",
			"hrsh7th/cmp-emoji",
			"kristijanhusak/vim-dadbod-completion",
		},
		{
			"Exafunction/codeium.nvim",
			cmd = "Codeium",
			build = ":Codeium Auth",
			opts = {},
		},
	},
	config = function()
		local luasnip = require("luasnip")
		local cmp = require("cmp")

		cmp.setup({
			experimental = { ghost_text = true },

			snippet = {
				expand = function(args)
					luasnip.lsp_expand(args.body) -- For `luasnip` users.
				end,
			},

			mapping = {
				["<CR>"] = cmp.mapping.confirm({ select = true, behavior = cmp.ConfirmBehavior.Replace }),
				["<C-Space>"] = cmp.mapping.complete(), -- Explicitly request completions.
				["<Tab>"] = cmp.mapping(function(fallback)
					if cmp.visible() then
						cmp.select_next_item()
					elseif luasnip.expand_or_locally_jumpable() then
						luasnip.expand_or_jump()
					else
						fallback()
					end
				end, {
					"i",
					"s",
				}),
				["<S-Tab>"] = cmp.mapping(function(fallback)
					if cmp.visible() then
						cmp.select_prev_item()
					elseif luasnip.expand_or_locally_jumpable(-1) then
						luasnip.jump(-1)
					else
						fallback()
					end
				end, {
					"i",
					"s",
				}),
			},

			sources = {
				{ name = "nvim_lsp" },
				{ name = "luasnip" },
				{ name = "buffer" },
				{ name = "nvim_lua" },
				{ name = "path" },
				{ name = "emoji" },
				{ name = "codeium" },
			},

			window = {
				documentation = cmp.config.window.bordered("rounded"),
			},

			formatting = {
				format = require("lspkind").cmp_format({
					mode = "symbol_text",
					max_width = 50,
					ellipsis_char = "...",
					menu = {
						buffer = "[BUF]",
						nvim_lsp = "[LSP]",
						luasnip = "[SNIP]",
						path = "[PATH]",
						emoji = "[EMOJI]",
						codeium = "[COD]",
					},
					symbol_map = { Codeium = "" },
				}),
			},
		})

		-- SQL
		cmp.setup.filetype({ "sql" }, {
			sources = {
				{ name = "vim-dadbod-completion" },
				{ name = "buffer" },
			},
			formatting = {
				format = require("lspkind").cmp_format({
					mode = "symbol",
					max_width = 50,
					ellipsis_char = "...",
					menu = {
						["vim-dadbod-completion"] = "[DB]",
					},
				}),
			},
		})

		-- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
		cmp.setup.cmdline({ "/", "?" }, {
			mapping = cmp.mapping.preset.cmdline(),
			sources = {
				{ name = "buffer" },
			},
		})

		-- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
		cmp.setup.cmdline({ ":" }, {
			mapping = cmp.mapping.preset.cmdline(),
			sources = { { name = "path" }, { name = "cmdline" } },
		})
	end,
}
