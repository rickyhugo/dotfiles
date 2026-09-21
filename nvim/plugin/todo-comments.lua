vim.pack.add({
	"https://github.com/nvim-lua/plenary.nvim",
	"https://github.com/folke/todo-comments.nvim",
})

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
