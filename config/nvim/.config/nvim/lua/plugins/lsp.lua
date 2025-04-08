return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{ "williamboman/mason.nvim", keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Open Mason" } } }, -- Required
		{ "williamboman/mason-lspconfig.nvim" }, -- Required
		{ "WhoIsSethDaniel/mason-tool-installer.nvim" }, -- Required
		{ "onsails/lspkind.nvim" }, -- Required
		{ "glepnir/lspsaga.nvim" }, -- Required

		-- Autocompletion
		{ "hrsh7th/nvim-cmp" }, -- Required
		{ "hrsh7th/cmp-nvim-lsp" }, -- Required
		{ "hrsh7th/cmp-buffer" }, -- Optional
		{ "hrsh7th/cmp-path" }, -- Optional
		{ "saadparwaiz1/cmp_luasnip" }, -- Optional
		{ "hrsh7th/cmp-nvim-lua" }, -- Optional

		-- Snippets
		{ "L3MON4D3/LuaSnip" }, -- Required
		{ "rafamadriz/friendly-snippets" }, -- Optional

		-- typescript
		{ "yioneko/nvim-vtsls" },

		-- misc
		{ "j-hui/fidget.nvim", opts = {} },
	},
	config = function()
		local lspconfig = require("lspconfig")
		local lsp_capabilities = require("cmp_nvim_lsp").default_capabilities()

		vim.api.nvim_create_autocmd("LspAttach", {
			desc = "LSP actions",
			callback = function(_)
				local builtin = require("telescope.builtin")

				vim.opt_local.omnifunc = "v:lua.vim.lsp.omnifunc"
				vim.keymap.set("n", "gd", builtin.lsp_definitions, { buffer = 0, desc = "Go to definition [LSP]" })
				vim.keymap.set("n", "gr", builtin.lsp_references, { buffer = 0, desc = "Show references [LSP]" })
				vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = 0, desc = "Go to declaration [LSP]" })
				vim.keymap.set(
					"n",
					"gi",
					vim.lsp.buf.implementation,
					{ buffer = 0, desc = "Go to implementation [LSP]" }
				)
				vim.keymap.set(
					"n",
					"gt",
					vim.lsp.buf.type_definition,
					{ buffer = 0, desc = "Go to type definition [LSP]" }
				)
				vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = 0, desc = "Hover symbol [LSP]" })

				vim.keymap.set("n", "<leader>rs", vim.lsp.buf.rename, { buffer = 0, desc = "Rename symbol [LSP]" })
				vim.keymap.set(
					"n",
					"<leader>ca",
					vim.lsp.buf.code_action,
					{ buffer = 0, desc = "Show code actions [LSP]" }
				)
				vim.keymap.set(
					"n",
					"<leader>fs",
					builtin.lsp_document_symbols,
					{ buffer = 0, desc = "Show document symbols [LSP]" }
				)

				vim.keymap.set(
					"n",
					"[d",
					vim.diagnostic.goto_prev,
					{ buffer = 0, desc = "Go to previous diagnostic [LSP]" }
				)
				vim.keymap.set(
					"n",
					"]d",
					vim.diagnostic.goto_next,
					{ buffer = 0, desc = "Go to next diagnostic [LSP]" }
				)
			end,
		})

		vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
			border = "rounded",
		})

		vim.diagnostic.config({
			virtual_text = true,
			underline = { severity_limit = vim.diagnostic.severity.ERROR },
			signs = true,
			update_in_insert = true,
			severity_sort = true,
			float = {
				style = "minimal",
				border = "rounded",
			},
		})

		require("mason").setup({
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		})

		require("mason-tool-installer").setup({
			ensure_installed = {
				"actionlint",
				"prettierd",
				"eslint_d",
				"shfmt",
				"shellharden", -- NOTE: requires rust
				"shellcheck",
				"hadolint",
				"markdownlint",
				"jsonlint",
				"yamllint",
				"stylua",
				"luacheck",
				"cspell",
				"codespell",
				"tflint",
				"gofumpt",
				"goimports",
				"golangci-lint",
				"gomodifytags",
				"impl",
				"checkmake",
			},
		})

		-- LSP configs
		-- lua
		local function default_setup(server)
			lspconfig[server].setup({
				capabilities = lsp_capabilities,
			})
		end

		local function lua_ls()
			require("lspconfig").lua_ls.setup({
				settings = {
					Lua = {
						runtime = {
							version = "LuaJIT",
						},
						diagnostics = {
							globals = { "vim" },
						},
						workspace = {
							library = {
								vim.env.VIMRUNTIME,
							},
						},
					},
				},
			})
		end

		-- python
		local python_lsp_root = {
			"pyproject.toml",
			"setup.py",
			"setup.cfg",
			"requirements.txt",
			"Pipfile",
			"pyrightconfig.json",
		}

		local function basedpyright()
			require("lspconfig").basedpyright.setup({
				root_dir = require("lspconfig.util").root_pattern(python_lsp_root),
				settings = {
					basedpyright = {
						disableOrganizeImports = true,
						analysis = {
							autoSearchPaths = true,
							autoImportCompletions = true,
							diagnosticMode = "openFilesOnly",
							logLevel = "Error",
						},
					},
				},
			})
		end

		local function ruff()
			require("lspconfig").ruff.setup({
				root_dir = require("lspconfig.util").root_pattern(python_lsp_root),
				trace = "messages",
				init_options = {
					settings = {
						logLevel = "error",
					},
				},
			})
		end

		-- go
		local function gopls()
			require("lspconfig").gopls.setup({
				settings = {
					gopls = {
						gofumpt = true,
						codelenses = {
							gc_details = false,
							generate = true,
							regenerate_cgo = true,
							run_govulncheck = true,
							test = true,
							tidy = true,
							upgrade_dependency = true,
							vendor = true,
						},
						hints = {
							assignVariableTypes = true,
							compositeLiteralFields = true,
							compositeLiteralTypes = true,
							constantValues = true,
							functionTypeParameters = true,
							parameterNames = true,
							rangeVariableTypes = true,
						},
						analyses = {
							nilness = true,
							unusedparams = true,
							unusedwrite = true,
							useany = true,
						},
						usePlaceholders = true,
						completeUnimported = true,
						staticcheck = true,
						directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
						semanticTokens = true,
					},
				},
			})
		end

		-- typescript
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
			command = "LspRestart eslint",
			desc = "Restart eslint upon changes in 'package.json' [JS/TS]",
		})

		local function vtsls()
			require("lspconfig").vtsls.setup({
				settings = {
					complete_function_calls = true,
					vtsls = {
						enableMoveToFileCodeAction = true,
						autoUseWorkspaceTsdk = true,
						experimental = {
							completion = {
								enableServerSideFuzzyMatch = true,
							},
						},
					},
					typescript = {
						preferences = {
							importModuleSpecifier = "non-relative",
						},
						updateImportsOnFileMove = { enabled = "always" },
						suggest = {
							completeFunctionCalls = true,
						},
						inlayHints = {
							enumMemberValues = { enabled = true },
							functionLikeReturnTypes = { enabled = true },
							parameterNames = { enabled = "literals" },
							parameterTypes = { enabled = true },
							propertyDeclarationTypes = { enabled = true },
							variableTypes = { enabled = false },
						},
					},
				},
			})
		end

		-- terraform
		local function terraformls()
			require("lspconfig").terraformls.setup({})
		end

		require("mason-lspconfig").setup({
			ensure_installed = {
				"eslint",
				"tailwindcss",
				"vtsls",
				"lua_ls",
				"bashls",
				"yamlls",
				"jsonls",
				"dockerls",
				"docker_compose_language_service",
				"taplo",
				-- "marksman",
				"basedpyright",
				"ruff",
				"rust_analyzer",
				"gopls",
				"terraformls",
				"jinja_lsp",
			},
			automatic_installation = true,
			handlers = {
				default_setup,
				lua_ls = lua_ls,
				-- pyright = pyright,
				basedpyright = basedpyright,
				ruff = ruff,
				gopls = gopls,
				vtsls = vtsls,
				terraformls = terraformls,
			},
		})
	end,
}
