vim.pack.add({ "https://github.com/mfussenegger/nvim-lint" })

local project_tools = require("config.project-tools")
local defaults = {
	zsh = { "zsh" },
	docker = { "hadolint" },
	json = { "jsonlint" },
	markdown = { "markdownlint", "proselint" },
	yaml = { "yamllint" },
	terraform = { "tflint" },
	go = { "golangcilint" },
	make = { "checkmake" },
	rust = { "clippy" },
}
require("lint").linters_by_ft = defaults
project_tools.setup_linters(defaults)
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
	group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
	callback = function(event)
		project_tools.lint(event.buf)
	end,
})
