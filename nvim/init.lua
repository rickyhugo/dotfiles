local icons = require("config.icons")
local tools = require("config.tools")

local gh = function(repo)
	return "https://github.com/" .. repo
end

-- INFO: vim.pack hooks
vim.api.nvim_create_autocmd("PackChanged", {
	callback = function(ev)
		local name, kind = ev.data.spec.name, ev.data.kind
		if name == "nvim-treesitter" and kind == "update" then
			if not ev.data.active then
				vim.cmd.packadd("nvim-treesitter")
			end
			vim.cmd("TSUpdate")
			vim.cmd("TSInstall all")
		end

		if name == "telescope-fzf-native.nvim" and (kind == "install" or kind == "update") then
			vim.system({ "make" }, { cwd = ev.data.path }):wait()
		end
	end,
})

vim.pack.add({
	{ src = gh("catppuccin/nvim"), name = "catppuccin" },
	{ src = gh("nvim-lua/plenary.nvim") },
	{ src = gh("nvim-tree/nvim-web-devicons") },
	{ src = gh("nvim-telescope/telescope-fzf-native.nvim") },
	{ src = gh("neovim/nvim-lspconfig") },
	{ src = gh("nvim-treesitter/nvim-treesitter"), version = vim.version.range("main") },
	{ src = gh("nvim-treesitter/nvim-treesitter-context") },
	{ src = gh("nvim-telescope/telescope.nvim") },
	{ src = gh("tpope/vim-surround") },
	{ src = gh("tpope/vim-fugitive") },
	{ src = gh("folke/zen-mode.nvim") },
	{ src = gh("folke/which-key.nvim") },
	{ src = gh("folke/todo-comments.nvim") },
	{ src = gh("folke/trouble.nvim") },
	{ src = gh("folke/snacks.nvim") },
	{ src = gh("stevearc/oil.nvim") },
	{ src = gh("MeanderingProgrammer/render-markdown.nvim") },
	{ src = gh("m4xshen/hardtime.nvim") },
	{ src = gh("lewis6991/gitsigns.nvim") },
	{ src = gh("nvim-lualine/lualine.nvim") },
	{ src = gh("danymat/neogen") },
	{ src = gh("j-hui/fidget.nvim") },
	{ src = gh("tpope/vim-dadbod") },
	{ src = gh("kristijanhusak/vim-dadbod-completion") },
	{ src = gh("kristijanhusak/vim-dadbod-ui") },
	{ src = gh("Saecki/crates.nvim") },
	{ src = gh("stevearc/conform.nvim") },
	{ src = gh("mfussenegger/nvim-lint") },
	{ src = gh("windwp/nvim-autopairs") },
	{ src = gh("williamboman/mason.nvim") },
	{ src = gh("williamboman/mason-lspconfig.nvim") },
	{ src = gh("WhoIsSethDaniel/mason-tool-installer.nvim") },
	{ src = gh("L3MON4D3/LuaSnip"), version = vim.version.range("2.*") },
	{ src = gh("moyiz/blink-emoji.nvim") },
	{ src = gh("rafamadriz/friendly-snippets") },
	{ src = gh("saghen/blink.compat") },
	{ src = gh("saghen/blink.cmp"), version = vim.version.range("1.*") },
	{ src = gh("antosha417/nvim-lsp-file-operations") },
	{ src = gh("echasnovski/mini.base16") },
	{ src = gh("nvim-tree/nvim-tree.lua") },
	{ src = gh("qvalentin/helm-ls.nvim") },
})

require("config.set")
require("config.remap")
require("config.lsp-autocmd")

-- INFO: colorscheme
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
		nvimtree = false,
		harpoon = true,
		blink_cmp = true,
		indent_blankline = {
			enabled = true,
			colored_indent_levels = false,
		},
		lsp_trouble = true,
		dadbod_ui = true,
		snacks = { enabled = true },
	},
})
vim.cmd.colorscheme("catppuccin")

