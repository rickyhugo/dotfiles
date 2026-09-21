-- Filetype/integration metadata only. config.tools is the allowlist; an integration
-- is never offered just because its plugin definition or executable exists.
local web_formatters = { "biome-check", "prettierd", "prettier", "eslint_d" }
local web_linters = { "eslint_d", "biomejs" }

local M = {
	formatters = {
		python = { "ruff_fix", "ruff_format", "ruff_organize_imports", "black", "isort", "autopep8", "yapf" },
		lua = { "stylua" },
		javascript = web_formatters,
		typescript = web_formatters,
		javascriptreact = web_formatters,
		typescriptreact = web_formatters,
		json = { "prettierd", "prettier", "biome" },
		json5 = { "prettierd", "prettier", "biome" },
		css = { "prettierd", "prettier", "biome" },
		html = { "prettierd", "prettier" },
		astro = { "prettierd", "prettier" },
		svelte = { "prettierd", "prettier" },
		graphql = { "prettierd", "prettier" },
		markdown = { "prettierd", "prettier", "mdformat" },
		yaml = { "prettierd", "prettier", "yamlfmt" },
		go = { "goimports", "gofumpt", "golines", "gofmt" },
		rust = { "rustfmt" },
		sh = { "shfmt", "shellharden" },
		zsh = { "shfmt" },
		toml = { "taplo" },
		zig = { "zigfmt" },
		terraform = { "terraform_fmt" },
	},
	linters = {
		python = { "ruff", "mypy", "pylint", "flake8" },
		lua = { "luacheck", "selene" },
		javascript = web_linters,
		typescript = web_linters,
		javascriptreact = web_linters,
		typescriptreact = web_linters,
		json = { "jsonlint" },
		markdown = { "markdownlint", "proselint", "vale" },
		yaml = { "yamllint" },
		go = { "golangcilint" },
		rust = { "clippy" },
		sh = { "shellcheck" },
		zsh = { "zsh" },
		dockerfile = { "hadolint" },
		terraform = { "tflint" },
		make = { "checkmake" },
	},
}

local packages = {
	formatters = {
		["biome-check"] = "biome",
		ruff_fix = "ruff",
		ruff_format = "ruff",
		ruff_organize_imports = "ruff",
		terraform_fmt = "terraform",
		zigfmt = "zig",
	},
	linters = { golangcilint = "golangci-lint", biomejs = "biome" },
}

function M.allowed(kind, name)
	local tools = require("config.tools")
	if kind == "lsp" then
		return vim.tbl_contains(tools.lsp, name)
	end
	local package = (packages[kind] or {})[name] or name
	return vim.tbl_contains(tools.lsp, package) or vim.tbl_contains(tools.lint, package)
end

function M.filter(kind, names)
	return vim.tbl_filter(function(name)
		return M.allowed(kind, name)
	end, names)
end

function M.for_ft(kind, ft)
	return M.filter(kind, M[kind][ft] or {})
end

return M
