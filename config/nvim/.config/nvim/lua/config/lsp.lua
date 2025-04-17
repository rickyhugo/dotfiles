local utils = require("config.utils")

vim.lsp.enable(utils.tools.lsp)

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

vim.api.nvim_create_user_command("LspInfo", "checkhealth vim.lsp", { desc = "Show LSP information" })
vim.api.nvim_create_user_command("LspLog", "view " .. require("vim.lsp.log").get_filename(), { desc = "Show LSP logs" })

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

		-- INFO: vtsls specific settings
		if client ~= nil and client.name == "vtsls" then
			local ts_augroup = vim.api.nvim_create_augroup("TypescriptAutocmds", { clear = true })

			vim.api.nvim_create_autocmd("BufWritePre", {
				group = ts_augroup,
				pattern = { "*.js", "*.jsx", "*.ts", "*.tsx" },
				callback = function()
					return require("vtsls").commands.organize_imports(vim.api.nvim_get_current_buf())
				end,
				desc = "Organize imports [JS/TS]",
			})

			vim.api.nvim_create_autocmd("BufWritePre", {
				group = ts_augroup,
				pattern = { "*.js", "*.jsx", "*.ts", "*.tsx" },
				callback = function()
					return require("vtsls").commands.fix_all(vim.api.nvim_get_current_buf())
				end,
				desc = "Autofix problems [JS/TS]",
			})

			vim.api.nvim_create_autocmd("BufWritePost", {
				group = ts_augroup,
				pattern = { "package.json" },
				command = ":e",
				desc = "Restart LSPs upon changes in 'package.json' [JS/TS]",
			})
		end

		-- INFO: eslint specific settings
		if client ~= nil and client.name == "eslint" then
			local buf_path = vim.api.nvim_buf_get_name(0)
			local start_dir = vim.fs.dirname(buf_path)

			local marker_lookup = {}
			for _, marker in ipairs(client.config.root_markers) do
				marker_lookup[marker] = true
			end

			local root_file = vim.fs.find(function(name, _)
				return marker_lookup[name]
			end, { upward = true, path = start_dir })[1]

			local root_dir = root_file and vim.fs.dirname(root_file) or start_dir

			client.config.settings.workspaceFolder = {
				uri = root_dir,
				name = vim.fn.fnamemodify(root_dir, ":t"),
			}
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
