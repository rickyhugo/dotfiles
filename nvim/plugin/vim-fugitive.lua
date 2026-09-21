vim.pack.add({ "https://github.com/tpope/vim-fugitive" })

vim.keymap.set("n", "<leader>gs", "<cmd>Git status<cr>", { desc = "Git status" })
vim.keymap.set("n", "<leader>ga", "<cmd>Git add .<cr>", { desc = "Git add" })
