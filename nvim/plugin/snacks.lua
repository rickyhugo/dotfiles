vim.pack.add({ "https://github.com/folke/snacks.nvim" })

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
