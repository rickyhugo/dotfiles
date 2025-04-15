return {
	cmd = { "rust-analyzer" },
	filetypes = { "rust" },
	root_markers = { "Cargo.toml" },

	capabilities = {
		experimental = {
			serverStatusNotification = true,
		},
	},

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
