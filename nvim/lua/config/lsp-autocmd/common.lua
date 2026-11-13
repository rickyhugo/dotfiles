vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("huen.lsp", {}),
	desc = "LSP actions",
	callback = function(event)
		local function map(lhs, rhs, desc)
			vim.keymap.set("n", lhs, rhs, { buffer = event.buf, desc = desc })
		end

		vim.bo[event.buf].omnifunc = "v:lua.vim.lsp.omnifunc"
		map("gd", function()
			require("telescope.builtin").lsp_definitions()
		end, "Go to definition [LSP]")
		map("gr", function()
			require("telescope.builtin").lsp_references()
		end, "Show references [LSP]")
		map("gD", vim.lsp.buf.declaration, "Go to declaration [LSP]")
		map("gi", vim.lsp.buf.implementation, "Go to implementation [LSP]")
		map("gt", vim.lsp.buf.type_definition, "Go to type definition [LSP]")

		map("K", function()
			vim.lsp.buf.hover({ border = "rounded" })
		end, "Hover symbol [LSP]")

		map("<leader>rs", vim.lsp.buf.rename, "Rename symbol [LSP]")
		map("<leader>ca", vim.lsp.buf.code_action, "Show code actions [LSP]")
		map("<leader>fs", function()
			require("telescope.builtin").lsp_document_symbols()
		end, "Show document symbols [LSP]")

		map("[d", function()
			vim.diagnostic.jump({ count = -1, float = true })
		end, "Go to previous diagnostic [LSP]")
		map("]d", function()
			vim.diagnostic.jump({ count = 1, float = true })
		end, "Go to next diagnostic [LSP]")
	end,
})
