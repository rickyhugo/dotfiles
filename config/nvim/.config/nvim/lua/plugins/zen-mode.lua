return {
	"folke/zen-mode.nvim",
	dependencies = {
		"folke/twilight.nvim",
	},
	opts = {},
	keys = { { "<leader>z", "<cmd>ZenMode<cr>", desc = "Toggle Zen Mode" } },
	plugins = {
		twilight = { enabled = true },
	},
}
