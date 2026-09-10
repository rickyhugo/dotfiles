vim.lsp.config["ty"] = {
	settings = {
		ty = {
			diagnosticMode = "openFilesOnly",
			showSyntaxErrors = true,
			completions = { autoImport = true },
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
			staticcheck = false,
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

vim.lsp.config["terraform-ls"] = { settings = {} }

vim.lsp.config["yamlls"] = {
	settings = {
		yaml = {
			schemas = {
				kubernetes = "k8s-*.yaml",
				["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
				["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
				["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
				["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
				["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
				["http://json.schemastore.org/circleciconfig"] = ".circleci/**/*.{yml,yaml}",
			},
		},
	},
}

vim.lsp.config["helm-ls"] = {
	settings = {
		["helm-ls"] = {
			yamlls = {
				path = "yaml-language-server",
			},
		},
	},
}
