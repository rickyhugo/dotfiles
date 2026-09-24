require("config.lsp-config")

require("config.project-tools").setup_lsp(require("config.tools").lsp)

require("config.lsp-autocmd.common")
require("config.lsp-autocmd.zig")
