-- Per-project wiring in <project>/.nvim-tools.lua: which LSP servers, formatters
-- and linters run. ~/.nvim-tools.lua is a global base that every buffer gets and
-- project files add to; without either, nothing runs. Executables come from the
-- $PATH Neovim inherits, e.g. the project's mise.local.toml via mise shims.
local M = {}

M.file = ".nvim-tools.lua"
M.mise_file = "mise.local.toml"
-- Changes restart the project's tools: LSP servers keep the version their shim
-- resolved at start, so a new pin in the mise config needs a restart.
local watched = { M.file, M.mise_file, "mise.toml", ".mise.toml", ".mise.local.toml", ".tool-versions" }
local lsp_formats = { never = true, fallback = true, prefer = true, first = true, last = true }

local projects = {} -- root -> project
local global -- { path, source, config?, error? } for ~/.nvim-tools.lua
local outside -- effective setup for buffers outside any project
local roots = {} -- directory -> root|false
local wrapped = {} -- lsp names gated by project
local watchers = {} -- root -> fs_event on the project directory
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

local function home()
	return realpath(vim.env.HOME)
end

function M.global_path()
	return home() .. "/" .. M.file
end

--- Nearest ancestor directory containing .nvim-tools.lua. Home is never a
--- project: its .nvim-tools.lua is the global base.
function M.find_root(path)
	local dir = realpath(path)
	if roots[dir] ~= nil then
		return roots[dir] or nil
	end
	local root, candidate = nil, dir
	while candidate do
		if candidate ~= home() and vim.uv.fs_stat(candidate .. "/" .. M.file) then
			root = candidate
			break
		end
		local parent = vim.fs.dirname(candidate)
		candidate = parent ~= candidate and parent or nil
	end
	roots[dir] = root or false
	return root
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
	check(config.tools == nil, "tools are not declared here; pin versions in " .. M.mise_file)
	local known = { lsp = true, format = true, lint = true, format_on_save = true, lsp_format = true }
	for key in pairs(config) do
		check(known[key], "unknown key '" .. tostring(key) .. "'")
	end
	check(config.lsp == nil or list_of_strings(config.lsp), "lsp must be a list of lsp config names")
	for _, key in ipairs({ "format", "lint" }) do
		check(config[key] == nil or type(config[key]) == "table", key .. " must be a table")
	end
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

