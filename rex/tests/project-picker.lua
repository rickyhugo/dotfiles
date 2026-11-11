local script = debug.getinfo(1, "S").source:gsub("^@", "")
if script:sub(1, 1) ~= "/" then
	script = (os.getenv("PWD") or ".") .. "/" .. script
end
local rex_dir = script:gsub("/tests/[^/]*$", "")
package.path = rex_dir .. "/?.lua;" .. package.path

local TERM = "com.superlogical.terminal.shell"
local real_write = io.write

local function quote(text)
	return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function real_exec(argv)
	local words = {}
	for index, arg in ipairs(argv) do
		words[index] = quote(arg)
	end
	local pipe = io.popen(table.concat(words, " ") .. ' 2>/dev/null; echo "__exit:$?"')
	local out = pipe:read("*a")
	pipe:close()
	local stdout, code = out:match("^(.*)__exit:(%d+)\n$")
	return { stdout = stdout, stderr = "", code = tonumber(code) }
end

local function sh(script_text, ...)
	local result = real_exec({ "/bin/sh", "-c", script_text, "sh", ... })
	assert(result.code == 0, "setup command failed: " .. script_text)
	return (result.stdout:gsub("\n$", ""))
end

local function json_encode(value)
	if type(value) == "string" then
		return '"' .. value:gsub('[%c"\\]', function(char)
			return string.format("\\u%04x", char:byte())
		end) .. '"'
	elseif type(value) ~= "table" then
		return tostring(value)
	end
	local parts = {}
	if #value > 0 then
		for index, item in ipairs(value) do
			parts[index] = json_encode(item)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		parts[#parts + 1] = json_encode(key) .. ":" .. json_encode(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function fail_call(code)
	return nil, "request failed (status=404 code=" .. code .. ")"
end

local function install(env)
	env = env or {}
	local fake = {
		calls = {},
		log = {},
		actions = {},
		binds = {},
		queued = {},
		created = {},
		windows = {},
		layers = {},
		focused = {},
		resizes = {},
		encoded = {},
		fzf_runs = {},
		client_lists = {},
		session_list = env.sessions or {},
		views = env.views or {},
		processes = env.processes or {},
		size = env.size or { desired = {} },
		sizes = env.sizes,
		app_clients = env.app_clients or { { client_id = "client:app" } },
		fzf = env.fzf or function()
			return { code = 130, stdout = "", stderr = "" }
		end,
	}
	local window_count = 0
	local function new_window(args)
		window_count = window_count + 1
		local window_id = "window:new" .. window_count
		fake.windows[#fake.windows + 1] = args
		local view = fake.views[args.session_id]
		view.windows = view.windows or {}
		view.windows[#view.windows + 1] = { window_id = window_id, layers = {} }
		return { window_id = window_id, block_ids = { "block:shell" .. window_count } }
	end
	local handlers = {
		["session.attach_all"] = function(args)
			assert(args.event_scope == "session", "no block event subscription")
			fake.subscribed = true
			return { sessions = fake.session_list }
		end,
		["session.list"] = function()
			return { sessions = fake.session_list }
		end,
		["server.status"] = function()
			return { host_id = "host" }
		end,
		["session.view"] = function(args)
			if not fake.subscribed then
				return fail_call("conflict")
			end
			local view = fake.views[args.session_id]
			if view == nil then
				return fail_call("session_not_found")
			end
			return view
		end,
		["block.method"] = function(args)
			if args.method == "size" then
				return fake.sizes and assert(fake.sizes[args.block_id], "unexpected size probe " .. args.block_id)
					or fake.size
			end
			assert(args.method == "process", "unexpected block method " .. tostring(args.method))
			local cwd = fake.processes[args.block_id]
			if not cwd then
				return fail_call("not_found")
			end
			return { foreground = { cwd = cwd } }
		end,
		["session.create"] = function(args)
			fake.created[#fake.created + 1] = args
			return { session_id = "session:new" }
		end,
		["session.new_window"] = new_window,
		["session.focus_block"] = function(args)
			fake.focused[#fake.focused + 1] = args
			return { revision = 1 }
		end,
		["session.resize_layer"] = function(args)
			fake.resizes[#fake.resizes + 1] = args.bounds
			for _, window in ipairs(fake.views[args.session_id].windows) do
				for _, layer in ipairs(window.layers) do
					if layer.layer_id == args.layer_id then
						layer.bounds = args.bounds
					end
				end
			end
			if env.on_resize then
				env.on_resize(fake, args.bounds)
			end
			return { revision = 1 }
		end,
		["client.list"] = function(args)
			fake.client_lists[#fake.client_lists + 1] = args
			return { clients = fake.app_clients }
		end,
	}
	local function call(method, args)
		fake.calls[#fake.calls + 1] = method
		fake.log[#fake.log + 1] = { method = method, args = args }
		if env.rpc_errors and env.rpc_errors[method] then
			return nil, env.rpc_errors[method]
		end
		local handler = assert(handlers[method], "unexpected rex.call " .. method)
		return handler(args)
	end
	local exec = setmetatable({
		start = function(argv, options)
			assert(argv[1] == "fzf", "only fzf is started asynchronously")
			if env.start_error then
				return nil, env.start_error
			end
			local run = { argv = argv, stdin = options.stdin, waits = 0 }
			fake.fzf_runs[#fake.fzf_runs + 1] = run
			return {
				wait = function(_, seconds)
					assert(seconds and seconds <= 0.5, "fzf waits are short so geometry keeps up")
					run.waits = run.waits + 1
					if env.on_wait then
						local result, err = env.on_wait(fake, run.waits)
						if result or err then
							return result, err
						end
					end
					if run.waits <= (env.ticks or 0) then
						return nil, "timeout"
					end
					return fake.fzf(argv, options.stdin, #fake.fzf_runs)
				end,
				running = function()
					return not run.killed
				end,
				kill = function()
					run.killed = true
				end,
			}
		end,
	}, {
		__call = function(_, argv)
			assert(argv[1] ~= "fzf", "fzf must not block the geometry loop")
			return real_exec(argv)
		end,
	})
	rawset(_G, "rex", {
		session_id = env.session_id,
		block_id = env.block_id,
		call = call,
		exec = exec,
		json = {
			encode = function(value)
				local text = json_encode(value)
				fake.encoded[text] = value
				return text
			end,
		},
		layout = {
			block = function(spec)
				return { block = spec }
			end,
		},
		session = {
			new_layer = function(args)
				fake.calls[#fake.calls + 1] = "session.new_layer"
				fake.log[#fake.log + 1] = { method = "session.new_layer", args = args }
				fake.layers[#fake.layers + 1] = args
				return { layer_id = "layer:1", block_ids = { "block:picker" } }
			end,
		},
		client = {
			queue = function(action, args)
				fake.log[#fake.log + 1] = { method = "queue:" .. action, args = args }
				fake.queued[#fake.queued + 1] = { action = action, args = args }
			end,
		},
		action = function(spec)
			fake.actions[#fake.actions + 1] = spec
			fake.actions[spec.name] = spec
		end,
		bind = function(key, action)
			fake.binds[key] = action
		end,
	})
	package.loaded["project-picker"] = nil
	package.loaded["repository-index"] = {
		cached = function()
			fake.cached_calls = (fake.cached_calls or 0) + 1
			return env.views_sequence and env.views_sequence[fake.cached_calls] or env.index_view
		end,
		open = env.open,
	}
	return fake
end

local function choose_label(label, query)
	return function(_, stdin)
		for record in stdin:gmatch("([^%z]*)%z") do
			local _, shown = record:match("^([^\t]*)\t([^\t]*)\t")
			if shown == label then
				return { code = 0, stdout = (query or "") .. "\0" .. record .. "\0", stderr = "" }
			end
		end
		error("no record shown as " .. label)
	end
end

local function shown_rows(stdin)
	local rows = {}
	for record in stdin:gmatch("([^%z]*)%z") do
		rows[#rows + 1] = record:match("^[^\t]*\t([^\t]*)\t")
	end
	return rows
end

local function view_with(layers, window_id)
	return { windows = { { window_id = window_id or "window:1", layers = layers } } }
end

local function terminal(block_id, extra)
	local block = { block_id = block_id, flavor = TERM, host_id = "host" }
	for key, value in pairs(extra or {}) do
		block[key] = value
	end
	return block
end

local function picker_view(bounds)
	return view_with({
		{
			layer_id = "layer:tiled",
			kind = "tiled",
			bounds = { 0, 0, 1, 1 },
			layout = { block_id = "block:host", rect = { 0, 0, 1, 1 } },
			blocks = { terminal("block:host") },
		},
		{
			layer_id = "layer:picker",
			kind = "floating",
			bounds = bounds,
			layout = { block_id = "block:picker", rect = bounds },
			blocks = { terminal("block:picker") },
		},
	})
end

local function size_report(columns, rows, stamp, client_id)
	return {
		client_id = client_id or "client:app",
		columns = columns,
		rows = rows,
		updated_at = "2026-11-10T10:00:" .. string.format("%02d", stamp) .. "Z",
	}
end

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local function expect_equal(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message or "mismatch", tostring(expected), tostring(actual)), 2)
	end
end

local function count(list, value)
	local total = 0
	for _, item in ipairs(list) do
		if item == value then
			total = total + 1
		end
	end
	return total
end

local function position(fake, method)
	for index, entry in ipairs(fake.log) do
		if entry.method == method then
			return index
		end
	end
end

local function argument(argv, flag)
	for index, arg in ipairs(argv) do
		if arg == flag then
			return argv[index + 1]
		end
		if arg:sub(1, #flag + 1) == flag .. "=" then
			return arg:sub(#flag + 2)
		end
	end
end

local function near(a, b)
	return math.abs(a - b) < 0.0005
end

local tmp = sh('cd "$(mktemp -d)" && pwd -P')
local function make_repo(name)
	local path = tmp .. "/" .. name
	sh('mkdir -p "$1" && git init -q "$1"', path)
	return path
end

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function invoke(fake, invocation)
	invocation.source = invocation.source or "projects"
	invocation.roots = invocation.roots or { tmp }
	invocation.client_id = invocation.client_id or "client:app"
	require("project-picker").run(invocation)
	return fake
end

local function open(fake, action, ctx, args)
	require("project-picker").setup({ roots = { tmp } })
	return fake.actions[action].run(ctx, args or {})
end

test("Ctrl+t f opens the project picker and Ctrl+t d opens the session picker", function()
	local fake = install({ views = { ["session:a"] = view_with({}) } })
	assert(loadfile(rex_dir .. "/init.lua"))()
	expect_equal(fake.binds["ctrl+t>f"], "project_picker", "f binding")
	expect_equal(fake.binds["ctrl+t>d"], "session_picker", "d binding")
	for _, name in ipairs({ "project_picker", "session_picker" }) do
		expect_equal(fake.actions[name].args.client_id, "string?", name .. " takes an optional client_id")
	end
	fake.actions.project_picker.run({ session_id = "session:a", client_id = "client:app" }, {})
	local invocation = fake.encoded[fake.layers[1].layout.block.options.command[7]]
	local home = os.getenv("HOME")
	expect_equal(
		table.concat(invocation.roots, ","),
		home .. "/anyfin," .. home .. "/personal," .. home .. "/.dotfiles",
		"roots"
	)
end)

test("both pickers open the same centered card in the invoking block's window", function()
	local layers = {}
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		local fake = install({
			views = {
				["session:a"] = {
					active_window_id = "window:active",
					windows = {
						{
							window_id = "window:active",
							layers = { { kind = "tiled", blocks = { terminal("block:x") } } },
						},
						{
							window_id = "window:mine",
							layers = { { kind = "tiled", blocks = { terminal("block:mine") } } },
						},
					},
				},
			},
		})
		local result =
			open(fake, action, { session_id = "session:a", block_id = "block:mine", client_id = "client:app" })
		expect_equal(result.block_ids[1], "block:picker", "action returns the picker block")
		layers[action] = fake.layers[1]
		expect_equal(#fake.windows, 0, "no window is created in a session that has one")
	end
	local project, session = layers.project_picker, layers.session_picker
	for _, layer in ipairs({ project, session }) do
		expect_equal(layer.window_id, "window:mine", "explicit owning window")
		local x, y, w, h = layer.bounds[1], layer.bounds[2], layer.bounds[3], layer.bounds[4]
		expect(near(x, (1 - w) / 2) and near(y, (1 - h) / 2), "opening bounds are centered")
		expect(layer.layout.block.options.size == nil, "startup size is not the geometry")
		expect_equal(layer.focus, true, "picker takes focus")
	end
	expect_equal(table.concat(project.bounds, ","), table.concat(session.bounds, ","), "same card")
	expect(project.layout.block.label ~= session.layout.block.label, "distinct titles")
	local command = project.layout.block.options.command
	expect_equal(table.concat(command, " ", 1, 5), "rex -C client:app do " .. rex_dir .. "/picker-runner.lua", "argv")
end)

test("an explicit client_id targets that app when two apps are connected", function()
	local fake = install({
		app_clients = { { client_id = "client:one" }, { client_id = "client:two" } },
		views = { ["session:a"] = view_with({}) },
	})
	open(fake, "session_picker", { session_id = "session:a", client_id = "client:cli" }, { client_id = "client:two" })
	local command = fake.layers[1].layout.block.options.command
	expect_equal(command[3], "client:two", "runner acts on the named app")
	local invocation = fake.encoded[command[7]]
	expect_equal(invocation.client_id, "client:two", "invocation client")
	expect_equal(invocation.source, "sessions", "invocation source")
	expect(fake.client_lists[1].session_id == nil, "apps are not filtered by session attachment")
end)

test("a key press targets the app that pressed it when two apps are connected", function()
	local fake = install({
		app_clients = { { client_id = "client:one" }, { client_id = "client:two" } },
		views = { ["session:a"] = view_with({}) },
	})
	open(fake, "project_picker", { session_id = "session:a", client_id = "client:one" })
	expect_equal(fake.layers[1].layout.block.options.command[3], "client:one", "invoking app")
end)

test("the picker refuses to guess between apps or accept an unknown client_id", function()
	for _, args in ipairs({ {}, { client_id = "client:gone" } }) do
		local fake = install({
			app_clients = {
				{ client_id = "client:one" },
				{ client_id = "client:two" },
				{ client_id = "client:gone", connection_state = "lost" },
			},
			views = { ["session:a"] = {} },
		})
		local ok, err =
			pcall(open, fake, "project_picker", { session_id = "session:a", client_id = "client:cli" }, args)
		expect(not ok and tostring(err):find(args.client_id and "client:gone" or "client_id=", 1, true), tostring(err))
		expect_equal(#fake.layers + #fake.windows, 0, "nothing opened")
	end
end)

test("an empty session gets a shell window before the picker opens in it", function()
	local fake = install({ views = { ["session:empty"] = { windows = {} } } })
	open(
		fake,
		"project_picker",
		{ session_id = "session:empty", client_id = "client:cli" },
		{ client_id = "client:app" }
	)
	expect_equal(#fake.windows, 1, "shell window created")
	expect_equal(fake.windows[1].layout.block.flavor, TERM, "normal shell")
	expect_equal(fake.layers[1].window_id, "window:new1", "picker opens in that window")
	expect(position(fake, "session.new_window") < position(fake, "session.new_layer"), "window first")
end)

test("a picker without a session fails with a clear error and creates nothing", function()
	local fake = install()
	local ok, err = pcall(open, fake, "session_picker", { client_id = "client:app" })
	expect(not ok and tostring(err):find("from a Rex session", 1, true), tostring(err))
	expect_equal(#fake.layers + #fake.windows + #fake.created, 0, "nothing created")
end)

test("the session picker lists stable IDs with readable, unambiguous labels", function()
	local fake = install({
		session_id = "session:here",
		sessions = {
			{ session_id = "session:aaaa-11111111", label = "work" },
			{ session_id = "session:bbbb-22222222", label = "work" },
			{ session_id = "session:here", label = "" },
			{ session_id = "session:tab", label = "a\tb" },
		},
	})
	invoke(fake, { source = "sessions" })
	local run = fake.fzf_runs[1]
	local rows = shown_rows(run.stdin)
	expect_equal(rows[2], "work  #11111111", "first duplicate")
	expect_equal(rows[3], "work  #22222222", "second duplicate")
	expect_equal(rows[4], "Untitled  (current)", "current session")
	expect_equal(rows[5], "a\\x09b", "escaped label")
	expect_equal(argument(run.argv, "--border-label"), " Sessions ", "title")
	expect_equal(argument(run.argv, "--prompt"), "session> ", "prompt")
	expect(argument(run.argv, "--header"):find("Ctrl-R", 1, true), "keyboard help")
	expect(not table.concat(run.argv, "\n"):find("load:", 1, true), "the session list is already fresh")
	expect_equal(#fake.queued + #fake.windows, 0, "cancel selects nothing")
	expect_equal(count(fake.calls, "session.view"), 0, "browsing does not touch other sessions")
end)

test("choosing an empty session gives it a shell before selecting it", function()
	local fake = install({
		sessions = { { session_id = "session:empty", label = "target" } },
		views = { ["session:empty"] = {} },
		fzf = choose_label("target"),
	})
	invoke(fake, { source = "sessions" })
	expect_equal(#fake.windows, 1, "shell window")
	expect_equal(fake.windows[1].session_id, "session:empty", "in the chosen session")
	expect_equal(fake.queued[1].args.session_id, "session:empty", "selected")
	expect(position(fake, "session.new_window") < position(fake, "queue:session.select"), "window before select")
end)

test("choosing a session with windows only selects it", function()
	local fake = install({
		sessions = { { session_id = "session:busy", label = "busy" } },
		views = { ["session:busy"] = view_with({}) },
		fzf = choose_label("busy"),
	})
	invoke(fake, { source = "sessions" })
	expect_equal(#fake.windows, 0, "no window")
	expect_equal(fake.queued[1].args.session_id, "session:busy", "selected")
end)

test("a session that disappeared keeps the query and refreshes with a notice", function()
	local fake
	fake = install({
		sessions = { { session_id = "session:gone", label = "gone" } },
		fzf = function(_, stdin, run)
			if run == 1 then
				fake.session_list = { { session_id = "session:still", label = "still" } }
				return choose_label("gone", "go")(nil, stdin)
			end
			return { code = 130, stdout = "", stderr = "" }
		end,
	})
	invoke(fake, { source = "sessions" })
	expect_equal(#fake.fzf_runs, 2, "picker reopened")
	local second = fake.fzf_runs[2]
	expect_equal(argument(second.argv, "--query"), "go", "query survives")
	local rows = shown_rows(second.stdin)
	expect(rows[1]:find("no longer exists", 1, true), "notice")
	expect_equal(rows[2], "still", "refreshed list")
	expect_equal(#fake.queued + #fake.windows + #fake.created, 0, "no replacement session")
end)

test("fitted bounds center the card and respect the window caps", function()
	local fitted_bounds = (install() and require("project-picker")).fitted_bounds
	local big = fitted_bounds({ 0.2, 0.15, 0.6, 0.7 }, { columns = 200, rows = 60 })
	expect(near(big[3], 0.5) and near(big[4], 0.5), "scales to 100x30")
	expect(near(big[1], 0.25) and near(big[2], 0.25), "centered")
	local small = fitted_bounds({ 0.2, 0.15, 0.6, 0.7 }, { columns = 50, rows = 15 })
	expect(near(small[3], 0.9) and near(small[4], 0.85), "capped")
	expect(near(small[1], 0.05) and near(small[2], 0.075), "capped and centered")
	expect_equal(fitted_bounds({ 0.249, 0.251, 0.501, 0.499 }, { columns = 200, rows = 60 }), nil, "deadband")
	expect_equal(fitted_bounds({ 0.05, 0.075, 0.9, 0.85 }, { columns = 60, rows = 20 }), nil, "already capped")
	local moved = fitted_bounds({ 0, 0, 0.5, 0.5 }, { columns = 200, rows = 60 })
	expect(near(moved[1], 0.25) and near(moved[2], 0.25), "correct size is still recentered")
end)

test("a delayed size report from the target app resizes the card once", function()
	local fake
	fake = install({
		session_id = "session:a",
		block_id = "block:picker",
		views = { ["session:a"] = picker_view({ 0.2, 0.15, 0.6, 0.7 }) },
		sizes = { ["block:host"] = { desired = {} }, ["block:picker"] = { desired = { size_report(999, 999, 1) } } },
		ticks = 6,
		on_wait = function(state, tick)
			if tick == 3 then
				state.sizes["block:host"] = {
					columns = 80,
					rows = 24,
					owner = "client:other",
					desired = { size_report(300, 90, 1, "client:other"), size_report(200, 60, 1) },
				}
			end
		end,
		index_view = { entries = {} },
	})
	invoke(fake, { client_id = "client:app" })
	expect_equal(#fake.resizes, 1, "one resize for one report")
	local bounds = fake.resizes[1]
	expect(near(bounds[3], 0.5) and near(bounds[4], 0.5), "sized from the target app's tiled-host report")
	expect(near(bounds[1], 0.25) and near(bounds[2], 0.25), "centered")
end)

test("stable host size does not repeatedly resize either picker", function()
	for _, source in ipairs({ "projects", "sessions" }) do
		local fake = install({
			session_id = "session:a",
			block_id = "block:picker",
			views = { ["session:a"] = picker_view({ 0.2, 0.15, 0.6, 0.7 }) },
			size = { desired = { size_report(200, 60, 1) } },
			ticks = 40,
			index_view = { entries = {} },
		})
		invoke(fake, { source = source })
		expect_equal(#fake.resizes, 1, "unchanged host report converges after one resize")
		expect_equal(fake.fzf_runs[1].waits, 41, "picker kept waiting")
	end
end)

test("more than four successive viewport changes keep fitting the card", function()
	local fake = install({
		session_id = "session:a",
		block_id = "block:picker",
		views = { ["session:a"] = picker_view({ 0.2, 0.15, 0.6, 0.7 }) },
		size = { desired = { size_report(200, 60, 1) } },
		ticks = 12,
		on_wait = function(state, tick)
			if tick <= 12 then
				state.size = { desired = { size_report(200 + tick * 20, 60 + tick * 6, tick) } }
			end
		end,
		index_view = { entries = {} },
	})
	invoke(fake, {})
	expect_equal(#fake.resizes, 13, "every viewport change gets fitted")
	for index, bounds in ipairs(fake.resizes) do
		expect(math.abs(bounds[3] * (200 + (index - 1) * 20) - 100) < 0.05, "card stays 100 columns")
		expect(math.abs(bounds[4] * (60 + (index - 1) * 6) - 30) < 0.02, "card stays 30 rows")
	end
end)

test("unchanged host reports recover a forcibly enlarged and shrunken own layer", function()
	local view = picker_view({ 0.25, 0.25, 0.5, 0.5 })
	local fake = install({
		session_id = "session:a",
		block_id = "block:picker",
		views = { ["session:a"] = view },
		size = { desired = { size_report(200, 60, 1) } },
		ticks = 8,
		on_wait = function(_, tick)
			if tick == 2 then
				view.windows[1].layers[2].bounds = { 0.05, 0.05, 0.9, 0.9 }
			elseif tick == 5 then
				view.windows[1].layers[2].bounds = { 0.4, 0.4, 0.2, 0.2 }
			end
		end,
		index_view = { entries = {} },
	})
	invoke(fake, {})
	expect_equal(#fake.resizes, 2, "both forced bounds recover")
	for _, bounds in ipairs(fake.resizes) do
		expect_equal(table.concat(bounds, ","), "0.25,0.25,0.5,0.5", "original centered card restored")
	end
end)

test("viewport shrink caps the card and later growth restores its fixed grid", function()
	local fake = install({
		session_id = "session:a",
		block_id = "block:picker",
		views = { ["session:a"] = picker_view({ 0.25, 0.25, 0.5, 0.5 }) },
		size = { desired = { size_report(200, 60, 1) } },
		ticks = 6,
		on_wait = function(state, tick)
			if tick == 1 then
				state.size = { desired = { size_report(80, 20, 2) } }
			elseif tick == 4 then
				state.size = { desired = { size_report(400, 120, 3) } }
			end
		end,
		index_view = { entries = {} },
	})
	invoke(fake, {})
	expect_equal(#fake.resizes, 2, "one resize per changed viewport")
	expect_equal(table.concat(fake.resizes[1], ","), "0.05,0.075,0.9,0.85", "small window uses centered caps")
	expect_equal(table.concat(fake.resizes[2], ","), "0.375,0.375,0.25,0.25", "large window restores 100x30")
end)

test("split and zoomed hosts measure the owning window rather than the active window", function()
	for _, zoomed in ipairs({ false, true }) do
		local view = picker_view({ 0.2, 0.15, 0.6, 0.7 })
		local window = view.windows[1]
		local tiled = window.layers[1]
		tiled.blocks = {
			terminal("block:decoy"),
			terminal("block:browser", { flavor = "com.superlogical.browser" }),
			terminal("block:host"),
		}
		tiled.layout = {
			rect = { 0, 0, 1, 1 },
			split = {
				before = { block_id = "block:decoy", rect = { 0, 0, 0.5, 1 } },
				after = {
					rect = { 0.5, 0, 0.5, 1 },
					split = {
						before = { block_id = "block:browser", rect = { 0.5, 0, 0.5, 0.5 } },
						after = { block_id = "block:host", rect = { 0.5, 0.5, 0.5, 0.5 } },
					},
				},
			},
		}
		window.zoomed_block_id = zoomed and "block:host" or nil
		view.active_window_id = "window:other"
		view.windows[2] = {
			window_id = "window:other",
			layers = { { kind = "tiled", blocks = { terminal("block:unrelated") } } },
		}
		local fake = install({
			session_id = "session:a",
			block_id = "block:picker",
			views = { ["session:a"] = view },
			sizes = {
				["block:decoy"] = { desired = { size_report(900, 900, 1, zoomed and "client:app" or "client:other") } },
				["block:host"] = { desired = { size_report(zoomed and 200 or 100, zoomed and 60 or 30, 1) } },
			},
			index_view = { entries = {} },
		})
		invoke(fake, {})
		expect_equal(table.concat(fake.resizes[1], ","), "0.25,0.25,0.5,0.5", "whole window measured")
	end
end)

test("split layout changes refit without requiring a new host report", function()
	local view = picker_view({ 0.25, 0.25, 0.5, 0.5 })
	local fake = install({
		session_id = "session:a",
		block_id = "block:picker",
		views = { ["session:a"] = view },
		size = { desired = { size_report(200, 60, 1) } },
		ticks = 2,
		on_wait = function(_, tick)
			if tick == 1 then
				local tiled = view.windows[1].layers[1]
				tiled.blocks[2] = terminal("block:browser", { flavor = "com.superlogical.browser" })
				tiled.layout = {
					rect = { 0, 0, 1, 1 },
					split = {
						before = { block_id = "block:host", rect = { 0, 0, 0.5, 1 } },
						after = { block_id = "block:browser", rect = { 0.5, 0, 0.5, 1 } },
					},
				}
			end
		end,
		index_view = { entries = {} },
	})
	invoke(fake, {})
	expect_equal(#fake.resizes, 1, "layout change refits")
	expect_equal(table.concat(fake.resizes[1], ","), "0.375,0.25,0.25,0.5", "new window estimate")
end)

test("geometry RPC failures propagate and stop the picker child", function()
	for _, method in ipairs({ "session.view", "block.method", "session.resize_layer" }) do
		local fake = install({
			session_id = "session:a",
			block_id = "block:picker",
			views = { ["session:a"] = picker_view({ 0.2, 0.15, 0.6, 0.7 }) },
			size = { desired = { size_report(200, 60, 1) } },
			rpc_errors = { [method] = method .. " denied" },
			index_view = { entries = {} },
		})
		local ok, err = pcall(invoke, fake, {})
		expect(not ok and tostring(err):find(method .. " denied", 1, true), "RPC failure must not look successful")
		expect(fake.fzf_runs[1].killed, "geometry failure kills own fzf")
		expect_equal(#fake.queued + #fake.created, 0, "failed picker selects nothing")
	end
end)

test("a host without a measurable tiled terminal fails with an actionable error", function()
	local view = picker_view({ 0.2, 0.15, 0.6, 0.7 })
	view.windows[1].layers[1].blocks[1].flavor = "com.superlogical.browser"
	local fake = install({
		session_id = "session:a",
		block_id = "block:picker",
		views = { ["session:a"] = view },
		index_view = { entries = {} },
	})
	local ok, err = pcall(invoke, fake, {})
	expect(not ok and tostring(err):find("tiled terminal", 1, true), tostring(err))
	expect(fake.fzf_runs[1].killed, "unmeasurable host stops the child")
end)

test("fzf start failures, wait failures and crashes are reported and the child is stopped", function()
	local fake = install({ start_error = "no such file", index_view = { entries = {} } })
	local ok, err = pcall(invoke, fake, {})
	expect(not ok and tostring(err):find("Cannot start fzf: no such file", 1, true), tostring(err))

	fake = install({
		index_view = { entries = {} },
		on_wait = function()
			return nil, "interrupted"
		end,
	})
	ok, err = pcall(invoke, fake, {})
	expect(not ok and tostring(err):find("interrupted", 1, true), tostring(err))
	expect(fake.fzf_runs[1].killed, "child killed")

	fake = install({
		index_view = { entries = {} },
		fzf = function()
			return { code = 2, stdout = "", stderr = "unknown option" }
		end,
	})
	ok, err = pcall(invoke, fake, {})
	expect(not ok and tostring(err):find("Picker failed: unknown option", 1, true), tostring(err))
end)

test("the project fzf command is titled and cancelling selects or creates nothing", function()
	local repo = make_repo("cancel")
	for _, code in ipairs({ 1, 130 }) do
		local fake = install({
			index_view = { entries = { { path = repo, label = "cancel" } } },
			fzf = function()
				return { code = code, stdout = code == 1 and "typed\0" or "", stderr = "" }
			end,
		})
		invoke(fake, {})
		local argv = fake.fzf_runs[1].argv
		expect(not table.concat(argv, "\n"):find("--margin", 1, true), "fzf must not add a margin")
		expect_equal(argument(argv, "--border-label"), " Projects ", "title")
		expect_equal(argument(argv, "--prompt"), "project> ", "prompt")
		expect_equal(argument(argv, "--with-nth"), "2", "search the shown label")
		expect_equal(argument(argv, "--nth"), "1", "within the shown label")
		expect_equal(#fake.queued, 0, "queued actions")
		expect_equal(#fake.created, 0, "created sessions")
		expect_equal(count(fake.calls, "block.method"), 0, "no session scan on cancel")
	end
end)

test("a repository without an existing session gets a new one", function()
	local repo = make_repo("fresh")
	local fake = install({
		sessions = { { session_id = "session:a", label = "a" } },
		views = { ["session:a"] = view_with({ { kind = "tiled", blocks = { terminal("block:a") } } }) },
		processes = { ["block:a"] = tmp },
		index_view = { entries = { { path = repo, label = "fresh" } } },
		fzf = choose_label("fresh"),
	})
	invoke(fake, {})
	expect_equal(#fake.created, 1, "created sessions")
	expect_equal(fake.created[1].label, "fresh", "label")
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "cwd")
	expect_equal(fake.queued[1].args.session_id, "session:new", "selected session")
end)

test("an existing session is reused from session.view snapshots without joining each session", function()
	local repo = make_repo("reuse")
	local fake = install({
		block_id = "block:picker",
		sessions = {
			{ session_id = "session:gone", label = "gone" },
			{ session_id = "session:decoys", label = "decoys" },
			{ session_id = "session:other", label = "other" },
			{ session_id = "session:hit", label = "hit" },
		},
		views = {
			["session:decoys"] = view_with({
				{ kind = "floating", blocks = { terminal("block:floating") } },
				{
					kind = "tiled",
					blocks = {
						terminal("block:remote", { host_id = "elsewhere" }),
						terminal("block:browser", { flavor = "com.superlogical.browser" }),
						terminal("block:picker"),
						terminal("block:vanished"),
					},
				},
			}),
			["session:other"] = view_with({ { kind = "tiled", blocks = { terminal("block:other") } } }),
			["session:hit"] = view_with({ { kind = "tiled", blocks = { terminal("block:hit") } } }, "window:hit"),
		},
		processes = {
			["block:floating"] = repo,
			["block:remote"] = repo,
			["block:browser"] = repo,
			["block:picker"] = repo,
			["block:other"] = tmp,
			["block:hit"] = repo .. "/nested/..",
		},
		index_view = { entries = { { path = repo, label = "reuse" } } },
		fzf = choose_label("reuse"),
	})
	sh('mkdir -p "$1/nested"', repo)
	invoke(fake, {})
	expect_equal(#fake.created, 0, "created sessions")
	expect_equal(fake.queued[1].args.session_id, "session:hit", "reused session")
	expect_equal(fake.queued[1].args.window_id, "window:hit", "reused window")
	expect_equal(fake.focused[1].block_id, "block:hit", "reused terminal focused")
	expect_equal(count(fake.calls, "session.attach"), 0, "session.attach calls")
	expect_equal(count(fake.calls, "session.view"), 4, "one view per session")
end)

test("a repository open in an inactive window selects that window, not the active one", function()
	local repo = make_repo("inactive")
	local fake = install({
		sessions = { { session_id = "session:work", label = "work" } },
		views = {
			["session:work"] = {
				active_window_id = "window:active",
				windows = {
					{ window_id = "window:active", layers = { { kind = "tiled", blocks = { terminal("block:a") } } } },
					{ window_id = "window:repo", layers = { { kind = "tiled", blocks = { terminal("block:repo") } } } },
				},
			},
		},
		processes = { ["block:a"] = tmp, ["block:repo"] = repo },
		index_view = { entries = { { path = repo, label = "inactive" } } },
		fzf = choose_label("inactive"),
	})
	invoke(fake, {})
	expect_equal(fake.queued[1].args.window_id, "window:repo", "selected window")
	expect_equal(fake.focused[1].session_id, "session:work", "focus in that session")
	expect_equal(fake.focused[1].block_id, "block:repo", "focused block")
	expect(position(fake, "session.focus_block") < position(fake, "queue:session.select"), "focus before select")
end)

test("only floating, remote, or picker blocks in a repository do not count as reuse", function()
	local repo = make_repo("decoy-only")
	local fake = install({
		sessions = { { session_id = "session:decoys", label = "decoys" } },
		views = {
			["session:decoys"] = view_with({
				{ kind = "floating", blocks = { terminal("block:floating") } },
				{ kind = "tiled", blocks = { terminal("block:remote", { host_id = "elsewhere" }) } },
			}),
		},
		processes = { ["block:floating"] = repo, ["block:remote"] = repo },
		index_view = { entries = { { path = repo, label = "decoy-only" } } },
		fzf = choose_label("decoy-only"),
	})
	invoke(fake, {})
	expect_equal(#fake.created, 1, "created sessions")
end)

test("a stale selection keeps the query and shows the refreshed list with a notice", function()
	local missing = tmp .. "/never-created"
	local repo = make_repo("alive")
	local fake = install({
		views_sequence = {
			{ entries = { { path = missing, label = "never-created" } } },
			{ entries = { { path = repo, label = "alive" } } },
		},
		fzf = function(_, stdin, run)
			if run == 1 then
				return choose_label("never-created", "nev")(nil, stdin)
			end
			return { code = 1, stdout = "nev\0", stderr = "" }
		end,
	})
	invoke(fake, {})
	expect_equal(#fake.fzf_runs, 2, "fzf runs")
	local second = fake.fzf_runs[2]
	expect_equal(argument(second.argv, "--query"), "nev", "query survives")
	expect(second.stdin:find("no longer available", 1, true), "notice in header row")
	expect(second.stdin:find("alive", 1, true), "refreshed entries")
	expect_equal(#fake.created + #fake.queued, 0, "nothing selected")
end)

test("unsafe directory names survive encoding, display and selection", function()
	local name = 'it\'s {a} "b"\ttab\nnewline'
	local repo = make_repo(name)
	local rows = {}
	local view = { entries = { { path = repo, label = name } } }
	local fake = install({
		index_view = view,
		open = function()
			return view
		end,
		fzf = function(_, stdin)
			rows[#rows + 1] = stdin
			local records = {}
			for record in stdin:gmatch("([^%z]*)%z") do
				records[#records + 1] = record
			end
			expect_equal(#records, 2, "status row plus one repository")
			expect(select(2, records[2]:gsub("\t", "")) == 2, "exactly three tab fields")
			expect(not records[2]:find("[\n]"), "no raw newline in a record")
			return { code = 0, stdout = "\0" .. records[2] .. "\0", stderr = "" }
		end,
	})
	invoke(fake, {})
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "exact path")
	expect_equal(fake.created[1].label, name, "exact label")

	local written = {}
	io.write = function(text)
		written[#written + 1] = text
	end
	local ok, err = pcall(require("project-picker").rows, { source = "projects", roots = { tmp } })
	io.write = real_write
	assert(ok, err)
	expect_equal(table.concat(written), rows[1], "reload rows match initial rows")
end)

test("reload rows keep the cached list and say so when refresh fails", function()
	local view = { entries = { { path = tmp .. "/x", label = "x" } } }
	install({
		index_view = view,
		open = function()
			return nil, "boom"
		end,
	})
	local written = {}
	io.write = function(text)
		written[#written + 1] = text
	end
	local ok, err = pcall(require("project-picker").rows, { source = "projects", roots = { tmp } })
	io.write = real_write
	assert(ok, err)
	local output = table.concat(written)
	expect(output:find("Refresh failed. boom", 1, true), "refresh notice")
	expect(output:find("\t" .. "x" .. "\t", 1, true), "cached entry kept")
end)

test("session reload rows list the current sessions", function()
	install({ sessions = { { session_id = "session:one", label = "one" } } })
	local written = {}
	io.write = function(text)
		written[#written + 1] = text
	end
	local ok, err = pcall(require("project-picker").rows, { source = "sessions" })
	io.write = real_write
	assert(ok, err)
	expect_equal(shown_rows(table.concat(written))[2], "one", "session row")
end)

test("the reload command round-trips quotes and braces through the shell", function()
	local root = "/tmp/it's {a} b"
	local fake = install({ index_view = { entries = {} } })
	invoke(fake, { roots = { root } })
	local binds = {}
	for index, arg in ipairs(fake.fzf_runs[1].argv) do
		if arg == "--bind" then
			binds[#binds + 1] = fake.fzf_runs[1].argv[index + 1]
		end
	end
	local reload = assert(binds[2]:match("^ctrl%-r:reload%-sync:(.*)$"), "ctrl-r reload bind")
	expect_equal(binds[1], "load:unbind(load)+reload-sync:" .. reload, "load bind reloads the same command")
	-- fzf reads {..} as placeholders, so none may reach it unquoted.
	expect(not reload:find("{[^']"), "braces are broken up for fzf")
	local printed = sh('rex() { for arg in "$@"; do printf "%s\\n" "$arg"; done; }; ' .. reload)
	local lines = {}
	for line in (printed .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	expect_equal(lines[1], "--autostart=false", "autostart flag")
	expect_equal(lines[2], "do", "do")
	expect_equal(lines[3], rex_dir .. "/picker-rows.lua", "rows script")
	expect_equal(lines[4], "--args", "args flag")
	expect_equal(lines[5], json_encode({ source = "projects", roots = { root } }), "encoded invocation")
end)

local failures = 0
for _, case in ipairs(tests) do
	local ok, err = pcall(case.fn)
	io.write = real_write
	print((ok and "ok   " or "FAIL ") .. case.name .. (ok and "" or "\n     " .. tostring(err)))
	if not ok then
		failures = failures + 1
	end
end
os.execute("rm -rf " .. quote(tmp))
os.exit(failures == 0 and 0 or 1)
