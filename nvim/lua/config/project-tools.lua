local M = {}
local state_path = vim.fn.stdpath("state") .. "/project-tools.json"
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
	local decoded = vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
	assert(type(decoded) == "table", "Invalid project-tools state")
	return decoded
end

function M.root(bufnr)
	bufnr = bufnr or 0
	local name = vim.api.nvim_buf_get_name(bufnr)
	local dir = name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd()
	local root = vim.fs.root(dir, ".git") or dir
	return vim.uv.fs_realpath(root) or vim.fs.normalize(root)
end

local function overrides(root)
	state = state or read_state()
	return state[root] or {}
end

local function save(root, value)
	for _, key in ipairs({ "lsp", "formatters", "linters" }) do
		if value[key] and not next(value[key]) then
			value[key] = nil
		end
	end
	-- Merge other repositories' changes from concurrent Neovim instances.
	local latest = read_state()
	latest[root] = next(value) and value or nil
	vim.fn.mkdir(vim.fs.dirname(state_path), "p")
	local temporary = state_path .. "." .. vim.fn.getpid() .. ".tmp"
	vim.fn.writefile({ vim.json.encode(latest) }, temporary)
	assert(vim.uv.fs_rename(temporary, state_path))
	state = latest
end

function M.lsp_enabled(name, bufnr)
	local value = (overrides(M.root(bufnr)).lsp or {})[name]
	if value ~= nil then
		return value
	end
	return lsp_defaults[name] == true
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
	for _, repo in pairs(state) do
		for name, enabled in pairs(repo.lsp or {}) do
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

function M.formatters(bufnr)
	local ft = vim.bo[bufnr].filetype
	return vim.deepcopy((overrides(M.root(bufnr)).formatters or {})[ft] or formatter_defaults[ft] or {})
end

function M.format_policy(bufnr)
	local repo = overrides(M.root(bufnr))
	if repo.lsp_format == false then
		return "never"
	end
	return vim.bo[bufnr].filetype == "rust" and "prefer" or "fallback"
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

function M.format_on_save(bufnr)
	if overrides(M.root(bufnr)).autoformat == false then
		return
	end
	return { timeout_ms = 500, lsp_format = M.format_policy(bufnr) }
end

function M.setup_linters(defaults)
	linter_defaults = defaults
end

local function linters(bufnr)
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

function M.lint(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
		return
	end
	local root = M.root(bufnr)
	local disabled = overrides(root).linters or {}
	local names = vim.tbl_filter(function(name)
		return disabled[name] ~= false
	end, linters(bufnr))
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
	generations[root] = (generations[root] or 0) + 1
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" and M.root(bufnr) == root then
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
				if wrapped[client.name] and not M.lsp_enabled(client.name, bufnr) then
					vim.lsp.buf_detach_client(bufnr, client.id)
					if not next(client.attached_buffers) then
						client:stop()
					end
				end
			end
			for _, name in ipairs(linters(bufnr)) do
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
	local repo = vim.deepcopy(overrides(root))
	change(repo)
	save(root, repo)
	reconcile(root)
end

local function select(items, title, callback)
	require("snacks").picker.select(items, {
		prompt = title,
		format_item = function(item)
			return item.text
		end,
	}, callback)
end

function M.pick(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local root, ft = M.root(bufnr), vim.bo[bufnr].filetype
	local repo = overrides(root)
	local items = {}
	local function toggle(label, enabled, change)
		items[#items + 1] = {
			text = (enabled and "[x] " or "[ ] ") .. label,
			change = change,
		}
	end
	toggle("Autoformat on save", repo.autoformat ~= false, function(value)
		value.autoformat = nil
		if repo.autoformat ~= false then
			value.autoformat = false
		end
	end)
	toggle("LSP formatting (fallback / Rust preferred)", repo.lsp_format ~= false, function(value)
		value.lsp_format = nil
		if repo.lsp_format ~= false then
			value.lsp_format = false
		end
	end)
	local servers = {}
	for name in pairs(lsp_defaults) do
		servers[name] = true
	end
	for _, path in ipairs(vim.api.nvim_get_runtime_file("lsp/*.lua", true)) do
		servers[vim.fn.fnamemodify(path, ":t:r")] = true
	end
	for name in vim.spairs(servers) do
		local config = vim.lsp.config[name]
		if config and (not config.filetypes or vim.tbl_contains(config.filetypes, ft)) then
			local enabled = M.lsp_enabled(name, bufnr)
			toggle("LSP · " .. name, enabled, function(value)
				value.lsp = value.lsp or {}
				local new = not enabled
				value.lsp[name] = new
				if new == (lsp_defaults[name] == true) then
					value.lsp[name] = nil
				end
				enable_lsp(name)
			end)
		end
	end
	local selected = M.formatters(bufnr)
	local candidates = vim.deepcopy(selected)
	for _, name in ipairs(formatter_defaults[ft] or {}) do
		if not vim.tbl_contains(candidates, name) then
			candidates[#candidates + 1] = name
		end
	end
	local function set_formatters(value, names)
		value.formatters = value.formatters or {}
		value.formatters[ft] = names
		if vim.deep_equal(names, formatter_defaults[ft] or {}) then
			value.formatters[ft] = nil
		end
	end
	for _, name in ipairs(candidates) do
		local index = vim.fn.index(selected, name)
		toggle("Formatter · " .. name .. (index >= 0 and (" · step " .. index + 1) or ""), index >= 0, function(value)
			local names = vim.deepcopy(selected)
			if index >= 0 then
				table.remove(names, index + 1)
			else
				local defaults = formatter_defaults[ft] or {}
				local position = #names + 1
				local default_index = vim.fn.index(defaults, name)
				if default_index >= 0 then
					for i, active in ipairs(names) do
						if vim.fn.index(defaults, active) > default_index then
							position = i
							break
						end
					end
				end
				table.insert(names, position, name)
			end
			set_formatters(value, names)
		end)
	end
	for _, name in ipairs(linters(bufnr)) do
		local enabled = (repo.linters or {})[name] ~= false
		toggle("Linter · " .. name, enabled, function(value)
			value.linters = value.linters or {}
			value.linters[name] = nil
			if enabled then
				value.linters[name] = false
			end
		end)
	end
	items[#items + 1] = { text = "Add formatter to " .. ft .. "…", add = true }
	items[#items + 1] = { text = "Reset repository to defaults", reset = true }
	select(items, "Project tools · " .. root .. " · " .. ft, function(item)
		if not item then
			return
		end
		if item.add then
			local available = {}
			for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/conform/formatters/*.lua", true)) do
				local name = vim.fn.fnamemodify(path, ":t:r")
				if not vim.tbl_contains(selected, name) then
					available[#available + 1] = { text = name }
				end
			end
			table.sort(available, function(a, b)
				return a.text < b.text
			end)
			select(available, "Append formatter · " .. ft, function(choice)
				if choice then
					M.update(root, function(value)
						selected[#selected + 1] = choice.text
						set_formatters(value, selected)
					end)
				end
				M.pick(bufnr)
			end)
			return
		end
		if item.reset then
			save(root, {})
			reconcile(root)
		else
			M.update(root, item.change)
		end
		M.pick(bufnr)
	end)
end

return M
