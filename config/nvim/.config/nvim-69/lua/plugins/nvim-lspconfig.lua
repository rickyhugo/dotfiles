return {
	"neovim/nvim-lspconfig",
	dependencies = {
		"saghen/blink.cmp",
		"williamboman/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		{
			"folke/lazydev.nvim",
			opts = {
				library = {
					{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
				},
			},
		},
		{ "j-hui/fidget.nvim", opts = {} },
		"yioneko/nvim-vtsls", -- js/ts lsp
	},
	opts = {
		servers = {
			-- misc
			taplo = {},
			jsonls = {},
			yamlls = {},
			marksman = {},

			-- shell
			bashls = {},

			-- docker
			dockerls = {},
			docker_compose_language_service = {},

			-- lua
			lua_ls = {
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
			},

			-- python
			basedpyright = {
				settings = {
					{
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
				},
			},
			ruff = {
				trace = "messages",
				init_options = {
					settings = {
						logLevel = "error",
					},
				},
			},

			-- rust
			bacon_ls = {
				autostart = true,
				settings = {
					init_options = {
						updateOnSave = true,
						updateOnSaveWaitMillis = 1000,
						updateOnChange = false,
					},
				},
			},
			rust_analyzer = {
				settings = {
					cargo = {
						allFeatures = true,
						loadOutDirsFromCheck = true,
						buildScripts = {
							enable = true,
						},
					},
					checkOnSave = false,
					diagnostics = {
						enable = false,
					},
					procMacro = {
						enable = true,
						ignored = {
							["async-trait"] = { "async_trait" },
							["napi-derive"] = { "napi" },
							["async-recursion"] = { "async_recursion" },
						},
					},
					files = {
						excludeDirs = {
							".direnv",
							".git",
							".github",
							".gitlab",
							"bin",
							"node_modules",
							"target",
							"venv",
							".venv",
						},
					},
				},
			},

			-- go
			gopls = {
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
			},

			-- web
			biome = {},
			eslint = {},
			tailwindcss = {},
			svelte = {},
			astro = {},
			vtsls = {
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
			},
		},
	},
	config = function(_, opts)
		local lspconfig = require("lspconfig")

		local python_servers = { "basedpyright", "ruff" }
		local python_server_root = require("lspconfig.util").root_pattern({
			"pyproject.toml",
			"pyrightconfig.json",
			"setup.py",
			"setup.cfg",
			"requirements.txt",
			"Pipfile",
		})

		local mason_server_name_overrides = { bacon_ls = "bacon-ls" }
		local ensure_installed_servers = {}

		for server, config in pairs(opts.servers) do
			config.capabilities = require("blink.cmp").get_lsp_capabilities(config.capabilities)
			lspconfig[server].setup(config)

			-- set `root_dir` for python servers
			if vim.tbl_contains(python_servers, server) then
				config.root_dir = python_server_root
			end

			-- override server name if it's in the `mason_server_name_overrides` table
			if mason_server_name_overrides[server] then
				server = mason_server_name_overrides[server]
			end

			-- accumulate the servers to ensure installation
			table.insert(ensure_installed_servers, server)
		end

		-- automatically install servers with mason
		local ensure_installed = require("config.utils").tools.mason_ensure_installed
		vim.list_extend(ensure_installed, ensure_installed_servers)
		require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

		vim.api.nvim_create_autocmd("LspAttach", {
			desc = "LSP actions",
			callback = function(args)
				local client = assert(vim.lsp.get_client_by_id(args.data.client_id), "must have valid client")
				local settings = opts.servers[client.name]

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

				-- Override server capabilities
				if settings.server_capabilities then
					for k, v in pairs(settings.server_capabilities) do
						if v == vim.NIL then
							---@diagnostic disable-next-line: cast-local-type
							v = nil
						end

						client.server_capabilities[k] = v
					end
				end

				-- js/ts specific settings
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
						command = "LspRestart eslint",
						desc = "Restart eslint upon changes in 'package.json' [JS/TS]",
					})
				end

				-- HACK: workaround for gopls not supporting semanticTokensProvider
				-- https://github.com/golang/go/issues/54531#issuecomment-1464982242
				if
					client ~= nil
					and client.name == "gopls"
					and not client.server_capabilities.semanticTokensProvider
				then
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
	end,
}
