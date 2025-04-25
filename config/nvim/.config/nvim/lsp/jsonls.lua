return {
	cmd = { "vscode-json-language-server", "--stdio" },
	root_markers = { ".git" },
	filetypes = { "json", "jsonc" },
	init_options = {
		provideFormatter = true,
	},
}
