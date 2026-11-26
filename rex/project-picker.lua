local M = {}
local terminal = "com.superlogical.terminal.shell"
local empty = "No Git repositories found under the configured roots"

local function exec(argv, options)
	local result, err = rex.exec(argv, options)
	assert(result, err)
	return result
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

local function attach_all()
	-- session.view requires access to the sessions on this connection.
	local listed, err = rex.call("session.attach_all", { event_scope = "session" })
	assert(listed, err)
	return listed.sessions or {}
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

local function repository_terminal(root, current_session)
	local status, status_err = rex.call("server.status", {})
	assert(status, status_err)
	assert(type(status.host_id) == "string" and status.host_id ~= "", "Cannot identify the local Rex host")
	local ordered, roots = {}, { [root] = root }
	for _, session in ipairs(attach_all()) do
		if session.session_id == current_session then
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
						if block.flavor == terminal and block.host_id == status.host_id then
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

local function open_repository(path, label, current_session)
	local checked = exec({
		"/bin/sh",
		"-c",
		'[ -d "$1" ] && [ -r "$1" ] && [ -x "$1" ] && { [ -f "$1/.git/HEAD" ] || [ -f "$1/.git" ]; }'
			.. ' && cd "$1" && pwd -P',
		"rex-picker-selected",
		path,
	})
	local root = checked.code == 0 and git_root(path)
	if not root or root ~= checked.stdout:gsub("\n$", "") then
		return false
	end
	local existing = repository_terminal(root, current_session)
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
		label = label,
		initial_windows = {
			{
				window_label = "Terminal",
				layout = rex.layout.block({ flavor = terminal, options = { cwd = path } }),
			},
		},
	})
	assert(session, err)
	rex.client.queue("session.select", { session_id = session.session_id })
	return true
end

-- A repository is a root or a visible directory at most two levels below it.
local function repositories(roots)
	local argv = {
		"/bin/sh",
		"-c",
		[[
for root; do
  for marker in "$root"/.git "$root"/*/.git "$root"/*/*/.git; do
    if [ -e "$marker" ]; then printf '%s\0' "${marker%/.git}"; fi
  done
done
]],
		"rex-picker-scan",
	}
	for _, root in ipairs(roots) do
		argv[#argv + 1] = root
	end
	-- Rex's Lua fails on a call chain in a for header, so the output gets a local.
	local output = exec(argv).stdout
	local paths, seen = {}, {}
	for path in output:gmatch("([^%z]+)%z") do
		if not seen[path] then
			seen[path] = true
			paths[#paths + 1] = path
		end
	end
	table.sort(paths)
	local entries = {}
	for position, path in ipairs(paths) do
		entries[position] = { path = path, label = path:match("[^/]+$") }
	end
	return entries
end

function M.setup(config)
	local roots = roots_snapshot(config.roots)
	rex.action({
		name = "project_picker",
		title = "Open Project Session",
		category = "Session",
		keywords = "project repo git picker",
		run = function(ctx)
			local entries = repositories(roots)
			local labels, items, titles = repository_labels(entries), {}, {}
			for position, entry in ipairs(entries) do
				items[position] = { id = entry.path, title = labels[position], icon = "folder" }
				titles[entry.path] = labels[position]
			end
			-- rex.ui.pick fails under pcall, so nothing here may wrap it.
			local choice, reason, detail = rex.ui.pick({
				title = "Open Project Session",
				placeholder = #entries == 0 and empty or "Filter projects",
				items = items,
			})
			if choice == nil then
				if reason == "cancelled" or reason == "timeout" or reason == "busy" then
					return
				end
				error("Project picker cannot prompt: " .. tostring(reason) .. (detail and (": " .. detail) or ""), 0)
			end
			if not open_repository(choice, titles[choice], ctx.session_id) then
				error("Repository is no longer available: " .. choice, 0)
			end
		end,
	})
end

return M
