return {
	"folke/snacks.nvim",
	priority = 1000,
	lazy = false,
	---@type snacks.Config
	opts = {
		bigfile = { enabled = false },
		dashboard = { enabled = false },
		explorer = { enabled = false },
		input = { enabled = false },
		scope = { enabled = false },
		scroll = { enabled = false },
		statuscolumn = { enabled = false },
		words = { enabled = false },
		dim = { enabled = false },
		animate = { enabled = false },
		zen = { enabled = false },

		notifier = {
			enabled = true,
			style = "compact",
			top_down = false,
			margin = { bottom = 1, right = 0 },
			-- INFO: remove redundant information notifications created when multiple LSPs are active
			filter = function(notif)
				return not (notif.level == "info" and notif.msg == "No information available")
			end,
		},

		indent = {
			enabled = true,
			scope = { enabled = true },
			chunk = { enabled = false },
			animate = { enabled = false },
		},

		picker = { enabled = true },
		quickfile = { enabled = true },
	},

	keys = {
		{
			"<leader>N",
			desc = "Neovim News",
			function()
				Snacks.win({
					file = vim.api.nvim_get_runtime_file("doc/news.txt", false)[1],
					width = 0.6,
					height = 0.6,
					wo = {
						spell = false,
						wrap = false,
						signcolumn = "yes",
						statuscolumn = " ",
						conceallevel = 3,
					},
				})
			end,
		},
	},
}
