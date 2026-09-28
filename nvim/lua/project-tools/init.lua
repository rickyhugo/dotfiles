-- Per-project tools declared in <project>/.nvim-tools.lua. Without that file nothing
-- runs: no LSP, formatter or linter. Every executable is resolved through a
-- declared tool, never looked up on $PATH implicitly.
local M = {}

M.file = ".nvim-tools.lua"
M.providers = { mise = true, venv = true, node = true, system = true }
local lsp_formats = { never = true, fallback = true, prefer = true, first = true, last = true }

local projects = {} -- root -> project
local roots = {} -- directory -> root|false
local wrapped = {} -- lsp name -> original cmd
local formatters = {} -- formatter name -> { base = user override } once wrapped
local warned = {}

local function warn_once(key, message)
	if not warned[key] then
		warned[key] = true
		vim.schedule(function()
			vim.notify("project-tools: " .. message, vim.log.levels.WARN)
		end)
	end
end

local function realpath(path)
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function contains(root, path)
	return path == root or vim.startswith(path, root .. "/")
end

local function buffer_dir(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
end

--- Nearest ancestor directory containing .nvim-tools.lua.
function M.find_root(path)
	local dir = realpath(path)
	if roots[dir] ~= nil then
		return roots[dir] or nil
	end
	local root, candidate = nil, dir
	while candidate do
		if vim.uv.fs_stat(candidate .. "/" .. M.file) then
			root = candidate
			break
		end
		local parent = vim.fs.dirname(candidate)
		candidate = parent ~= candidate and parent or nil
	end
	roots[dir] = root or false
	return root
end

local function executable(path)
	return path and vim.fn.executable(path) == 1 and path or nil
end

local function wanted(tool, exe)
	return not tool.bin or vim.tbl_contains(tool.bin, exe)
end

-- Each resolver fills tool.bins (executable -> absolute path) and tool.status.
local resolvers = {}

local function mise_start(name, tool)
	if vim.fn.executable("mise") == 0 then
		tool.status = "mise not found"
		return
	end
	-- Run outside the project so its own mise config cannot change the answer.
	return vim.system({ "mise", "bin-paths", "--json", name .. "@" .. tool.version }, { cwd = "/", text = true })
end

local function mise_finish(tool, result)
	local ok, entries = pcall(vim.json.decode, result.stdout or "")
	if result.code ~= 0 or not ok or type(entries) ~= "table" or #entries == 0 then
		tool.status = "not installed"
		return
	end
	for _, entry in ipairs(entries) do
		if wanted(tool, entry.name) then
			tool.bins[entry.name] = executable(entry.path)
		end
	end
end

local function local_dir(dir)
	return function(name, tool, root)
		for _, exe in ipairs(tool.bin or { name }) do
			tool.bins[exe] = executable(vim.fs.joinpath(root, dir, exe))
		end
	end
end
resolvers.venv = local_dir(".venv/bin")
resolvers.node = local_dir("node_modules/.bin")

function resolvers.system(name, tool)
	for _, exe in ipairs(tool.bin or { name }) do
		local path = vim.fn.exepath(exe)
		tool.bins[exe] = path ~= "" and path or nil
	end
end

local function resolve_tools(project)
	local pending = {}
	for name, tool in pairs(project.tools) do
		tool.bins = {}
		tool.status = nil
		if tool.provider == "mise" then
			pending[name] = mise_start(name, tool)
		else
			resolvers[tool.provider](name, tool, project.root)
		end
	end
	for name, process in pairs(pending) do
		mise_finish(project.tools[name], process:wait(5000))
	end
	for _, tool in pairs(project.tools) do
		if not tool.status then
			tool.status = next(tool.bins) and "ok" or "no executables found"
		end
	end
end

local function list_of_strings(value)
	return vim.islist(value) and vim.iter(value):all(function(item)
		return type(item) == "string"
	end)
end

local function check(condition, message)
	if not condition then
		error(message, 0)
	end
end

local function validate(config)
	check(type(config) == "table", "must return a table")
	local known = { tools = true, lsp = true, format = true, lint = true, format_on_save = true, lsp_format = true }
	for key in pairs(config) do
		check(known[key], "unknown key '" .. tostring(key) .. "'")
	end
	for _, key in ipairs({ "tools", "format", "lint" }) do
		check(config[key] == nil or type(config[key]) == "table", key .. " must be a table")
	end
	for name, tool in pairs(config.tools or {}) do
		local where = "tools['" .. tostring(name) .. "']"
		check(type(name) == "string", "tools must be keyed by tool name")
		check(type(tool) == "table", where .. " must be a table")
		for key in pairs(tool) do
			check(key == "provider" or key == "version" or key == "bin", where .. ": unknown key '" .. key .. "'")
		end
		check(M.providers[tool.provider], where .. ": provider must be one of mise, venv, node, system")
		if tool.provider == "mise" then
			check(type(tool.version) == "string", where .. ": version is required for mise")
		else
			check(tool.version == nil, where .. ": version comes from the " .. tool.provider .. " provider itself")
		end
		check(tool.bin == nil or list_of_strings(tool.bin), where .. ": bin must be a list of executable names")
	end
	check(config.lsp == nil or list_of_strings(config.lsp), "lsp must be a list of lsp config names")
	for ft, names in pairs(config.format or {}) do
		local where = "format['" .. tostring(ft) .. "']"
		check(type(names) == "table", where .. " must be a list")
		for key, value in pairs(names) do
			if type(key) == "number" then
				check(type(value) == "string", where .. ": formatter names must be strings")
			else
				check(key == "lsp_format" or key == "stop_after_first", where .. ": unknown key '" .. key .. "'")
			end
		end
		check(names.lsp_format == nil or lsp_formats[names.lsp_format], where .. ": invalid lsp_format")
	end
	for ft, names in pairs(config.lint or {}) do
		check(list_of_strings(names), "lint['" .. tostring(ft) .. "'] must be a list of linter names")
	end
	check(config.format_on_save == nil or type(config.format_on_save) == "boolean", "format_on_save must be a boolean")
	check(config.lsp_format == nil or lsp_formats[config.lsp_format], "invalid lsp_format")
end

local function read(path)
	local contents = vim.secure.read(path)
	if not contents then
		error("not trusted; run :trust " .. path .. " or save it from Neovim", 0)
	end
	-- Declarations only: the file gets an empty environment.
	local chunk, err = load(contents, "@" .. path, "t", {})
	if not chunk then
		error(err, 0)
	end
	local config = chunk()
	validate(config)
	return config
end

local function load_project(root)
	local path = root .. "/" .. M.file
	local project = { root = root, path = path, tools = {}, lsp = {}, format = {}, lint = {} }
	local ok, config = pcall(read, path)
	if not ok then
		project.error = config
		warn_once("error:" .. root, M.file .. " in " .. root .. ": " .. config)
		return project
	end
	project.tools = vim.deepcopy(config.tools or {})
	project.lsp_names = config.lsp or {}
	for _, name in ipairs(project.lsp_names) do
		project.lsp[name] = true
	end
	project.format = config.format or {}
	project.lint = config.lint or {}
	project.format_on_save = config.format_on_save ~= false
	project.lsp_format = config.lsp_format or "fallback"
	resolve_tools(project)
	return project
end

--- Absolute path of `exe` in a project, from the declared tools only.
function M.resolve(project, exe)
	exe = vim.fs.basename(exe)
	local providers = {}
	for name, tool in vim.spairs(project.tools) do
		if tool.bins[exe] then
			providers[#providers + 1] = name
		end
	end
	if #providers == 0 then
		return nil, exe .. " is not provided by any tool in " .. M.file
	end
	return project.tools[providers[1]].bins[exe], nil, providers
end

local enable_lsp

function M.get(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local root = M.find_root(buffer_dir(bufnr))
	return root and M.load(root) or nil
end

function M.load(root)
	if not projects[root] then
		local project = load_project(root)
		projects[root] = project
		for _, name in ipairs(project.lsp_names or {}) do
			enable_lsp(name)
		end
	end
	return projects[root]
end

function M.loaded()
	return projects
end

local function by_filetype(sections, ft)
	local names = sections[ft]
	if not names then
		names = {}
		for part in ft:gmatch("[^.]+") do
			vim.list_extend(names, sections[part] or {})
		end
	end
	return vim.list_extend(vim.deepcopy(names), sections["*"] or {})
end

-- LSP -------------------------------------------------------------------------

-- Many lspconfig cmd functions call vim.lsp.rpc.start themselves; intercept it
-- to see or rewrite the argv they build.
local function intercept_rpc_start(replacement, fn, ...)
	local rpc = vim.lsp.rpc
	local original = rpc.start
	rpc.start = function(argv, ...)
		return replacement(original, argv, ...)
	end
	local ok, result = pcall(fn, ...)
	rpc.start = original
	if not ok then
		error(result, 0)
	end
	return result
end

local function original_cmd(name)
	if wrapped[name] ~= nil then
		return wrapped[name] or nil
	end
	return (vim.lsp.config[name] or {}).cmd
end

--- Executable an LSP config would start for a project root.
function M.lsp_command(name, root)
	local cmd = original_cmd(name)
	if type(cmd) == "table" then
		return cmd[1]
	end
	if type(cmd) == "function" then
		local captured
		pcall(intercept_rpc_start, function(_, argv)
			captured = argv[1]
			error("captured", 0)
		end, cmd, {}, { root_dir = root })
		return captured
	end
end

local function project_for_root(root)
	local project_root = root and M.find_root(root)
	return project_root and M.load(project_root) or nil
end

local function start_lsp(cmd, dispatchers, client_config)
	local project = assert(project_for_root(client_config.root_dir))
	local function start(rpc_start, argv, ...)
		argv = vim.deepcopy(argv)
		argv[1] = assert(M.resolve(project, argv[1]))
		return rpc_start(argv, ...)
	end
	if type(cmd) == "function" then
		return intercept_rpc_start(start, cmd, dispatchers, client_config)
	end
	return start(vim.lsp.rpc.start, cmd, dispatchers, {
		cwd = client_config.cmd_cwd,
		env = client_config.cmd_env,
		detached = client_config.detached,
	})
end

enable_lsp = function(name)
	if wrapped[name] == nil then
		local config = vim.lsp.config[name]
		if not config then
			warn_once("lsp:" .. name, "unknown LSP config '" .. name .. "'")
			return
		end
		local root_dir, cmd = config.root_dir, config.cmd
		wrapped[name] = cmd or false
		vim.lsp.config(name, {
			root_dir = function(bufnr, on_dir)
				local project = M.get(bufnr)
				if not (project and project.lsp[name]) then
					return
				end
				local command = M.lsp_command(name, project.root)
				local _, err = command and M.resolve(project, command)
				if not command or err then
					warn_once("lsp-cmd:" .. project.root .. name, name .. ": " .. (err or "cannot tell its command"))
					return
				end
				local function accept(root)
					-- Never root a server above its project, so its command resolves there too.
					root = root and realpath(root)
					if not root or not contains(project.root, root) then
						root = project.root
					end
					if vim.api.nvim_buf_is_valid(bufnr) and project == M.get(bufnr) then
						on_dir(root)
					end
				end
				if type(root_dir) == "function" then
					root_dir(bufnr, accept)
				else
					accept(root_dir or (config.root_markers and vim.fs.root(bufnr, config.root_markers)))
				end
			end,
			cmd = cmd and function(dispatchers, client_config)
				return start_lsp(cmd, dispatchers, client_config)
			end,
		})
	end
	if not vim.lsp.is_enabled(name) then
		vim.lsp.enable(name)
	end
end

-- Formatting --------------------------------------------------------------------

local function base_override(name, bufnr)
	local base
	if formatters[name] then
		base = formatters[name].base
	else
		base = require("conform").formatters[name]
	end
	return type(base) == "function" and base(bufnr) or vim.deepcopy(base or {})
end

-- The executable conform would run, or false for Lua formatters such as
-- trim_whitespace, or nil for unknown ones.
local function formatter_command(name, override)
	if override.command or override.format then
		return override.command or false
	end
	local parent = type(override.inherit) == "string" and override.inherit or name
	local ok, builtin = pcall(require, "conform.formatters." .. parent)
	if not ok then
		return nil
	end
	return builtin.command or false
end

--- Executable name for a formatter in a buffer; false when it runs no executable.
function M.formatter_command(name, bufnr)
	local override = base_override(name, bufnr)
	local command = formatter_command(name, override)
	if type(command) == "function" then
		local file = vim.api.nvim_buf_get_name(bufnr)
		local ok, value = pcall(command, override, { buf = bufnr, filename = file, dirname = vim.fs.dirname(file) })
		command = ok and value or nil
	end
	return command
end

local function wrap_formatter(name)
	if formatters[name] then
		return
	end
	local conform = require("conform")
	formatters[name] = { base = conform.formatters[name] }
	conform.formatters[name] = function(bufnr)
		local override = base_override(name, bufnr)
		local original = formatter_command(name, override)
		if not original then
			return override
		end
		override.command = function(self, ctx)
			local command = type(original) == "function" and original(self, ctx) or original
			local project = M.get(ctx.buf)
			local path, err = project and M.resolve(project, command)
			if not path then
				warn_once("fmt:" .. (project and project.root or "") .. name, name .. ": " .. (err or "no project"))
				return "project-tools: " .. vim.fs.basename(command) .. " not declared"
			end
			return path
		end
		return override
	end
end

--- conform formatters_by_ft entry for a buffer.
function M.formatters(bufnr)
	local project = M.get(bufnr)
	if not project then
		return { lsp_format = "never" }
	end
	local ft = vim.bo[bufnr].filetype
	local list = project.format[ft] or {}
	local names = vim.list_extend(vim.deepcopy(list), project.format["*"] or {})
	names.lsp_format = list.lsp_format or project.lsp_format
	names.stop_after_first = list.stop_after_first
	for _, name in ipairs(names) do
		wrap_formatter(name)
	end
	return names
end

function M.format_on_save(bufnr)
	local project = M.get(bufnr)
	if project and project.format_on_save then
		return { timeout_ms = 500 }
	end
end

-- Linting -------------------------------------------------------------------------

function M.linter_command(name, bufnr)
	local ok, command = pcall(vim.api.nvim_buf_call, bufnr, function()
		local linter = require("lint").linters[name]
		linter = type(linter) == "function" and linter() or linter
		return type(linter.cmd) == "function" and linter.cmd() or linter.cmd
	end)
	return ok and command or nil
end

function M.linters(bufnr)
	local project = M.get(bufnr)
	return project and by_filetype(project.lint, vim.bo[bufnr].filetype) or {}
end

function M.lint(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
		return
	end
	local project = M.get(bufnr)
	if not project then
		return
	end
	local names = {}
	for _, name in ipairs(M.linters(bufnr)) do
		local command = M.linter_command(name, bufnr)
		local _, err = command and M.resolve(project, command)
		if command and not err then
			names[#names + 1] = name
		else
			warn_once("lint:" .. project.root .. name, name .. ": " .. (err or "unknown linter"))
		end
	end
	vim.api.nvim_buf_call(bufnr, function()
		require("lint").try_lint(names, {
			wrap_linter = function(linter)
				local command = type(linter.cmd) == "function" and linter.cmd() or linter.cmd
				linter.cmd = M.resolve(project, command)
				return linter
			end,
		})
	end)
end

-- Lifecycle -------------------------------------------------------------------------

--- Re-read a project's file and restart its tools in open buffers.
function M.reload(root)
	roots = {}
	warned = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" then
			local buffer_root = M.find_root(buffer_dir(bufnr))
			local old = projects[root]
			if buffer_root == root or (old and contains(root, realpath(buffer_dir(bufnr)))) then
				for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
					if wrapped[client.name] ~= nil then
						client:stop(true)
					end
				end
				for _, name in ipairs(old and M.linters(bufnr) or {}) do
					vim.diagnostic.reset(require("lint").get_namespace(name), bufnr)
				end
			end
		end
	end
	projects[root] = nil
	M.load(root)
	vim.schedule(function()
		if next(wrapped) then
			vim.cmd.doautoall("nvim.lsp.enable FileType")
		end
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(bufnr) and M.find_root(buffer_dir(bufnr)) == root then
				M.lint(bufnr)
			end
		end
	end)
end

function M.reload_all()
	for root in pairs(vim.deepcopy(projects)) do
		M.reload(root)
	end
	roots = {}
end

local template = [[
-- Tools for this project. Nothing runs unless it is declared here.
-- Providers: mise (version required, "latest" allowed; any backend such as
-- npm:, pipx:, go: or github:), venv (.venv/bin), node (node_modules/.bin),
-- system ($PATH, for toolchain tools like rustfmt).
-- `bin` limits which executables a tool provides; venv, node and system
-- default to the tool name.
return {
	tools = {
		-- ["lua-language-server"] = { provider = "mise", version = "3.19.1" },
		-- ["npm:bash-language-server"] = { provider = "mise", version = "5.8.0" },
		-- stylua = { provider = "mise", version = "2.5.2" },
		-- ruff = { provider = "venv" },
		-- basedpyright = { provider = "venv", bin = { "basedpyright-langserver" } },
	},
	lsp = {
		-- "lua_ls",
	},
	format = {
		-- lua = { "stylua" },
		-- rust = { lsp_format = "prefer" },
	},
	lint = {
		-- ["*"] = { "typos" },
	},
	-- format_on_save = true,
	-- lsp_format = "fallback",
}
]]

function M.edit(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local dir = buffer_dir(bufnr)
	local root = M.find_root(dir) or vim.fs.root(dir, ".git") or vim.fn.getcwd()
	local path = root .. "/" .. M.file
	if not vim.uv.fs_stat(path) then
		vim.fn.writefile(vim.split(template, "\n", { trimempty = true }), path)
		vim.secure.trust({ action = "allow", path = path })
		roots = {}
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
end

--- Install declared mise tools that are not installed at their version.
function M.install(bufnr)
	local project = M.get(bufnr or 0)
	if not project then
		return vim.notify("project-tools: no " .. M.file .. " for this buffer", vim.log.levels.WARN)
	end
	local jobs = {}
	for name, tool in vim.spairs(project.tools) do
		if tool.provider == "mise" and tool.status == "not installed" then
			jobs[#jobs + 1] = { name = name, tool = tool }
		end
	end
	if #jobs == 0 then
		return vim.notify("project-tools: nothing to install")
	end
	local remaining = #jobs
	local function done(name, ok, message)
		vim.schedule(function()
			vim.notify(
				"project-tools: " .. name .. (ok and " installed" or (" failed: " .. tostring(message))),
				ok and vim.log.levels.INFO or vim.log.levels.ERROR
			)
			remaining = remaining - 1
			if remaining == 0 then
				M.reload(project.root)
			end
		end)
	end
	for _, job in ipairs(jobs) do
		local name, tool = job.name, job.tool
		vim.notify("project-tools: installing " .. name .. "@" .. tool.version)
		vim.system({ "mise", "install", name .. "@" .. tool.version }, { cwd = "/", text = true }, function(result)
			done(name, result.code == 0, result.stderr)
		end)
	end
end

return M
