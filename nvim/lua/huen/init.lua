if vim.g.vscode then
    -- VSCode extension
else
    -- Ordinary neovim
    require("huen.set")
    require("huen.remap")
    require("huen.packer")
end
