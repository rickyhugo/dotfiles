-- Run with: nvim --clean --headless -l nvim/tests/project-tools.lua
-- Uses installed Conform/nvim-lint, isolated state, fake executables on $PATH and a tiny real LSP server.
local original_stdpath = vim.fn.stdpath
local plugins = original_stdpath("data") .. "/site/pack/core/opt"
local directory = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
vim.fn.mkdir(directory .. "/state", "p")
directory = vim.uv.fs_realpath(directory)
vim.fn.stdpath = function(kind)
	return (kind == "state" or kind == "data") and (directory .. "/" .. kind) or original_stdpath(kind)
end
local home = directory .. "/home"
vim.fn.mkdir(home, "p")
vim.env.HOME = home
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.opt.rtp:append(plugins .. "/conform.nvim")
vim.opt.rtp:append(plugins .. "/nvim-lint")

local notifications = {}
vim.notify = function(message)
	notifications[#notifications + 1] = message
end

local function check(value, message)
	assert(value, message)
end

local function wait_for(predicate, message)
	check(vim.wait(3000, predicate, 20), message)
end

local function notified(text)
	return vim.iter(notifications):any(function(message)
		return message:find(text, 1, true) ~= nil
	end)
end

local function write(path, lines, mode)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(type(lines) == "string" and vim.split(lines, "\n") or lines, path)
	if mode then
		vim.uv.fs_chmod(path, mode)
	end
end

local function script(path, body)
	write(path, "#!/bin/sh\n" .. body, 493)
end

local function project(name, config, mise)
	local root = directory .. "/" .. name
	vim.fn.mkdir(root .. "/.git", "p")
	if mise ~= false then
		write(root .. "/mise.local.toml", "[tools]")
	end
	if config then
		write(root .. "/.nvim-tools.lua", config)
	end
	return root
end

local function open(path, lines)
	write(path, lines or { "x = 1" })
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.bo[buf].filetype = "lua"
	return buf
end

local function run()
	-- Executables on $PATH, as `mise activate` would provide them.
	local bin = directory .. "/bin"
	script(bin .. "/fakefmt", "sed 's/x/y/'")
	script(bin .. "/fakelint", 'grep -q bad && echo "1:bad line"; exit 0')
	local server = directory .. "/server.py"
	write(
		server,
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
]]
	)
	script(bin .. "/testls-server", 'exec python3 "' .. server .. '"')
	vim.env.PATH = bin .. ":" .. vim.env.PATH

	local config_a = [[
return {
	lsp = { "project_test" },
	format = { lua = { "fakefmt", "trim_whitespace" } },
	lint = { lua = { "fakelint", "ghostlint" } },
}
]]
	local root_a = project("a", config_a)
	local root_b = project("b", nil, false)
	local root_c = project("c", 'return { tools = { ruff = { provider = "venv" } } }')
	local root_d = project("d", "return { lsp = {} }", false)

	vim.cmd.source(vim.fn.getcwd() .. "/nvim/plugin/project-tools.lua")
	local tools = require("project-tools")
	local conform = require("conform")
	conform.setup({ formatters_by_ft = { ["_"] = tools.formatters }, format_on_save = tools.format_on_save })
	conform.formatters.fakefmt = { command = "fakefmt", stdin = true }
	local lint = require("lint")
	local function parser(output)
		return output:match("bad") and { { lnum = 0, col = 0, message = "bad", severity = 1 } } or {}
	end
	lint.linters.fakelint = { cmd = "fakelint", stdin = true, parser = parser }
	lint.linters.ghostlint = { cmd = "ghostlint", stdin = true, parser = parser }
	vim.lsp.config("project_test", { cmd = { "testls-server" }, filetypes = { "lua" }, root_markers = { ".git" } })

	-- Discovery and validation -------------------------------------------------
	check(tools.find_root(root_a .. "/sub/deeper") == root_a, "nested directories must find the project")
	check(tools.find_root(root_b) == nil, "a repo without the file is not a project")
	check(tools.load(root_c).error:find("pin versions in mise.local.toml", 1, true), "tools belong in mise")
	check(not tools.load(root_d).error, "a minimal file must load")
	wait_for(function()
		return notified("no mise.local.toml in " .. root_d)
	end, "a project without mise.local.toml must warn")
	check(not notified("no mise.local.toml in " .. root_a), "a project with mise.local.toml must not warn")

	local a = open(root_a .. "/sub/test.lua", { "x = 1", "bad" })
	local b = open(root_b .. "/test.lua")
	check(tools.get(a) and not tools.get(a).error, "project a must load")
	check(tools.get(b) == nil, "project b must have no tools")

	-- LSP --------------------------------------------------------------------------
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 1
	end, "declared LSP must attach")
	check(vim.lsp.get_clients({ bufnr = a })[1].root_dir == root_a, "LSP keeps its root_markers root")
	vim.wait(200)
	check(#vim.lsp.get_clients({ bufnr = b }) == 0, "LSP must not attach outside declaring projects")

	-- Formatting -----------------------------------------------------------------------
	check(tools.format_on_save(b) == nil, "no project means no format on save")
	check(tools.formatters(b).lsp_format == "never", "no project means no LSP formatting")
	check(tools.format_on_save(a).timeout_ms == 2000, "format on save defaults on")
	check(tools.formatters(a).lsp_format == "fallback", "lsp_format defaults to fallback")
	conform.format({ bufnr = a, async = false })
	check(vim.api.nvim_buf_get_lines(a, 0, 1, false)[1] == "y = 1", "declared formatter must run from $PATH")
	check(#conform.list_formatters(b) == 0, "no formatters outside projects")

	-- Linting --------------------------------------------------------------------------
	tools.lint(a)
	wait_for(function()
		return #vim.diagnostic.get(a, { namespace = lint.get_namespace("fakelint") }) == 1
	end, "declared linter must run")
	wait_for(function()
		return notified("ghostlint: ghostlint not found on $PATH")
	end, "a missing linter must warn")
	local before = #notifications
	tools.lint(a)
	vim.wait(100)
	check(#notifications == before, "a missing linter warns only once")

	-- Reload -----------------------------------------------------------------------------
	local client_id = vim.lsp.get_clients({ bufnr = a })[1].id
	write(root_a .. "/mise.local.toml", { "[tools]", 'stylua = "latest"' })
	wait_for(function()
		local client = vim.lsp.get_clients({ bufnr = a })[1]
		return client and client.id ~= client_id
	end, "a mise.local.toml change must restart LSP servers")

	local reduced =
		config_a:gsub('lsp = { "project_test" },', ""):gsub('lint = { lua = { "fakelint", "ghostlint" } },', "")
	-- An outside edit applies directly: no reload call, no trust prompt.
	local confirm = vim.fn.confirm
	vim.fn.confirm = function()
		error("loading .nvim-tools.lua must not prompt")
	end
	write(root_a .. "/.nvim-tools.lua", reduced)
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 0
	end, "removed LSP must detach when the file changes on disk")
	vim.fn.confirm = confirm
	check(#vim.diagnostic.get(a, { namespace = lint.get_namespace("fakelint") }) == 0, "removed linter clears")

	-- Global base ----------------------------------------------------------------------
	check(tools.find_root(home .. "/somewhere") == nil, "home is never a project")
	check(tools.get(b) == nil, "without a global file, buffers outside projects get nothing")
	write(
		home .. "/.nvim-tools.lua",
		[[
return {
	format = { ["*"] = { "trim_whitespace" }, lua = { "trim_newlines" } },
	lint = { ["*"] = { "fakelint" } },
	format_on_save = false,
}
]]
	)
	wait_for(function()
		return tools.get(b) ~= nil
	end, "creating the global file applies it outside projects")
	check(vim.deep_equal(tools.linters(b), { "fakelint" }), "outside projects: global linters")
	local outside_formatters = tools.formatters(b)
	check(
		vim.deep_equal({ outside_formatters[1], outside_formatters[2] }, { "trim_newlines", "trim_whitespace" }),
		"outside projects: global formatters, filetype first"
	)
	check(tools.format_on_save(b) == nil, "outside projects: global format_on_save")

	local root_e = project(
		"e",
		'return { lint = { lua = { "ghostlint", "fakelint" } }, format = { lua = { "fakefmt" } }, format_on_save = true }'
	)
	local e = open(root_e .. "/test.lua")
	check(vim.deep_equal(tools.linters(e), { "ghostlint", "fakelint" }), "linters add up without duplicates")
	local project_formatters = tools.formatters(e)
	check(
		vim.deep_equal(
			{ project_formatters[1], project_formatters[2], project_formatters[3] },
			{ "fakefmt", "trim_whitespace" }
		),
		"a project's filetype formatters replace the global ones; '*' still applies"
	)
	check(tools.format_on_save(e) ~= nil, "project settings win over global ones")
	vim.bo[e].filetype = "lua.special"
	check(tools.formatters(e)[1] == "fakefmt", "dotted filetypes use the formatters of their first part")
	vim.bo[e].filetype = "lua"

	vim.api.nvim_set_current_buf(e)
	tools.show()
	local shown = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
	check(shown:find("-- project: ", 1, true) and shown:find("return {", 1, true), "show lists sources and the table")
	local ok_chunk, shown_config = pcall(load(shown, "show", "t", {}))
	check(ok_chunk and vim.deep_equal(shown_config, tools.effective(e)), "show prints loadable effective config")
	check(#vim.lsp.get_clients({ bufnr = 0 }) == 0, "the show buffer starts no LSP")
	vim.cmd.close()

	vim.fn.delete(home .. "/.nvim-tools.lua")
	wait_for(function()
		return tools.get(b) == nil
	end, "deleting the global file removes it everywhere")
	check(vim.deep_equal(tools.linters(e), { "ghostlint", "fakelint" }), "projects keep their own tools")

	-- Edit + health ---------------------------------------------------------------------
	vim.api.nvim_set_current_buf(b)
	tools.edit(b)
	check(vim.uv.fs_stat(root_b .. "/.nvim-tools.lua"), "edit must create the file")
	check(not tools.load(root_b).error, "template must be valid: " .. tostring(tools.load(root_b).error))
	local reported = {}
	for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
		vim.health[level] = function(message)
			reported[#reported + 1] = level .. ": " .. message
		end
	end
	require("project-tools.health").check()
	local text = table.concat(reported, "\n")
	check(text:find("format lua fakefmt → " .. bin .. "/fakefmt", 1, true), "health reports formatter paths")
	check(text:find("warn: no mise.local.toml", 1, true), "health reports a missing mise.local.toml")

	vim.fn.delete(root_a .. "/" .. tools.file)
	wait_for(function()
		return tools.loaded()[root_a] == nil
	end, "deleting the file unloads the project")
	check(tools.get(a) == nil, "buffers of a deleted project have no tools")
end

local ok, err = xpcall(run, debug.traceback)
for _, client in ipairs(vim.lsp.get_clients()) do
	client:stop(true)
end
vim.fn.delete(directory, "rf")
if not ok then
	io.stderr:write(err .. "\n")
	os.exit(1)
end
print("project-tools: all checks passed")
