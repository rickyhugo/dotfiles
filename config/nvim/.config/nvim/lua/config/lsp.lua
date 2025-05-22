require("config.lsp-config")

vim.lsp.enable(require("config.tools").lsp)

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("huen.lsp", {}),
	desc = "LSP actions",
	callback = function(args)
		local client = assert(vim.lsp.get_client_by_id(args.data.client_id), "must have valid client")

		local builtin = require("telescope.builtin")

		vim.opt_local.omnifunc = "v:lua.vim.lsp.omnifunc"
		vim.keymap.set("n", "gd", builtin.lsp_definitions, { buffer = true, desc = "Go to definition [LSP]" })
		vim.keymap.set("n", "gr", builtin.lsp_references, { buffer = true, desc = "Show references [LSP]" })
		vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = true, desc = "Go to declaration [LSP]" })
		vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { buffer = true, desc = "Go to implementation [LSP]" })
		vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, { buffer = true, desc = "Go to type definition [LSP]" })

		vim.keymap.set("n", "K", function()
			vim.lsp.buf.hover({ border = "rounded" })
		end, { buffer = true, desc = "Hover symbol [LSP]" })

		vim.keymap.set("n", "<leader>rs", vim.lsp.buf.rename, { buffer = true, desc = "Rename symbol [LSP]" })
		vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = true, desc = "Show code actions [LSP]" })
		vim.keymap.set(
			"n",
			"<leader>fs",
			builtin.lsp_document_symbols,
			{ buffer = true, desc = "Show document symbols [LSP]" }
		)

		vim.keymap.set("n", "[d", function()
			vim.diagnostic.jump({ count = -1, float = true })
		end, { buffer = true, desc = "Go to previous diagnostic [LSP]" })
		vim.keymap.set("n", "]d", function()
			vim.diagnostic.jump({ count = 1, float = true })
		end, { buffer = true, desc = "Go to next diagnostic [LSP]" })

		-- INFO: setup custom LSP commands
		if client ~= nil then
			local lsp_cmd = require("config.lsp-cmd")

			if lsp_cmd[client.name] then
				lsp_cmd[client.name]()
			end
		end

		-- HACK: workaround for gopls not supporting semanticTokensProvider
		-- https://github.com/golang/go/issues/54531#issuecomment-1464982242
		if client ~= nil and client.name == "gopls" and not client.server_capabilities.semanticTokensProvider then
			local semantic = client.config.capabilities.textDocument.semanticTokens
			client.server_capabilities.semanticTokensProvider = {
				full = true,
				legend = {
					---@diagnostic disable-next-line: need-check-nil
					tokenModifiers = semantic.tokenModifiers,
					---@diagnostic disable-next-line: need-check-nil
					tokenTypes = semantic.tokenTypes,
				},
				range = true,
			}
		end
	end,
})
