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
			-- workspace.library comes from lazydev.nvim (plugin/lazydev.lua).
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

vim.lsp.config["jsonls"] = {
	settings = {
		json = { validate = { enable = true } },
	},
	-- Schemas for package.json, tsconfig.json, renovate.json, ... by file name.
	-- Looked up at start, since SchemaStore.nvim loads after this file.
	before_init = function(_, config)
		config.settings.json.schemas = require("schemastore").json.schemas()
	end,
}

vim.lsp.config["yamlls"] = {
	-- lspconfig's list plus GitHub workflows (see set.lua).
	filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values", "yaml.github" },
	settings = {
		yaml = {
			-- Off, so the built-in catalog download doesn't compete with SchemaStore.nvim.
			-- Project-specific mappings go in a project's .nvim-tools.lua `settings`.
			schemaStore = { enable = false, url = "" },
		},
	},
	-- Same pinned catalog as jsonls, looked up at start (SchemaStore.nvim loads later).
	before_init = function(_, config)
		config.settings.yaml.schemas = require("schemastore").yaml.schemas()
	end,
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

vim.lsp.config["zls"] = {
	-- Set to 'zls' if `zls` is in your PATH
	cmd = { "zls" },
	filetypes = { "zig" },
	root_markers = { "build.zig" },
	-- There are two ways to set config options:
	--   - edit your `zls.json` that applies to any editor that uses ZLS
	--   - set in-editor config options with the `settings` field below.
	--
	-- Further information on how to configure ZLS:
	-- https://zigtools.org/zls/configure/
	settings = {
		zls = {
			-- Whether to enable build-on-save diagnostics
			--
			-- Further information about build-on save:
			-- https://zigtools.org/zls/guides/build-on-save/
			enable_build_on_save = true,
		},
	},
}
