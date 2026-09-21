vim.pack.add({
	"https://github.com/williamboman/mason.nvim",
	"https://github.com/neovim/nvim-lspconfig",
	"https://github.com/williamboman/mason-lspconfig.nvim",
	"https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim",
})

require("mason").setup()
vim.keymap.set("n", "<leader>cm", "<cmd>Mason<cr>", { desc = "Mason" })

local tools = require("config.tools")
local ensure_installed = {}
vim.list_extend(ensure_installed, tools.lsp)
vim.list_extend(ensure_installed, tools.lint)
require("mason-tool-installer").setup({ ensure_installed = ensure_installed })
