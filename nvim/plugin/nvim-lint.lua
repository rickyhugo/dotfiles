vim.pack.add({ "https://github.com/mfussenegger/nvim-lint" })

require("lint").linters_by_ft = {
	zsh = { "zsh" },
	docker = { "hadolint" },
	json = { "jsonlint" },
	markdown = { "markdownlint", "proselint" },
	yaml = { "yamllint" },
	terraform = { "tflint" },
	go = { "golangcilint" },
	make = { "checkmake" },
	rust = { "clippy" },
}
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
	group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
	callback = function()
		require("lint").try_lint()
		require("lint").try_lint("typos")
	end,
})
