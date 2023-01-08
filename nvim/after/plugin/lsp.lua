local keymap = vim.keymap.set

local lsp = require("lsp-zero")
lsp.preset("recommended")

-- default LSPs
lsp.ensure_installed({
	"tsserver",
	"eslint",
	"sumneko_lua",
	"pylsp",
	"rust_analyzer",
	"tailwindcss",
	"bashls",
	"cssls",
	"yamlls",
	"dockerls",
	"html",
	"jsonls",
})

-- fix undefined global 'vim' in lua
lsp.configure("sumneko_lua", {
	settings = {
		Lua = {
			diagnostics = {
				globals = { "vim" },
			},
		},
	},
})

-- python LSP
lsp.configure("pylsp", {
	settings = {
		pylsp = {
			configurationSources = { "flake8" },
			plugins = {
				-- diagnostics
				pyflakes = { enabled = false },
				pycodestyle = { enabled = false },
				mccabe = { enabled = false },
				pylint = { enabled = false },
				flake8 = { enabled = false },
				-- formatting
				yapf = { enabled = false },
				autopep8 = { enabled = false },
			},
		},
	},
})

-- Customize autocompletion later...
-- local cmp = require('cmp')
-- local cmp_select = { behavior = cmp.SelectBehavior.Select }
-- local cmp_mappings = lsp.defaults.cmp_mappings({
--     ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
--     ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
--     ['<C-y>'] = cmp.mapping.confirm({ select = true }),
--     ["<C-Space>"] = cmp.mapping.complete(),
-- })
--
-- lsp.setup_nvim_cmp({
--     mapping = cmp_mappings
-- })

lsp.on_attach(function(client, bufnr)
	local opts = { buffer = bufnr, remap = false }

	if client.name == "eslint" then
		vim.cmd.LspStop("eslint")
		return
	end

	keymap("n", "gd", vim.lsp.buf.definition, opts)
	keymap("n", "gt", vim.lsp.buf.type_definition, opts)
	keymap("n", "gD", vim.lsp.buf.declaration, opts)
	keymap("n", "gi", vim.lsp.buf.implementation, opts)

	keymap("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
	keymap("n", "<leader>vd", vim.diagnostic.open_float, opts)
	keymap("n", "[d", vim.diagnostic.goto_next, opts)
	keymap("n", "]d", vim.diagnostic.goto_prev, opts)
	keymap("n", "<leader>vca", vim.lsp.buf.code_action, opts)
	keymap("n", "<leader>vrn", vim.lsp.buf.rename, opts)

	keymap("n", "<C-k>", vim.lsp.buf.signature_help, opts)
	keymap("i", "<C-h>", vim.lsp.buf.signature_help, opts)

	-- LSP saga keymaps
	keymap("n", "K", "<cmd>Lspsaga hover_doc<CR>", opts)
	keymap("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", opts)
	keymap("n", "<leader>pd", "<cmd>Lspsaga peek_definition<CR>", opts)
	keymap("n", "gr", "<cmd>Lspsaga lsp_finder<CR>", opts)
end)

lsp.setup()

local mason_null_ls = require("mason-null-ls")

mason_null_ls.setup({
	ensure_installed = {
		-- ts/js
		"prettier",
		"stylua",
		"eslint_d",
		-- python
		-- Note: python linting modules are not handled
		-- by Mason due to import issues
		"black",
		"isort",
		"pydocstyle",
		-- rust
		"rustfmt",
		-- shell
		"shellcheck",
		"beautysh",
		"shellharden",
		-- yaml
		"yamllint",
		"yamlfmt",
		-- docker
		"hadolint",
		-- json
		"jsonlint",
		"fixjson",
		-- markdown
		"alex",
		"markdownlint",
		"write_good",
		-- toml
		"taplo",
	},
})

vim.diagnostic.config({
	virtual_text = true,
	underline = { severity_limit = "Error" },
	signs = true,
	update_in_insert = false,
})
