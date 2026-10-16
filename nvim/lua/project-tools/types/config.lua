---@meta

---@alias ProjectToolsLspFormat "never"|"fallback"|"prefer"|"first"|"last"

---LSP server names, with optional client-side features.
---@class ProjectToolsLsp
---@field [integer] string LSP config names, e.g. "lua_ls" or "tsgo".
---@field codelens? boolean Show CodeLens annotations. Defaults to false.

---Ordered formatter names and optional per-filetype overrides.
---@class ProjectToolsFormatters
---@field [integer] string Conform formatter names.
---@field lsp_format? ProjectToolsLspFormat Override the top-level LSP formatting policy.
---@field stop_after_first? boolean Stop after the first available formatter.

---Declarations in ~/.nvim-tools.lua or a project's .nvim-tools.lua.
---Project values override the global base; LSP names and linters are combined.
---@class ProjectToolsConfig
---@field lsp? ProjectToolsLsp LSP servers and client-side features.
---@field format? table<string, ProjectToolsFormatters> Formatters by filetype; "*" applies to every filetype.
---@field lint? table<string, string[]> Linters by filetype; "*" applies to every filetype.
---@field format_on_save? boolean Format on save. Defaults to true.
---@field lsp_format? ProjectToolsLspFormat LSP formatting policy. Defaults to "fallback".
---@field settings? table<string, table> Server settings keyed by LSP name; deep-merged over the global base.
---@field restart_on? string[] Files whose changes restart tools. Relative to the project root (or home outside projects); ~/ and absolute paths are exact.
