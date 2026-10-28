local M = {}
local module_source = debug.getinfo(1, "S").source:gsub("^@", "")
local terminal = "com.superlogical.terminal.shell"
local card_shape = { columns = 52, rows = 30 }

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

local function sessions()
	local result, err = rex.call("session.list", {})
	assert(result, err)
	local entries = {}
	for _, session in ipairs(result.sessions) do
		local label = session.label
		if not label or label == "" then
			label = "Untitled"
		end
		entries[#entries + 1] = { session_id = session.session_id, label = label }
	end
	table.sort(entries, function(a, b)
		if a.label == b.label then
			return a.session_id < b.session_id
		end
		return a.label < b.label
	end)
	return entries
end

local function display(text)
	return (
		text:gsub("\\", "\\\\"):gsub("[%z\1-\31\127]", function(char)
			return string.format("\\x%02x", char:byte())
		end)
	)
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

local function repository_records(view, notice)
	local records = {
		"status\t" .. display(
			notice
				or view.notice
				or (
					#view.entries == 0 and "No Git repositories found under the configured roots"
					or "Ctrl-R refreshes repositories"
				)
		) .. "\t",
	}
	local labels = repository_labels(view.entries)
	for position, entry in ipairs(view.entries) do
		local label = labels[position]
		records[#records + 1] = hex(entry.path) .. "\t" .. display(label) .. "\t" .. hex(label)
	end
	return records
end

local function repository_selection(row)
	local encoded_path, shown, encoded_label = row:match("^([^\t]+)\t([^\t]*)\t([^\t]*)$")
	assert(encoded_path, "Picker returned an invalid selection")
	local path, label = unhex(encoded_path), unhex(encoded_label)
	assert(
		path:sub(1, 1) == "/"
			and not path:find("%z")
			and not label:find("%z")
			and label ~= ""
			and display(label) == shown,
		"Picker returned an invalid selection"
	)
	return { entry = { path = path }, label = label }
end

local function shell_quote(text)
	-- Adjacent shell quotes keep literal braces from becoming fzf placeholders.
	return "'" .. text:gsub("'", "'\\''"):gsub("{", "{''") .. "'"
end

local function reload_command(roots)
	local directory = assert(module_source:match("^(.*/)"), "Cannot locate repository rows adapter")
	if directory:sub(1, 1) ~= "/" then
		directory = physical_directory(directory)
	end
	local args, err = rex.json.encode({ roots = roots })
	assert(args, err)
	local argv =
		{ "rex", "--autostart=false", "do", directory:gsub("/$", "") .. "/repository-picker-rows.lua", "--args", args }
	for position, arg in ipairs(argv) do
		argv[position] = shell_quote(arg)
	end
	return table.concat(argv, " ")
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

local function repository_session(root)
	local listed, list_err = rex.call("session.list", {})
	assert(listed, list_err)
	local status, status_err = rex.call("server.status", {})
	assert(status, status_err)
	assert(type(status.host_id) == "string" and status.host_id ~= "", "Cannot identify the local Rex host")
	local ordered, roots = {}, { [root] = root }
	local current, picker = os.getenv("REX_SESSION"), os.getenv("REX_BLOCK")
	for _, session in ipairs(listed.sessions) do
		if session.session_id == current then
			table.insert(ordered, 1, session)
		else
			ordered[#ordered + 1] = session
		end
	end
	for _, session in ipairs(ordered) do
		local attached, attach_err = rex.call("session.attach", { session_id = session.session_id })
		assert(attached or tostring(attach_err):match("code=([%w_]+)") == "session_not_found", attach_err)
		local view = attached and assert(attached.view, "Session attachment returned no view")
		for _, window in ipairs(view and view.windows or {}) do
			for _, layer in ipairs(window.layers or {}) do
				if layer.kind == "tiled" then
					for _, block in ipairs(layer.blocks or {}) do
						if
							block.flavor == terminal
							and block.host_id == status.host_id
							and block.block_id ~= picker
						then
							local process, process_err = rex.call("block.method", {
								session_id = session.session_id,
								block_id = block.block_id,
								method = "process",
								args = {},
							})
							assert(process or tostring(process_err):match("code=([%w_]+)") == "not_found", process_err)
							if process then
								local cwd = process.foreground and process.foreground.cwd
								if type(cwd) ~= "string" or cwd == "" then
									cwd = process.child and process.child.cwd
								end
								if type(cwd) == "string" then
									if roots[cwd] == nil then
										roots[cwd] = git_root(cwd) or false
									end
									if roots[cwd] == root then
										return session.session_id
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

local sources = {
	repos = {
		action = "project_picker",
		title = "Open Git Repository Session",
		keywords = "project repo git picker",
		empty = "No Git repositories found under the configured roots",
		select = function(entry, label)
			local checked = exec({
				"/bin/sh",
				"-c",
				'[ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ] && { [ -f "$1/.git/HEAD" ] || [ -f "$1/.git" ]; }'
					.. ' && cd "$1" && pwd -P',
				"rex-picker-selected",
				entry.path,
			})
			if checked.code ~= 0 then
				return nil, "Repository is no longer available. Ctrl-R refreshes this list."
			end
			local root = git_root(entry.path)
			if not root or root ~= checked.stdout:gsub("\n$", "") then
				return nil, "Repository is no longer available. Ctrl-R refreshes this list."
			end
			local existing = repository_session(root)
			if existing then
				rex.client.queue("session.select", { session_id = existing })
				return true
			end
			local session, err = rex.call("session.create", {
				label = label,
				initial_windows = {
					{
						window_label = "Terminal",
						layout = rex.layout.block({ flavor = terminal, options = { cwd = entry.path } }),
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
		title = "Switch Rex Session",
		keywords = "session switch existing detached picker",
		empty = "No existing Rex sessions",
		entries = sessions,
		select = function(entry)
			rex.client.queue("session.select", { session_id = entry.session_id })
		end,
	},
}

local function valid_dimension(length)
	return type(length) == "number" and length > 0 and length < math.huge and length % 1 == 0
end

local function wait_for_size(client_id)
	for attempt = 1, 50 do
		local size, err = rex.call("block.method", {
			session_id = rex.session_id,
			block_id = rex.block_id,
			method = "size",
			args = {},
		})
		assert(size, "Cannot read picker terminal size: " .. tostring(err or "no size returned"))
		local owner = type(size) == "table" and size.owner
		if type(owner) == "string" and owner ~= "" then
			if client_id == nil then
				client_id = owner
			end
			if
				owner == client_id
				and valid_dimension(size.columns)
				and valid_dimension(size.rows)
				and type(size.desired) == "table"
			then
				for _, desired in ipairs(size.desired) do
					if
						type(desired) == "table"
						and desired.client_id == client_id
						and desired.columns == size.columns
						and desired.rows == size.rows
					then
						return size
					end
				end
			end
		end
		if attempt < 50 then
			rex.sleep(0.01)
		end
	end
	error("Timed out waiting for the target Rex app to report and apply the picker terminal size", 0)
end

local function centered_margin(length, target)
	return math.max(0, math.floor((length - target) / 2))
end

local function choose(source, entries, client_id, view, query, notice, command)
	assert(view or #entries > 0, source.empty)
	local records, by_row = {}, {}
	if view then
		records = repository_records(view, notice)
	else
		for index, entry in ipairs(entries) do
			records[index] = index .. "\t" .. display(entry.label)
			by_row[records[index]] = { entry = entry, label = entry.label }
		end
	end
	local size = wait_for_size(client_id)
	local argv = {
		"fzf",
		"--read0",
		"--print0",
		"--layout=reverse",
		"--border=rounded",
		"--margin=" .. centered_margin(size.rows, card_shape.rows) .. "," .. centered_margin(
			size.columns,
			card_shape.columns
		),
		"--padding=1,2",
		"--color=bg:#1e1e2e",
		"--delimiter=\t",
		"--with-nth=2",
		"--nth=1",
		"--no-multi",
		"--info=hidden",
		"--no-separator",
		"--prompt=> ",
	}
	if view then
		argv[#argv + 1] = "--print-query"
		argv[#argv + 1] = "--header-lines=1"
		argv[#argv + 1] = "--with-shell=/bin/sh -c"
		argv[#argv + 1] = "--bind"
		argv[#argv + 1] = "load:unbind(load)+reload-sync:" .. command
		argv[#argv + 1] = "--bind"
		argv[#argv + 1] = "ctrl-r:reload-sync:" .. command
		argv[#argv + 1] = "--query"
		argv[#argv + 1] = query
	end
	local result = exec(argv, {
		stdin = #records > 0 and table.concat(records, "\0") .. "\0" or "",
		env = { FZF_DEFAULT_OPTS = "", FZF_DEFAULT_OPTS_FILE = "" },
	})
	local row, returned_query = result.stdout
	if view and result.code ~= 130 then
		returned_query, row = row:match("^([^%z]*)%z(.*)$")
	end
	if result.code == 1 or result.code == 130 then
		return
	end
	assert(result.code == 0, failure(result, "Picker failed"))
	assert(row and row:sub(-1) == "\0" and not row:sub(1, -2):find("%z"), "Picker returned an invalid selection")
	local selected = view and repository_selection(row:sub(1, -2)) or by_row[row:sub(1, -2)]
	assert(selected, "Picker returned an invalid selection")
	if view then
		return { entry = selected.entry, label = selected.label, query = returned_query }
	end
	return selected.entry
end

local function target_client(ctx)
	local result, err = rex.call("client.list", { kinds = { "app" }, session_id = ctx.session_id })
	assert(result, err)
	for _, client in ipairs(result.clients) do
		if client.client_id == ctx.client_id then
			return client.client_id
		end
	end
	if #result.clients == 1 then
		if not ctx.client_id then
			return result.clients[1].client_id
		end
		local caller = rex.call("client.inspect", { client_id = ctx.client_id })
		if caller and caller.client and caller.client.info and caller.client.info.kind == "cli" then
			return result.clients[1].client_id
		end
	end
	error("Open the picker using the shortcut in the target Rex app", 0)
end

function M.setup(config)
	local roots = roots_snapshot(config.roots)
	local directory = assert(module_source:match("^(.*/)"), "Cannot locate picker runner")
	if directory:sub(1, 1) ~= "/" then
		directory = physical_directory(directory)
		assert(directory ~= "", "Cannot locate picker runner directory")
	end
	local runner = directory:gsub("/$", "") .. "/picker-runner.lua"
	for kind, source in pairs(sources) do
		local title = source.title
		rex.action({
			name = source.action,
			title = title,
			category = "Session",
			keywords = source.keywords,
			run = function(ctx)
				local client = target_client(ctx)
				local snapshot, encode_err = rex.json.encode({ kind = kind, roots = roots, client_id = client })
				assert(snapshot, encode_err)
				local layer, err = rex.session.new_layer({
					session_id = ctx.session_id,
					bounds = { 0, 0, 1, 1 },
					focus = true,
					layout = {
						block = {
							flavor = terminal,
							label = title,
							options = {
								command = { "rex", "-C", client, "do", runner, "--args", snapshot },
								theme = { background = "#1e1e2e", foreground = "#cdd6f4", scheme = "dark" },
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
	local source = assert(sources[invocation.kind], "Unknown picker kind")
	local roots = roots_snapshot(invocation.roots)
	if invocation.kind == "repos" then
		local index = require("repository-index")
		local view = index.cached(roots)
		local command = reload_command(roots)
		local query, notice = "", view.notice
		while true do
			local choice = choose(source, view.entries, invocation.client_id, view, query, notice, command)
			if not choice then
				return
			end
			query = choice.query
			local selected, select_err = source.select(choice.entry, choice.label)
			if selected then
				return
			end
			view, notice = index.cached(roots), select_err
		end
	end
	local entry = choose(source, source.entries(roots), invocation.client_id)
	if entry then
		source.select(entry)
	end
end

function M.repository_rows(invocation)
	local roots = roots_snapshot(invocation.roots)
	local index = require("repository-index")
	local prior = index.cached(roots)
	local view, err = index.open(roots, true)
	local notice = not view and ("Refresh failed. " .. err) or nil
	io.write(table.concat(repository_records(view or prior, notice), "\0") .. "\0")
end

return M