-- INFO: diagnostics
vim.diagnostic.config({
	virtual_text = true,
	underline = { severity_limit = vim.diagnostic.severity.ERROR },
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = icons.diagnostic.Error,
			[vim.diagnostic.severity.WARN] = icons.diagnostic.Warn,
			[vim.diagnostic.severity.INFO] = icons.diagnostic.Info,
			[vim.diagnostic.severity.HINT] = icons.diagnostic.Hint,
		},
	},
	update_in_insert = true,
	severity_sort = true,
	float = {
		style = "minimal",
		border = "rounded",
	},
})

-- INFO: lualine
require("lualine").setup({
	options = {
		theme = "auto",
		globalstatus = vim.o.laststatus == 3,
		disabled_filetypes = {
			statusline = { "NvimTree", "alpha" },
			winbar = { "NvimTree", "alpha" },
		},
		section_separators = { left = "", right = "" },
		component_separators = { left = "", right = "" },
	},
	sections = {
		lualine_a = {
			{
				"mode",
				fmt = function(str)
					return str:sub(1, 1)
				end,
			},
		},
		lualine_b = {
			{
				"diagnostics",
				symbols = {
					error = icons.diagnostic.Error,
					warn = icons.diagnostic.Warn,
					info = icons.diagnostic.Info,
					hint = icons.diagnostic.Hint,
				},
			},
		},
		lualine_c = {},
		lualine_x = { "location", "progress" },
		lualine_y = {
			{
				"diff",
				source = function()
					local gitsigns = vim.b.gitsigns_status_dict
					if gitsigns then
						return {
							added = gitsigns.added,
							modified = gitsigns.changed,
							removed = gitsigns.removed,
						}
					end
				end,
			},
		},
		lualine_z = { "branch" },
	},
	inactive_sections = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = {},
		lualine_x = {},
		lualine_y = {},
		lualine_z = {},
	},

	winbar = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = { { "filename", path = 1 } },
		lualine_x = {},
		lualine_y = {},
		lualine_z = {},
	},
	inactive_winbar = {
		lualine_a = {},
		lualine_b = {},
		lualine_c = { { "filename", path = 1 } },
		lualine_x = {},
		lualine_y = {},
		lualine_z = {},
	},

	extensions = { "nvim-tree" },
})

-- INFO: fugitive
vim.keymap.set("n", "<leader>gs", "<cmd>Git status<cr>", { desc = "Git status" })
vim.keymap.set("n", "<leader>ga", "<cmd>Git add .<cr>", { desc = "Git add" })

-- INFO: mason
require("mason").setup()
vim.keymap.set("n", "<leader>cm", "<cmd>Mason<cr>", { desc = "Mason" })

local ensure_installed = {}
vim.list_extend(ensure_installed, tools.lsp)
vim.list_extend(ensure_installed, tools.lint)
require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

-- INFO: blink.cmp
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

-- INFO: treesitter
require("nvim-treesitter").setup()
vim.api.nvim_create_autocmd("FileType", {
	callback = function(args)
		local buf, filetype = args.buf, args.match

		local language = vim.treesitter.language.get_lang(filetype)
		if not language then
			return
		end

		-- check if parser exists and load it
		if not vim.treesitter.language.add(language) then
			return
		end

		-- enables syntax highlighting and other treesitter features
		vim.treesitter.start(buf, language)

		-- enables treesitter based indentation
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})

