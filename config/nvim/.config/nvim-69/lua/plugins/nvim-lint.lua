return {
	"mfussenegger/nvim-lint",
	lazy = true,
	opts = {
		events = { "BufWritePost", "BufReadPost", "InsertLeave" },
	},
	config = function(_, opts)
		local lint = require("lint")
	end,
}
