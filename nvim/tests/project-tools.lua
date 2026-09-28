-- Run with: nvim --clean --headless -l nvim/tests/project-tools.lua
-- Uses installed Conform/nvim-lint, isolated data/state, a fake mise and a tiny real LSP server.
local original_stdpath = vim.fn.stdpath
local plugins = original_stdpath("data") .. "/site/pack/core/opt"
local directory = vim.uv.fs_realpath(vim.fn.tempname()) or vim.fn.tempname()
vim.fn.mkdir(directory, "p")
directory = vim.uv.fs_realpath(directory)
vim.fn.stdpath = function(kind)
	return (kind == "state" or kind == "data") and (directory .. "/" .. kind) or original_stdpath(kind)
end
vim.fn.mkdir(directory .. "/state", "p")
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
vim.opt.rtp:append(plugins .. "/conform.nvim")
vim.opt.rtp:append(plugins .. "/nvim-lint")

local function check(value, message)
	assert(value, message)
end

local function wait_for(predicate, message)
	check(vim.wait(3000, predicate, 20), message)
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

local function project(name, config)
	local root = directory .. "/" .. name
	vim.fn.mkdir(root .. "/.git", "p")
	if config then
		write(root .. "/.nvim-tools.lua", config)
		vim.secure.trust({ action = "allow", path = root .. "/.nvim-tools.lua" })
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
	-- Providers --------------------------------------------------------------
	-- A fake mise that knows one installed tool version.
	local mise_bin = directory .. "/mise-installs/misetool/1.2.0/bin"
	script(mise_bin .. "/misetool", "exit 0")
	local fake_mise = directory .. "/mise-bin"
	script(
		fake_mise .. "/mise",
		string.format(
			'[ "$1 $2 $3" = "bin-paths --json misetool@1.2.0" ] && echo \'[{"name":"misetool","path":"%s/misetool"}]\' || echo "[]"',
			mise_bin
		)
	)
	local system_bin = directory .. "/system-bin"
	script(system_bin .. "/fakelint", 'grep -q bad && echo "1:bad line"; exit 0')
	script(system_bin .. "/misetool", "exit 0")
	vim.env.PATH = fake_mise .. ":" .. system_bin .. ":" .. vim.env.PATH

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

	local config_a = [[
return {
	tools = {
		fakefmt = { provider = "venv" },
		testls = { provider = "venv", bin = { "testls-server" } },
		fakelint = { provider = "system" },
		misetool = { provider = "mise", version = "1.2.0" },
		oldtool = { provider = "mise", version = "1.0.0" },
	},
	lsp = { "project_test" },
	format = { lua = { "fakefmt", "trim_whitespace" } },
	lint = { lua = { "fakelint" } },
}
]]
	local root_a = project("a", config_a)
	script(root_a .. "/.venv/bin/fakefmt", "sed 's/x/y/'")
	script(root_a .. "/.venv/bin/testls-server", 'exec python3 "' .. server .. '"')
	local root_b = project("b")
	local root_c = project("c", 'return { tools = { ruff = { provider = "pip" } } }')
	local root_d = project("d", 'return { tools = { stylua = { provider = "mise" } } }')

	vim.cmd.source(vim.fn.getcwd() .. "/nvim/plugin/project-tools.lua")
	local tools = require("project-tools")
	local conform = require("conform")
	conform.setup({ formatters_by_ft = { ["_"] = tools.formatters }, format_on_save = tools.format_on_save })
	conform.formatters.fakefmt = { command = "fakefmt", stdin = true }
	local lint = require("lint")
	lint.linters.fakelint = {
		cmd = "fakelint",
		stdin = true,
		parser = function(output)
			return output:match("bad") and { { lnum = 0, col = 0, message = "bad", severity = 1 } } or {}
		end,
	}
	vim.lsp.config("project_test", { cmd = { "testls-server" }, filetypes = { "lua" }, root_markers = { ".git" } })

	-- Discovery and validation -------------------------------------------------
	check(tools.find_root(root_a .. "/sub/deeper") == root_a, "nested directories must find the project")
	check(tools.find_root(root_b) == nil, "a repo without the file is not a project")
	check(tools.load(root_c).error:find("provider must be one of", 1, true), "unknown providers must be rejected")
	check(tools.load(root_d).error:find("version is required", 1, true), "mise tools must declare a version")

	local a = open(root_a .. "/sub/test.lua", { "x = 1", "bad" })
	local b = open(root_b .. "/test.lua")
	local project_a = tools.get(a)
	check(project_a and not project_a.error, "project a must load: " .. tostring(project_a and project_a.error))
	check(tools.get(b) == nil, "project b must have no tools")

	-- Resolution ------------------------------------------------------------------
	check(tools.resolve(project_a, "fakefmt") == root_a .. "/.venv/bin/fakefmt", "venv executables resolve")
	check(tools.resolve(project_a, "/elsewhere/fakefmt") == root_a .. "/.venv/bin/fakefmt", "only basenames matter")
	check(tools.resolve(project_a, "misetool") == mise_bin .. "/misetool", "mise must win over system PATH")
	check(tools.resolve(project_a, "fakelint") == system_bin .. "/fakelint", "system executables resolve on PATH")
	check(project_a.tools.oldtool.status == "not installed", "uninstalled mise versions must not be used")
	check(tools.resolve(project_a, "oldtool") == nil, "uninstalled tools provide nothing")
	check(tools.resolve(project_a, "python3") == nil, "undeclared executables must not resolve")

	-- LSP --------------------------------------------------------------------------
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 1
	end, "declared LSP must attach")
	local client = vim.lsp.get_clients({ bufnr = a })[1]
	check(client.root_dir == root_a, "LSP must be rooted at the project")
	vim.wait(200)
	check(#vim.lsp.get_clients({ bufnr = b }) == 0, "LSP must not attach outside declaring projects")

	-- Formatting -----------------------------------------------------------------------
	check(tools.format_on_save(b) == nil, "no project means no format on save")
	check(tools.formatters(b).lsp_format == "never", "no project means no LSP formatting")
	check(tools.format_on_save(a).timeout_ms == 500, "format on save defaults on")
	check(tools.formatters(a).lsp_format == "fallback", "lsp_format defaults to fallback")
	check(tools.formatter_command("trim_whitespace", a) == false, "Lua formatters run no executable")
	conform.format({ bufnr = a, async = false })
	check(vim.api.nvim_buf_get_lines(a, 0, 1, false)[1] == "y = 1", "declared formatter must run from the venv")
	check(#conform.list_formatters(b) == 0, "no formatters outside projects")

	-- Linting --------------------------------------------------------------------------
	tools.lint(a)
	wait_for(function()
		return #vim.diagnostic.get(a, { namespace = lint.get_namespace("fakelint") }) == 1
	end, "declared linter must run")

	-- Reload -----------------------------------------------------------------------------
	local reduced = config_a:gsub('lsp = { "project_test" },', ""):gsub('lint = { lua = { "fakelint" } },', "")
	write(root_a .. "/.nvim-tools.lua", reduced)
	vim.secure.trust({ action = "allow", path = root_a .. "/.nvim-tools.lua" })
	tools.reload(root_a)
	wait_for(function()
		return #vim.lsp.get_clients({ bufnr = a }) == 0
	end, "removed LSP must detach on reload")
	check(#vim.diagnostic.get(a, { namespace = lint.get_namespace("fakelint") }) == 0, "removed linter clears")

	-- Edit + health ---------------------------------------------------------------------
	vim.api.nvim_set_current_buf(b)
	tools.edit(b)
	check(vim.uv.fs_stat(root_b .. "/.nvim-tools.lua"), "edit must create the file")
	local project_b = tools.load(root_b)
	check(not project_b.error, "template must be valid: " .. tostring(project_b.error))
	local reported = {}
	for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
		vim.health[level] = function(message)
			reported[#reported + 1] = level .. ": " .. message
		end
	end
	require("project-tools.health").check()
	local text = table.concat(reported, "\n")
	check(text:find("oldtool (mise 1.0.0): not installed", 1, true), "health must report missing versions")
	check(text:find("format lua fakefmt → " .. root_a, 1, true), "health must report resolved formatters")
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
