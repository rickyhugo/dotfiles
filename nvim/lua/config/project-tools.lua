local M = {}
local state_path = vim.fn.stdpath("state") .. "/project-tools.json"
local global_key = "__global__"
local state
local wrapped = {}
local generations = {}
local formatter_defaults = {}
local linter_defaults = {}
local lsp_defaults = {}

local function read_state()
	if vim.fn.filereadable(state_path) == 0 then
		return {}
	end
	local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(state_path), "\n"))
	if not ok or type(decoded) ~= "table" then
		vim.schedule(function()
			vim.notify("Ignoring invalid project-tools state: " .. state_path, vim.log.levels.WARN)
		end)
		return {}
	end
	return decoded
end

local function realpath(path)
	return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function buffer_context(bufnr)
	bufnr = bufnr or 0
	local name = vim.api.nvim_buf_get_name(bufnr)
	local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
	local project = vim.fs.root(dir, ".git")
	return {
		root = realpath(project or dir),
		project = project and realpath(project) or nil,
	}
end

function M.root(bufnr)
	return buffer_context(bufnr).root
end

function M.project_root(bufnr)
	return buffer_context(bufnr).project
end

local function overrides(key)
	state = state or read_state()
	return (key and state[key]) or {}
end

local function clean(value)
	for _, key in ipairs({ "lsp", "formatters", "linters" }) do
		if value[key] and not next(value[key]) then
			value[key] = nil
		end
	end
	return value
end

local function save(key, value)
	assert(key, "project-tools state key is required")
	value = clean(value)
	-- Merge other scopes changed by concurrent Neovim instances.
	local latest = read_state()
	latest[key] = next(value) and value or nil
	vim.fn.mkdir(vim.fs.dirname(state_path), "p")
	local temporary = state_path .. "." .. vim.fn.getpid() .. ".tmp"
	vim.fn.writefile({ vim.json.encode(latest) }, temporary)
	assert(vim.uv.fs_rename(temporary, state_path))
	state = latest
end

local function value_source(bufnr, section, name, fallback)
	local project = M.project_root(bufnr)
	local project_values = project and (overrides(project)[section] or {}) or {}
	if project_values[name] ~= nil then
		return project_values[name], "project"
	end
	local global_values = overrides(global_key)[section] or {}
	if global_values[name] ~= nil then
		return global_values[name], "global"
	end
	return fallback, "default"
end

function M.lsp_enabled(name, bufnr)
	local enabled = value_source(bufnr, "lsp", name, lsp_defaults[name] == true)
	return enabled
end

local function enable_lsp(name)
	if not wrapped[name] then
		local config = vim.lsp.config[name]
		if not config then
			return
		end
		local original = config.root_dir
		vim.lsp.config(name, {
			root_dir = function(bufnr, on_dir)
				if not M.lsp_enabled(name, bufnr) then
					return
				end
				local function accept(root)
					if vim.api.nvim_buf_is_valid(bufnr) and M.lsp_enabled(name, bufnr) then
						on_dir(root)
					end
				end
				if type(original) == "function" then
					original(bufnr, accept)
				else
					-- A nil root leaves Neovim's root_markers/single-file handling intact.
					accept(original)
				end
			end,
		})
		wrapped[name] = true
	end
	vim.lsp.enable(name)
end

function M.setup_lsp(names)
	for _, name in ipairs(names) do
		lsp_defaults[name] = true
		enable_lsp(name)
	end
	state = state or read_state()
	for _, scope in pairs(state) do
		for name, enabled in pairs(scope.lsp or {}) do
			if enabled then
				enable_lsp(name)
			end
		end
	end
	-- Also covers a client that finishes starting while its toggle is changed.
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("project-tools-lsp", { clear = true }),
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			if client and wrapped[client.name] and not M.lsp_enabled(client.name, event.buf) then
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(event.buf) then
						vim.lsp.buf_detach_client(event.buf, client.id)
					end
					if not next(client.attached_buffers) then
						client:stop()
					end
				end)
			end
		end,
	})
end

local function global_formatters(ft)
	local configured = (overrides(global_key).formatters or {})[ft]
	return vim.deepcopy(configured ~= nil and configured or formatter_defaults[ft] or {})
end

