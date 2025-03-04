return {
	"mfussenegger/nvim-lint",
	lazy = false,
	opts = {
		events = { "BufWritePost", "BufReadPost", "InsertLeave" },
	},
	config = function(_, opts)
		local lint = require("lint")
	end,
}
