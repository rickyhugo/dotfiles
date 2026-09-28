-- Per-project wiring in <project>/.nvim-tools.lua: which LSP servers, formatters
-- and linters run. Without that file nothing runs. Executables come from the
-- $PATH Neovim inherits, e.g. the project's mise.local.toml via `mise activate`.
local M = {}

M.file = ".nvim-tools.lua"
M.mise_file = "mise.local.toml"
-- Changes restart the project's tools: LSP servers keep the version their shim
-- resolved at start, so a new pin in the mise config needs a restart.
local watched = { M.file, M.mise_file, "mise.toml", ".mise.toml", ".mise.local.toml", ".tool-versions" }
local lsp_formats = { never = true, fallback = true, prefer = true, first = true, last = true }

local projects = {} -- root -> project
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

local function load_project(root)
	local path = root .. "/" .. M.file
	local project =
		{ root = root, path = path, source = sources(root), lsp_names = {}, lsp = {}, format = {}, lint = {} }
	if not vim.uv.fs_stat(root .. "/" .. M.mise_file) then
		warn_once("mise:" .. root, "no " .. M.mise_file .. " in " .. root .. "; tools come from whatever $PATH has")
	end
	local ok, config = pcall(read, path)
	if not ok then
		project.error = config
		warn_once("error:" .. root, M.file .. " in " .. root .. ": " .. config)
		return project
	end
	project.lsp_names = config.lsp or {}
	for _, name in ipairs(project.lsp_names) do
		project.lsp[name] = true
	end
	project.format = config.format or {}
	project.lint = config.lint or {}
	project.format_on_save = config.format_on_save ~= false
	project.lsp_format = config.lsp_format or "fallback"
	return project
end

local enable_lsp, watch

function M.get(bufnr)
	bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
	local root = M.find_root(buffer_dir(bufnr))
	return root and M.load(root) or nil
end

function M.load(root)
	if not projects[root] then
		local project = load_project(root)
		projects[root] = project
		watch(root)
		for _, name in ipairs(project.lsp_names) do
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
	local list = project.format[vim.bo[bufnr].filetype] or {}
	local names = vim.list_extend(vim.deepcopy(list), project.format["*"] or {})
	names.lsp_format = list.lsp_format or project.lsp_format
	names.stop_after_first = list.stop_after_first
	return names
end

function M.format_on_save(bufnr)
	local project = M.get(bufnr)
	if project and project.format_on_save then
		return { timeout_ms = 500 }
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
		warn_once("lint:" .. project.root .. name, name .. ": " .. (command or name) .. " not found on $PATH")
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

--- Re-read a project's file and restart its tools in open buffers.
function M.reload(root)
	roots = {}
	warned = {}
	local old = projects[root]
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if owned(root, bufnr) then
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
				if wrapped[client.name] then
					client:stop(true)
				end
			end
			for _, name in ipairs(old and by_filetype(old.lint, vim.bo[bufnr].filetype) or {}) do
				vim.diagnostic.reset(require("lint").get_namespace(name), bufnr)
			end
		end
	end
	projects[root] = nil
	-- A deleted file unloads the project; its buffers fall back to any outer one.
	if vim.uv.fs_stat(root .. "/" .. M.file) then
		M.load(root)
	end
	vim.schedule(function()
		if next(wrapped) then
			vim.cmd.doautoall("nvim.lsp.enable FileType")
		end
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if owned(root, bufnr) then
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

-- Reload when a watched file changes outside Neovim (another editor, git
-- checkout, `mise use`). The directory is watched because editors often replace
-- files on save.
watch = function(root)
	if watchers[root] then
		return
	end
	local watcher, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
	if not watcher or not timer then
		return
	end
	watchers[root] = watcher
	watcher:start(root, {}, function(err, filename)
		if err or (filename and not vim.tbl_contains(watched, vim.fs.basename(filename))) then
			return
		end
		timer:stop()
		timer:start(200, 0, function()
			vim.schedule(function()
				local project = projects[root]
				if (project and project.source) ~= sources(root) then
					M.reload(root)
				end
			end)
		end)
	end)
end

local template = [[
-- Editor tools for this project. Nothing runs unless it is declared here.
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

function M.edit(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local dir = buffer_dir(bufnr)
	local root = M.find_root(dir) or vim.fs.root(dir, ".git") or vim.fn.getcwd()
	local path = root .. "/" .. M.file
	if not vim.uv.fs_stat(path) then
		vim.fn.writefile(vim.split(template, "\n", { trimempty = true }), path)
		roots = {}
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
end

return M