-- INFO: telescope
require("telescope").setup({
	pickers = {
		find_files = {
			hidden = true, -- show hidden files
			theme = "ivy",
		},
		buffers = {
			theme = "ivy",
		},
		grep_string = {
			theme = "dropdown",
		},
	},
	defaults = {
		file_ignore_patterns = { ".git/" },
		mappings = {
			i = {
				["<esc>"] = "close", -- close explorer with <esc>
			},
		},
	},
	extensions = {
		fzf = {},
	},
})
require("telescope").load_extension("fzf")
require("config.telescope-multigrep").setup()
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<C-p>", builtin.find_files, { desc = "Telescope find files" })
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Telescope live grep" })
vim.keymap.set("n", "<C-b>", builtin.buffers, { desc = "Telescope buffers" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Telescope help tags" })
vim.keymap.set("n", "<leader>en", function()
	builtin.find_files({
		cwd = vim.fn.stdpath("config"),
	})
end, { desc = "Open neovim config" })

-- INFO: zen-mode
require("zen-mode").setup({
	plugins = {
		twilight = { enabled = false },
	},
})
vim.keymap.set("n", "<leader>z", "<cmd>ZenMode<cr>", { desc = "Toggle Zen Mode" })

-- INFO: todo-comments
require("todo-comments").setup({
	keywords = {
		FIX = {
			icon = " ", -- icon used for the sign, and in search results
			color = "error", -- can be a hex color, or a named color (see below)
			alt = { "FIXME", "BUG", "FIXIT", "ISSUE" }, -- a set of other keywords that all map to this FIX keywords
			-- signs = false, -- configure signs for some keywords individually
		},
		TODO = { icon = " ", color = "info" },
		HACK = { icon = " ", color = "warning" },
		WARN = { icon = " ", color = "warning", alt = { "WARNING", "XXX" } },
		PERF = { icon = " ", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
		NOTE = { icon = " ", color = "hint", alt = { "INFO" } },
	},
})
vim.keymap.set("n", "[t", function()
	require("todo-comments").jump_prev()
end, { desc = "Go to previous TODO comment" })
vim.keymap.set("n", "]t", function()
	require("todo-comments").jump_next()
end, { desc = "Go to next TODO comment" })

-- INFO: trouble
require("trouble").setup()
vim.keymap.set(
	"n",
	"<leader>xx",
	"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
	{ desc = "Buffer Diagnostics (Trouble)" }
)

-- INFO: snacks
local snacks_opts = {
	bigfile = { enabled = false },
	dashboard = { enabled = false },
	explorer = { enabled = false },
	input = { enabled = false },
	scope = { enabled = true },
	scroll = { enabled = false },
	statuscolumn = { enabled = false },
	words = { enabled = false },
	dim = { enabled = false },
	animate = { enabled = false },
	zen = { enabled = false },
	gh = { enabled = true },
	gitbrowse = { enabled = true },
	image = { enabled = true },

	notifier = {
		enabled = true,
		style = "compact",
		top_down = false,
		margin = { bottom = 1, right = 0 },
	},

	indent = {
		enabled = true,
		scope = { enabled = true },
		chunk = { enabled = false },
		animate = { enabled = false },
	},

	picker = {
		enabled = true,
		sources = {
			gh_issue = {},
			gh_pr = {},
		},
	},
	quickfile = { enabled = true },
}
require("snacks").setup(snacks_opts)
require("config.snacks-remap")

-- INFO: gitsigns
require("gitsigns").setup({
	signs = {
		add = { text = "▎" },
		change = { text = "▎" },
		delete = { text = "" },
		topdelete = { text = "" },
		changedelete = { text = "▎" },
		untracked = { text = "▎" },
	},
	signs_staged = {
		add = { text = "▎" },
		change = { text = "▎" },
		delete = { text = "" },
		topdelete = { text = "" },
		changedelete = { text = "▎" },
	},
	on_attach = function(buffer)
		local gs = package.loaded.gitsigns

		local function map(mode, l, r, desc)
			vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
		end

		map("n", "]h", function()
			if vim.wo.diff then
				vim.cmd.normal({ "]c", bang = true })
			else
				gs.nav_hunk("next")
			end
		end, "Next Hunk")
		map("n", "[h", function()
			if vim.wo.diff then
				vim.cmd.normal({ "[c", bang = true })
			else
				gs.nav_hunk("prev")
			end
		end, "Prev Hunk")
		map("n", "]H", function()
			gs.nav_hunk("last")
		end, "Last Hunk")
		map("n", "[H", function()
			gs.nav_hunk("first")
		end, "First Hunk")
		map({ "n", "v" }, "<leader>ghs", ":Gitsigns stage_hunk<CR>", "Stage Hunk")
		map({ "n", "v" }, "<leader>ghr", ":Gitsigns reset_hunk<CR>", "Reset Hunk")
		map("n", "<leader>ghS", gs.stage_buffer, "Stage Buffer")
		map("n", "<leader>ghu", gs.undo_stage_hunk, "Undo Stage Hunk")
		map("n", "<leader>ghR", gs.reset_buffer, "Reset Buffer")
		map("n", "<leader>ghp", gs.preview_hunk_inline, "Preview Hunk Inline")
		map("n", "<leader>ghb", function()
			gs.blame_line({ full = true })
		end, "Blame Line")
		map("n", "<leader>ghB", function()
			gs.blame()
		end, "Blame Buffer")
		map("n", "<leader>ghd", gs.diffthis, "Diff This")
		map("n", "<leader>ghD", function()
			gs.diffthis("~")
		end, "Diff This ~")
		map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", "GitSigns Select Hunk")
	end,
})

-- INFO: neogen
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
vim.keymap.set("n", "<leader>nf", function()
	require("neogen").generate({})
end, { desc = "Generate docstring in current context" })

-- INFO: conform
require("conform").setup({
	formatters_by_ft = {
		javascript = { "biome-check" },
		typescript = { "biome-check" },
		javascriptreact = { "biome-check" },
		typescriptreact = { "biome-check" },
		css = { "prettierd" },
		html = { "prettierd" },
		astro = { "prettierd" },
		svelte = { "prettierd" },
		graphql = { "prettierd" },
		json = { "prettierd" },
		json5 = { "prettierd" },
		yaml = { "prettierd" },
		markdown = { "prettierd" },
		lua = { "stylua" },
		python = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
		sh = { "shfmt", "shellharden" },
		toml = { "taplo" },
		rust = { lsp_fallback = "prefer" },
		go = { "goimports", "gofumpt", "golines" },
		zig = { "zigfmt" },
		terraform = { "terraform_fmt" },
	},
	format_on_save = {
		lsp_fallback = true,
		async = false,
		timeout_ms = 500,
	},
})

-- INFO: nvim-lint
require("lint").linters_by_ft = {
	zsh = { "zsh" },
	docker = { "hadolint" },
	json = { "jsonlint" },
	markdown = { "markdownlint", "proselint" },
	yaml = { "yamllint" },
	terraform = { "tflint" },
	go = { "golangcilint" },
	make = { "checkmake" },
	rust = { "clippy" },
}
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
	group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
	callback = function()
		require("lint").try_lint()
		require("lint").try_lint("typos")
	end,
})

-- INFO: nvim-tree
require("nvim-tree").setup({
	sync_root_with_cwd = true,
	filters = { custom = { "^\\.git$" } },
	renderer = {
		indent_markers = { enable = true },
		icons = {
			padding = "  ",
			git_placement = "after",
		},
	},
	view = {
		side = "right",
		signcolumn = "yes",
		width = 40,
		relativenumber = true,
	},
})
vim.keymap.set("n", "<leader>tt", "<cmd>NvimTreeToggle<cr>", { desc = "Toggle file tree" })

-- INFO: oil
require("oil").setup()
vim.keymap.set("n", "<leader>ft", "<cmd>Oil<cr>", { desc = "Open file explorer" })

-- INFO: dadbod
vim.g.db_ui_use_nerd_fonts = 1

-- INFO: misc
require("render-markdown").setup()
require("hardtime").setup()
require("nvim-autopairs").setup()
require("helm-ls").setup()
require("fidget").setup({
	notification = { window = { avoid = { "NvimTree" } } },
})
require("crates").setup({
	completion = {
		crates = {
			enabled = true,
		},
	},
	lsp = {
		enabled = true,
		actions = true,
		completion = true,
		hover = true,
	},
})
