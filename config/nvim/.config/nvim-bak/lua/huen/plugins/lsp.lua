return {
	"neovim/nvim-lspconfig",
	dependencies = {
		{
			"williamboman/mason.nvim",
			keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
			opts = {},
		}, -- Required
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
		local keymap = vim.keymap.set

		-- rust
		lspconfig.bacon_ls.setup({
			capabilities = lsp_capabilities,
			autostart = true,
			settings = {
				init_options = {
					updateOnSave = true,
					updateOnSaveWaitMillis = 1000,
					updateOnChange = false,
				},
			},
		})

		vim.api.nvim_create_autocmd("LspAttach", {
			desc = "LSP actions",
			callback = function(event)
				local opts = { buffer = event.buf }
				local client = vim.lsp.get_client_by_id(event.data.client_id)

				keymap("n", "gd", vim.lsp.buf.definition, opts)
				keymap("n", "gt", vim.lsp.buf.type_definition, opts)
				keymap("n", "gD", vim.lsp.buf.declaration, opts)
				keymap("n", "gi", vim.lsp.buf.implementation, opts)
				keymap("n", "gw", vim.lsp.buf.document_symbol, opts)
				keymap("n", "gW", vim.lsp.buf.workspace_symbol, opts)
				keymap("n", "[d", function()
					vim.diagnostic.goto_prev({ float = { border = "rounded" } })
				end)
				keymap("n", "]d", function()
					vim.diagnostic.goto_next({ float = { border = "rounded" } })
				end)

				-- NOTE: LSP saga keymaps
				-- keymap("n", "[d", "<cmd>Lspsaga diagnostic_jump_prev<CR>", opts)
				-- keymap("n", "]d", "<cmd>Lspsaga diagnostic_jump_next<CR>", opts)
				keymap("n", "<leader>ld", "<Cmd>Lspsaga show_line_diagnostics<CR>")
				keymap("n", "K", "<cmd>Lspsaga hover_doc<CR>", opts)
				keymap("n", "<leader>pd", "<cmd>Lspsaga peek_definition<CR>", opts)
				keymap("n", "<leader>pt", "<cmd>Lspsaga peek_type_definition<CR>", opts)
				keymap("n", "gr", "<cmd>Lspsaga finder<CR>", opts)
				keymap("n", "<leader>rn", "<Cmd>Lspsaga rename<CR>", opts)

				if client ~= nil and client.server_capabilities.codeActionProvider then
					keymap("n", "<leader>ca", "<cmd>Lspsaga code_action<CR>", opts)
					keymap("v", "<leader>ca", "<cmd>Lspsaga code_action<CR>", opts)
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

				-- workaround for gopls not supporting semanticTokensProvider
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

		vim.diagnostic.config({
			virtual_text = true,
			underline = { severity_limit = vim.diagnostic.severity.ERROR },
			signs = true,
			update_in_insert = true,
			severity_sort = true,
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
				"biome",
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
				"gomodifytags",
				"golangci-lint",
				"golines",
				"impl",
				"checkmake",
				"bacon",
				"bacon-ls",
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

		--- Gets a path to a package in the Mason registry.
		--- Prefer this to `get_package`, since the package might not always be
		--- available yet and trigger errors.
		---@param pkg string
		---@param path? string
		local function get_pkg_path(pkg, path)
			pcall(require, "mason")
			local root = vim.env.MASON or (vim.fn.stdpath("data") .. "/mason")
			path = path or ""
			local ret = root .. "/packages/" .. pkg .. "/" .. path
			return ret
		end

		local function vtsls()
			require("lspconfig").vtsls.setup({
				settings = {
					complete_function_calls = true,
					vtsls = {
						-- tsserver = {
						-- 	globalPlugins = {
						-- 		{
						-- 			name = "@astrojs/ts-plugin",
						-- 			location = get_pkg_path(
						-- 				"astro-language-server",
						-- 				"/node_modules/@astrojs/ts-plugin"
						-- 			),
						-- 			enableForWorkspaceTypeScriptVersions = true,
						-- 		},
						-- 	},
						-- },
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

		-- astro
		local function astro()
			require("lspconfig").astro.setup({})
		end

		-- rust
		local function rust_analyzer()
			require("lspconfig").rust_analyzer.setup({
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
			})
		end

		require("mason-lspconfig").setup({
			ensure_installed = {
				"eslint",
				"tailwindcss",
				"vtsls",
				"lua_ls",
				"bashls",
				"yamlls",
				"dockerls",
				"docker_compose_language_service",
				"taplo",
				"marksman",
				"basedpyright",
				"ruff",
				"rust_analyzer",
				"gopls",
				"svelte",
				"astro",
			},
			automatic_installation = true,
			handlers = {
				default_setup,
				lua_ls = lua_ls,
				basedpyright = basedpyright,
				ruff = ruff,
				gopls = gopls,
				vtsls = vtsls,
				astro = astro,
				rust_analyzer = rust_analyzer,
			},
		})
	end,
}
