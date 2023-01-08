-- If you want icons for diagnostic errors, you'll need to define them somewhere:
vim.fn.sign_define("DiagnosticSignError", { text = " ", texthl = "DiagnosticSignError" })
vim.fn.sign_define("DiagnosticSignWarn", { text = " ", texthl = "DiagnosticSignWarn" })
vim.fn.sign_define("DiagnosticSignInfo", { text = " ", texthl = "DiagnosticSignInfo" })
vim.fn.sign_define("DiagnosticSignHint", { text = "", texthl = "DiagnosticSignHint" })

-- Unless you are still migrating, remove the deprecated commands from v1.x
vim.cmd([[ let g:neo_tree_remove_legacy_commands = 1 ]])

-- Neo-tree keybindings
vim.keymap.set("n", "<Leader>tt", "<Cmd>Neotree reveal toggle<CR>", { desc = "Toggle file tree" })
vim.keymap.set("n", "<Leader>tc", "<Cmd>Neotree action=close source=filesystem<CR>", { desc = "Close file tree" })
vim.keymap.set("n", "<Leader>tf", "<Cmd>Neotree reveal action=focus<CR>", { desc = "Focus file tree" })

require("neo-tree").setup({
	-- Close Neo-tree if it is the last window left in the tab
	close_if_last_window = true,
	window = {
		width = 30,
	},

	--    event_handlers = {
	--		-- Offset bufferline after open
	--		{
	--			event = "neo_tree_window_after_open",
	--			handler = function()
	--				require("bufferline.api").set_offset(40, "Filetree")
	--			end,
	--		},
	--		-- Reset bufferline before close
	--		{
	--			event = "neo_tree_window_before_close",
	--			handler = function()
	--				require("bufferline.api").set_offset(0)
	--			end,
	--		},
	--	},

	-- Show hidden files
	--	filesystem = {
	--		filtered_items = {
	--			visible = false,
	--			hide_dotfiles = false,
	--			hide_gitignored = false,
	--		},
	--	},
})
