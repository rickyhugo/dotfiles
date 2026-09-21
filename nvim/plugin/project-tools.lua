vim.api.nvim_create_user_command("ProjectTools", function()
	require("config.project-tools").pick()
end, { desc = "Configure tools for the current repository" })

vim.keymap.set("n", "<leader>ct", "<cmd>ProjectTools<cr>", { desc = "Project tools" })
