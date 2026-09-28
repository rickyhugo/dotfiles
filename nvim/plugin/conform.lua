vim.pack.add({ "https://github.com/stevearc/conform.nvim" })

local project_tools = require("project-tools")

require("conform").setup({
	-- Everything comes from .nvim-tools.lua; "_" covers every filetype.
	formatters_by_ft = { ["_"] = project_tools.formatters },
	format_on_save = project_tools.format_on_save,
})
