local null_ls = require("null-ls")

local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics

-- to setup format on save
local augroup = vim.api.nvim_create_augroup("LspFormatting", {})

null_ls.setup({
	sources = {
		-- formatting
		formatting.yamlfmt,
		formatting.taplo,
		formatting.shellharden,
		formatting.beautysh,
		formatting.fixjson,
		formatting.rustfmt,
		formatting.stylua,
		formatting.prettier,
		formatting.black,
		formatting.isort,
		-- diagnostics
		diagnostics.eslint_d.with({
			-- only enable eslint if root has .eslintrc.cjs
			condition = function(utils)
				return utils.root_has_file(".eslintrc.cjs")
			end,
		}),
		diagnostics.mypy,
        diagnostics.pylint,
        diagnostics.flake8,
		diagnostics.alex,
		diagnostics.checkmake,
		diagnostics.hadolint,
		diagnostics.jsonlint,
		diagnostics.markdownlint,
		diagnostics.pydocstyle,
		diagnostics.shellcheck,
		diagnostics.write_good,
		diagnostics.yamllint,
	},
	-- configure format on save
	on_attach = function(current_client, bufnr)
		if current_client.supports_method("textDocument/formatting") then
			vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
			vim.api.nvim_create_autocmd("BufWritePre", {
				group = augroup,
				buffer = bufnr,
				callback = function()
					vim.lsp.buf.format({
						filter = function(client)
							--  only use null-ls for formatting instead of lsp server
							return client.name == "null-ls"
						end,
						bufnr = bufnr,
					})
				end,
			})
		end
	end,
})
