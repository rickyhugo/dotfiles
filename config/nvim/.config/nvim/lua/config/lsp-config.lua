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
		checkOnSave = true,
		diagnostics = {
			enable = true,
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
