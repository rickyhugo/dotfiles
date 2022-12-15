require("huen.set")
require("huen.remap")
require("huen.packer")

if vim.g.vscode then
    -- VSCode extension
else
    -- ordinary Neovim
    vim.cmd [[autocmd BufWritePre <buffer> lua vim.lsp.buf.formatting_sync()]]
end
