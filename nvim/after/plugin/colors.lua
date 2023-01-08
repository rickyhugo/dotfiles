local theme = "mocha"
local palette = require("catppuccin.palettes").get_palette(theme)

vim.cmd.colorscheme("catppuccin-" .. theme)
vim.cmd("silent !kitty @ set-background-opacity 1.0")
vim.cmd("silent !kitty @ set-spacing padding-top=5")
vim.cmd("silent !kitty @ set-colors background=\\" .. palette.base)
