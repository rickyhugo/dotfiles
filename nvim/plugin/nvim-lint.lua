vim.pack.add({ "https://github.com/mfussenegger/nvim-lint" })

local project_tools = require("project-tools")
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
	group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
	callback = function(event)
		project_tools.lint(event.buf)
	end,
})