function M.formatters(bufnr)
	local ft = vim.bo[bufnr].filetype
	local project = M.project_root(bufnr)
	local configured = project and (overrides(project).formatters or {})[ft] or nil
	return vim.deepcopy(configured ~= nil and configured or global_formatters(ft))
end

local function default_format_policy(ft)
	return ft == "rust" and "prefer" or "fallback"
end

local function normalize_policy(value, ft)
	if value == false then
		return "never"
	end
	if value == "never" or value == "prefer" or value == "fallback" then
		return value
	end
	return default_format_policy(ft)
end

local function global_format_policy(ft)
	return normalize_policy(overrides(global_key).lsp_format, ft)
end

function M.format_policy(bufnr)
	local ft = vim.bo[bufnr].filetype
	local project = M.project_root(bufnr)
	local value
	if project then
		value = overrides(project).lsp_format
	end
	return value ~= nil and normalize_policy(value, ft) or global_format_policy(ft)
end

function M.setup_formatters(defaults)
	formatter_defaults = vim.deepcopy(defaults)
	local function resolve(bufnr)
		local names = M.formatters(bufnr)
		names.lsp_format = M.format_policy(bufnr)
		return names
	end
	-- The fallback also handles filetypes added through the picker or persisted state.
	local dynamic = { ["_"] = resolve }
	for ft in pairs(defaults) do
		dynamic[ft] = resolve
	end
	return dynamic
end

local function global_autoformat()
	return overrides(global_key).autoformat ~= false
end

function M.autoformat(bufnr)
	local project = M.project_root(bufnr)
	local value
	if project then
		value = overrides(project).autoformat
	end
	if value ~= nil then
		return value
	end
	return global_autoformat()
end

function M.format_on_save(bufnr)
	if not M.autoformat(bufnr) then
		return
	end
	return { timeout_ms = 500, lsp_format = M.format_policy(bufnr) }
end

function M.setup_linters(defaults)
	linter_defaults = defaults
end

