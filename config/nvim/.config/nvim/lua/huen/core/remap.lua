local keymap = vim.keymap.set

keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selected block of code down" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selected block of code up" })

keymap("n", "J", "mzJ`z", { desc = "Keep cursor in place when 'J'" })
keymap("n", "<C-d>", "<C-d>zz", { desc = "Keep cursor in place when '<C-d>'" })
keymap("n", "<C-u>", "<C-u>zz", { desc = "keep cursor in place when '<C-u>'" })

keymap("n", "n", "nzzzv", { desc = "Keep searched word centered when 'n'" })
keymap("n", "N", "Nzzzv", { desc = "keep searched word centered when 'N'" })

keymap("x", "<leader>p", '"_dP', { desc = "Persist yanked buffer after select + paste" })
keymap("n", "<leader>d", '"_d', { desc = "Persist yanked buffer after select + paste" })
keymap("v", "<leader>d", '"_d', { desc = "Persist yanked buffer after select + paste" })

keymap("n", "<leader>y", '"+y', { desc = "Persist yanked buffer after yank + paste" })
keymap("v", "<leader>y", '"+y', { desc = "Persist yanked buffer after yank + paste" })
keymap("n", "<leader>Y", '"+Y', { desc = "Persist yanked buffer after yank + paste" })

keymap("n", "Q", "<nop>", { desc = "Disable 'Q'" })
keymap("n", "q", "<nop>", { desc = "Disable recording" })

keymap(
	"n",
	"<leader>s",
	[[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
	{ desc = "Substitute all occurrences of the word under cursor" }
)
keymap("v", "<C-s>", [["hy:%s/<C-r>h//g<left><left>]], { desc = "Substitute all occurrences of selected text" })

keymap("n", "<leader>w", ":w<CR>", { desc = "Write buffer" })
keymap("n", "<leader>bd", "<cmd>bd<CR>", { desc = "Delete buffer" })

keymap("n", "<M-h>", "<C-w>h", { desc = "Navigate to left pane" })
keymap("n", "<M-j>", "<C-w>j", { desc = "Navigate to bottom pane" })
keymap("n", "<M-k>", "<C-w>k", { desc = "Navigate to top pane" })
keymap("n", "<M-l>", "<C-w>l", { desc = "Navigate to right pane" })

keymap("n", ",b", "F_", { desc = "Backward snake case navigation" })
keymap("n", ",e", "f_", { desc = "Forward snake case navigation" })

keymap("n", "<C-h>", "10<C-w>>", { desc = "Resize buffer (left)" })
keymap("n", "<C-j>", "10<C-w>+", { desc = "Resize buffer (bottom)" })
keymap("n", "<C-k>", "10<C-w>-", { desc = "Resize buffer (top)" })
keymap("n", "<C-l>", "10<C-w><", { desc = "Resize buffer (right)" })

keymap("n", "<leader>cx", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make shell script executable" })

keymap("n", "<leader>th", function()
	vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = "Toggle inlay hints" })

keymap("v", "<leader>64d", "c<c-r>=system('base64 --decode', @\")<cr><esc>", { desc = "Decode base64" })
keymap("v", "<leader>64e", "c<c-r>=system('base64 --wrap=0', @\")<cr><esc>", { desc = "Encode base64" })

-- keymap("n", "<leader>cl", "<cmd>Lazy<cr>", { desc = "Open lazy.nvim" })

-- TODO: quickfix navigation
-- keymap("n", "<C-k>", "<cmd>cnext<CR>zz")
-- keymap("n", "<C-j>", "<cmd>cprev<CR>zz")
-- keymap("n", "<leader>k", "<cmd>lnext<CR>zz")
-- keymap("n", "<leader>j", "<cmd>lprev<CR>zz")
