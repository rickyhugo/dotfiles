local M = {}
local terminal = "com.superlogical.terminal.shell"
local empty = "No Git repositories found under the configured roots"

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
	local result, err = rex.exec(argv)
	assert(result, err)
	local paths, seen, names = {}, {}, {}
	for path in result.stdout:gmatch("([^%z]+)%z") do
		if not seen[path] then
			seen[path] = true
			paths[#paths + 1] = path
			local name = path:match("[^/]+$")
			names[name] = (names[name] or 0) + 1
		end
	end
	table.sort(paths)
	local items = {}
	for position, path in ipairs(paths) do
		local name = path:match("[^/]+$")
		-- The title becomes the session label, so equal names get their parent directory.
		local title = names[name] > 1 and path:match("[^/]+/[^/]+$") or name
		items[position] = { id = path, title = title, icon = "folder" }
	end
	return items
end

local function shell_window(path)
	return {
		window_label = "Terminal",
		layout = rex.layout.block({ flavor = terminal, options = { cwd = path } }),
	}
end

-- A project's session is the one that has its label. Returns that session's ID.
local function project_session(label, path)
	-- session.view needs the access that session.attach_all gives this connection.
	local listed, err = rex.call("session.attach_all", { event_scope = "session" })
	assert(listed, err)
	for _, session in ipairs(listed.sessions or {}) do
		if session.label == label then
			local view, view_err = rex.call("session.view", { session_id = session.session_id })
			assert(view, view_err)
			if #(view.windows or {}) == 0 then
				local window = shell_window(path)
				window.session_id = session.session_id
				assert(rex.call("session.new_window", window))
			end
			return session.session_id
		end
	end
	local session, create_err = rex.call("session.create", { label = label, initial_windows = { shell_window(path) } })
	assert(session, create_err)
	return session.session_id
end

function M.setup(config)
	local roots = {}
	for position, root in ipairs(config.roots) do
		roots[position] = (root:gsub("^~", os.getenv("HOME")))
	end
	rex.action({
		name = "project_picker",
		title = "Open Project Session",
		category = "Session",
		keywords = "project repo git picker",
		run = function()
			local items, labels = repositories(roots), {}
			for _, item in ipairs(items) do
				labels[item.id] = item.title
			end
			-- rex.ui.pick fails under pcall, so nothing here may wrap it.
			local path, reason, detail = rex.ui.pick({
				title = "Open Project Session",
				placeholder = #items == 0 and empty or "Filter projects",
				items = items,
			})
			if path == nil then
				if reason == "cancelled" or reason == "timeout" or reason == "busy" then
					return
				end
				error("Project picker cannot prompt: " .. tostring(reason) .. (detail and (": " .. detail) or ""), 0)
			end
			rex.client.queue("session.select", { session_id = project_session(labels[path], path) })
		end,
	})
end

return M
