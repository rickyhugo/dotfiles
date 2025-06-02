local LspBuf = {}
LspBuf.action = setmetatable({}, {
	__index = function(_, action)
		return function()
			vim.lsp.buf.code_action({
				apply = true,
				context = {
					only = { action },
					diagnostics = {},
				},
			})
		end
	end,
})

local M = {}

M.vtsls = function()
	local augroup = vim.api.nvim_create_augroup("VtslsAutocmds", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = { "package.json" },
		command = "LspRestart",
		desc = "Restart LSPs upon changes in 'package.json' [VTSLS]",
	})

	vim.keymap.set("n", "<leader>co", function()
		return require("vtsls").commands.organize_imports(vim.api.nvim_get_current_buf())
	end, { buffer = true, desc = "Organize imports [VTSLS]" })

	vim.keymap.set("n", "<leader>cD", function()
		return require("vtsls").commands.fix_all(vim.api.nvim_get_current_buf())
	end, { buffer = true, desc = "Fix all diagnostics [VTSLS]" })
end

M.svelte = function()
	local augroup = vim.api.nvim_create_augroup("SvelteAutocmds", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = augroup,
		pattern = { "package.json" },
		command = "LspRestart",
		desc = "Restart LSPs upon changes in 'package.json' [SVELTE]",
	})

	vim.keymap.set(
		"n",
		"<leader>co",
		LspBuf.action["source.organizeImports"],
		{ buffer = true, desc = "Organize imports [SVELTE]" }
	)

	vim.keymap.set(
		"n",
		"<leader>cD",
		LspBuf.action["source.fixAll.ts"],
		{ buffer = true, desc = "Fix all diagnostics [SVELTE]" }
	)
end

return M
