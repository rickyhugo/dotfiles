local M = {}
local module_source = debug.getinfo(1, "S").source:gsub("^@", "")
local terminal = "com.superlogical.terminal.shell"
local theme = { background = "#1e1e2e", foreground = "#cdd6f4", scheme = "dark" }
local card = { columns = 100, rows = 30, max_width = 0.9, max_height = 0.85 }
local opening_bounds = { 0.2, 0.15, 0.6, 0.7 }
local tick_seconds = 0.1

local function exec(argv, options)
	local result, err = rex.exec(argv, options)
	assert(result, err)
	return result
end

local function failure(result, message)
	if result.stderr and result.stderr ~= "" then
		return message .. ": " .. result.stderr
	end
	return message .. " (exit " .. tostring(result.code) .. ")"
end

local function rex_error_code(err)
	return tostring(err):match("code=([%w_]+)")
end

local function roots_snapshot(roots)
	assert(type(roots) == "table", "Picker config requires a roots list")
	local copy = {}
	for _, root in ipairs(roots) do
		assert(type(root) == "string" and root ~= "" and not root:find("%z"), "Invalid picker root")
		if root == "~" or root:sub(1, 2) == "~/" then
			root = assert(os.getenv("HOME"), "HOME is required for tilde roots") .. root:sub(2)
		end
		assert(root:sub(1, 1) == "/", "Picker roots must be absolute paths or start with ~/")
		copy[#copy + 1] = root
	end
	return copy
end

local function physical_directory(path)
	local result = exec({
		"/bin/sh",
		"-c",
		'[ ! -d "$1" ] || { cd "$1" && pwd -P; }',
		"rex-picker",
		path,
	})
	assert(result.code == 0, failure(result, "Cannot read picker directory " .. path))
	return (result.stdout:gsub("\n$", ""))
end

local function script_path(name)
	local directory = assert(module_source:match("^(.*/)"), "Cannot locate the picker scripts")
	if directory:sub(1, 1) ~= "/" then
		directory = physical_directory(directory)
		assert(directory ~= "", "Cannot locate the picker scripts")
	end
	return directory:gsub("/$", "") .. "/" .. name
end

local function display(text)
	return (
		text:gsub("\\", "\\\\"):gsub("[%z\1-\31\127]", function(char)
			return string.format("\\x%02x", char:byte())
		end)
	)
end

local function hex(text)
	return (text:gsub(".", function(char)
		return string.format("%02x", char:byte())
	end))
end

local function unhex(text)
	assert(#text % 2 == 0 and not text:find("[^0-9a-f]"), "Picker returned an invalid selection")
	return (text:gsub("..", function(pair)
		return string.char(tonumber(pair, 16))
	end))
end

local function shell_quote(text)
	-- Adjacent shell quotes keep literal braces from becoming fzf placeholders.
	return "'" .. text:gsub("'", "'\\''"):gsub("{", "{''") .. "'"
end

local function attach_all()
	-- session.view requires access to the sessions on this connection.
	local listed, err = rex.call("session.attach_all", { event_scope = "session" })
	assert(listed, err)
	return listed.sessions or {}
end

local function shell_layout()
	return rex.layout.block({ flavor = terminal })
end

local function repository_labels(entries)
	local labels, parts, starts = {}, {}, {}
	for index, entry in ipairs(entries) do
		parts[index] = {}
		for part in entry.path:gmatch("[^/]+") do
			parts[index][#parts[index] + 1] = part
		end
		starts[index] = #parts[index]
		labels[index] = entry.label
	end
	while true do
		local counts, expanded = {}, false
		for _, label in ipairs(labels) do
			counts[label] = (counts[label] or 0) + 1
		end
		for index, label in ipairs(labels) do
			if counts[label] > 1 and starts[index] > 1 then
				starts[index] = starts[index] - 1
				labels[index] = table.concat(parts[index], "/", starts[index])
				expanded = true
			end
		end
		if not expanded then
			return labels
		end
	end
end

local function git_root(cwd)
	if type(cwd) ~= "string" or cwd:sub(1, 1) ~= "/" or cwd:find("%z") then
		return
	end
	local result = exec({ "git", "-C", cwd, "rev-parse", "--path-format=absolute", "--show-toplevel" })
	if result.code == 0 then
		local root = result.stdout:gsub("\n$", "")
		if root ~= "" then
			return root
		end
	end
end

local function block_cwd(session_id, block_id)
	local process, err = rex.call("block.method", {
		session_id = session_id,
		block_id = block_id,
		method = "process",
		args = {},
	})
	assert(process or rex_error_code(err) == "not_found", err)
	if not process then
		return
	end
	local cwd = process.foreground and process.foreground.cwd
	if type(cwd) ~= "string" or cwd == "" then
		cwd = process.child and process.child.cwd
	end
	return type(cwd) == "string" and cwd or nil
end

local function repository_terminal(root)
	local status, status_err = rex.call("server.status", {})
	assert(status, status_err)
	assert(type(status.host_id) == "string" and status.host_id ~= "", "Cannot identify the local Rex host")
	local ordered, roots = {}, { [root] = root }
	for _, session in ipairs(attach_all()) do
		if session.session_id == rex.session_id then
			table.insert(ordered, 1, session)
		else
			ordered[#ordered + 1] = session
		end
	end
	for _, session in ipairs(ordered) do
		local view, view_err = rex.call("session.view", { session_id = session.session_id })
		assert(view or rex_error_code(view_err) == "session_not_found", view_err)
		for _, window in ipairs(view and view.windows or {}) do
			for _, layer in ipairs(window.layers or {}) do
				if layer.kind == "tiled" then
					for _, block in ipairs(layer.blocks or {}) do
						if
							block.flavor == terminal
							and block.host_id == status.host_id
							and block.block_id ~= rex.block_id
						then
							local cwd = block_cwd(session.session_id, block.block_id)
							if cwd then
								if roots[cwd] == nil then
									roots[cwd] = git_root(cwd) or false
								end
								if roots[cwd] == root then
									return {
										session_id = session.session_id,
										window_id = window.window_id,
										block_id = block.block_id,
									}
								end
							end
						end
					end
				end
			end
		end
	end
end

local function project_view(view, notice)
	local labels, rows = repository_labels(view.entries), {}
	for position, entry in ipairs(view.entries) do
		rows[position] = { id = entry.path, text = labels[position] }
	end
	return { rows = rows, notice = notice or view.notice }
end

local stale = " Ctrl-R refreshes this list."

local sources = {
	projects = {
		action = "project_picker",
		title = "Open Project Session",
		label = "Projects",
		keywords = "project repo git picker",
		prompt = "project> ",
		help = "Enter: open or reuse its session   Ctrl-R: rescan   Esc: close",
		empty = "No Git repositories found under the configured roots",
		refresh_on_load = true,
		valid_id = function(id)
			return id:sub(1, 1) == "/"
		end,
		load = function(invocation, fresh)
			local roots = roots_snapshot(invocation.roots)
			local index = require("repository-index")
			local prior = index.cached(roots)
			if not fresh then
				return project_view(prior)
			end
			local view, err = index.open(roots, true)
			return project_view(view or prior, not view and ("Refresh failed. " .. err) or nil)
		end,
		select = function(choice)
			local checked = exec({
				"/bin/sh",
				"-c",
				'[ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ] && { [ -f "$1/.git/HEAD" ] || [ -f "$1/.git" ]; }'
					.. ' && cd "$1" && pwd -P',
				"rex-picker-selected",
				choice.id,
			})
			local root = checked.code == 0 and git_root(choice.id)
			if not root or root ~= checked.stdout:gsub("\n$", "") then
				return nil, "Repository is no longer available." .. stale
			end
			local existing = repository_terminal(root)
			if existing then
				local focused, focus_err = rex.call("session.focus_block", {
					session_id = existing.session_id,
					block_id = existing.block_id,
				})
				assert(focused or rex_error_code(focus_err) == "not_found", focus_err)
				rex.client.queue("session.select", { session_id = existing.session_id, window_id = existing.window_id })
				return true
			end
			local session, err = rex.call("session.create", {
				label = choice.text,
				initial_windows = {
					{
						window_label = "Terminal",
						layout = rex.layout.block({ flavor = terminal, options = { cwd = choice.id } }),
					},
				},
			})
			assert(session, err)
			rex.client.queue("session.select", { session_id = session.session_id })
			return true
		end,
	},
	sessions = {
		action = "session_picker",
		title = "Switch Session",
		label = "Sessions",
		keywords = "session switch picker",
		prompt = "session> ",
		help = "Enter: switch   Ctrl-R: refresh   Esc: close",
		empty = "No Rex sessions",
		valid_id = function(id)
			return id:match("^session:[%w%-]+$") ~= nil
		end,
		load = function()
			local listed, err = rex.call("session.list", {})
			assert(listed, err)
			local labels, counts, rows = {}, {}, {}
			for position, session in ipairs(listed.sessions or {}) do
				local label = session.label
				if type(label) ~= "string" or label == "" then
					label = "Untitled"
				end
				labels[position] = label
				counts[label] = (counts[label] or 0) + 1
			end
			for position, session in ipairs(listed.sessions or {}) do
				local text = labels[position]
				if counts[text] > 1 then
					text = text .. "  #" .. session.session_id:sub(-8)
				end
				if session.session_id == rex.session_id then
					text = text .. "  (current)"
				end
				rows[position] = { id = session.session_id, text = text }
			end
			return { rows = rows }
		end,
		select = function(choice)
			attach_all()
			local view, err = rex.call("session.view", { session_id = choice.id })
			if not view then
				assert(rex_error_code(err) == "session_not_found", err)
				return nil, "That session no longer exists." .. stale
			end
			if #(view.windows or {}) == 0 then
				local window, window_err = rex.call("session.new_window", {
					session_id = choice.id,
					window_label = "Terminal",
					layout = shell_layout(),
				})
				assert(window, window_err)
			end
			rex.client.queue("session.select", { session_id = choice.id })
			return true
		end,
	},
}

local function records(source, view)
	local status = view.notice or (#view.rows == 0 and source.empty) or ""
	local lines = { "status\t" .. display(status) .. "\t" }
	for _, row in ipairs(view.rows) do
		lines[#lines + 1] = hex(row.id) .. "\t" .. display(row.text) .. "\t" .. hex(row.text)
	end
	return table.concat(lines, "\0") .. "\0"
end

local function decode(source, row)
	local encoded_id, shown, encoded_text = row:match("^([^\t]+)\t([^\t]*)\t([^\t]*)$")
	assert(encoded_id, "Picker returned an invalid selection")
	local id, text = unhex(encoded_id), unhex(encoded_text)
	assert(
		source.valid_id(id) and not id:find("%z") and not text:find("%z") and text ~= "" and display(text) == shown,
		"Picker returned an invalid selection"
	)
	return { id = id, text = text }
end

local function reload_command(invocation)
	local args, err = rex.json.encode({ source = invocation.source, roots = invocation.roots })
	assert(args, err)
	local argv = { "rex", "--autostart=false", "do", script_path("picker-rows.lua"), "--args", args }
	for position, arg in ipairs(argv) do
		argv[position] = shell_quote(arg)
	end
	return table.concat(argv, " ")
end

local function valid_dimension(length)
	return type(length) == "number" and length > 0 and length % 1 == 0
end

local function round(fraction)
	return math.floor(fraction * 10000 + 0.5) / 10000
end

function M.fitted_bounds(bounds, viewport)
	local width = math.min(card.columns / viewport.columns, card.max_width)
	local height = math.min(card.rows / viewport.rows, card.max_height)
	local fitted = { round((1 - width) / 2), round((1 - height) / 2), round(width), round(height) }
	for position = 1, 4 do
		if math.abs(fitted[position] - bounds[position]) > 0.002 then
			return fitted
		end
	end
end

local function own_layer()
	local view, err = rex.call("session.view", { session_id = rex.session_id })
	assert(view, err)
	for _, window in ipairs(view.windows or {}) do
		for _, layer in ipairs(window.layers or {}) do
			for _, block in ipairs(layer.kind == "floating" and layer.blocks or {}) do
				if block.block_id == rex.block_id then
					return window, layer
				end
			end
		end
	end
	error("Cannot locate the picker layer in its Rex session", 0)
end

local function app_size(block_id, client_id)
	local size, err = rex.call("block.method", {
		session_id = rex.session_id,
		block_id = block_id,
		method = "size",
		args = {},
	})
	assert(size, err)
	for _, desired in ipairs(size.desired or {}) do
		if desired.client_id == client_id and valid_dimension(desired.columns) and valid_dimension(desired.rows) then
			return desired
		end
	end
end

local function block_rect(node, block_id)
	if not node then
		return
	end
	if node.block_id == block_id then
		return node.rect
	end
	if node.split then
		return block_rect(node.split.before, block_id) or block_rect(node.split.after, block_id)
	end
end

local function window_viewport(window, client_id)
	local has_terminal = false
	for _, layer in ipairs(window.layers or {}) do
		for _, block in ipairs(layer.kind == "tiled" and layer.blocks or {}) do
			if
				block.flavor == terminal and (not window.zoomed_block_id or window.zoomed_block_id == block.block_id)
			then
				has_terminal = true
				local rect = window.zoomed_block_id and { 0, 0, 1, 1 } or block_rect(layer.layout, block.block_id)
				assert(rect and rect[3] > 0 and rect[4] > 0, "Cannot measure the tiled terminal's layout rectangle")
				local desired = app_size(block.block_id, client_id)
				if desired then
					return { columns = desired.columns / rect[3], rows = desired.rows / rect[4] }
				end
			end
		end
	end
	assert(has_terminal, "Cannot size the picker. Open it in a window with a visible tiled terminal")
end

local function geometry(client_id)
	if not (rex.session_id and rex.block_id) then
		return function() end
	end
	attach_all()
	return function()
		local window, layer = own_layer()
		local viewport = window_viewport(window, client_id)
		local bounds = viewport and M.fitted_bounds(layer.bounds, viewport)
		if bounds then
			local resized, err = rex.call(
				"session.resize_layer",
				{ session_id = rex.session_id, layer_id = layer.layer_id, bounds = bounds }
			)
			assert(resized, err)
		end
	end
end

local function run_fzf(argv, stdin, fit)
	local handle, start_err = rex.exec.start(argv, {
		stdin = stdin,
		env = { FZF_DEFAULT_OPTS = "", FZF_DEFAULT_OPTS_FILE = "" },
	})
	assert(handle, "Cannot start fzf: " .. tostring(start_err))
	local ok, result = pcall(function()
		while true do
			fit()
			local result, wait_err = handle:wait(tick_seconds)
			if result then
				return result
			end
			assert(wait_err == "timeout", "Waiting for fzf failed: " .. tostring(wait_err))
		end
	end)
	if not ok then
		pcall(handle.kill, handle)
		error(result, 0)
	end
	return result
end

local function choose(source, view, query, command, fit)
	local argv = {
		"fzf",
		"--read0",
		"--print0",
		"--print-query",
		"--layout=reverse",
		"--border=rounded",
		"--border-label= " .. source.label .. " ",
		"--padding=1,2",
		"--color=bg:#1e1e2e",
		"--delimiter=\t",
		"--with-nth=2",
		"--nth=1",
		"--no-multi",
		"--info=hidden",
		"--no-separator",
		"--prompt=" .. source.prompt,
		"--header=" .. source.help,
		"--header-lines=1",
		"--with-shell=/bin/sh -c",
	}
	if source.refresh_on_load then
		argv[#argv + 1] = "--bind"
		argv[#argv + 1] = "load:unbind(load)+reload-sync:" .. command
	end
	for _, arg in ipairs({ "--bind", "ctrl-r:reload-sync:" .. command, "--query", query }) do
		argv[#argv + 1] = arg
	end
	local result = run_fzf(argv, records(source, view), fit)
	if result.code == 1 or result.code == 130 then
		return
	end
	assert(result.code == 0, failure(result, "Picker failed"))
	local returned_query, row = result.stdout:match("^([^%z]*)%z(.*)$")
	assert(row and row:sub(-1) == "\0" and not row:sub(1, -2):find("%z"), "Picker returned an invalid selection")
	local choice = decode(source, row:sub(1, -2))
	choice.query = returned_query
	return choice
end

local function app_client(ctx, requested)
	local listed, err = rex.call("client.list", { kinds = { "app" } })
	assert(listed, err)
	local apps, connected = {}, {}
	for _, client in ipairs(listed.clients or {}) do
		if client.connection_state ~= "lost" then
			apps[#apps + 1] = client.client_id
			connected[client.client_id] = true
		end
	end
	if requested ~= nil then
		assert(connected[requested], "No connected Rex app has client ID " .. tostring(requested))
		return requested
	end
	if ctx.client_id and connected[ctx.client_id] then
		return ctx.client_id
	end
	if #apps == 1 then
		return apps[1]
	end
	error("Cannot tell which Rex app to use. Press the shortcut in that app, or pass client_id=<app client ID>", 0)
end

local function picker_window(session_id, block_id)
	attach_all()
	local view, err = rex.call("session.view", { session_id = session_id })
	assert(view, err)
	local windows = view.windows or {}
	if #windows == 0 then
		local window, window_err = rex.call("session.new_window", {
			session_id = session_id,
			window_label = "Terminal",
			layout = shell_layout(),
		})
		assert(window, window_err)
		return window.window_id
	end
	for _, window in ipairs(windows) do
		for _, layer in ipairs(window.layers or {}) do
			for _, block in ipairs(layer.blocks or {}) do
				if block_id and block.block_id == block_id then
					return window.window_id
				end
			end
		end
	end
	return view.active_window_id or windows[1].window_id
end

function M.setup(config)
	local roots = roots_snapshot(config.roots)
	local runner = script_path("picker-runner.lua")
	for name, source in pairs(sources) do
		rex.action({
			name = source.action,
			title = source.title,
			category = "Session",
			keywords = source.keywords,
			args = { client_id = "string?" },
			run = function(ctx, args)
				assert(ctx.session_id, "Open the picker from a Rex session")
				local client = app_client(ctx, args and args.client_id)
				local snapshot, encode_err = rex.json.encode({ source = name, roots = roots, client_id = client })
				assert(snapshot, encode_err)
				local layer, err = rex.session.new_layer({
					session_id = ctx.session_id,
					window_id = picker_window(ctx.session_id, ctx.block_id),
					bounds = opening_bounds,
					focus = true,
					layout = {
						block = {
							flavor = terminal,
							label = source.label,
							options = {
								command = { "rex", "-C", client, "do", runner, "--args", snapshot },
								theme = theme,
							},
						},
					},
				})
				assert(layer, err)
				return layer
			end,
		})
	end
end

function M.run(invocation)
	local source = assert(sources[invocation.source], "Unknown picker source")
	local command = reload_command(invocation)
	local fit = geometry(invocation.client_id)
	local view, query = source.load(invocation, false), ""
	while true do
		local choice = choose(source, view, query, command, fit)
		if not choice then
			return
		end
		query = choice.query
		local selected, notice = source.select(choice)
		if selected then
			return
		end
		view = source.load(invocation, false)
		view.notice = notice
	end
end

function M.rows(invocation)
	local source = assert(sources[invocation.source], "Unknown picker source")
	io.write(records(source, source.load(invocation, true)))
end

return M
