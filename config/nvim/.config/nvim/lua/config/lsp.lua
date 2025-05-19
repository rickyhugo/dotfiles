local utils = require("config.utils")

vim.lsp.config["basedpyright"] = {
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
}

vim.lsp.config["lua_ls"] = {
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
}

vim.lsp.config["gopls"] = {
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
}

vim.lsp.config["rust_analyzer"] = {
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
}

vim.lsp.config["vtsls"] = {
	settings = {
		complete_function_calls = true,
		vtsls = {
			enableMoveToFileCodeAction = true,
			autoUseWorkspaceTsdk = true,
			experimental = {
				maxInlayHintLength = 30,
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
				parameterNames = { enabled = "literals" },
				parameterTypes = { enabled = true },
				variableTypes = { enabled = true },
				propertyDeclarationTypes = { enabled = true },
				functionLikeReturnTypes = { enabled = true },
				enumMemberValues = { enabled = true },
			},
		},
	},
}

vim.lsp.enable(utils.tools.lsp)

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

local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

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

		-- INFO: webdev specific settings
		if client ~= nil and contains({ "vtsls", "svelte", "astro" }, client.name) then
			vim.api.nvim_create_autocmd("BufWritePost", {
				group = vim.api.nvim_create_augroup("WebdevAutocmds", { clear = true }),
				pattern = { "package.json" },
				command = "LspRestart",
				desc = "Restart LSPs upon change in 'package.json' [WEB]",
			})
		end

		-- INFO: vtsls specific settings
		if client ~= nil and client.name == "vtsls" then
			vim.api.nvim_create_autocmd("BufWritePre", {
				group = vim.api.nvim_create_augroup("VtslsAutocmds", { clear = true }),
				pattern = { "*.js", "*.jsx", "*.ts", "*.tsx" },
				callback = function()
					return require("vtsls").commands.organize_imports(vim.api.nvim_get_current_buf())
				end,
				desc = "Organize imports [VTSLS]",
			})

			vim.keymap.set(
				"n",
				"<leader>cD",
				LspBuf.action["source.fixAll.ts"],
				{ buffer = true, desc = "Fix all diagnostics [VTSLS]" }
			)
		end

		-- INFO: svelte specific settings
		if client ~= nil and client.name == "svelte" then
			vim.api.nvim_create_autocmd("BufWritePre", {
				group = vim.api.nvim_create_augroup("SvelteAutocmds", { clear = true }),
				pattern = { "*.svelte" },
				callback = LspBuf.action["source.organizeImports"],
				desc = "Organize imports [SVELTE]",
			})

			vim.keymap.set(
				"n",
				"<leader>cD",
				LspBuf.action["source.fixAll"],
				{ buffer = true, desc = "Fix all diagnostics [SVELTE]" }
			)
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