local function union(...)
	local result = {}
	for _, list in ipairs({ ... }) do
		for _, name in ipairs(list) do
			if not vim.tbl_contains(result, name) then
				result[#result + 1] = name
			end
		end
	end
	return result
end

local function default_linters(bufnr)
	local ft = vim.bo[bufnr].filetype
	local names = vim.deepcopy(linter_defaults[ft] or {})
	if not linter_defaults[ft] then
		for part in ft:gmatch("[^.]+") do
			vim.list_extend(names, linter_defaults[part] or {})
		end
	end
	if not vim.tbl_contains(names, "typos") then
		names[#names + 1] = "typos"
	end
	return names
end

local function linter_candidates(bufnr)
	local catalog = require("config.project-tool-catalog")
	return catalog.filter("linters", union(default_linters(bufnr), catalog.for_ft("linters", vim.bo[bufnr].filetype)))
end

local function linter_enabled(name, bufnr)
	return value_source(bufnr, "linters", name, vim.tbl_contains(default_linters(bufnr), name))
end

local function linters(bufnr)
	return vim.tbl_filter(function(name)
		return linter_enabled(name, bufnr)
	end, linter_candidates(bufnr))
end

function M.linters(bufnr)
	return vim.deepcopy(linters(bufnr))
end

function M.lint(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
		return
	end
	local root = M.root(bufnr)
	local names = linters(bufnr)
	local generation = generations[root]
	vim.api.nvim_buf_call(bufnr, function()
		require("lint").try_lint(names, {
			wrap_linter = function(linter)
				local parser = linter.parser
				if type(parser) == "function" then
					parser = require("lint.parser").accumulate_chunks(parser)
				end
				local on_done = parser.on_done
				parser.on_done = function(publish, ...)
					on_done(function(diagnostics)
						if generations[root] == generation then
							publish(diagnostics)
						else
							-- Allow nvim-lint to close its pipes without reviving stale diagnostics.
							local current = vim.api.nvim_buf_is_valid(bufnr)
									and vim.diagnostic.get(
										bufnr,
										{ namespace = require("lint").get_namespace(linter.name) }
									)
								or {}
							publish(current)
						end
					end, ...)
				end
				linter.parser = parser
				return linter
			end,
		})
	end)
end

local function reconcile(root)
	local touched = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_loaded(bufnr)
			and vim.bo[bufnr].buftype == ""
			and (not root or M.root(bufnr) == root)
		then
			local buffer_root = M.root(bufnr)
			if not touched[buffer_root] then
				generations[buffer_root] = (generations[buffer_root] or 0) + 1
				touched[buffer_root] = true
			end
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
				if wrapped[client.name] and not M.lsp_enabled(client.name, bufnr) then
					vim.lsp.buf_detach_client(bufnr, client.id)
					if not next(client.attached_buffers) then
						client:stop()
					end
				end
			end
			for _, name in ipairs(linter_candidates(bufnr)) do
				vim.diagnostic.reset(require("lint").get_namespace(name), bufnr)
			end
			M.lint(bufnr)
		end
	end
	-- Re-evaluate already-open buffers through Neovim's native activation mechanism.
	if next(wrapped) then
		vim.lsp.enable(vim.tbl_keys(wrapped))
	end
end

function M.update(root, change)
	local project = vim.deepcopy(overrides(root))
	change(project)
	save(root, project)
	reconcile(root)
end

function M.update_global(change)
	local global = vim.deepcopy(overrides(global_key))
	change(global)
	save(global_key, global)
	reconcile()
end

local function update_scope(scope, root, change)
	if scope == "global" then
		M.update_global(change)
	else
		M.update(root, change)
	end
end

local function executable(command)
	if type(command) ~= "string" then
		return nil
	end
	return vim.fn.executable(command) == 1
end

local function lsp_command(config)
	local command = config.cmd
	return type(command) == "table" and command[1] or command
end

local function source_label(source)
	return source == "project" and "project override" or source == "global" and "global default" or "built-in default"
end

local function scope_source(scope, project_value, global_value)
	if scope == "project" and project_value ~= nil then
		return "project"
	end
	if global_value ~= nil then
		return "global"
	end
	return "default"
end

local function set_nested(value, section, name, enabled, parent)
	value[section] = value[section] or {}
	value[section][name] = enabled
	if enabled == parent then
		value[section][name] = nil
	end
end

-- Runtime state is kept separate from the UI: enabled does not mean running.
function M.inspect(bufnr, requested_scope)
	local context = buffer_context(bufnr)
	local root, project, ft = context.root, context.project, vim.bo[bufnr].filetype
	local scope = (requested_scope == "global" or not project) and "global" or "project"
	local project_state = project and overrides(project) or {}
	local global_state = overrides(global_key)
	local catalog = require("config.project-tool-catalog")
	local view = {
		root = root,
		project = project,
		ft = ft,
		scope = scope,
		lsp = {},
		formatters = {},
		linters = {},
		settings = {},
	}
	local function apply(change)
		update_scope(scope, project, change)
	end
	local function add(kind, item)
		view[kind][#view[kind] + 1] = item
		return item
	end

	local autoformat = M.autoformat(bufnr)
	local autoformat_parent = true
	if scope == "project" then
		autoformat_parent = global_autoformat()
	end
	local autoformat_source = scope_source(scope, project_state.autoformat, global_state.autoformat)
	add("settings", {
		name = "Autoformat on save",
		enabled = autoformat,
		available = true,
		status = autoformat and "on" or "off",
		detail = source_label(autoformat_source),
		source = autoformat_source,
		toggle = function()
			apply(function(value)
				local enabled = not autoformat
				value.autoformat = enabled
				if enabled == autoformat_parent then
					value.autoformat = nil
				end
			end)
		end,
	})

	local policy = M.format_policy(bufnr)
	local policy_parent = scope == "project" and global_format_policy(ft) or default_format_policy(ft)
	local policy_source = scope_source(scope, project_state.lsp_format, global_state.lsp_format)
	local next_policy = ({ fallback = "prefer", prefer = "never", never = "fallback" })[policy]
	add("settings", {
		name = "LSP formatting",
		enabled = policy ~= "never",
		available = true,
		status = policy,
		detail = (policy == "fallback" and "external first" or policy == "prefer" and "LSP first" or "disabled")
			.. " · "
			.. source_label(policy_source),
		source = policy_source,
		toggle = function()
			apply(function(value)
				value.lsp_format = next_policy
				if next_policy == policy_parent then
					value.lsp_format = nil
				end
			end)
		end,
	})
	view.autoformat = autoformat
	view.lsp_format = policy

	local attached = {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		attached[client.name] = client
	end
	for _, name in ipairs(require("config.tools").lsp) do
		local config = vim.lsp.config[name]
		if config and ((config.filetypes and vim.tbl_contains(config.filetypes, ft)) or attached[name]) then
			local enabled = value_source(bufnr, "lsp", name, lsp_defaults[name] == true)
			local parent = lsp_defaults[name] == true
			if scope == "project" and (global_state.lsp or {})[name] ~= nil then
				parent = global_state.lsp[name]
			end
			local source = scope_source(scope, (project_state.lsp or {})[name], (global_state.lsp or {})[name])
			local available = executable(lsp_command(config))
			local client = attached[name]
			local formatting = client
					and client:supports_method(vim.lsp.protocol.Methods.textDocument_formatting, bufnr)
				or false
			local diagnostics = client and (catalog.lsp_roles[name] or {}).diagnostics == true or false
			local capabilities = {}
			if formatting then
				capabilities[#capabilities + 1] = "formatting"
			end
			if diagnostics then
				capabilities[#capabilities + 1] = "diagnostics"
			end
			local status = client and "running"
				or (available == false and "missing executable")
				or (enabled and "enabled · not attached")
				or (available and "available" or "availability unknown")
			add("lsp", {
				name = name,
				enabled = enabled,
				available = available,
				status = status,
				detail = (#capabilities > 0 and table.concat(capabilities, " + ") .. " · " or "")
					.. source_label(source),
				source = source,
				running = client ~= nil,
				formatting = formatting,
				diagnostics = diagnostics,
				toggle = function()
					apply(function(value)
						set_nested(value, "lsp", name, not enabled, parent)
						enable_lsp(name)
					end)
				end,
			})
		end
	end

	local selected = M.formatters(bufnr)
	local global_selected = global_formatters(ft)
	local parent_formatters = scope == "project" and global_selected or formatter_defaults[ft] or {}
	local project_formatters = (project_state.formatters or {})[ft]
	local global_formatters_override = (global_state.formatters or {})[ft]
	local formatter_source = scope_source(scope, project_formatters, global_formatters_override)
	local conform = require("conform")
	local to_run, uses_lsp = conform.list_formatters_to_run(bufnr)
	view.uses_lsp = uses_lsp
	local scheduled = {}
	for _, info in ipairs(to_run) do
		scheduled[info.name] = true
	end
	local candidates = catalog.filter(
		"formatters",
		union(selected, global_selected, formatter_defaults[ft] or {}, catalog.for_ft("formatters", ft))
	)
	local function set_formatters(value, names)
		value.formatters = value.formatters or {}
		value.formatters[ft] = names
		if vim.deep_equal(names, parent_formatters) then
			value.formatters[ft] = nil
		end
	end
	for _, name in ipairs(candidates) do
		local index = vim.fn.index(selected, name)
		local info = conform.get_formatter_info(name, bufnr)
		local status = not info.available and "unavailable"
			or (index >= 0 and (scheduled[name] and "ready" or "skipped · LSP preferred"))
			or "available"
		local item = add("formatters", {
			name = name,
			enabled = index >= 0,
			available = info.available,
			status = status,
			detail = (index >= 0 and ("step " .. index + 1 .. " · ") or "")
				.. source_label(formatter_source)
				.. (info.available_msg and (" · " .. info.available_msg) or ""),
			source = formatter_source,
			step = index >= 0 and index + 1 or nil,
			toggle = function()
				apply(function(value)
					local names = vim.deepcopy(selected)
					if index >= 0 then
						table.remove(names, index + 1)
					else
						local position = #names + 1
						local parent_index = vim.fn.index(parent_formatters, name)
						if parent_index >= 0 then
							for active_index, active in ipairs(names) do
								local active_parent_index = vim.fn.index(parent_formatters, active)
								if active_parent_index > parent_index then
									position = active_index
									break
								end
							end
						end
						table.insert(names, position, name)
					end
					set_formatters(value, names)
				end)
			end,
		})
		if index >= 0 then
			item.move = function(offset)
				local target = index + 1 + offset
				if target < 1 or target > #selected then
					return
				end
				apply(function(value)
					local names = vim.deepcopy(selected)
					local formatter = table.remove(names, index + 1)
					table.insert(names, target, formatter)
					set_formatters(value, names)
				end)
			end
		end
	end

	local lint = require("lint")
	local running = lint.get_running(bufnr)
	for _, name in ipairs(linter_candidates(bufnr)) do
		local enabled = linter_enabled(name, bufnr)
		local default = vim.tbl_contains(default_linters(bufnr), name)
		local parent = default
		if scope == "project" and (global_state.linters or {})[name] ~= nil then
			parent = global_state.linters[name]
		end
		local source = scope_source(scope, (project_state.linters or {})[name], (global_state.linters or {})[name])
		local ok, command = pcall(function()
			return vim.api.nvim_buf_call(bufnr, function()
				local linter = lint.linters[name]
				linter = type(linter) == "function" and linter() or linter
				return type(linter.cmd) == "function" and linter.cmd() or linter.cmd
			end)
		end)
		local available = ok and executable(command) or false
		local status = vim.tbl_contains(running, name) and "running"
			or (not available and "missing executable")
			or (enabled and "ready · on read/save" or "available")
		add("linters", {
			name = name,
			enabled = enabled,
			available = available,
			status = status,
			detail = source_label(source),
			source = source,
			toggle = function()
				apply(function(value)
					set_nested(value, "linters", name, not enabled, parent)
				end)
			end,
		})
	end

	local running_lsps, lsp_formatters, lsp_diagnostics, external_formatters, external_linters = {}, {}, {}, {}, {}
	for _, item in ipairs(view.lsp) do
		if item.running then
			running_lsps[#running_lsps + 1] = item.name
		end
		if item.running and item.formatting then
			lsp_formatters[#lsp_formatters + 1] = item.name
		end
		if item.running and item.diagnostics then
			lsp_diagnostics[#lsp_diagnostics + 1] = item.name
		end
	end
	for _, item in ipairs(view.formatters) do
		if item.enabled and item.available then
			external_formatters[#external_formatters + 1] = item.name
		end
	end
	for _, item in ipairs(view.linters) do
		if item.name ~= "typos" and item.enabled and item.available then
			external_linters[#external_linters + 1] = item.name
		end
	end
	local format_lsp = #lsp_formatters > 0
	local diagnostics_lsp = #lsp_diagnostics > 0
	local headline, advice, level
	if #view.lsp == 0 then
		headline = "No LSP configured for this filetype"
		level = #external_formatters > 0 and #external_linters > 0 and "ok" or "warn"
		advice = (#external_formatters > 0 and "formatter ready" or "formatter needed")
			.. " · "
			.. (#external_linters > 0 and "linter ready" or "linter needed")
	elseif #running_lsps == 0 then
		headline = "No LSP attached to this buffer"
		level = "warn"
		advice = "Check enabled servers; external tools remain independent"
	elseif format_lsp and diagnostics_lsp then
		headline = "LSP covers formatting + diagnostics"
		level = "ok"
		if policy == "never" then
			advice = "LSP is sufficient; formatting is currently disabled"
		elseif #external_formatters > 0 or #external_linters > 0 then
			advice = "External tools are optional project-specific extras"
		else
			advice = "You can rely on the LSP for both"
		end
	elseif diagnostics_lsp then
		headline = "LSP covers diagnostics, not formatting"
		level = #external_formatters > 0 and "ok" or "warn"
		advice = #external_formatters > 0 and "Keep the formatter enabled" or "Enable an available formatter"
	elseif format_lsp then
		headline = "LSP covers formatting, not diagnostics"
		level = #external_linters > 0 and "ok" or "warn"
		advice = #external_linters > 0 and "Keep the linter enabled" or "Enable an available linter"
	else
		headline = "LSP does not cover formatting or diagnostics"
		level = #external_formatters > 0 and #external_linters > 0 and "ok" or "warn"
		advice = (#external_formatters > 0 and "formatter ready" or "formatter needed")
			.. " · "
			.. (#external_linters > 0 and "linter ready" or "linter needed")
	end
	view.coverage = {
		headline = headline,
		advice = advice,
		level = level,
		formatters = lsp_formatters,
		diagnostics = lsp_diagnostics,
	}
	view.reset = function()
		if scope == "global" then
			save(global_key, {})
			reconcile()
		else
			save(project, {})
			reconcile(project)
		end
	end
	return view
end

function M.pick(bufnr, scope, show_missing)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.api.nvim_buf_is_valid(bufnr) then
		require("config.project-tools-picker").open(bufnr, scope, show_missing)
	end
end

return M
