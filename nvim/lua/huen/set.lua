vim.scriptencoding = "utf-8"
vim.opt.encoding = "utf-8"

vim.opt.number = true
vim.opt.relativenumber = true

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
vim.opt.signcolumn = "yes"
vim.opt.isfname:append("@-@")

vim.opt.backupskip = "/tmp/*,/private/tmp/*"
vim.opt.inccommand = "split"
vim.opt.ignorecase = true

vim.opt.expandtab = true
vim.opt.breakindent = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
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

vim.opt.colorcolumn = "79"

vim.opt.updatetime = 50

vim.g.mapleader = " "

vim.g.python3_host_prog = "/home/huen/.pyenv/versions/neovim/bin/python"

vim.g.loaded_perl_provider = 0

-- reset terminal view on close
vim.cmd([[
    augroup kitty_terminal_view
        autocmd!
        au VimLeave * :silent !kitty @ set-spacing padding=15
        au VimLeave * :silent !kitty @ set-background-opacity 0.85
        au VimLeave * :silent !kitty @ set-colors background=black
    augroup END
]])
