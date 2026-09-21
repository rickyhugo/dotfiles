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
require("config.project-tool-catalog").lsp_roles.project_test = { diagnostics = true }

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
        result = {'capabilities': {'textDocumentSync': 1, 'documentFormattingProvider': True}} if msg.get('method') == 'initialize' else None
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
	local function pick(text, scope)
		tools.pick(a, scope, true)
		for _, item in ipairs(picker_items) do
			if item.text:find(text, 1, true) then
				choose(item)
				return
			end
		end
		error("Missing picker item: " .. text)
	end
	tools.pick(a)
	check(#picker_items > 6, "dashboard must show settings and tools together")
	check(picker_items[1].text:find("Coverage", 1, true), "dashboard must start with the coverage verdict")
	pick("Autoformat on save")
	check(tools.format_on_save(a) ~= nil, "autoformat toggle must re-enable")
	pick("LSP formatting")
	check(tools.format_policy(a) == "fallback", "LSP formatting toggle must re-enable")
	pick("luacheck")
	check(vim.tbl_contains(captured[a].names, "luacheck"), "linter toggle must re-enable")
	pick("trim_whitespace")
	pick("stylua")
	check(vim.deep_equal(tools.formatters(a), { "stylua", "trim_whitespace" }), "restore default pipeline order")
	local formatter_items = tools.inspect(a).formatters
	for _, item in ipairs(formatter_items) do
		if item.name == "trim_whitespace" then
			item.move(-1)
		end
	end
	check(vim.deep_equal(tools.formatters(a), { "trim_whitespace", "stylua" }), "formatter steps must be reorderable")
	for _, item in ipairs(tools.inspect(a).formatters) do
		if item.name == "stylua" then
			item.move(-1)
		end
	end
	check(vim.deep_equal(tools.formatters(a), { "stylua", "trim_whitespace" }), "restoring order must inherit defaults")
	pick("project_test")
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 1
	end, "LSP toggle must reattach")
	check(
		tools.inspect(a).coverage.headline == "LSP covers formatting + diagnostics",
		"coverage must explain LSP sufficiency"
	)
	check(vim.lsp.get_clients({ bufnr = b })[1].id == client_b, "re-enable must preserve other repo")

	local state_file = vim.fn.stdpath("state") .. "/project-tools.json"
	local saved = vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	check(saved[root_a].linters.typos == false, "overrides must persist")
	saved[root_b] = { autoformat = false }
	vim.fn.writefile({ vim.json.encode(saved) }, state_file)
	pick("Clear project overrides")
	saved = vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	check(saved[root_a] == nil, "reset removes overrides")
	check(saved[root_b].autoformat == false, "writes must preserve other instance's repo state")
	check(tools.format_on_save(a) ~= nil, "reset restores defaults")

	-- Global defaults apply everywhere and project values only override them.
	tools.inspect(a, "global").settings[1].toggle()
	check(tools.format_on_save(a) == nil, "global autoformat default must affect the current project")
	check(tools.format_on_save(b) == nil, "global autoformat default must affect other projects")
	local project_autoformat = tools.inspect(a).settings[1]
	check(project_autoformat.source == "global", "project dashboard must identify inherited global values")
	project_autoformat.toggle()
	check(tools.format_on_save(a) ~= nil, "project setting must override the global default")
	check(tools.format_on_save(b) == nil, "project override must not leak to another repository")
	tools.inspect(a).reset()
	check(tools.format_on_save(a) == nil, "clearing project settings must restore global inheritance")
	tools.inspect(a, "global").reset()
	check(tools.format_on_save(a) ~= nil, "resetting global settings must restore built-in defaults")
	check(tools.format_on_save(b) == nil, "global reset must preserve repository overrides")
	local outside_dir = directory .. "/outside"
	vim.fn.mkdir(outside_dir, "p")
	local outside = vim.fn.bufadd(outside_dir .. "/test.lua")
	vim.fn.bufload(outside)
	vim.bo[outside].filetype = "lua"
	check(tools.inspect(outside).scope == "global", "files outside Git must edit global defaults")

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
	tools.pick(python)
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
	end, "real dashboard picker must open")
	local picker = snacks.picker.get()[1]
	wait_for(function()
		return picker:count() > 6
	end, "real dashboard must render all tool categories")
	picker.input:set("Autoformat")
	picker:find()
	wait_for(function()
		return picker.list:count() == 1
	end, "dashboard filtering must find settings")
	local autoformat_before = tools.autoformat(python)
	picker:action("confirm")
	wait_for(function()
		return tools.autoformat(python) ~= autoformat_before and not picker.closed and picker.list:count() == 1
	end, "toggle must refresh the dashboard in place")
	picker:action("confirm")
	wait_for(function()
		return tools.autoformat(python) == autoformat_before
	end, "second toggle must restore the inherited value")
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
