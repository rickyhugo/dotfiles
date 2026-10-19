vim.pack.add({ "https://github.com/mfussenegger/nvim-lint" })

-- nvim-lint ships actionlint but not jactionlint, so register it here; project
-- files can then name "jactionlint" like any built-in linter.
-- https://jactionlint.jdx.dev/usage
local severities = {
	error = vim.diagnostic.severity.ERROR,
	warn = vim.diagnostic.severity.WARN,
	info = vim.diagnostic.severity.INFO,
}
require("lint").linters.jactionlint = {
	cmd = "jactionlint",
	stdin = true,
	args = {
		"--format",
		"json",
		"--stdin-filename",
		function()
			return vim.api.nvim_buf_get_name(0)
		end,
		"-",
	},
	ignore_exitcode = true, -- exits 1 when there are findings
	parser = function(output)
		if not output or output == "" then
			return {}
		end
		local decoded = vim.json.decode(output)
		if type(decoded) ~= "table" then
			return {}
		end
		return vim.iter(decoded)
			:map(function(item)
				return {
					lnum = item.line - 1,
					end_lnum = (item.end_line or item.line) - 1,
					col = item.column - 1,
					end_col = item.end_column or item.column,
					severity = severities[item.severity] or vim.diagnostic.severity.WARN,
					source = "jactionlint: " .. (item.kind or item.id or "jactionlint"),
					message = item.message,
				}
			end)
			:totable()
	end,
}

local project_tools = require("project-tools")
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
	group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
	callback = function(event)
		project_tools.lint(event.buf)
	end,
})
