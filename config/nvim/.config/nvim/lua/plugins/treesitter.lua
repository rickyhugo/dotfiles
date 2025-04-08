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
					"jinja",
					"jinja_inline",
					"devicetree",
					"bash",
					"gitignore",
					"git_config",
					"gitcommit",
					"git_rebase",
					"gitattributes",
					"diff",
					"printf",
					"lua",
					"luadoc",
					"luap",
					"markdown",
					"markdown_inline",
					"python",
					"requirements",
					"regex",
					"sql",
					"query",
					"vim",
					"vimdoc",
					"toml",
					"yaml",
					"xml",
					"json",
					"jsonc",
					"json5",
					"html",
					"javascript",
					"jsdoc",
					"typescript",
					"tsx",
					"dockerfile",
					"rust",
					"ron",
					"hcl",
					"terraform",
					"helm",
					"go",
					"gomod",
					"zig",
				},
				sync_install = false,
				auto_install = true,
				highlight = {
					enable = true,
					additional_vim_regex_highlighting = false,
				},
				indent = {
					enable = true,
				},
			})
		end,
	},
}
