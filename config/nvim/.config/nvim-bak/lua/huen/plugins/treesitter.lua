return {
	{
		"mfussenegger/nvim-treehopper",
		keys = { { "m", mode = { "o", "x" } } },
		config = function()
			vim.cmd([[
        omap     <silent> m :<C-U>lua require('tsht').nodes()<CR>
        xnoremap <silent> m :lua require('tsht').nodes()<CR>
      ]])
		end,
	},

	{
		"nvim-treesitter/nvim-treesitter-context",
		event = "BufReadPre",
		config = true,
	},

	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.configs").setup({
				ensure_installed = {
					"devicetree",
					"bash",
					"gitignore",
					"lua",
					"markdown",
					"markdown_inline",
					"python",
					"regex",
					"sql",
					"vim",
					"vimdoc",
					"toml",
					"yaml",
					"json",
					"html",
					"javascript",
					"typescript",
					"tsx",
					"requirements",
					"dockerfile",
					"rust",
					"ron",
					"hcl",
					"terraform",
					"helm",
					"go",
					"zig",
					"svelte",
					"css",
					"astro",
				},
				sync_install = false,
				auto_install = true,
				highlight = {
					enable = true,
					additional_vim_regex_highlighting = false,
				},
				indent = {
					enable = true,
					disable = { "python" },
				},
			})
		end,
	},
}
