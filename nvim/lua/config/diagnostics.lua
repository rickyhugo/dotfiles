local icons = require("config.icons")

vim.diagnostic.config({
	virtual_text = true,
	underline = { severity = vim.diagnostic.severity.ERROR },
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = icons.diagnostic.Error,
			[vim.diagnostic.severity.WARN] = icons.diagnostic.Warn,
			[vim.diagnostic.severity.INFO] = icons.diagnostic.Info,
			[vim.diagnostic.severity.HINT] = icons.diagnostic.Hint,
		},
	},
	update_in_insert = false,
	severity_sort = true,
	float = {
		style = "minimal",
		border = "rounded",
	},
})
