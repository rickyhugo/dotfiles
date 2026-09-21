vim.scriptencoding = "utf-8"
vim.opt.encoding = "utf-8"

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.cursorcolumn = true

vim.t_Co = 256
vim.opt.termguicolors = true

vim.opt.clipboard = "unnamedplus"
vim.opt.mouse = "a"

vim.opt.title = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.showcmd = true
vim.opt.cmdheight = 1
vim.opt.laststatus = 2
vim.opt.shell = "zsh"

vim.opt.scrolloff = 10
vim.opt.signcolumn = "yes:1"
vim.opt.isfname:append("@-@")

vim.opt.backupskip = "/tmp/*,/private/tmp/*"
vim.opt.inccommand = "split"
vim.opt.ignorecase = true

vim.opt.expandtab = true
vim.opt.breakindent = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.ai = true -- Auto indent
vim.opt.si = true -- Smart indent
vim.opt.smarttab = true

vim.opt.wrap = false -- Wrap lines

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

vim.opt.backspace = "start,eol,indent"
vim.opt.path:append({ "**" }) -- Finding files - Search down into subfolders

vim.opt.colorcolumn = "81"

vim.opt.updatetime = 50

vim.g.mapleader = " "

vim.g.loaded_perl_provider = 0

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.opt.splitright = true -- Vertical split to the right

vim.opt.fillchars = { eob = " " } -- Remove '~'

-- Remove clutter from cmdline
vim.opt.showmode = false
vim.opt.showcmd = false

vim.opt.winborder = "rounded"

-- Prepend mise shims to PATH
vim.env.PATH = vim.env.HOME .. "/.local/share/mise/shims:" .. vim.env.PATH

-- Resolve Python from PATH on both macOS and Linux, including mise shims.
local python3 = vim.fn.exepath("python3")
if python3 ~= "" then
	vim.g.python3_host_prog = python3
end

vim.api.nvim_create_user_command("VimPackUpdate", function()
	vim.pack.update()
end, {})
vim.api.nvim_create_user_command("VimPackUpdateForce", function()
	vim.pack.update(nil, { force = true })
end, {})
vim.api.nvim_create_user_command("VimPackDel", function(opts)
	vim.pack.del(opts.fargs)
end, { nargs = "*" })

vim.api.nvim_create_user_command("LspInfo", function()
	vim.cmd("checkhealth vim.lsp")
end, {})
