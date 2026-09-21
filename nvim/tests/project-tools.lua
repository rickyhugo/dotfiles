-- Run with: nvim --clean --headless -l nvim/tests/project-tools.lua
-- Uses installed Conform/nvim-lint, isolated state, and a tiny real LSP server.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
directory = vim.uv.fs_realpath(directory)
local original_stdpath = vim.fn.stdpath
local data = original_stdpath("data")
vim.fn.stdpath = function(kind)
	return kind == "state" and directory .. "/state" or original_stdpath(kind)
end
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.opt.rtp:append(data .. "/site/pack/core/opt/conform.nvim")
vim.opt.rtp:append(data .. "/site/pack/core/opt/nvim-lint")

local function check(value, message)
	assert(value, message)
end

local function wait_for(predicate, message)
	check(vim.wait(3000, predicate, 20), message)
end

local function run()
	local server = directory .. "/server.py"
	vim.fn.writefile(
		vim.split(
			[[
import json, sys
while True:
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line == b'\r\n':
            break
        key, value = line.decode().split(':', 1)
        headers[key.lower()] = value.strip()
    msg = json.loads(sys.stdin.buffer.read(int(headers['content-length'])))
    if msg.get('method') == 'exit':
        break
    if 'id' in msg:
        result = {'capabilities': {'textDocumentSync': 1}} if msg.get('method') == 'initialize' else None
        body = json.dumps({'jsonrpc': '2.0', 'id': msg['id'], 'result': result}).encode()
        sys.stdout.buffer.write(f'Content-Length: {len(body)}\r\n\r\n'.encode() + body)
        sys.stdout.buffer.flush()
]],
			"\n"
		),
		server
	)
	local function buffer(repo)
		vim.fn.mkdir(directory .. "/" .. repo .. "/.git", "p")
		local buf = vim.fn.bufadd(directory .. "/" .. repo .. "/test.lua")
		vim.fn.bufload(buf)
		vim.bo[buf].filetype = "lua"
		return buf
	end
	local a, b = buffer("a"), buffer("b")
	local tools = require("config.project-tools")
	local root_a, root_b = tools.root(a), tools.root(b)
	check(root_a ~= root_b, "repo roots must be distinct")
	vim.fn.writefile({ "gitdir: /some/worktree/metadata" }, directory .. "/worktree.git")
	vim.fn.mkdir(directory .. "/worktree", "p")
	vim.fn.rename(directory .. "/worktree.git", directory .. "/worktree/.git")
	local worktree = vim.fn.bufadd(directory .. "/worktree/file.lua")
	check(tools.root(worktree) == directory .. "/worktree", "Git worktree file detection")

	local captured = {}
	local lint = require("lint")
	local original_try_lint = lint.try_lint
	lint.try_lint = function(names, opts)
		captured[vim.api.nvim_get_current_buf()] = { names = names, opts = opts }
	end
	tools.setup_linters({ lua = { "luacheck" } })
	local conform = require("conform")
	conform.setup({
		formatters_by_ft = tools.setup_formatters({ lua = { "stylua", "trim_whitespace" }, rust = {} }),
		format_on_save = tools.format_on_save,
	})
	vim.lsp.config("project_test", { cmd = { "python3", server }, filetypes = { "lua" }, root_markers = { ".git" } })
	tools.setup_lsp({ "project_test" })
	vim.lsp.enable("project_test")
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 1 and #vim.lsp.get_clients({ bufnr = b }) == 1
	end, "both repos should attach")
	local client_b = vim.lsp.get_clients({ bufnr = b })[1].id
	local ns = lint.get_namespace("luacheck")
	vim.diagnostic.set(ns, a, { { lnum = 0, col = 0, message = "old diagnostic" } })
	tools.lint(a)
	local stale = captured[a].opts.wrap_linter({
		name = "luacheck",
		parser = function()
			return { { lnum = 0, col = 0, message = "stale result" } }
		end,
	})
	stale.parser.on_chunk("lint output")
	tools.update(root_a, function(repo)
		repo.lsp = { project_test = false }
		repo.linters = { luacheck = false, typos = false }
		repo.formatters = { lua = {} }
		repo.autoformat = false
		repo.lsp_format = false
	end)
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 0
	end, "disabled repo must detach")
	check(vim.lsp.get_clients({ bufnr = b })[1].id == client_b, "other repo client must survive")
	check(#captured[a].names == 0, "disabled linters must not run")
	check(#vim.diagnostic.get(a, { namespace = ns }) == 0, "disabled diagnostics must clear")
	check(tools.format_on_save(a) == nil, "autoformat must disable")
	check(tools.format_on_save(b).lsp_format == "fallback", "other repo formatting must survive")
	check(#conform.list_formatters(a) == 0, "empty override must disable the whole chain")
	check(#tools.formatters(b) == 2, "other repo formatter chain must survive")
	check(conform.formatters_by_ft.lua(a).lsp_format == "never", "manual formatting policy must disable LSP")
	local published
	stale.parser.on_done(function(diagnostics)
		published = diagnostics
	end, a, root_a)
	wait_for(function()
		return published ~= nil
	end, "pending parser must finish")
	check(published and #published == 0, "in-flight lint output must not revive diagnostics")

	-- Drive picker actions without opening windows, exercising the user-facing toggles.
	local picker_items, choose
	package.loaded.snacks =
		{ picker = {
			select = function(items, _, callback)
				picker_items, choose = items, callback
			end,
		} }
	local function pick(text)
		tools.pick(a)
		for _, item in ipairs(picker_items) do
			if item.text:find(text, 1, true) then
				choose(item)
				return
			end
		end
		error("Missing picker item: " .. text)
	end
	pick("Autoformat on save")
	check(tools.format_on_save(a) ~= nil, "autoformat toggle must re-enable")
	pick("LSP formatting")
	check(tools.format_policy(a) == "fallback", "LSP formatting toggle must re-enable")
	pick("Linter · luacheck")
	check(vim.tbl_contains(captured[a].names, "luacheck"), "linter toggle must re-enable")
	pick("Formatter · trim_whitespace")
	pick("Formatter · stylua")
	check(vim.deep_equal(tools.formatters(a), { "stylua", "trim_whitespace" }), "restore default pipeline order")
	pick("LSP · project_test")
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 1
	end, "LSP toggle must reattach")
	check(vim.lsp.get_clients({ bufnr = b })[1].id == client_b, "re-enable must preserve other repo")

	local state_file = vim.fn.stdpath("state") .. "/project-tools.json"
	local saved = vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	check(saved[root_a].linters.typos == false, "overrides must persist")
	saved[root_b] = { autoformat = false }
	vim.fn.writefile({ vim.json.encode(saved) }, state_file)
	pick("Reset repository to defaults")
	saved = vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	check(saved[root_a] == nil, "reset removes overrides")
	check(saved[root_b].autoformat == false, "writes must preserve other instance's repo state")
	check(tools.format_on_save(a) ~= nil, "reset restores defaults")
	package.loaded["config.project-tools"] = nil
	check(require("config.project-tools").format_on_save(b) == nil, "fresh module must load persisted state")
	lint.try_lint = original_try_lint
end

local ok, err = xpcall(run, debug.traceback)
for _, client in ipairs(vim.lsp.get_clients()) do
	client:stop(true)
end
vim.wait(1000, function()
	return #vim.lsp.get_clients() == 0
end)
vim.fn.delete(directory, "rf")
if not ok then
	error(err)
end
print("project-tools: all checks passed")
