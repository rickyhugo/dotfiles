local utils = require("config.utils")

vim.diagnostic.config({
	virtual_text = true,
	underline = { severity_limit = vim.diagnostic.severity.ERROR },
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = utils.icons.diagnostic.Error,
			[vim.diagnostic.severity.WARN] = utils.icons.diagnostic.Warn,
			[vim.diagnostic.severity.INFO] = utils.icons.diagnostic.Info,
			[vim.diagnostic.severity.HINT] = utils.icons.diagnostic.Hint,
		},
	},
	update_in_insert = true,
	severity_sort = true,
	float = {
		style = "minimal",
		border = "rounded",
	},
})
