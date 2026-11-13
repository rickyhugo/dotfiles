vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.colorcolumn = "81"
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or "") .. "\nsetlocal shiftwidth< tabstop< colorcolumn<"