local function source(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local contents = file:read("*a")
	file:close()
	return contents
end

-- Watched files, to tell real changes from events that change nothing.
local function sources(root)
	local parts = {}
	for _, name in ipairs(watched) do
		parts[#parts + 1] = name .. "\0" .. (source(root .. "/" .. name) or "")
	end
	return table.concat(parts, "\0")
end

local function read(path)
	local contents = source(path)
	if not contents then
		error("cannot read " .. path, 0)
	end
	-- Declarations only: the file gets an empty environment, so it can name
	-- tools but not run code.
	local chunk, err = load(contents, "@" .. path, "t", {})
	if not chunk then
		error(err, 0)
	end
	local config = chunk()
	validate(config)
	return config
end

local function union(...)
	local result = {}
	-- By count, not ipairs: a missing (nil) list must not end the loop.
	for i = 1, select("#", ...) do
		for _, name in ipairs(select(i, ...) or {}) do
			if not vim.tbl_contains(result, name) then
				result[#result + 1] = name
			end
		end
	end
	return result
end

-- lsp, lint and format["*"] add up; a project's format list for a filetype
-- replaces the global one; project settings win.
local function merge(base, own)
	base, own = base or {}, own or {}
	local format = vim.deepcopy(base.format or {})
	for ft, list in pairs(own.format or {}) do
		format[ft] = ft == "*" and union(format["*"], list) or vim.deepcopy(list)
	end
	local lint = vim.deepcopy(base.lint or {})
	for ft, list in pairs(own.lint or {}) do
		lint[ft] = union(lint[ft], list)
	end
	local function setting(key, default)
		if own[key] ~= nil then
			return own[key]
		end
		if base[key] ~= nil then
			return base[key]
		end
		return default
	end
	return {
		lsp = union(base.lsp, own.lsp),
		format = format,
		lint = lint,
		format_on_save = setting("format_on_save", true),
		lsp_format = setting("lsp_format", "fallback"),
	}
end

local function apply(target, config)
	target.lsp_names = config.lsp
	target.lsp = {}
	for _, name in ipairs(config.lsp) do
		target.lsp[name] = true
	end
	target.format = config.format
	target.lint = config.lint
	target.format_on_save = config.format_on_save
	target.lsp_format = config.lsp_format
	return target
end

local enable_lsp, watch

local function load_global()
	if not global then
		local path = M.global_path()
		global = { path = path, source = source(path) }
		if global.source then
			local ok, config = pcall(read, path)
			if ok then
				global.config = config
			else
				global.error = config
				warn_once("error:global", path .. ": " .. config)
			end
		end
		watch(home(), { M.file }, function()
			return (global and global.source) ~= source(M.global_path())
		end, function()
			M.reload_global()
		end)
	end
	return global
end

--- The global file's state: { path, source, config?, error? }.
function M.global()
	return load_global()
end

local function load_project(root)
	local path = root .. "/" .. M.file
	local project = { root = root, path = path, source = sources(root) }
	if not vim.uv.fs_stat(root .. "/" .. M.mise_file) then
		warn_once("mise:" .. root, "no " .. M.mise_file .. " in " .. root .. "; tools come from whatever $PATH has")
	end
	local ok, config = pcall(read, path)
	if not ok then
		-- A broken project file still gets the global base.
		project.error = config
		warn_once("error:" .. root, M.file .. " in " .. root .. ": " .. config)
		config = nil
	end
	return apply(project, merge(load_global().config, config))
end

--- Effective setup for a buffer: its project merged over the global base, the
--- global base alone outside projects, or nil when neither file exists.
function M.get(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local root = M.find_root(buffer_dir(bufnr))
	if root then
		return M.load(root)
	end
	return M.outside()
end

function M.load(root)
	if not projects[root] then
		local project = load_project(root)
		projects[root] = project
		watch(root, watched, function()
			return (projects[root] and projects[root].source) ~= sources(root)
		end, function()
			M.reload(root)
		end)
		for _, name in ipairs(project.lsp_names) do
			enable_lsp(name)
		end
	end
	return projects[root]
end

--- The global base as buffers outside any project get it, or nil.
function M.outside()
	if not outside and load_global().config then
		outside = apply({ path = global.path, global = true }, merge(global.config, nil))
		for _, name in ipairs(outside.lsp_names) do
			enable_lsp(name)
		end
	end
	return outside
end

--- The effective config for a buffer, as a plain .nvim-tools.lua table, or nil.
function M.effective(bufnr)
	local project = M.get(bufnr)
	if not project then
		return nil
	end
	return {
		lsp = vim.deepcopy(project.lsp_names),
		format = vim.deepcopy(project.format),
		lint = vim.deepcopy(project.lint),
		format_on_save = project.format_on_save,
		lsp_format = project.lsp_format,
	}
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
	return union(names, sections["*"])
end

-- LSP -------------------------------------------------------------------------

-- Only attach a server to buffers whose project declares it.
enable_lsp = function(name)
	if not wrapped[name] then
		local config = vim.lsp.config[name]
		if not config then
			warn_once("lsp:" .. name, "unknown LSP config '" .. name .. "'")
			return
		end
		local root_dir = config.root_dir
		wrapped[name] = true
		vim.lsp.config(name, {
			root_dir = function(bufnr, on_dir)
				local project = M.get(bufnr)
				if not (project and project.lsp[name]) then
					return
				end
				if type(root_dir) == "function" then
					root_dir(bufnr, on_dir)
				else
					-- nil keeps Neovim's root_markers handling.
					on_dir(root_dir)
				end
			end,
		})
	end
	if not vim.lsp.is_enabled(name) then
		vim.lsp.enable(name)
	end
end

-- Formatting --------------------------------------------------------------------

--- conform formatters_by_ft entry for a buffer.
function M.formatters(bufnr)
	local project = M.get(bufnr)
	if not project then
		return { lsp_format = "never" }
	end
	local ft = vim.bo[bufnr].filetype
	local list = project.format[ft]
	-- A dotted filetype like yaml.docker-compose uses its first part that has a
	-- list; chains are not combined, unlike linters.
	for part in ft:gmatch("[^.]+") do
		list = list or project.format[part]
	end
	list = list or {}
	local names = union(list, project.format["*"])
	names.lsp_format = list.lsp_format or project.lsp_format
	names.stop_after_first = list.stop_after_first
	return names
end

function M.format_on_save(bufnr)
	local project = M.get(bufnr)
	if project and project.format_on_save then
		-- Daemons like prettierd need ~0.5s for their first format after starting.
		return { timeout_ms = 2000 }
	end
end

-- Linting -------------------------------------------------------------------------

function M.linters(bufnr)
	local project = M.get(bufnr)
	return project and by_filetype(project.lint, vim.bo[bufnr].filetype) or {}
end

local function linter_command(name, bufnr)
	local ok, command = pcall(vim.api.nvim_buf_call, bufnr, function()
		local linter = require("lint").linters[name]
		linter = type(linter) == "function" and linter() or linter
		return type(linter.cmd) == "function" and linter.cmd() or linter.cmd
	end)
	return ok and command or nil
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
	-- nvim-lint warns on every run for a missing executable; warn once instead.
	local names = vim.tbl_filter(function(name)
		local command = linter_command(name, bufnr)
		if command and vim.fn.executable(command) == 1 then
			return true
		end
		warn_once(
			"lint:" .. (project.root or "global") .. name,
			name .. ": " .. (command or name) .. " not found on $PATH"
		)
		return false
	end, M.linters(bufnr))
	vim.api.nvim_buf_call(bufnr, function()
		require("lint").try_lint(names)
	end)
end

-- Lifecycle -------------------------------------------------------------------------

-- Buffers under root that are not inside a nested project.
local function owned(root, bufnr)
	if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= "" then
		return false
	end
	local dir = realpath(buffer_dir(bufnr))
	local nearest = M.find_root(dir)
	return contains(root, dir) and (nearest == nil or nearest == root or not contains(root, nearest))
end

-- Stop the tools of `buffers`, refresh the loaded state, then let everything
-- start again from the new files.
local function restart(buffers, refresh)
	local previous = {}
	for _, bufnr in ipairs(buffers) do
		previous[bufnr] = M.linters(bufnr)
	end
	roots = {}
	warned = {}
	for _, bufnr in ipairs(buffers) do
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			if wrapped[client.name] then
				client:stop(true)
			end
		end
		for _, name in ipairs(previous[bufnr]) do
			vim.diagnostic.reset(require("lint").get_namespace(name), bufnr)
		end
	end
	refresh()
	vim.schedule(function()
		if next(wrapped) then
			vim.cmd.doautoall("nvim.lsp.enable FileType")
		end
		for _, bufnr in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				M.lint(bufnr)
			end
		end
	end)
end

--- Re-read a project's file and restart its tools in open buffers.
function M.reload(root)
	local buffers = vim.tbl_filter(function(bufnr)
		return owned(root, bufnr)
	end, vim.api.nvim_list_bufs())
	restart(buffers, function()
		projects[root] = nil
		-- A deleted file unloads the project; its buffers fall back to any outer
		-- one or the global base.
		if vim.uv.fs_stat(root .. "/" .. M.file) then
			M.load(root)
		end
	end)
end

--- Re-read the global file; every buffer may change, so everything restarts.
function M.reload_global()
	local buffers = vim.tbl_filter(function(bufnr)
		return vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == ""
	end, vim.api.nvim_list_bufs())
	restart(buffers, function()
		global, outside, projects = nil, nil, {}
		load_global()
	end)
end

function M.reload_all()
	M.reload_global()
end

--- Reload whatever `path` configures, after it was saved.
function M.changed(path)
	path = realpath(path)
	if path == M.global_path() then
		M.reload_global()
	else
		M.reload(vim.fs.dirname(path))
	end
end

-- Reload when a watched file changes outside Neovim (another editor, git
-- checkout, `mise use`). The directory is watched because editors often replace
-- files on save; `stale` filters out events that change nothing.
watch = function(dir, names, stale, reload)
	if watchers[dir] then
		return
	end
	local watcher, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
	if not watcher or not timer then
		return
	end
	watchers[dir] = watcher
	watcher:start(dir, {}, function(err, filename)
		if err or (filename and not vim.tbl_contains(names, vim.fs.basename(filename))) then
			return
		end
		timer:stop()
		timer:start(200, 0, function()
			vim.schedule(function()
				if stale() then
					reload()
				end
			end)
		end)
	end)
end

local template = [[
-- Editor tools for this project, added to the global ~/.nvim-tools.lua.
-- Executables come from $PATH: pin them in mise.local.toml ([tools]).
return {
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

local global_template = [[
-- Editor tools for every buffer; project .nvim-tools.lua files add to these.
-- Executables come from $PATH, e.g. your global mise config.
return {
	lsp = {},
	format = {
		-- ["*"] = { "trim_whitespace", "trim_newlines" },
	},
	lint = {
		-- ["*"] = { "typos" },
	},
}
]]

local function open(path, contents)
	if not vim.uv.fs_stat(path) then
		vim.fn.writefile(vim.split(contents, "\n", { trimempty = true }), path)
		roots = {}
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
end

--- Open a scratch split with the buffer's effective config and where it came from.
function M.show(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local project, config = M.get(bufnr), M.effective(bufnr)
	local ft = vim.bo[bufnr].filetype
	local lines =
		{ "-- Effective " .. M.file .. " for " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":~:.") }
	local g = load_global()
	lines[#lines + 1] = "-- global:  "
		.. vim.fn.fnamemodify(g.path, ":~")
		.. (g.error and (" (error: " .. g.error .. ")") or g.config and "" or " (none)")
	if project and project.root then
		lines[#lines + 1] = "-- project: "
			.. vim.fn.fnamemodify(project.path, ":~")
			.. (project.error and (" (error: " .. project.error .. ")") or "")
	else
		lines[#lines + 1] = "-- project: none"
	end
	if config then
		local formatters = M.formatters(bufnr)
		lines[#lines + 1] = "-- this buffer (filetype "
			.. (ft ~= "" and ft or "none")
			.. "): format = "
			.. (#formatters > 0 and table.concat(formatters, ", ") or "none")
			.. " (lsp_format "
			.. formatters.lsp_format
			.. "), lint = "
			.. (#M.linters(bufnr) > 0 and table.concat(M.linters(bufnr), ", ") or "none")
		vim.list_extend(lines, vim.split("return " .. vim.inspect(config), "\n"))
	else
		lines[#lines + 1] = "-- Nothing applies: no global file and no project file."
	end

	local name = "project-tools://effective"
	local existing = vim.fn.bufnr(name)
	if existing ~= -1 then
		vim.api.nvim_buf_delete(existing, { force = true })
	end
	vim.cmd("botright new")
	local buf = vim.api.nvim_get_current_buf()
	-- buftype first, so the lua filetype below starts no LSP or linter here.
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "lua"
	vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close" })
end

function M.edit_global()
	open(M.global_path(), global_template)
end

function M.edit(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local dir = buffer_dir(bufnr)
	local root = M.find_root(dir) or vim.fs.root(dir, ".git") or vim.fn.getcwd()
	open(root .. "/" .. M.file, template)
end

return M
