local tools = require("project-tools")

local commands = {
	health = function()
		vim.cmd.checkhealth("project-tools")
	end,
	edit = function()
		tools.edit()
	end,
	install = function()
		tools.install()
	end,
	reload = function()
		tools.reload_all()
	end,
}

vim.api.nvim_create_user_command("ProjectTools", function(command)
	local action = commands[command.args ~= "" and command.args or "health"]
	if not action then
		return vim.notify("ProjectTools: unknown subcommand " .. command.args, vim.log.levels.ERROR)
	end
	action()
end, {
	nargs = "?",
	complete = function()
		return vim.tbl_keys(commands)
	end,
	desc = "Project tools from .nvim-tools.lua (health|edit|install|reload)",
})

vim.keymap.set("n", "<leader>ct", "<cmd>ProjectTools<cr>", { desc = "Project tools health" })
vim.keymap.set("n", "<leader>cT", "<cmd>ProjectTools edit<cr>", { desc = "Edit project tools" })

local group = vim.api.nvim_create_augroup("project-tools", { clear = true })
-- Load before FileType so the project's LSP servers are enabled in time to attach.
vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
	group = group,
	callback = function(event)
		tools.get(event.buf)
	end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
	group = group,
	pattern = "*/" .. tools.file,
	callback = function(event)
		-- Saving it from Neovim is what trusting it means.
		vim.secure.trust({ action = "allow", bufnr = event.buf })
		tools.reload(vim.fs.dirname(vim.uv.fs_realpath(event.match) or event.match))
	end,
})
