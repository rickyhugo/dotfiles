vim.pack.add({
	{ src = "https://github.com/L3MON4D3/LuaSnip", version = vim.version.range("2.*") },
	"https://github.com/danymat/neogen",
})

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
