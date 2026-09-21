-- Run with: nvim --clean --headless -l nvim/tests/project-tools.lua
-- Uses installed Conform/nvim-lint/Snacks, isolated state, and a tiny real LSP server.
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
vim.opt.rtp:append(data .. "/site/pack/core/opt/snacks.nvim")
local configured_tools = vim.deepcopy(require("config.tools"))
configured_tools.lsp[#configured_tools.lsp + 1] = "project_test"
configured_tools.lint[#configured_tools.lint + 1] = "trim_whitespace"
package.loaded["config.tools"] = configured_tools

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
	local function pick(text, section)
		tools.pick(a, section, true)
		for _, item in ipairs(picker_items) do
			if item.text:find(text, 1, true) then
				choose(item)
				return
			end
		end
		error("Missing picker item: " .. text)
	end
	tools.pick(a)
	check(#picker_items == 4, "overview must be limited to four categories")
	check(picker_items[1].text:find("Language servers", 1, true), "overview must start with LSP status")
	pick("Autoformat on save", "settings")
	check(tools.format_on_save(a) ~= nil, "autoformat toggle must re-enable")
	pick("LSP formatting", "settings")
	check(tools.format_policy(a) == "fallback", "LSP formatting toggle must re-enable")
	pick("luacheck", "linters")
	check(vim.tbl_contains(captured[a].names, "luacheck"), "linter toggle must re-enable")
	pick("trim_whitespace", "formatters")
	pick("stylua", "formatters")
	check(vim.deep_equal(tools.formatters(a), { "stylua", "trim_whitespace" }), "restore default pipeline order")
	pick("project_test", "lsp")
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 1
	end, "LSP toggle must reattach")
	check(vim.lsp.get_clients({ bufnr = b })[1].id == client_b, "re-enable must preserve other repo")

	local state_file = vim.fn.stdpath("state") .. "/project-tools.json"
	local saved = vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	check(saved[root_a].linters.typos == false, "overrides must persist")
	saved[root_b] = { autoformat = false }
	vim.fn.writefile({ vim.json.encode(saved) }, state_file)
	pick("Reset repository to defaults", "settings")
	saved = vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	check(saved[root_a] == nil, "reset removes overrides")
	check(saved[root_b].autoformat == false, "writes must preserve other instance's repo state")
	check(tools.format_on_save(a) ~= nil, "reset restores defaults")

	-- Python alternatives are filetype-specific, and availability is not selection.
	local python = buffer("python")
	vim.bo[python].filetype = "python"
	conform.formatters.black = { command = "python3" }
	conform.formatters.ruff_fix = { command = "python3" }
	conform.formatters.ruff_format = { command = "project-tools-test-missing-command" }
	conform.formatters.ruff_organize_imports = { command = "project-tools-test-missing-command" }
	vim.fn.mkdir(directory .. "/lsp", "p")
	vim.fn.writefile(
		{ 'return { cmd = { "python3" }, filetypes = { "python" } }' },
		directory .. "/lsp/unlisted_python.lua"
	)
	vim.opt.rtp:append(directory)
	lint.linters.flake8 = { cmd = "python3" }
	lint.linters.ruff = { cmd = "python3" }
	lint.linters.mypy = { cmd = "project-tools-test-missing-command" }
	tools.update(tools.root(python), function(repo)
		repo.formatters = { python = { "ruff_format" } }
	end)
	local function find_tool(kind, name)
		for _, item in ipairs(tools.inspect(python)[kind]) do
			if item.name == name then
				return item
			end
		end
		return nil
	end
	check(find_tool("formatters", "black") == nil, "installed but unlisted formatter must be excluded")
	check(find_tool("formatters", "autopep8") == nil, "unlisted formatter suggestions must be excluded")
	check(find_tool("linters", "flake8") == nil, "installed but unlisted linter must be excluded")
	check(find_tool("linters", "mypy") == nil, "unlisted linter suggestions must be excluded")
	check(find_tool("lsp", "unlisted_python") == nil, "runtime LSP definitions must not bypass tools.lua")
	local ruff_fix = find_tool("formatters", "ruff_fix")
	check(ruff_fix.available and not ruff_fix.enabled, "Ruff integration must be allowed by the Ruff tool entry")
	local ruff = find_tool("formatters", "ruff_format")
	check(
		ruff.enabled and not ruff.available and ruff.status == "unavailable",
		"selected missing formatter must not say ready"
	)
	tools.pick(python, "formatters")
	local text = vim.iter(picker_items)
		:map(function(item)
			return item.text
		end)
		:join("\n")
	check(text:find("ruff_format", 1, true), "selected unavailable tools must remain visible")
	check(text:find("ruff_fix", 1, true), "listed relevant alternatives must be visible")
	check(not text:find("black", 1, true), "unlisted formatter must not appear in picker")
	check(not text:find("Browse all", 1, true), "picker must not offer an unrestricted catalog")
	check(not text:find("stylua", 1, true), "unrelated formatters must be excluded")
	check(text:find("Show unavailable tools", 1, true), "missing alternatives must be collapsed")
	local ruff_lint = find_tool("linters", "ruff")
	check(ruff_lint.available and not ruff_lint.enabled, "listed alternative linter starts disabled")
	ruff_lint.toggle()
	check(vim.tbl_contains(captured[python].names, "ruff"), "enabling an alternative linter must run it")
	local ruff_ns = lint.get_namespace("ruff")
	vim.diagnostic.set(ruff_ns, python, { { lnum = 0, col = 0, message = "old alternative linter diagnostic" } })
	find_tool("linters", "ruff").toggle()
	check(not vim.tbl_contains(captured[python].names, "ruff"), "disabling an alternative must stop reruns")
	check(#vim.diagnostic.get(python, { namespace = ruff_ns }) == 0, "alternative linter diagnostics must clear")
	configured_tools.lint[#configured_tools.lint + 1] = "mypy"
	check(find_tool("linters", "mypy") ~= nil, "adding a tool to tools.lua must make its integration eligible")
	table.remove(configured_tools.lint)
	local lsp = tools.inspect(b).lsp[1]
	check(lsp.running and lsp.status == "running", "attached client must report actual running state")
	-- Exercise the real Snacks layout and highlighted format callback as well.
	package.loaded.snacks = nil
	local snacks = require("snacks")
	snacks.setup({ picker = { enabled = true } })
	tools.pick(python)
	wait_for(function()
		return #snacks.picker.get() == 1
	end, "real overview picker must open")
	local picker = snacks.picker.get()[1]
	wait_for(function()
		return picker:count() == 4
	end, "real overview must render four rows")
	picker:close()
	tools.pick(python, "formatters")
	wait_for(function()
		return #snacks.picker.get() == 1
	end, "real formatter picker must open")
	picker = snacks.picker.get()[1]
	wait_for(function()
		return picker:count() > 2
	end, "real formatter rows must render")
	picker:close()
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
