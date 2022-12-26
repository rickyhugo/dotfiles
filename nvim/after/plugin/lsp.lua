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
				pyflakes = { enabled = false },
				pycodestyle = { enabled = false },
				mccabe = { enabled = false },
				yapf = { enabled = false },
				autopep8 = { enabled = false },
				flake8 = { enabled = false },
				pylint = { enabled = false },
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

	vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
	vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, opts)
	vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
	vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
	vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)

	vim.keymap.set("n", "<leader>vws", vim.lsp.buf.workspace_symbol, opts)
	vim.keymap.set("n", "<leader>vd", vim.diagnostic.open_float, opts)
	vim.keymap.set("n", "[d", vim.diagnostic.goto_next, opts)
	vim.keymap.set("n", "]d", vim.diagnostic.goto_prev, opts)
	vim.keymap.set("n", "<leader>vca", vim.lsp.buf.code_action, opts)
	vim.keymap.set("n", "<leader>vrn", vim.lsp.buf.rename, opts)

	vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
	vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
	vim.keymap.set("i", "<C-h>", vim.lsp.buf.signature_help, opts)
end)

lsp.setup()

local mason_null_ls = require("mason-null-ls")

mason_null_ls.setup({
	ensure_installed = {
		"prettier",
		"stylua",
		"eslint_d",
		"black",
		"isort",
		"flake8",
		"pylint",
		"mypy",
		"pydocstyle",
		"rustfmt",
		"shellcheck",
		"beautysh",
		"shellharden",
		"yamllint",
		"yamlfmt",
		"hadolint",
		"jsonlint",
		"fixjson",
		"alex",
		"markdownlint",
		"write_good",
		"taplo",
	},
})

vim.diagnostic.config({
	virtual_text = true,
	underline = { severity_limit = "Error" },
	signs = true,
	update_in_insert = false,
})
