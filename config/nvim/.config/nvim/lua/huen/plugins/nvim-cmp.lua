return {
	"hrsh7th/nvim-cmp",
	event = "InsertEnter",
	dependencies = {
		{
			"L3MON4D3/LuaSnip",
			dependencies = "rafamadriz/friendly-snippets",
			opts = { history = true, updateevents = "TextChanged" },
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

		-- ai
		{
			"zbirenbaum/copilot-cmp",
			config = function()
				require("copilot_cmp").setup()
			end,
		},
		-- "Exafunction/codeium.nvim",
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

				-- ai
				-- { name = "codeium" },
				{ name = "copilot" },
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

						-- ai
						-- codeium = "[AI]",
						copilot = "[AI]",
					},
					symbol_map = { Codeium = " ", Copilot = " " },
				}),
			},

			-- ai
			sorting = {
				priority_weight = 2,
				comparators = {
					require("copilot_cmp.comparators").prioritize,

					-- Below is the default comparator list and order for nvim-cmp
					cmp.config.compare.offset,
					cmp.config.compare.exact,
					cmp.config.compare.score,
					cmp.config.compare.recently_used,
					cmp.config.compare.locality,
					cmp.config.compare.kind,
					cmp.config.compare.sort_text,
					cmp.config.compare.length,
					cmp.config.compare.order,
				},
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
