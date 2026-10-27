local directory = debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*/)") or "./"
package.path = directory .. "?.lua;" .. package.path
local native_exec = rex and rex.exec
local native_json = rex and rex.json
local native_open, native_rename, native_remove = io.open, os.rename, os.remove

local function equal(actual, expected)
	assert(actual == expected, "Expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function contains(text, fragment)
	assert(text:find(fragment, 1, true), "Missing " .. fragment .. " in " .. text)
end

local function fails(fn, fragment)
	local ok, err = pcall(fn)
	assert(not ok, "Expected an error")
	if fragment then
		contains(tostring(err), fragment)
	end
end

local function copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in pairs(value) do
		result[key] = copy(item)
	end
	return result
end

local function result(code, stdout, stderr)
	return { code = code, ok = code == 0, stdout = stdout or "", stderr = stderr or "" }
end

local function records(text)
	local items = {}
	for item in text:gmatch("([^%z]+)%z") do
		items[#items + 1] = item
	end
	return items
end

local function visible_label(row)
	return row:match("^[^\t]+\t([^\t]+)")
end

local function repository_path(row)
	return (assert(row:match("^(%x+)\t")):gsub("..", function(pair)
		return string.char(tonumber(pair, 16))
	end))
end

local function terminal_view(blocks, kind)
	return { windows = { { layers = { { kind = kind or "tiled", blocks = blocks } } } } }
end

local function local_terminal(id)
	return { block_id = id, flavor = "com.superlogical.terminal.shell", host_id = "host:local" }
end

local function ready_size(columns, rows, client_id)
	client_id = client_id or "client:one"
	return {
		columns = columns,
		rows = rows,
		owner = client_id,
		desired = { { client_id = client_id, columns = columns, rows = rows } },
	}
end

local function mock(options)
	local state = options or {}
	package.loaded["repository-index"] = nil
	state.actions, state.bindings, state.layers = {}, {}, {}
	state.calls, state.created, state.queued, state.encoded = {}, {}, {}, {}
	state.size_calls, state.sleeps = {}, {}
	if state.size == nil and not state.size_error then
		state.size = ready_size(80, 24)
	end
	state.files, state.workers, state.fzfs = state.files or {}, {}, {}
	state.scans, state.resolutions = 0, 0
	state.git_checks = {}
	state.attached = { [os.getenv("REX_SESSION") or "session:origin"] = true }
	io.open = function(name, mode)
		if not name:find("/rex/project-picker/v1/", 1, true) then
			return native_open(name, mode)
		end
		if mode == "rb" then
			if not state.files[name] then
				return nil, "not found"
			end
			return {
				read = function()
					return state.files[name]
				end,
				close = function()
					return true
				end,
			}
		end
		return {
			write = function(_, text)
				if state.write_error then
					return nil, state.write_error
				end
				state.files[name] = text
				return true
			end,
			close = function()
				return not state.close_error, state.close_error
			end,
		}
	end
	os.rename = function(from, to)
		if not to:find("/rex/project-picker/v1/", 1, true) then
			return native_rename(from, to)
		end
		if state.before_publish then
			state.before_publish(from, to)
		end
		if state.rename_error then
			return nil, state.rename_error
		end
		state.files[to], state.files[from] = state.files[from], nil
		state.cache_file = to
		return true
	end
	os.remove = function(name)
		if name:find("/rex/project-picker/v1/", 1, true) then
			state.files[name] = nil
			return true
		end
		return native_remove(name)
	end
	rex = {
		args = { mode = "pick" },
		session_id = state.session_id or os.getenv("REX_SESSION") or "session:origin",
		block_id = state.block_id or "block:picker",
		sleep = function(seconds)
			state.sleeps[#state.sleeps + 1] = seconds
			if state.on_sleep then
				state.on_sleep(seconds)
			end
		end,
		action = function(action)
			assert(not state.actions[action.name], "Duplicate action")
			state.actions[action.name] = action
		end,
		bind = function(key, action, args)
			state.bindings[key] = { action = action, args = args }
		end,
		json = {
			encode = function(value)
				local token = "snapshot-" .. (#state.encoded + 1)
				state.encoded[#state.encoded + 1] = token
				state.encoded[token] = copy(value)
				return token
			end,
			decode = function(token)
				if state.encoded[token] then
					return copy(state.encoded[token])
				end
				return nil, "invalid JSON"
			end,
		},
		layout = {
			block = function(block)
				return { block = block }
			end,
		},
		exec = setmetatable({
			start = function(argv, opts)
				if state.start_error then
					return nil, state.start_error
				end
				equal(opts.detach, true)
				equal(opts.stdout, false)
				equal(opts.stderr, false)
				equal(opts.env.REX_SESSION, false)
				equal(opts.env.REX_BLOCK, false)
				equal(opts.env.REX_CLIENT, false)
				local worker = { argv = argv, opts = opts, job = copy(state.encoded[argv[#argv]]) }
				state.workers[#state.workers + 1] = worker
				function worker:running()
					return not self.completed
				end
				function worker:wait()
					if not self.completed then
						local ok, value = pcall(require("repository-index").refresh, self.job)
						self.completed = ok and result(0) or result(1, "", tostring(value))
					end
					return self.completed
				end
				return worker
			end,
		}, {
			__call = function(_, argv, opts)
				if argv[1] == "/bin/sh" then
					if argv[4] == "rex-picker-selected" then
						state.checked = argv[5]
						local physical = (state.directories or {})[argv[5]]
						if state.selected_missing or physical == false then
							return result(1)
						end
						return result(0, (physical or argv[5]) .. "\n")
					end
					state.resolutions = state.resolutions + 1
					local path = argv[5]
					local physical = (state.directories or {})[path]
					if physical == false then
						return result(0)
					end
					return result(0, (physical or path) .. "\n")
				elseif argv[1] == "git" then
					equal(argv[2], "-C")
					equal(argv[4], "rev-parse")
					equal(argv[5], "--path-format=absolute")
					equal(argv[6], "--show-toplevel")
					state.git_checks[#state.git_checks + 1] = argv[3]
					local root = (state.git_roots or {})[argv[3]]
					if root == false then
						return result(128, "", "not a git repository")
					end
					return result(0, (root or argv[3]) .. "\n")
				elseif argv[1] == "rg" then
					state.scans = state.scans + 1
					if state.discovery_error then
						return result(2, "", state.discovery_error)
					end
					local markers = (state.markers or {})[opts.cwd] or ""
					return result(markers == "" and 1 or 0, markers)
				elseif argv[1] == "fzf" then
					state.fzf = { argv = argv, opts = opts, records = records(opts.stdin) }
					state.fzfs[#state.fzfs + 1] = state.fzf
					if state.on_fzf then
						local value = state.on_fzf(state.fzf, #state.fzfs)
						if value then
							return value
						end
					end
					if state.fzf_error then
						return nil, state.fzf_error
					end
					local code = state.fzf_code or 0
					if code ~= 0 then
						return result(code, "", state.fzf_stderr)
					end
					local output = state.fzf_output
					if not output then
						output = state.fzf.records[state.pick or 1]
						if not output then
							return result(130)
						end
						output = output .. "\0"
						for _, arg in ipairs(argv) do
							if arg == "--print-query" then
								output = "\0\0" .. output
							end
						end
					end
					return result(0, output)
				elseif argv[1] == "/usr/bin/shasum" then
					return result(0, string.rep("a", 64) .. "  -\n")
				elseif argv[1] == "/usr/bin/mktemp" then
					state.temp_count = (state.temp_count or 0) + 1
					return result(0, argv[2]:gsub("XXXXXXXX$", string.format("%08d", state.temp_count)) .. "\n")
				end
				error("Unexpected command " .. table.concat(argv, " "))
			end,
		}),
		call = function(method, args)
			if method == "block.method" and args.method == "size" then
				state.size_calls[#state.size_calls + 1] = args
				equal(args.session_id, rex.session_id)
				equal(args.block_id, rex.block_id)
				equal(next(args.args), nil)
				if state.size_responses then
					local response = state.size_responses[math.min(#state.size_calls, #state.size_responses)]
					return response.size, response.error
				end
				return state.size, state.size_error
			end
			state.calls[#state.calls + 1] = { method = method, args = args }
			if state.api_errors and state.api_errors[method] then
				return nil, state.api_errors[method]
			end
			if method == "client.list" then
				return { clients = state.clients or { { client_id = "client:one" } } }
			elseif method == "client.inspect" then
				local client = (state.inspected_clients or {})[args.client_id]
				if not client then
					return nil, "Client not found"
				end
				return { client = client }
			elseif method == "session.list" then
				return { sessions = state.sessions or {} }
			elseif method == "server.status" then
				return state.status or { host_id = "host:local" }
			elseif method == "session.attach" then
				local view = (state.views or {})[args.session_id]
				if not view then
					return nil,
						"stream response for session.attach failed: session not found (status=404 code=session_not_found)"
				end
				state.attached[args.session_id] = true
				return { client_id = "client:stream", view = view }
			elseif method == "session.view" or method == "block.method" then
				if not state.attached[args.session_id] then
					return nil, "stream response failed: stream is not attached to session (status=409 code=conflict)"
				end
				if method == "session.view" then
					return (state.views or {})[args.session_id],
						"stream response for session.view failed: session not found (status=404 code=session_not_found)"
				end
				equal(args.method, "process")
				equal(next(args.args), nil)
				return (state.processes or {})[args.block_id],
					"stream response for block.method failed: block not found (status=404 code=not_found)"
			elseif method == "session.create" then
				state.created[#state.created + 1] = args
				state.sessions = state.sessions or {}
				state.sessions[#state.sessions + 1] = { session_id = "session:new", label = args.label }
				state.views, state.processes = state.views or {}, state.processes or {}
				state.views["session:new"] = terminal_view({ local_terminal("block:new") })
				state.processes["block:new"] =
					{ foreground = { cwd = args.initial_windows[1].layout.block.options.cwd } }
				return { session_id = "session:new" }
			end
			error("Unexpected method " .. method)
		end,
		session = {
			new_layer = function(layer)
				state.layers[#state.layers + 1] = layer
				return { layer_id = "layer:picker" }
			end,
		},
		client = {
			queue = function(action, args)
				if state.queue_error then
					error(state.queue_error)
				end
				state.queued[#state.queued + 1] = { action = action, args = args }
			end,
		},
	}
	return state
end

local report = { passed = 0 }
local function test(name, fn)
	local ok, err = pcall(fn)
	assert(ok, name .. ": " .. tostring(err))
	report.passed = report.passed + 1
	print("ok " .. report.passed .. " - " .. name)
end

local picker
test("require has no Rex effects even with old mode arguments", function()
	rex = setmetatable({}, {
		__index = function()
			error("Import touched Rex")
		end,
	})
	package.loaded["project-picker"] = nil
	picker = require("project-picker")
	equal(type(picker.setup), "function")
	equal(type(picker.run), "function")
end)

test("setup only registers the two stable action names", function()
	local state = mock()
	picker.setup({ roots = { "~/anyfin" } })
	equal(type(state.actions.project_picker.run), "function")
	equal(type(state.actions.session_picker.run), "function")
	equal(next(state.bindings), nil)
	equal(#state.layers, 0)
	equal(#state.calls, 0)
end)

test("init config binds both registered picker actions", function()
	local state = mock()
	assert(loadfile(directory .. "init.lua"))()
	local bound = {}
	for _, binding in pairs(state.bindings) do
		bound[binding.action] = true
	end
	equal(bound.project_picker, true)
	equal(bound.session_picker, true)
end)

test("child receives the setup snapshot and an exact selected client", function()
	local state = mock({ clients = { { client_id = "client:one" }, { client_id = "client:two" } } })
	local config = { roots = { "~/anyfin", "/personal projects" } }
	picker.setup(config)
	config.roots[1] = "/changed"
	config.roots[3] = "/later"
	state.actions.project_picker.run({ session_id = "session:origin", client_id = "client:two" })
	local layer = state.layers[1]
	equal(layer.session_id, "session:origin")
	equal(layer.focus, true)
	equal(layer.layout.block.options.shell, nil)
	local command = layer.layout.block.options.command
	equal(command[1], "rex")
	equal(command[2], "-C")
	equal(command[3], "client:two")
	equal(command[4], "do")
	contains(command[5], "/picker-runner.lua")
	equal(command[6], "--args")
	local invocation = state.encoded[command[7]]
	equal(invocation.kind, "repos")
	equal(invocation.client_id, "client:two")
	equal(invocation.roots[1], os.getenv("HOME") .. "/anyfin")
	equal(invocation.roots[2], "/personal projects")
	equal(#invocation.roots, 2)
	state.actions.session_picker.run({ session_id = "session:origin", client_id = "client:one" })
	equal(state.layers[2].layout.block.options.shell, nil)
	local session_command = state.layers[2].layout.block.options.command
	equal(state.encoded[session_command[7]].kind, "sessions")
	equal(state.encoded[session_command[7]].client_id, "client:one")
	state.actions.project_picker.run({ session_id = "session:origin", client_id = "client:one" })
	local next_command = state.layers[3].layout.block.options.command
	equal(next_command[3], "client:one")
	local next_invocation = state.encoded[next_command[7]]
	equal(next_invocation.client_id, "client:one")
	equal(next_invocation.roots[1], os.getenv("HOME") .. "/anyfin")
	equal(next_invocation.roots[2], "/personal projects")
	equal(#next_invocation.roots, 2)
	for _, popup in ipairs(state.layers) do
		equal(#popup.bounds, 4)
		equal(popup.bounds[1], 0)
		equal(popup.bounds[2], 0)
		equal(popup.bounds[3], 1)
		equal(popup.bounds[4], 1)
	end
	equal(#state.calls, 3)
	for _, call in ipairs(state.calls) do
		equal(call.method, "client.list")
		equal(call.args.kinds[1], "app")
		equal(call.args.session_id, "session:origin")
	end
end)

test("action without a caller uses the only attached app", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		local state = mock()
		picker.setup({ roots = {} })
		state.actions[action].run({ session_id = "session:origin" })
		local command = state.layers[1].layout.block.options.command
		equal(command[3], "client:one")
		equal(state.encoded[command[7]].client_id, "client:one")
		local theme = state.layers[1].layout.block.options.theme
		equal(theme.background, "#1e1e2e")
		equal(theme.foreground, "#cdd6f4")
		equal(theme.scheme, "dark")
		equal(#state.calls, 1)
		equal(state.calls[1].method, "client.list")
	end
end)

test("transient CLI caller with API origin falls back to the only attached app", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		local state = mock({
			inspected_clients = {
				["client:transient"] = { client_id = "client:transient", info = { kind = "cli" } },
			},
		})
		picker.setup({ roots = {} })
		state.actions[action].run({ session_id = "session:origin", client_id = "client:transient", origin = "api" })
		equal(#state.layers, 1)
		local command = state.layers[1].layout.block.options.command
		equal(command[3], "client:one")
		equal(state.encoded[command[7]].client_id, "client:one")
	end
end)

test("missing callers never fall back even with CLI origin", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		for _, context in ipairs({
			{ client_id = "app:missing" },
			{ client_id = "app:missing", origin = "api" },
			{ client_id = "app:missing", origin = "cli" },
		}) do
			local state = mock()
			picker.setup({ roots = {} })
			fails(function()
				state.actions[action].run(context)
			end, "target Rex app")
			equal(#state.layers, 0)
		end
	end
end)

test("app and unknown callers never fall back even with CLI origin", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		for _, info in ipairs({ { kind = "app" }, { kind = "unknown" }, {} }) do
			local state = mock({
				inspected_clients = { ["client:caller"] = { client_id = "client:caller", info = info } },
			})
			picker.setup({ roots = {} })
			fails(function()
				state.actions[action].run({ session_id = "session:origin", client_id = "client:caller", origin = "cli" })
			end, "target Rex app")
			equal(#state.layers, 0)
		end
	end
end)

test("ambiguous or absent apps do not open a layer", function()
	for _, clients in ipairs({ {}, { { client_id = "client:one" }, { client_id = "client:two" } } }) do
		local state = mock({ clients = clients })
		picker.setup({ roots = {} })
		fails(function()
			state.actions.session_picker.run({})
		end, "target Rex app")
		equal(#state.layers, 0)
	end
end)

test("duplicate session labels preserve exact IDs and include detached sessions", function()
	local state = mock({
		sessions = {
			{ session_id = "session:two", label = "same" },
			{ session_id = "session:one", label = "same" },
		},
		pick = 2,
	})
	picker.run({ kind = "sessions", roots = {} })
	equal(#state.fzf.records, 2)
	equal(state.fzf.records[1], "1\tsame")
	equal(state.fzf.records[2], "2\tsame")
	equal(state.calls[1].method, "session.list")
	equal(next(state.calls[1].args), nil)
	equal(#state.created, 0)
	equal(#state.queued, 1)
	equal(state.queued[1].action, "session.select")
	equal(state.queued[1].args.session_id, "session:two")
end)

test("display control characters never become identity delimiters", function()
	local state = mock({ sessions = { { session_id = "session:\tsecond", label = "a\tlabel\n\27" } } })
	picker.run({ kind = "sessions", roots = {} })
	contains(state.fzf.records[1], "a\\x09label\\x0a\\x1b")
	equal(state.queued[1].args.session_id, "session:\tsecond")
end)

test("unnamed sessions remain selectable", function()
	local state = mock({ sessions = { { session_id = "session:unnamed" } } })
	picker.run({ kind = "sessions", roots = {} })
	contains(state.fzf.records[1], "Untitled")
	equal(state.queued[1].args.session_id, "session:unnamed")
end)

test("repository roots include direct roots, nested repos, worktrees, and deduplicate overlaps", function()
	local state = mock({
		directories = { ["/absent"] = false, ["/alias"] = "/work" },
		markers = {
			["/work"] = "./.git/HEAD\0./a/repo/.git/HEAD\0./b/repo/.git/HEAD\0./tree with spaces/.git\0",
			["/work/a/repo"] = "./.git/HEAD\0",
		},
		pick = 4,
	})
	picker.run({ kind = "repos", roots = { "/work", "/work/a/repo", "/alias", "/absent" } })
	equal(#state.fzf.records, 4)
	equal(#state.created, 1)
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/tree with spaces")
	equal(state.created[1].initial_windows[1].layout.block.options.theme, nil)
	equal(state.created[1].initial_windows[1].bounds, nil)
	equal(state.created[1].initial_windows[1].layout.bounds, nil)
	equal(state.created[1].initial_windows[1].layout.block.bounds, nil)
	equal(state.created[1].label, "tree with spaces")
	equal(state.queued[1].args.session_id, "session:new")
end)

test("repository paths exclude every hidden segment relative to each configured root", function()
	local hidden_root = os.getenv("HOME") .. "/.dotfiles"
	local state = mock({
		markers = {
			["/work"] = table.concat({
				"./.git/HEAD",
				"./.hidden-project/.git/HEAD",
				"./project/.claude/worktrees/name/.git",
				"./project/.git/HEAD",
				"./project/.git/modules/embedded/.git/HEAD",
				"./repo.with.dots/.git/HEAD",
				"./team/.cache/repo/.git/HEAD",
				"./team/.hidden-project/.git",
				"./team/nested/repo/.git/HEAD",
				"./visible-worktree/.git",
			}, "\0") .. "\0",
			[hidden_root] = table.concat({
				"./.git/HEAD",
				"./.cache/repo/.git/HEAD",
				"./nested/repo.with.dots/.git/HEAD",
				"./visible-worktree/.git",
			}, "\0") .. "\0",
			["/work/team/nested/repo"] = "./.git/HEAD\0",
		},
	})
	picker.run({ kind = "repos", roots = { "/work", "~/.dotfiles", "/work/team/nested/repo" } })
	local expected = {
		hidden_root,
		hidden_root .. "/nested/repo.with.dots",
		hidden_root .. "/visible-worktree",
		"/work",
		"/work/project",
		"/work/repo.with.dots",
		"/work/team/nested/repo",
		"/work/visible-worktree",
	}
	table.sort(expected)
	equal(#state.fzf.records, #expected)
	for index, path in ipairs(expected) do
		equal(repository_path(state.fzf.records[index]), path)
	end
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, expected[1])
end)

test("duplicate repository labels open the selected absolute path", function()
	local state = mock({ markers = { ["/work"] = "./a/repo/.git/HEAD\0./b/repo/.git/HEAD\0" }, pick = 2 })
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(visible_label(state.fzf.records[1]), "a/repo")
	equal(visible_label(state.fzf.records[2]), "b/repo")
	equal(state.created[1].label, "b/repo")
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/b/repo")
end)

test("repository labels use only the shortest distinguishing suffix and leave unique names bare", function()
	local state = mock({
		markers = {
			["/work"] = table.concat({
				"./a/.git/HEAD",
				"./a/repo/.git/HEAD",
				"./alpha/team/repo/.git/HEAD",
				"./b/repo/.git/HEAD",
				"./beta/team/repo/.git/HEAD",
				"./solo/repo/.git/HEAD",
				"./team/.git/HEAD",
				"./unique/.git/HEAD",
			}, "\0") .. "\0",
		},
		fzf_code = 130,
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	local expected = { "a", "a/repo", "alpha/team/repo", "b/repo", "beta/team/repo", "solo/repo", "team", "unique" }
	equal(#state.fzf.records, #expected)
	for index, label in ipairs(expected) do
		equal(visible_label(state.fzf.records[index]), label)
	end
end)

test("rendering keeps cached entries and raw identities unchanged", function()
	local state = mock({ markers = { ["/work"] = "./a/repo/.git/HEAD\0./b/repo/.git/HEAD\0" }, pick = 2 })
	local index = require("repository-index")
	local view = assert(index.open({ "/work" }))
	local original = copy(view.entries)
	index.open = function()
		return view
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	for position, entry in ipairs(view.entries) do
		for key, value in pairs(original[position]) do
			equal(entry[key], value)
		end
		equal(repository_path(state.fzf.records[position]), entry.path)
		equal(state.fzf.records[position], entry.id .. "\t" .. visible_label(state.fzf.records[position]))
		equal(entry.detail, entry.path)
	end
	equal(state.created[1].label, "b/repo")
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/b/repo")
end)

test("display escaping keeps literal escape names distinct from control characters", function()
	local state = mock({ markers = { ["/work"] = "./line\nbreak/.git/HEAD\0./line\\x0abreak/.git/HEAD\0" }, pick = 2 })
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(visible_label(state.fzf.records[1]), "line\\x0abreak")
	equal(visible_label(state.fzf.records[2]), "line\\\\x0abreak")
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/line\\x0abreak")
end)

test("escaped duplicate repository names keep their shortest distinguishing suffixes", function()
	local state = mock({
		markers = {
			["/work"] = "./a/line\nbreak/.git/HEAD\0./a/line\\x0abreak/.git/HEAD\0"
				.. "./b/line\nbreak/.git/HEAD\0./b/line\\x0abreak/.git/HEAD\0",
		},
		pick = 4,
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	local expected = { "a/line\\x0abreak", "a/line\\\\x0abreak", "b/line\\x0abreak", "b/line\\\\x0abreak" }
	for index, label in ipairs(expected) do
		equal(visible_label(state.fzf.records[index]), label)
	end
	equal(state.created[1].label, "b/line\\x0abreak")
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/b/line\\x0abreak")
end)

test("repository selection reuses exact and nested terminal cwd roots without relying on labels", function()
	for _, cwd in ipairs({ "/work/repo", "/work/repo/src/deep" }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:detached", label = "unrelated name" } },
			views = { ["session:detached"] = terminal_view({ local_terminal("block:repo") }) },
			processes = { ["block:repo"] = { foreground = { cwd = cwd }, child = {}, ancestors = {} } },
			git_roots = { [cwd] = "/work/repo" },
		})
		local resolutions
		state.on_fzf = function()
			equal(#state.calls, 0)
			equal(#state.git_checks, 0)
			equal(state.checked, nil)
			resolutions = state.resolutions
		end
		picker.run({ kind = "repos", roots = { "/work" } })
		equal(state.checked, "/work/repo")
		equal(#state.created, 0)
		equal(#state.queued, 1)
		equal(state.queued[1].args.session_id, "session:detached")
		equal(state.resolutions, resolutions)
		equal(#state.git_checks, cwd == "/work/repo" and 1 or 2)
		equal(state.git_checks[1], "/work/repo")
		if cwd ~= "/work/repo" then
			equal(state.git_checks[2], cwd)
		end
	end
end)

test("canonical Git roots match symlink cwd spellings", function()
	local state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		sessions = { { session_id = "session:alias", label = "alias" } },
		views = { ["session:alias"] = terminal_view({ local_terminal("block:alias") }) },
		processes = { ["block:alias"] = { foreground = { cwd = "/alias/repo/subdir" } } },
		git_roots = { ["/alias/repo/subdir"] = "/work/repo" },
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 0)
	equal(state.queued[1].args.session_id, "session:alias")
end)

test("selected repository validation compares physical roots before looking up sessions", function()
	local state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		directories = { ["/work/repo"] = "/physical/repo" },
		git_roots = { ["/work/repo"] = "/physical/repo" },
		sessions = { { session_id = "session:physical" } },
		views = { ["session:physical"] = terminal_view({ local_terminal("block:physical") }) },
		processes = { ["block:physical"] = { foreground = { cwd = "/physical/repo" } } },
		on_fzf = function(_, count)
			if count > 1 then
				return result(130)
			end
		end,
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(state.checked, "/work/repo")
	equal(#state.fzfs, 1)
	equal(#state.created, 0)
	equal(state.queued[1].args.session_id, "session:physical")
	equal(#state.git_checks, 1)
end)

test("same labels, nested repositories, and other worktrees never identify the selected tree", function()
	for _, other in ipairs({ "/other/repo", "/work/repo/nested", "/work/repo-worktree" }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:other", label = "repo" } },
			views = { ["session:other"] = terminal_view({ local_terminal("block:other") }) },
			processes = { ["block:other"] = { foreground = { cwd = other .. "/src" } } },
			git_roots = { [other .. "/src"] = other },
		})
		picker.run({ kind = "repos", roots = { "/work" } })
		equal(#state.created, 1)
		equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/repo")
		equal(state.queued[1].args.session_id, "session:new")
	end
end)

test("two child streams reuse a newly created session when only the origin starts attached", function()
	local origin = os.getenv("REX_SESSION") or "session:origin"
	local state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		sessions = { { session_id = origin } },
		views = { [origin] = terminal_view({}) },
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	state.attached = { [origin] = true }
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 1)
	equal(#state.queued, 2)
	equal(state.queued[1].args.session_id, "session:new")
	equal(state.queued[2].args.session_id, "session:new")
end)

test("reuse examines only local tiled terminal blocks", function()
	local remote = local_terminal("block:remote")
	remote.host_id = "host:remote"
	local nonterminal = local_terminal("block:editor")
	nonterminal.flavor = "editor"
	local view = terminal_view({ remote, nonterminal, local_terminal("block:outside") })
	view.windows[1].layers[2] = { kind = "floating", blocks = { local_terminal("block:floating") } }
	local state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		sessions = { { session_id = "session:other", label = "repo" } },
		views = { ["session:other"] = view },
		processes = {
			["block:remote"] = { foreground = { cwd = "/work/repo" } },
			["block:editor"] = { foreground = { cwd = "/work/repo" } },
			["block:floating"] = { foreground = { cwd = "/work/repo" } },
			["block:outside"] = { foreground = { cwd = "/outside" } },
		},
		git_roots = { ["/outside"] = false },
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 1)
	local process_calls = 0
	for _, call in ipairs(state.calls) do
		if call.method == "block.method" then
			equal(call.args.block_id, "block:outside")
			process_calls = process_calls + 1
		end
	end
	equal(process_calls, 1)
end)

test("foreground cwd wins and child cwd is used only when foreground cwd is unavailable", function()
	for _, foreground in ipairs({ {}, { cwd = "/outside" }, { cwd = "/work/repo" } }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:existing", label = "repo" } },
			views = { ["session:existing"] = terminal_view({ local_terminal("block:existing") }) },
			processes = {
				["block:existing"] = {
					foreground = foreground,
					child = { cwd = "/work/repo" },
					ancestors = { { cwd = "/work/repo" } },
				},
			},
			git_roots = { ["/outside"] = false },
		})
		picker.run({ kind = "repos", roots = { "/work" } })
		equal(#state.created, foreground.cwd == "/outside" and 1 or 0)
		equal(state.queued[1].args.session_id, foreground.cwd == "/outside" and "session:new" or "session:existing")
	end
end)

test("vanished sessions and terminal blocks do not prevent reuse of a remaining valid session", function()
	local state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		sessions = {
			{ session_id = "session:gone" },
			{ session_id = "session:partly-gone" },
			{ session_id = "session:valid" },
		},
		views = {
			["session:partly-gone"] = terminal_view({ local_terminal("block:gone") }),
			["session:valid"] = terminal_view({ local_terminal("block:valid") }),
		},
		processes = { ["block:valid"] = { foreground = { cwd = "/work/repo" } } },
	})
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 0)
	equal(state.queued[1].args.session_id, "session:valid")
end)

test("multiple matching sessions use stable list order unless the current session matches", function()
	local getenv = os.getenv
	for _, current in ipairs({ "session:second", "session:unrelated" }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:first" }, { session_id = "session:second" } },
			views = {
				["session:first"] = terminal_view({ local_terminal("block:first") }),
				["session:second"] = terminal_view({ local_terminal("block:picker"), local_terminal("block:second") }),
			},
			processes = {
				["block:first"] = { foreground = { cwd = "/work/repo" } },
				["block:second"] = { foreground = { cwd = "/work/repo" } },
			},
		})
		os.getenv = function(name)
			if name == "REX_SESSION" then
				return current
			elseif name == "REX_BLOCK" then
				return "block:picker"
			end
			return getenv(name)
		end
		local ok, err = pcall(picker.run, { kind = "repos", roots = { "/work" } })
		os.getenv = getenv
		assert(ok, err)
		equal(#state.created, 0)
		equal(state.queued[1].args.session_id, current == "session:second" and current or "session:first")
		for _, call in ipairs(state.calls) do
			if call.method == "block.method" then
				assert(call.args.block_id ~= "block:picker", "The picker must not identify its own repository")
			end
		end
	end
end)

test("repository lookup failures never blindly create a duplicate", function()
	for _, method in ipairs({ "session.list", "server.status", "session.attach", "block.method" }) do
		for _, message in ipairs({
			"lookup unavailable",
			"stream response failed: stream is not attached to session (status=409 code=conflict)",
			"stream response failed: permission denied (status=403 code=forbidden)",
			"stream response failed: unexpected lookup error (status=500 code=not_found_internal)",
		}) do
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:existing" } },
				views = { ["session:existing"] = terminal_view({ local_terminal("block:existing") }) },
				processes = { ["block:existing"] = { foreground = { cwd = "/work/repo" } } },
				api_errors = { [method] = message },
			})
			fails(function()
				picker.run({ kind = "repos", roots = { "/work" } })
			end, message)
			equal(#state.created, 0)
			equal(#state.queued, 0)
		end
	end
	local state = mock({ markers = { ["/work"] = "./repo/.git/HEAD\0" }, status = {} })
	fails(function()
		picker.run({ kind = "repos", roots = { "/work" } })
	end, "local Rex host")
	equal(#state.created, 0)
	state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		sessions = { { session_id = "session:existing" } },
	})
	local call = rex.call
	rex.call = function(method, args)
		if method == "session.attach" then
			return { client_id = "client:stream" }
		end
		return call(method, args)
	end
	fails(function()
		picker.run({ kind = "repos", roots = { "/work" } })
	end, "no view")
	equal(#state.created, 0)
	equal(#state.queued, 0)
end)

test("a stale Git marker cannot route to an ancestor repository session", function()
	for _, marker in ipairs({ "./repo/.git/HEAD\0", "./repo/.git\0" }) do
		for _, root in ipairs({ "/work", "", false }) do
			local state = mock({ markers = { ["/work"] = marker }, git_roots = { ["/work/repo"] = root } })
			state.on_fzf = function(chooser, count)
				if count == 2 then
					contains(table.concat(chooser.argv, " "), "no longer available")
					return result(130)
				end
			end
			picker.run({ kind = "repos", roots = { "/work" } })
			equal(#state.calls, 0)
			equal(#state.created, 0)
			equal(#state.queued, 0)
		end
	end
end)

test("direct worktree roots and filesystem root join correctly", function()
	for _, root in ipairs({ "/worktree", "/" }) do
		local state = mock({ markers = { [root] = "./.git\0" } })
		picker.run({ kind = "repos", roots = { root } })
		equal(state.created[1].initial_windows[1].layout.block.options.cwd, root)
	end
end)

test("paths with newlines remain exact when creating the repository session", function()
	for _, case in ipairs({
		{ name = "line\nbreak", label = "line\\x0abreak" },
		{ name = "line\n", label = "line\\x0a" },
		{ name = "line\n\n", label = "line\\x0a\\x0a" },
	}) do
		local state = mock({ markers = { ["/space root"] = "./" .. case.name .. "/.git/HEAD\0" } })
		picker.run({ kind = "repos", roots = { "/space root" } })
		equal(visible_label(state.fzf.records[1]), case.label)
		equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/space root/" .. case.name)
	end
end)

test("both sources admit only an exact row with one final NUL", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		for _, change in ipairs({
			function(row)
				return row:match("^[^\t]+") .. "\tchanged\0"
			end,
			function(row)
				return "999999\t" .. visible_label(row) .. "\0"
			end,
			function(row)
				return row .. "\0" .. row .. "\0"
			end,
			function(row)
				return row
			end,
			function(row)
				return row .. "\0\0"
			end,
			function(row)
				return row .. "\n\0"
			end,
			function(row)
				return row .. "\r\0"
			end,
			function(row)
				return row .. "\0\n"
			end,
			function()
				return "\0"
			end,
			function()
				return ""
			end,
		}) do
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
				on_fzf = function(chooser)
					local prefix = kind == "repos" and "query\n\t\\\0\0" or ""
					return result(0, prefix .. change(chooser.records[1]))
				end,
			})
			fails(function()
				picker.run({ kind = kind, roots = { "/work" } })
			end)
			equal(#state.created, 0)
			equal(#state.queued, 0)
			equal(#state.calls, kind == "repos" and 0 or 1)
			equal(#state.git_checks, 0)
			equal(state.checked, nil)
		end
	end
end)

test("cancellation has no session creation or selection effects for either source", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		for _, code in ipairs({ 1, 130 }) do
			local state = mock({
				fzf_code = code,
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
			})
			picker.run({ kind = kind, roots = { "/work" } })
			equal(#state.created, 0)
			equal(#state.queued, 0)
			equal(#state.size_calls, 1)
			if kind == "repos" then
				equal(#state.calls, 0)
				equal(#state.git_checks, 0)
			end
		end
	end
end)

test("both sources share rounded fzf UI without inherited options", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:one", label = "one" } },
			session_id = "session:child",
			block_id = "block:child",
			size = ready_size(357, 75),
		})
		picker.run({ kind = kind, roots = { "/work" } })
		contains(table.concat(state.fzf.argv, " "), "--border=rounded")
		contains("\0" .. table.concat(state.fzf.argv, "\0") .. "\0", "\0--color=bg:#1e1e2e\0")
		local flags = "\0" .. table.concat(state.fzf.argv, "\0") .. "\0"
		contains(flags, "\0--with-nth=2\0")
		contains(flags, "\0--nth=1\0")
		contains(flags, "\0--info=hidden\0")
		contains(flags, "\0--no-separator\0")
		contains(flags, "\0--prompt=> \0")
		contains(flags, "\0--margin=22,152\0")
		contains(flags, "\0--padding=1,2\0")
		assert(not flags:find("--header", 1, true))
		assert(not flags:find("--border-label", 1, true))
		equal(state.fzf.opts.env.FZF_DEFAULT_OPTS, "")
		equal(state.fzf.opts.env.FZF_DEFAULT_OPTS_FILE, "")
		equal(
			state.fzf.records[1],
			state.fzf.records[1]:match("^[^\t]+") .. "\t" .. (kind == "repos" and "repo" or "one")
		)
		equal(#state.size_calls, 1)
		equal(state.size_calls[1].session_id, "session:child")
		equal(state.size_calls[1].block_id, "block:child")
		equal(#state.sleeps, 0)
	end
end)

test("both pickers use the same 52 column by 30 row card on even grids", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:one", label = "one" } },
			size = ready_size(356, 74),
			fzf_code = 130,
		})
		picker.run({ kind = kind, roots = { "/work" } })
		contains("\0" .. table.concat(state.fzf.argv, "\0") .. "\0", "\0--margin=22,152\0")
		equal(#state.sleeps, 0)
	end
end)

test("startup waits for the owner's first reported grid before launching either picker", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:one", label = "one" } },
			size_responses = {
				{ size = { columns = 80, rows = 24, owner = "client:target", desired = {} } },
				{ size = ready_size(357, 75, "client:target") },
			},
			fzf_code = 130,
		})
		state.on_sleep = function(seconds)
			equal(seconds, 0.01)
			equal(#state.fzfs, 0)
			equal(#state.created, 0)
			equal(#state.queued, 0)
		end
		picker.run({ kind = kind, roots = { "/work" }, client_id = "client:target" })
		contains("\0" .. table.concat(state.fzf.argv, "\0") .. "\0", "\0--margin=22,152\0")
		equal(#state.size_calls, 2)
		equal(#state.sleeps, 1)
		equal(#state.fzfs, 1)
	end
end)

test("the target's reported columns and rows must both match the applied grid", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		local pending_columns = ready_size(357, 75, "client:target")
		pending_columns.desired[1].columns = 80
		local pending_rows = ready_size(357, 75, "client:target")
		pending_rows.desired[1].rows = 24
		local other_client = ready_size(357, 75, "client:target")
		other_client.desired[1].client_id = "client:other"
		local applied = ready_size(357, 75, "client:target")
		table.insert(applied.desired, 1, { client_id = "client:other", columns = 357, rows = 75 })
		local state = mock({
			markers = { ["/work"] = "./repo/.git/HEAD\0" },
			sessions = { { session_id = "session:one", label = "one" } },
			size_responses = {
				{ size = pending_columns },
				{ size = pending_rows },
				{ size = other_client },
				{ size = applied },
			},
			fzf_code = 130,
		})
		state.on_sleep = function(seconds)
			equal(seconds, 0.01)
			equal(#state.fzfs, 0)
		end
		picker.run({ kind = kind, roots = { "/work" }, client_id = "client:target" })
		equal(#state.size_calls, 4)
		equal(#state.sleeps, 3)
		contains("\0" .. table.concat(state.fzf.argv, "\0") .. "\0", "\0--margin=22,152\0")
	end
end)

test("unreported grids and wrong owners time out without launching or selecting", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		local wrong_owner = ready_size(357, 75, "client:other")
		wrong_owner.desired[#wrong_owner.desired + 1] = { client_id = "client:target", columns = 357, rows = 75 }
		for _, size in ipairs({
			{ columns = 80, rows = 24, owner = "client:target", desired = {} },
			{ columns = 357, rows = 75, owner = "client:target" },
			{
				columns = 357,
				rows = 75,
				owner = "client:target",
				desired = { client_id = "client:target", columns = 357, rows = 75 },
			},
			{ columns = 357, rows = 75, desired = { { client_id = "client:target", columns = 357, rows = 75 } } },
			wrong_owner,
		}) do
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
				size = size,
			})
			fails(function()
				picker.run({ kind = kind, roots = { "/work" }, client_id = "client:target" })
			end, "Timed out")
			equal(#state.size_calls, 50)
			equal(#state.sleeps, 49)
			for _, seconds in ipairs(state.sleeps) do
				equal(seconds, 0.01)
			end
			equal(#state.fzfs, 0)
			equal(#state.created, 0)
			equal(#state.queued, 0)
		end
	end
end)

test("client-reported 80 by 24 grids work with explicit targets and direct invocation", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		for _, invocation in ipairs({
			{ kind = kind, roots = { "/work" }, client_id = "client:target" },
			{ kind = kind, roots = { "/work" } },
		}) do
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
				size = ready_size(80, 24, "client:target"),
				fzf_code = 130,
			})
			picker.run(invocation)
			contains("\0" .. table.concat(state.fzf.argv, "\0") .. "\0", "\0--margin=0,14\0")
			equal(#state.size_calls, 1)
			equal(#state.sleeps, 0)
		end
	end
end)

test("small terminals clamp each card margin independently", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		for _, case in ipairs({
			{ columns = 40, rows = 10, margin = "0,0" },
			{ columns = 52, rows = 30, margin = "0,0" },
			{ columns = 53, rows = 31, margin = "0,0" },
			{ columns = 100, rows = 15, margin = "0,24" },
			{ columns = 50, rows = 40, margin = "5,0" },
		}) do
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
				size = ready_size(case.columns, case.rows),
				fzf_code = 130,
			})
			picker.run({ kind = kind, roots = { "/work" } })
			contains("\0" .. table.concat(state.fzf.argv, "\0") .. "\0", "\0--margin=" .. case.margin .. "\0")
			equal(#state.size_calls, 1)
		end
	end
end)

test("unavailable or invalid terminal dimensions fail instead of painting a full-window fallback", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		for _, response in ipairs({
			{},
			{ size = false },
			{ size = "invalid" },
			{ size = {} },
			{ size = ready_size(nil, 75) },
			{ size = ready_size(357, nil) },
			{ size = ready_size("357", 75) },
			{ size = ready_size(357, "75") },
			{ size = ready_size(0, 75) },
			{ size = ready_size(357, 0) },
			{ size = ready_size(-357, 75) },
			{ size = ready_size(357, -75) },
			{ size = ready_size(0 / 0, 75) },
			{ size = ready_size(357, 0 / 0) },
			{ size = ready_size(math.huge, 75) },
			{ size = ready_size(357, math.huge) },
			{ size = ready_size(357.5, 75) },
			{ size = ready_size(357, 75.5) },
		}) do
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
				size_responses = { response },
			})
			fails(function()
				picker.run({ kind = kind, roots = { "/work" } })
			end, "picker terminal size")
			assert(#state.size_calls <= 50)
			equal(#state.fzfs, 0)
			equal(#state.created, 0)
			equal(#state.queued, 0)
		end
	end
end)

test("size API errors stop immediately without launching either picker", function()
	for _, kind in ipairs({ "repos", "sessions" }) do
		for _, pending in ipairs({ false, true }) do
			local responses = { { error = "size API unavailable" } }
			if pending then
				table.insert(responses, 1, { size = { columns = 80, rows = 24, owner = "client:one", desired = {} } })
			end
			local state = mock({
				markers = { ["/work"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:one", label = "one" } },
				size_responses = responses,
			})
			fails(function()
				picker.run({ kind = kind, roots = { "/work" }, client_id = "client:one" })
			end, "size API unavailable")
			equal(#state.size_calls, pending and 2 or 1)
			equal(#state.sleeps, pending and 1 or 0)
			equal(#state.fzfs, 0)
			equal(#state.created, 0)
			equal(#state.queued, 0)
		end
	end
end)

test("empty session sources still fail without running fzf", function()
	local state = mock()
	fails(function()
		picker.run({ kind = "sessions", roots = {} })
	end, "No existing Rex sessions")
	equal(state.fzf, nil)
	equal(#state.created, 0)
	equal(#state.queued, 0)
end)

test("complete empty repository lists permit cancellation and refresh", function()
	local state = mock({ directories = { ["/absent"] = false } })
	picker.run({ kind = "repos", roots = { "/absent" } })
	equal(#state.fzf.records, 0)
	equal(#state.created, 0)
	local view = assert(require("repository-index").open({ "/absent" }))
	equal(view.provenance, "cached")
	equal(#view.entries, 0)
end)

test("discovery and subprocess failures never create or select sessions", function()
	for _, options in ipairs({
		{ discovery_error = "permission denied" },
		{ fzf_code = 2, fzf_stderr = "invalid fzf option" },
		{ fzf_error = "fzf executable missing" },
		{ fzf_output = "99\tforged\0" },
	}) do
		options.markers = { ["/work"] = "./repo/.git/HEAD\0" }
		local state = mock(options)
		fails(function()
			picker.run({ kind = "repos", roots = { "/work" } })
		end)
		equal(#state.created, 0)
		equal(#state.queued, 0)
	end
end)

test("API errors do not create replacement sessions", function()
	local state = mock({ api_errors = { ["session.list"] = "server unavailable" } })
	fails(function()
		picker.run({ kind = "sessions", roots = {} })
	end, "server unavailable")
	equal(#state.created, 0)
	state =
		mock({ sessions = { { session_id = "session:gone", label = "gone" } }, queue_error = "session disappeared" })
	fails(function()
		picker.run({ kind = "sessions", roots = {} })
	end, "session disappeared")
	equal(#state.created, 0)
	state = mock({
		markers = { ["/work"] = "./repo/.git/HEAD\0" },
		api_errors = { ["session.create"] = "creation failed" },
	})
	fails(function()
		picker.run({ kind = "repos", roots = { "/work" } })
	end, "creation failed")
	equal(#state.queued, 0)
end)

test("invalid roots and unknown sources fail before registration or selection", function()
	for _, root in ipairs({ "relative", "~someone/repo", "", "bad\0root" }) do
		local state = mock()
		fails(function()
			picker.setup({ roots = { root } })
		end)
		equal(next(state.actions), nil)
	end
	local state = mock()
	fails(function()
		picker.run({ kind = "other", roots = {} })
	end, "Unknown picker kind")
	equal(#state.created, 0)
	equal(#state.queued, 0)
end)

local function cached_state(state)
	return state.encoded[assert(state.files[state.cache_file])]
end

local function seed(state)
	local index = require("repository-index")
	local view = assert(index.open({ "/work" }))
	equal(view.provenance, "discovered")
	return index, view
end

test("warm complete records are searchable before the detached worker finishes", function()
	local state = mock({ markers = { ["/work"] = "./a/repo/.git/HEAD\0./b/repo/.git/HEAD\0" }, fzf_code = 130 })
	seed(state)
	local scans, resolutions = state.scans, state.resolutions
	state.on_fzf = function(chooser)
		equal(#chooser.records, 2)
		equal(state.scans, scans)
		equal(state.resolutions, resolutions)
		equal(state.workers[2]:running(), true)
		equal(#state.calls, 0)
		equal(#state.git_checks, 0)
		assert(not table.concat(chooser.argv, " "):find("--header", 1, true))
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 0)
	equal(#state.workers, 2)
end)

test("cold opening waits for the entire union and publishes before completion", function()
	local state = mock({ markers = { ["/work"] = "./one/.git/HEAD\0", ["/other"] = "./two/.git\0" } })
	local index = require("repository-index")
	local view = assert(index.open({ "/work", "/other" }))
	equal(#view.entries, 2)
	equal(view.entries[1].path, "/other/two")
	equal(view.entries[2].path, "/work/one")
	equal(cached_state(state).attempt.status, "ok")
	equal(state.workers[1]:running(), false)
end)

test("invalid cache schemas, roots, policies, paths, and JSON cause complete cold discovery", function()
	local mutations = {
		function(cache)
			cache.schema = 99
		end,
		function(cache)
			cache.identity = "wrong roots"
		end,
		function(cache)
			cache.configured_roots_hex = {}
		end,
		function(cache)
			cache.policy = "obsolete"
		end,
		function(cache)
			cache.snapshot.complete = false
		end,
		function(cache)
			cache.snapshot.paths_hex = { "2f6f757473696465" }
		end,
		function(cache)
			cache.snapshot.paths_hex = { cache.snapshot.paths_hex[1], cache.snapshot.paths_hex[1] }
		end,
		function(cache)
			cache.snapshot.paths_hex = { "zz" }
		end,
		function(_, state)
			state.files[state.cache_file] = "corrupt JSON"
		end,
	}
	for _, mutate in ipairs(mutations) do
		local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
		local index = seed(state)
		mutate(cached_state(state), state)
		state.markers["/work"] = "./fresh/.git/HEAD\0"
		local fresh = assert(index.open({ "/work" }))
		equal(fresh.provenance, "discovered")
		equal(fresh.entries[1].path, "/work/fresh")
		equal(state.scans, 2)
	end
end)

test("a partial failed refresh retains the last successful complete snapshot", function()
	local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
	local index = seed(state)
	state.discovery_error = "permission denied"
	local fresh, err = index.open({ "/work" }, true)
	equal(fresh, nil)
	contains(err, "permission denied")
	equal(cached_state(state).attempt.status, "error")
	equal(#cached_state(state).snapshot.paths_hex, 1)
	local retained = assert(index.open({ "/work" }))
	equal(retained.entries[1].path, "/work/old")
	contains(retained.notice, "permission denied")
end)

test("atomic publication exposes only the previous or complete replacement", function()
	local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
	local index = seed(state)
	local old = state.files[state.cache_file]
	state.markers["/work"] = "./new/.git/HEAD\0./other/.git\0"
	state.before_publish = function(from, to)
		equal(state.files[to], old)
		equal(from:match("^(.*/)"), to:match("^(.*/)"))
		local candidate = state.encoded[state.files[from]]
		equal(candidate.snapshot.complete, true)
		equal(#candidate.snapshot.paths_hex, 2)
	end
	local fresh = assert(index.open({ "/work" }, true))
	equal(#fresh.entries, 2)
	equal(fresh.entries[1].path, "/work/new")
	assert(state.files[state.cache_file] ~= old)
end)

test("write, close, and rename failures do not replace a complete cache", function()
	for _, field in ipairs({ "write_error", "close_error", "rename_error" }) do
		local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
		local index = seed(state)
		local old = state.files[state.cache_file]
		state[field] = "storage unavailable"
		state.markers["/work"] = "./new/.git/HEAD\0"
		local fresh, err = index.open({ "/work" }, true)
		equal(fresh, nil)
		contains(err, "storage unavailable")
		equal(state.files[state.cache_file], old)
		equal(cached_state(state).attempt.status, "ok")
		for name in pairs(state.files) do
			equal(name, state.cache_file)
		end
	end
end)

test("Ctrl-R with zero matches preserves exact query bytes and reuses in-flight discovery", function()
	local state = mock({ markers = { ["/work"] = "./b/repo/.git/HEAD\0" } })
	seed(state)
	local query = "missing '[$]\n\t\\"
	state.on_fzf = function(chooser, count)
		if count == 1 then
			state.markers["/work"] = "./a/repo/.git/HEAD\0./b/repo/.git/HEAD\0"
			equal(state.workers[2]:running(), true)
			return result(1, query .. "\0ctrl-r\0")
		end
		equal(count, 2)
		equal(#state.workers, 2)
		equal(#chooser.records, 2)
		equal(chooser.argv[#chooser.argv - 1], "--query")
		equal(chooser.argv[#chooser.argv], query)
		return result(0, query .. "\0\0" .. chooser.records[2] .. "\0")
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/b/repo")
end)

test("failed Ctrl-R retains the prior rows and query without session calls", function()
	local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
	seed(state)
	local original
	state.on_fzf = function(chooser, count)
		if count == 1 then
			original = chooser.records[1]
			state.discovery_error = "denied during refresh"
			return result(0, "same query\0ctrl-r\0" .. original .. "\0")
		end
		equal(chooser.records[1], original)
		equal(chooser.argv[#chooser.argv], "same query")
		contains(table.concat(chooser.argv, " "), "Refresh failed")
		contains(table.concat(chooser.argv, " "), "denied during refresh")
		return result(130)
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 0)
	equal(#state.calls, 0)
	equal(#state.queued, 0)
end)

test("Ctrl-R after a completed background attempt requests a new complete scan", function()
	local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
	seed(state)
	state.on_fzf = function(chooser, count)
		if count == 1 then
			equal(state.workers[2]:wait().code, 0)
			state.markers["/work"] = "./new/.git/HEAD\0"
			return result(0, "new\0ctrl-r\0" .. chooser.records[1] .. "\0")
		end
		equal(#state.workers, 3)
		equal(state.scans, 3)
		equal(visible_label(chooser.records[1]), "new")
		equal(repository_path(chooser.records[1]), "/work/new")
		equal(chooser.argv[#chooser.argv], "new")
		return result(130)
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(#state.created, 0)
end)

test("canceling a cached chooser leaves its worker able to publish for reopening", function()
	local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" }, fzf_code = 130 })
	seed(state)
	picker.run({ kind = "repos", roots = { "/work" } })
	local worker = state.workers[2]
	equal(worker:running(), true)
	state.markers["/work"] = "./new/.git/HEAD\0"
	equal(worker:wait().code, 0)
	local reopened = assert(require("repository-index").open({ "/work" }))
	equal(reopened.provenance, "cached")
	equal(reopened.entries[1].path, "/work/new")
	equal(#state.created, 0)
end)

test("baseline singleflight coalesces queued success and failure outcomes", function()
	for _, failing in ipairs({ false, true }) do
		local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
		local index = seed(state)
		assert(index.open({ "/work" }))
		local job = copy(state.workers[2].job)
		state.discovery_error = failing and "scan failed" or nil
		equal(state.workers[2]:wait().code, 0)
		local scans = state.scans
		local attempt_id = cached_state(state).attempt.id
		local coalesced = index.refresh(job)
		equal(coalesced.attempt_id, attempt_id)
		equal(state.scans, scans)
		equal(cached_state(state).attempt.status, failing and "error" or "ok")
		local command = table.concat(state.workers[2].argv, " ")
		contains(command, "/usr/bin/lockf -k ")
		assert(not command:find(" -C ", 1, true))
	end
end)

test("completed discovery does not replace active rows or redirect duplicate labels", function()
	local state = mock({ markers = { ["/work"] = "./b/repo/.git/HEAD\0./c/repo/.git/HEAD\0" } })
	seed(state)
	state.on_fzf = function(chooser)
		local selected = chooser.records[2]
		state.markers["/work"] = "./a/repo/.git/HEAD\0./b/repo/.git/HEAD\0./c/repo/.git/HEAD\0"
		equal(state.workers[2]:wait().code, 0)
		equal(#chooser.records, 2)
		return result(0, "repo\0\0" .. selected .. "\0")
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(state.created[1].initial_windows[1].layout.block.options.cwd, "/work/c/repo")
end)

test("removed chosen repositories create nothing and keep the query for refresh", function()
	local state = mock({ markers = { ["/work"] = "./gone/.git/HEAD\0" }, selected_missing = true })
	state.on_fzf = function(chooser, count)
		if count == 1 then
			return result(0, "gone\0\0" .. chooser.records[1] .. "\0")
		end
		equal(count, 2)
		equal(chooser.argv[#chooser.argv], "gone")
		contains(table.concat(chooser.argv, " "), "no longer available")
		return result(130)
	end
	picker.run({ kind = "repos", roots = { "/work" } })
	equal(state.checked, "/work/gone")
	equal(#state.created, 0)
	equal(#state.queued, 0)
	equal(#state.calls, 0)
	equal(#state.git_checks, 0)
end)

test("worker launch failures keep warm lists but fail cold opens clearly", function()
	local state = mock({ markers = { ["/work"] = "./old/.git/HEAD\0" } })
	local index = seed(state)
	state.start_error = "launcher unavailable"
	local retained = assert(index.open({ "/work" }))
	equal(retained.entries[1].path, "/work/old")
	contains(retained.notice, "launcher unavailable")
	state = mock({ start_error = "launcher unavailable" })
	local cold, err = require("repository-index").open({ "/work" })
	equal(cold, nil)
	contains(err, "launcher unavailable")
end)

local integration_directory = os.getenv("REX_PICKER_TEST_DIRECTORY")
if integration_directory then
	local function quote(word)
		return "'" .. word:gsub("'", "'\\''") .. "'"
	end
	local function command(argv, options)
		if native_exec then
			return assert(native_exec(argv, options))
		end
		local words = {}
		for _, word in ipairs(argv) do
			words[#words + 1] = quote(word)
		end
		local prefix = options and options.cwd and "cd " .. quote(options.cwd) .. " && " or ""
		for key, value in pairs(options and options.env or {}) do
			prefix = prefix .. key .. "=" .. quote(value) .. " "
		end
		local pipe = assert(io.popen("(" .. prefix .. table.concat(words, " ") .. ") 2>&1; printf '\\000%d' \"$?\""))
		local output = pipe:read("*a")
		pipe:close()
		local stdout, code = output:match("^(.*)%z(%d+)$")
		return result(assert(tonumber(code)), stdout)
	end

	test("real fzf searches only visible labels and returns untouched identity rows", function()
		for _, kind in ipairs({ "repos", "sessions" }) do
			local state = mock({
				markers = { ["/secretprefix"] = "./repo/.git/HEAD\0" },
				sessions = { { session_id = "session:secretprefix", label = "repo" } },
				fzf_code = 130,
			})
			picker.run({ kind = kind, roots = { "/secretprefix" } })
			local temporary = command({ "mktemp", integration_directory .. "/fzf-rows.XXXXXXXX" })
			equal(temporary.code, 0)
			local path = temporary.stdout:gsub("\n$", "")
			local file = assert(native_open(path, "wb"))
			assert(file:write(state.fzf.opts.stdin))
			assert(file:close())
			for _, query in ipairs({ "repo", "secretprefix", state.fzf.records[1]:match("^([^\t]+)\t") }) do
				local argv = { "/bin/sh", "-c", 'input=$1; shift; exec "$@" < "$input"', "picker-fzf", path }
				local skip = false
				for _, arg in ipairs(state.fzf.argv) do
					if skip then
						skip = false
					elseif arg == "--query" then
						skip = true
					elseif arg ~= "--print-query" and arg ~= "--expect=ctrl-r" then
						argv[#argv + 1] = arg
					end
				end
				argv[#argv + 1] = "--filter=" .. query
				local filtered = command(argv, { env = state.fzf.opts.env })
				equal(filtered.code, query == "repo" and 0 or 1)
				equal(filtered.stdout, query == "repo" and state.fzf.opts.stdin or "")
			end
		end
	end)

	test("real Git roots reuse symlink subdirectories without conflating nested repos or worktrees", function()
		local temporary = command({ "mktemp", "-d", integration_directory .. "/git-roots.XXXXXXXX" })
		equal(temporary.code, 0)
		local root = temporary.stdout:gsub("\n$", "")
		local setup = command({
			"/bin/sh",
			"-c",
			[[
set -eu
root=$1
git init -q "$root/main"
git -C "$root/main" -c user.name=Picker -c user.email=picker@example.invalid commit -q --allow-empty -m initial
git -C "$root/main" worktree add -q -b picker-test "$root/tree"
git init -q "$root/main/nested"
mkdir -p "$root/main/src" "$root/tree/src" "$root/main/nested/src" "$root/main/stale"
printf 'gitdir: /nonexistent/picker-worktree\n' > "$root/main/stale/.git"
ln -s "$root/main" "$root/alias"
]],
			"picker-git-test",
			root,
		})
		equal(setup.code, 0)
		equal(command({ "git", "init", "-q", root .. "/line\n\n" }).code, 0)
		equal(command({ "mkdir", "-p", root .. "/line\n\n/src" }).code, 0)
		for _, case in ipairs({
			{ selected = "main", cwd = "main", reused = true },
			{ selected = "main", cwd = "main/src", reused = true },
			{ selected = "main", cwd = "alias/src", reused = true },
			{ selected = "alias", cwd = "main", reused = true },
			{ selected = "main", cwd = "main/nested", reused = false },
			{ selected = "main", cwd = "main/nested/src", reused = false },
			{ selected = "main", cwd = "tree/src", reused = false },
			{ selected = "main/nested", cwd = "main/nested/src", reused = true },
			{ selected = "tree", cwd = "tree", marker = ".git", reused = true },
			{ selected = "tree", cwd = "tree/src", marker = ".git", reused = true },
			{ selected = "line\n\n", cwd = "line\n\n", reused = true },
			{ selected = "line\n\n", cwd = "line\n\n/src", reused = true },
			{ selected = "main/stale", cwd = "main", marker = ".git", unavailable = true },
			{ selected = "missing", cwd = "main", unavailable = true },
		}) do
			local state = mock({
				markers = { [root] = "./" .. case.selected .. "/" .. (case.marker or ".git/HEAD") .. "\0" },
				sessions = { { session_id = "session:existing", label = "unrelated" } },
				views = { ["session:existing"] = terminal_view({ local_terminal("block:existing") }) },
				processes = { ["block:existing"] = { foreground = { cwd = root .. "/" .. case.cwd } } },
				on_fzf = function(chooser, count)
					if count > 1 then
						contains(table.concat(chooser.argv, " "), "no longer available")
						return result(130)
					end
				end,
			})
			local mocked_exec = rex.exec
			rex.exec = setmetatable({ start = mocked_exec.start }, {
				__call = function(_, argv, options)
					if argv[1] == "git" or (argv[1] == "/bin/sh" and argv[4] == "rex-picker") then
						return command(argv, options)
					elseif argv[1] == "/bin/sh" and argv[4] == "rex-picker-selected" then
						state.checked = argv[5]
						return command(argv, options)
					end
					return mocked_exec(argv, options)
				end,
			})
			picker.run({ kind = "repos", roots = { root } })
			equal(state.checked, root .. "/" .. case.selected)
			if case.unavailable then
				equal(#state.created, 0)
				equal(#state.queued, 0)
				equal(#state.calls, 0)
			else
				equal(#state.created, case.reused and 0 or 1)
				equal(state.queued[1].args.session_id, case.reused and "session:existing" or "session:new")
			end
		end
	end)

	test("real ripgrep preserves visible repositories without traversing hidden descendants", function()
		local temporary = command({ "mktemp", "-d", integration_directory .. "/picker.XXXXXXXX" })
		equal(temporary.code, 0)
		local root = temporary.stdout:gsub("\n$", "")
		local setup = command({
			"/bin/sh",
			"-c",
			[[
set -eu
root=$1
for repo in "" project project/nested repo.with.dots "line
break" "quote'[$]" .hidden-project project/.claude/tree team/.cache/repo .dotfiles; do
  mkdir -p "$root/$repo/.git/objects"
  printf 'ref: refs/heads/main\n' > "$root/$repo/.git/HEAD"
done
for repo in visible-worktree "tree with spaces" .dotfiles/visible-child; do
  mkdir -p "$root/$repo"
  printf 'gitdir: /nonexistent/worktree\n' > "$root/$repo/.git"
done
printf 'project\nvisible-worktree\n' > "$root/.gitignore"
printf '%s\n' '--glob=!**' > "$root/rg-config"
mkdir -p "$root/project/.cache/discarded"
chmod 000 "$root/project/.git/objects" "$root/project/.cache/discarded"
]],
			"picker-test",
			root,
		})
		equal(setup.code, 0)
		local state = mock({ fzf_code = 130 })
		local mocked_exec = rex.exec
		rex.exec = setmetatable({ start = mocked_exec.start }, {
			__call = function(_, argv, options)
				if argv[1] == "fzf" or argv[1] == "/usr/bin/shasum" or argv[1] == "/usr/bin/mktemp" then
					return mocked_exec(argv, options)
				end
				options = options or {}
				options.env = { RIPGREP_CONFIG_PATH = root .. "/rg-config" }
				return command(argv, options)
			end,
		})
		local ok, err = pcall(picker.run, {
			kind = "repos",
			roots = { root, root .. "/.dotfiles", root .. "/project/nested", root .. "/visible-worktree" },
		})
		equal(command({ "chmod", "700", root .. "/project/.git/objects", root .. "/project/.cache/discarded" }).code, 0)
		assert(ok, err)
		local expected = {
			"",
			"/.dotfiles",
			"/.dotfiles/visible-child",
			"/line\nbreak",
			"/project",
			"/project/nested",
			"/quote'[$]",
			"/repo.with.dots",
			"/tree with spaces",
			"/visible-worktree",
		}
		equal(#state.fzf.records, #expected)
		for index, relative in ipairs(expected) do
			equal(repository_path(state.fzf.records[index]), root .. relative)
		end
		equal(#state.created, 0)
		equal(#state.queued, 0)
	end)
	if native_exec then
		test("real Rex workers publish complete private cache states and reuse warm snapshots", function()
			local cache_home = os.getenv("XDG_CACHE_HOME") or ""
			assert(
				cache_home:sub(1, #integration_directory + 1) == integration_directory .. "/",
				"Use a private test cache"
			)
			io.open, os.rename, os.remove = native_open, native_rename, native_remove
			rex = { exec = native_exec, json = native_json }
			package.loaded["repository-index"] = nil
			local temporary = assert(native_exec({ "mktemp", "-d", integration_directory .. "/cache-picker.XXXXXXXX" }))
			equal(temporary.code, 0)
			local root = temporary.stdout:gsub("\n$", "")
			local setup = assert(native_exec({
				"/bin/sh",
				"-c",
				'mkdir -p "$1/a/repo/.git" "$1/b/repo"; printf main > "$1/a/repo/.git/HEAD"; printf gitdir > "$1/b/repo/.git"',
				"cache-picker-test",
				root,
			}))
			equal(setup.code, 0)
			local index = require("repository-index")
			local cold = assert(index.open({ root }))
			equal(cold.provenance, "discovered")
			equal(#cold.entries, 2)
			equal(cold.entries[1].path, root .. "/a/repo")
			equal(cold.entries[2].path, root .. "/b/repo")
			local warm = assert(index.open({ root }))
			equal(warm.provenance, "cached")
			equal(warm.entries[2].id, cold.entries[2].id)
			local fresh = assert(index.open({ root }, true))
			equal(fresh.provenance, "discovered")
			equal(#fresh.entries, 2)
			local empty = assert(index.open({ root .. "/absent" }))
			equal(#empty.entries, 0)
			equal(assert(index.open({ root .. "/absent" })).provenance, "cached")
			assert(index.open({ root .. "/absent" }, true))
		end)
	end
end

print("Passed " .. tostring(report.passed) .. " picker tests")
io.open, os.rename, os.remove = native_open, native_rename, native_remove
return report
