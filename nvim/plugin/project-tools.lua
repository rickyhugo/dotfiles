vim.api.nvim_create_user_command("ProjectTools", function(command)
	require("config.project-tools").pick(nil, command.bang and "global" or nil)
end, { bang = true, desc = "Configure project tools (! edits global defaults)" })

vim.keymap.set("n", "<leader>ct", "<cmd>ProjectTools<cr>", { desc = "Project tools" })
