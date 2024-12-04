return {
	"ThePrimeagen/refactoring.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-treesitter/nvim-treesitter",
	},
	cmd = "Refactor",
	config = function()
		require("refactoring").setup({})
	end,
	keys = {
		{
			"<leader>re",
			"<cmd>Refactor extract <cr>",
			mode = "x",
			desc = "Extract (Refactor)",
		},
		{
			"<leader>rf",
			"<cmd>Refactor extract_to_file <cr>",
			mode = "x",
			desc = "Extract to file (Refactor)",
		},
		{
			"<leader>rv",
			"<cmd>Refactor extract_var <cr>",
			mode = "x",
			desc = "Extract variable (Refactor)",
		},
		{
			"<leader>ri",
			"<cmd>Refactor inline_var<cr>",
			mode = { "n", "x" },
			desc = "Inline variable (Refactor)",
		},
		{
			"<leader>rI",
			"<cmd>Refactor inline_func<cr>",
			mode = "n",
			desc = "Inline function (Refactor)",
		},
		{
			"<leader>rb",
			"<cmd>Refactor extract_block<cr>",
			mode = "n",
			desc = "Extract block (Refactor)",
		},
		{
			"<leader>rbf",
			"<cmd>Refactor extract_block_to_file<cr>",
			mode = "n",
			desc = "Extract block to file (Refactor)",
		},
	},
}
