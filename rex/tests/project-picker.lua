local script = debug.getinfo(1, "S").source:gsub("^@", "")
if script:sub(1, 1) ~= "/" then
	script = (os.getenv("PWD") or ".") .. "/" .. script
end
local rex_dir = script:gsub("/tests/[^/]*$", "")
package.path = rex_dir .. "/?.lua;" .. package.path

local TERM = "com.superlogical.terminal.shell"
local FZF = "/opt/tools/fzf"
local real_write = io.write
local owned_files = {}

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
		closed = {},
		resizes = {},
		encoded = {},
		fzf_runs = {},
		exec_runs = {},
		login_calls = 0,
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
			error("picker must never resize after creation")
		end,
		["session.close_layer"] = function(args)
			if not fake.subscribed then
				return fail_call("conflict")
			end
			local view = fake.views[args.session_id]
			if not view then
				return fail_call("session_not_found")
			end
			for _, window in ipairs(view.windows or {}) do
				for index, layer in ipairs(window.layers or {}) do
					if layer.layer_id == args.layer_id then
						table.remove(window.layers, index)
						fake.closed[#fake.closed + 1] = args
						if env.on_close then
							env.on_close(args, fake)
						end
						return { revision = 1 }
					end
				end
			end
			return fail_call("not_found")
		end,
		["client.list"] = function(args)
			fake.client_lists[#fake.client_lists + 1] = args
			return { clients = fake.app_clients }
		end,
	}
	local function call(method, args)
		fake.calls[#fake.calls + 1] = method
		fake.log[#fake.log + 1] = { method = method, args = args }
		if env.on_call then
			env.on_call(method, args, fake)
		end
		if env.rpc_errors and env.rpc_errors[method] then
			return nil, env.rpc_errors[method]
		end
		local handler = assert(handlers[method], "unexpected rex.call " .. method)
		return handler(args)
	end
	local function exec(argv, options)
		fake.exec_runs[#fake.exec_runs + 1] = { argv = argv, options = options }
		if argv[2] == "-lc" then
			fake.login_calls = fake.login_calls + 1
			if env.login_error then
				return nil, env.login_error
			end
			if env.login_prefix then
				return real_exec({ "/bin/zsh", "-lc", env.login_prefix .. argv[3] })
			end
			return env.login_result
				or {
					code = 0,
					stdout = "startup noise\n\0rex-picker-environment\0/opt/tools:/usr/bin:/bin\0"
						.. FZF
						.. "\0after\n",
					stderr = "",
				}
		end
		if argv[1] == "fzf" or argv[1] == (env.fzf_executable or FZF) then
			if env.exec_error then
				return nil, env.exec_error
			end
			fake.fzf_runs[#fake.fzf_runs + 1] = { argv = argv, stdin = options.stdin, options = options }
			return fake.fzf(argv, options.stdin, #fake.fzf_runs)
		end
		return real_exec(argv)
	end
	rawset(_G, "rex", {
		session_id = env.session_id,
		block_id = env.block_id,
		call = call,
		exec = exec,
		json = {
			encode = function(value)
				if env.encode_error then
					return nil, env.encode_error
				end
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
				local command = args.layout.block.options.command
				owned_files[#owned_files + 1] = command[3]
				owned_files[#owned_files + 1] = command[4]
				if env.layer_error then
					return nil, env.layer_error
				end
				if env.layer_throw then
					error(env.layer_throw)
				end
				local number = #fake.layers
				local layer_id = "layer:" .. number
				local block_id = number == 1 and "block:picker" or "block:picker" .. number
				local view = assert(fake.views[args.session_id])
				for _, window in ipairs(view.windows or {}) do
					if window.window_id == args.window_id then
						window.layers = window.layers or {}
						window.layers[#window.layers + 1] = {
							layer_id = layer_id,
							kind = "floating",
							state = "normal",
							blocks = {
								{
									block_id = block_id,
									flavor = args.layout.block.flavor,
									label = args.layout.block.label,
								},
							},
						}
					end
				end
				if env.on_layer then
					env.on_layer(args, fake)
				end
				return env.layer_response or { layer_id = layer_id, block_ids = { block_id } }
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
			return env.views_sequence and env.views_sequence[fake.cached_calls] or env.index_view or { entries = {} }
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

local function picker_view()
	return view_with({
		{
			layer_id = "layer:tiled",
			kind = "tiled",
			bounds = { 0, 0, 1, 1 },
			layout = { block_id = "block:host", rect = { 0, 0, 1, 1 } },
			blocks = { terminal("block:host") },
		},
	})
end

local function tagged_picker(id, name, client)
	return {
		layer_id = "layer:" .. id,
		kind = "floating",
		blocks = { terminal("block:" .. id, { label = "rex.picker." .. name .. ":" .. (client or "client:app") }) },
	}
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

local function read_file(path)
	local file = assert(io.open(path, "rb"))
	local text = assert(file:read("*a"))
	assert(file:close())
	return text
end

local function write_file(path, text)
	local file = assert(io.open(path, "wb"))
	assert(file:write(text))
	assert(file:close())
end

local function launch_invocation(fake, command)
	return assert(fake.encoded[command[7]], "launch snapshot")
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

local function close_picker(fake, result)
	for _, view in pairs(fake.views) do
		for _, window in ipairs(view.windows or {}) do
			for index = #(window.layers or {}), 1, -1 do
				if window.layers[index].layer_id == result.layer_id then
					table.remove(window.layers, index)
				end
			end
		end
	end
end

test("each picker closes before fresh IDs, rows, files, and geometry are prepared", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		local env = { views = { ["session:a"] = picker_view() } }
		local fake = install(env)
		local ctx = { session_id = "session:a", client_id = "client:app" }
		local first = open(fake, action, ctx)
		local command = fake.layers[1].layout.block.options.command
		local files, processes, cached = #owned_files, #fake.exec_runs, fake.cached_calls
		local probes, lists = count(fake.calls, "block.method"), count(fake.calls, "session.list")
		env.index_view = { entries = { { path = tmp .. "/changed", label = "changed" } } }
		fake.session_list = { { session_id = "session:changed", label = "changed" } }
		fake.size = { desired = { size_report(400, 120, 1) } }
		env.on_call = function(method)
			if method == "block.method" or method == "session.list" then
				expect_equal(#fake.closed, 1, "close before rows or geometry")
			end
		end
		fake.subscribed = false
		local second = fake.actions[action].run(ctx, {})
		expect(second.layer_id ~= first.layer_id, "fresh layer")
		expect(second.block_ids[1] ~= first.block_ids[1], "fresh block")
		expect_equal(#fake.closed, 1, "old picker closed")
		expect_equal(fake.closed[1].layer_id, first.layer_id, "closed original layer")
		expect_equal(#fake.layers, 2, "two successive launches")
		expect_equal(#fake.views[ctx.session_id].windows[1].layers, 2, "one tiled and one picker layer")
		expect_equal(#owned_files, files + 2, "fresh files")
		expect_equal(#fake.exec_runs, processes, "no processes")
		expect_equal(fake.cached_calls, cached + (action == "project_picker" and 1 or 0), "fresh repository rows")
		expect_equal(
			count(fake.calls, "session.list"),
			lists + (action == "session_picker" and 1 or 0),
			"fresh session rows"
		)
		expect_equal(count(fake.calls, "block.method"), probes + 1, "fresh geometry")
		expect_equal(#fake.resizes, 0, "no resize")
		local fresh = fake.layers[2]
		local fresh_command = fresh.layout.block.options.command
		expect(command[3] ~= fresh_command[3] and command[4] ~= fresh_command[4], "new backing files")
		expect_equal(shown_rows(read_file(fresh_command[3]))[2], "changed", "updated rows")
		expect_equal(argument(fresh_command, "--query"), "", "fresh query")
		expect_equal(table.concat(fresh.bounds, ","), "0.375,0.375,0.25,0.25", "updated viewport")
	end
end)

test("replacement moves a minimized picker to the invoking session without selecting its old owner", function()
	local fake = install({
		views = { ["session:a"] = picker_view(), ["session:b"] = view_with({}) },
		app_clients = { { client_id = "client:one" }, { client_id = "client:two" } },
	})
	local first = open(fake, "project_picker", { session_id = "session:a", client_id = "client:two" })
	local layer = fake.views["session:a"].windows[1].layers[2]
	layer.state = "minimized"
	fake.views["session:a"].active_window_id = "window:elsewhere"
	local result = fake.actions.project_picker.run(
		{ session_id = "session:b", block_id = "block:elsewhere", client_id = "client:cli" },
		{ client_id = "client:two" }
	)
	expect(result.layer_id ~= first.layer_id, "fresh picker across sessions")
	expect_equal(fake.closed[1].session_id, "session:a", "old owner closed")
	expect_equal(#fake.views["session:a"].windows[1].layers, 1, "old floating layer removed")
	expect_equal(fake.layers[2].session_id, "session:b", "invoking session owns replacement")
	expect_equal(fake.views["session:a"].active_window_id, "window:elsewhere", "old session never activated")
	expect_equal(
		count(fake.calls, "session.set_layer_state") + count(fake.calls, "client.perform") + #fake.queued,
		0,
		"no restore or session selection"
	)
	local other = fake.actions.project_picker.run(
		{ session_id = "session:b", client_id = "client:two" },
		{ client_id = "client:one" }
	)
	expect(other.layer_id ~= first.layer_id, "other app has an independent picker")
	for index, client in ipairs({ "client:two", "client:two", "client:one" }) do
		local command = fake.layers[index].layout.block.options.command
		expect_equal(command[5], client, "wrapper retains its target app")
		expect_equal(launch_invocation(fake, command).client_id, client, "acceptance snapshot retains target")
		expect_equal(fake.layers[index].layout.block.label, "rex.picker.projects:" .. client, "app-specific tag")
	end
	package.loaded["project-picker"] = nil
	fake.session_list = { { session_id = "session:a" }, { session_id = "session:b" } }
	local rediscovered = open(fake, "project_picker", { session_id = "session:a", client_id = "client:one" })
	expect(rediscovered.layer_id ~= other.layer_id, "reload replaces target app's picker")
	expect_equal(#fake.closed, 2, "reload closes only the target app")
	expect_equal(fake.closed[2].layer_id, other.layer_id, "other app's picker left alone")
	expect_equal(#fake.views["session:b"].windows[1].layers, 1, "other app's picker survives reload")
end)

test("all four picker transitions close the old layer before creating the requested type across setup calls", function()
	for _, from in ipairs({ "project_picker", "session_picker" }) do
		for _, to in ipairs({ "project_picker", "session_picker" }) do
			local fake = install({ views = { ["session:a"] = view_with({}) } })
			local ctx = { session_id = "session:a", client_id = "client:app" }
			local first = open(fake, from, ctx)
			local baseline = #fake.log
			local second = open(fake, to, ctx)
			expect(second.layer_id ~= first.layer_id, "every action creates fresh IDs")
			expect_equal(#fake.closed, 1, "one old picker closed")
			expect_equal(fake.closed[1].layer_id, first.layer_id, "correct old layer")
			expect_equal(#fake.views[ctx.session_id].windows[1].layers, 1, "one total picker")
			local closed = false
			for index = baseline + 1, #fake.log do
				local method = fake.log[index].method
				if method == "session.close_layer" then
					closed = true
				elseif method == "session.new_layer" then
					expect(closed, "close precedes replacement")
				end
			end
			expect_equal(
				fake.layers[2].layout.block.label,
				"rex.picker." .. (to == "project_picker" and "projects" or "sessions") .. ":client:app",
				"requested type"
			)
		end
	end
end)

test("reload closes both kinds and duplicate tags across sessions before creating an empty host", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		local fake = install({
			views = {
				["session:a"] = view_with({ tagged_picker("a", "projects"), tagged_picker("b", "projects") }),
				["session:b"] = view_with({ tagged_picker("c", "sessions"), tagged_picker("d", "sessions") }),
				["session:empty"] = { windows = {} },
			},
			sessions = { { session_id = "session:a" }, { session_id = "session:empty" }, { session_id = "session:b" } },
		})
		package.loaded["project-picker"] = nil
		local result = open(fake, action, { session_id = "session:empty", client_id = "client:app" })
		expect(result and result.layer_id, "fresh picker created")
		expect_equal(#fake.closed, 4, "all duplicate tags closed")
		expect_equal(
			#fake.views["session:a"].windows[1].layers + #fake.views["session:b"].windows[1].layers,
			0,
			"old owners empty"
		)
		expect_equal(#fake.layers, 1, "one new picker")
		expect_equal(#fake.windows, 1, "new host belongs to invoking session")
		expect_equal(fake.layers[1].session_id, "session:empty", "invoking session")
		local closes = 0
		for _, entry in ipairs(fake.log) do
			if entry.method == "session.close_layer" then
				closes = closes + 1
			elseif entry.method == "session.new_window" or entry.method == "session.new_layer" then
				expect_equal(closes, 4, "all closes finish before creating anything")
			end
		end
	end
end)

test(
	"discovery scans current first and leaves generic, tiled, wrong-flavor, multiblock and other-app decoys",
	function()
		for _, name in ipairs({ "projects", "sessions" }) do
			local tag = "rex.picker." .. name .. ":client:app"
			local function tagged(id, label, kind, flavor, multiple)
				local blocks = { terminal("block:" .. id, { label = label, flavor = flavor or TERM }) }
				if multiple then
					blocks[2] = terminal("block:extra")
				end
				return { layer_id = "layer:" .. id, kind = kind or "floating", blocks = blocks }
			end
			local decoys = {
				tagged("generic", name == "projects" and "Projects" or "Sessions"),
				tagged("tiled", tag, "tiled"),
				tagged("browser", tag, "floating", "com.superlogical.browser"),
				tagged("multiple", tag, "floating", TERM, true),
				tagged("different-app", "rex.picker." .. name .. ":client:other"),
			}
			local fake = install({
				views = { ["session:a"] = view_with(decoys), ["session:b"] = view_with({ tagged("other", tag) }) },
				sessions = { { session_id = "session:b" }, { session_id = "session:a" } },
			})
			local result = open(fake, name == "projects" and "project_picker" or "session_picker", {
				session_id = "session:a",
				client_id = "client:app",
			})
			expect(result.layer_id ~= "layer:other", "exact reserved singleton terminal replaced")
			expect_equal(fake.closed[1].layer_id, "layer:other", "only owned picker closed")
			expect_equal(#fake.layers, 1, "fresh creation")
			expect_equal(#decoys, 6, "decoys plus fresh picker")
			for index = 1, 5 do
				expect_equal(
					decoys[index].layer_id,
					"layer:" .. ({ "generic", "tiled", "browser", "multiple", "different-app" })[index],
					"decoy retained"
				)
			end
			decoys[#decoys + 1] = tagged("current", tag)
			fake.views["session:b"].windows[1].layers = { tagged("other-again", tag) }
			package.loaded["project-picker"] = nil
			local baseline = #fake.log
			result = open(fake, name == "projects" and "project_picker" or "session_picker", {
				session_id = "session:a",
				client_id = "client:app",
			})
			expect(result.layer_id ~= "layer:current", "current picker also replaced")
			expect_equal(#fake.closed, 4, "all current and other duplicates closed")
			local viewed = {}
			for index = baseline + 1, #fake.log do
				local entry = fake.log[index]
				if entry.method == "session.view" then
					viewed[#viewed + 1] = entry.args.session_id
				elseif entry.method == "session.close_layer" then
					expect(#viewed >= 2, "complete scan before first close")
				end
			end
			expect_equal(viewed[1], "session:a", "current scanned first")
			expect_equal(viewed[2], "session:b", "other session still scanned")
		end
	end
)

test("discovery skips vanished sessions but propagates unexpected failures and unlocks retry", function()
	local env = {
		views = { ["session:a"] = view_with({}) },
		sessions = { { session_id = "session:gone" } },
	}
	local fake = install(env)
	local ctx = { session_id = "session:a", client_id = "client:app" }
	local first = open(fake, "project_picker", ctx)
	expect_equal(#fake.layers, 1, "missing other session skipped")
	close_picker(fake, first)
	package.loaded["project-picker"] = nil
	env.on_call = function(method, args)
		if method == "session.view" and args.session_id == "session:gone" then
			error("discovery denied")
		end
	end
	local ok, err = pcall(open, fake, "project_picker", ctx)
	expect(not ok and tostring(err):find("discovery denied", 1, true), "unexpected error propagated")
	expect_equal(#fake.layers, 1, "no creation on failed scan")
	env.on_call = nil
	fake.actions.project_picker.run(ctx, {})
	expect_equal(#fake.layers, 2, "retry unblocked and discovers again")
end)

test("failed discovery never closes a partial scan and cross-type retry scans every owner again", function()
	local env = {
		views = {
			["session:a"] = view_with({ tagged_picker("first", "projects") }),
			["session:b"] = view_with({ tagged_picker("last", "sessions") }),
		},
		sessions = { { session_id = "session:b" }, { session_id = "session:a" } },
		rpc_errors = {},
	}
	local fake = install(env)
	env.on_call = function(method, args)
		if method == "session.view" and args.session_id == "session:b" then
			env.rpc_errors[method] = "scan denied"
		end
	end
	local ctx = { session_id = "session:a", client_id = "client:app" }
	local ok, err = pcall(open, fake, "project_picker", ctx)
	expect(not ok and tostring(err):find("scan denied", 1, true), "scan error propagated")
	expect_equal(#fake.closed + #fake.layers, 0, "partial discovery neither closes nor creates")
	env.on_call, env.rpc_errors = nil, {}
	fake.actions.session_picker.run(ctx, {})
	expect_equal(#fake.closed, 2, "retry finds all candidates")
	expect_equal(#fake.layers, 1, "only completed retry creates")
	expect_equal(fake.layers[1].layout.block.label, "rex.picker.sessions:client:app", "cross-type retry released")
end)

test("partial discovery close failure rescans and closes every remaining layer before replacement", function()
	for _, closes_before_failure in ipairs({ 0, 1, 2 }) do
		local env = {
			views = {
				["session:a"] = view_with({
					tagged_picker("first", "projects"),
					tagged_picker("duplicate", "projects"),
				}),
				["session:b"] = view_with({ tagged_picker("last", "sessions") }),
			},
			sessions = { { session_id = "session:b" }, { session_id = "session:a" } },
			rpc_errors = {},
		}
		local fake = install(env)
		env.on_call = function(method)
			if method == "session.close_layer" and #fake.closed == closes_before_failure then
				env.rpc_errors[method] = "close denied"
			end
		end
		local ctx = { session_id = "session:a", client_id = "client:app" }
		local ok, err = pcall(open, fake, "project_picker", ctx)
		expect(not ok and tostring(err):find("close denied", 1, true), "close error propagated")
		expect_equal(#fake.closed, closes_before_failure, "successful prefix closed")
		expect_equal(#fake.layers, 0, "no creation after partial failure")
		env.on_call, env.rpc_errors = nil, {}
		fake.actions.session_picker.run(ctx, {})
		expect_equal(#fake.closed, 3, "retry closes every remaining candidate")
		expect_equal(#fake.layers, 1, "one replacement after converged cleanup")
		expect_equal(#fake.views["session:b"].windows[1].layers, 0, "other owner empty")
		expect_equal(#fake.views["session:a"].windows[1].layers, 1, "one total picker")
	end
end)

test("closing known or rediscovered pickers refreshes placement after their window disappears", function()
	for _, reload in ipairs({ false, true }) do
		local env = { views = { ["session:a"] = view_with({}) } }
		local fake = install(env)
		local ctx = { session_id = "session:a", client_id = "client:app" }
		local first = open(fake, "project_picker", ctx)
		if reload then
			package.loaded["project-picker"] = nil
		end
		env.on_close = function()
			fake.views[ctx.session_id] = { windows = {} }
		end
		local result = open(fake, "session_picker", ctx)
		expect(result.layer_id ~= first.layer_id, "fresh picker")
		expect_equal(#fake.windows, 1, "removed window replaced with fresh host")
		expect_equal(fake.layers[2].window_id, "window:new1", "stale discovery window never reused")
		expect_equal(#fake.views[ctx.session_id].windows[1].layers, 1, "fresh picker actually placed")
	end
end)

test("exact stale layer or session errors permit one replacement without another global scan", function()
	for _, missing in ipairs({ "layer", "session" }) do
		local fake = install({ views = { ["session:a"] = view_with({}), ["session:b"] = view_with({}) } })
		local first = open(fake, "project_picker", { session_id = "session:a", client_id = "client:app" })
		if missing == "layer" then
			close_picker(fake, first)
		else
			fake.views["session:a"] = nil
		end
		local ctx = { session_id = "session:b", client_id = "client:app" }
		local second = fake.actions.project_picker.run(ctx, {})
		local third = fake.actions.project_picker.run(ctx, {})
		expect(second.layer_id ~= first.layer_id, "fresh layer after exact stale error")
		expect(third.layer_id ~= second.layer_id, "next action also replaces")
		expect_equal(#fake.layers, 3, "one launch per action")
		expect_equal(count(fake.calls, "session.view"), 3, "fresh placement view on each open")
	end
end)

test("plain close errors replace only a confirmed missing layer or owner session", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		for _, missing in ipairs({ "layer", "session" }) do
			local env = {
				views = { ["session:a"] = picker_view(), ["session:b"] = picker_view() },
				sessions = { { session_id = "session:a" }, { session_id = "session:b" } },
				rpc_errors = {},
			}
			local fake = install(env)
			local first = open(fake, action, { session_id = "session:a", client_id = "client:app" })
			if missing == "layer" then
				close_picker(fake, first)
				env.rpc_errors["session.close_layer"] = "layer " .. first.layer_id .. " not found"
			else
				fake.views["session:a"] = nil
				fake.session_list = { { session_id = "session:b" } }
				env.rpc_errors["session.close_layer"] = "session session:a not found"
				env.on_call = function(method, args)
					if method == "session.view" then
						env.rpc_errors[method] = args.session_id == "session:a" and "session session:a not found" or nil
					end
				end
			end
			local ctx = { session_id = "session:b", client_id = "client:app" }
			local second = fake.actions[action].run(ctx, {})
			expect(second.layer_id ~= first.layer_id, "confirmed stale picker replaced")
			expect_equal(#fake.layers, 2, "exactly one replacement")
			expect_equal(fake.layers[2].session_id, ctx.session_id, "replacement belongs to invoking session")
			env.rpc_errors["session.close_layer"] = nil
			local third = fake.actions[action].run(ctx, {})
			expect(third.layer_id ~= second.layer_id, "next action replaces after plain error")
			expect_equal(#fake.layers, 3, "one launch per request")
		end
	end
end)

test("failed close verification keeps a listed owner and releases the shared busy slot", function()
	for _, view_error in ipairs({ "session view denied", "request failed (code=session_not_found)" }) do
		local env = {
			views = { ["session:a"] = picker_view() },
			sessions = { { session_id = "session:a" } },
			rpc_errors = {},
		}
		local fake = install(env)
		local ctx = { session_id = "session:a", client_id = "client:app" }
		local first = open(fake, "project_picker", ctx)
		env.rpc_errors["session.close_layer"] = "close denied"
		env.rpc_errors["session.view"] = view_error
		local ok, err = pcall(fake.actions.project_picker.run, ctx, {})
		expect(not ok and tostring(err):find("close denied", 1, true), "original close failure propagated")
		expect_equal(#fake.layers, 1, "listed owner prevents a duplicate")
		env.rpc_errors = {}
		local retry = fake.actions.session_picker.run(ctx, {})
		expect(retry.layer_id ~= first.layer_id, "cross-type retry replaces retained instance")
		expect_equal(fake.closed[1].layer_id, first.layer_id, "ownership retained through failed verification")
	end
end)

test("failed owner lookup never creates a replacement and releases the busy slot", function()
	for _, owner_exists in ipairs({ false, true }) do
		local env = {
			views = { ["session:a"] = picker_view(), ["session:b"] = picker_view() },
			sessions = { { session_id = "session:a" }, { session_id = "session:b" } },
			rpc_errors = {},
		}
		local fake = install(env)
		local first = open(fake, "project_picker", { session_id = "session:a", client_id = "client:app" })
		if not owner_exists then
			fake.views["session:a"] = nil
			fake.session_list = { { session_id = "session:b" } }
		end
		env.rpc_errors["session.close_layer"] = "close failed"
		env.rpc_errors["session.view"] = "view failed"
		env.rpc_errors["session.list"] = "owner lookup failed"
		local ctx = { session_id = "session:b", client_id = "client:app" }
		local ok, err = pcall(fake.actions.project_picker.run, ctx, {})
		expect(not ok and tostring(err):find("owner lookup failed", 1, true), "lookup failure propagated")
		expect_equal(#fake.layers, 1, "unknown owner state prevents creation")
		env.rpc_errors = {}
		local retry = fake.actions.project_picker.run(ctx, {})
		expect(retry.layer_id ~= first.layer_id, "retry replaces retained or confirmed missing owner")
		expect_equal(#fake.layers, 2, "retry creates one replacement")
		expect_equal(#fake.closed, owner_exists and 1 or 0, "live owner closed before retry creates")
	end
end)

test("close and client lookup errors keep the instance and release the busy slot", function()
	for _, method in ipairs({ "session.attach_all", "session.close_layer", "client.list" }) do
		local errors = {
			"request failed (code=permission_denied)",
			"not_found in an unrelated message",
			"permission denied",
			"request timed out",
			"method not supported",
			"layer layer:1 not found",
		}
		if method ~= "session.close_layer" then
			errors[#errors + 1] = "request failed (code=not_found)"
			errors[#errors + 1] = "request failed (code=session_not_found)"
		end
		for _, message in ipairs(errors) do
			local env = {
				views = { ["session:a"] = view_with({}) },
				sessions = { { session_id = "session:a" } },
				rpc_errors = {},
			}
			local fake = install(env)
			local ctx = { session_id = "session:a", client_id = "client:app" }
			local first = open(fake, "project_picker", ctx)
			env.rpc_errors[method] = message
			local ok, err = pcall(fake.actions.project_picker.run, ctx, {})
			expect(not ok and tostring(err):find(message, 1, true), "original RPC failure propagates")
			expect_equal(#fake.layers, 1, "no duplicate on failure")
			env.rpc_errors[method] = nil
			local retry = fake.actions.session_picker.run(ctx, {})
			expect(retry.layer_id ~= first.layer_id, "cross-type retry replaces retained instance")
			expect_equal(fake.closed[1].layer_id, first.layer_id, "failed close did not forget ownership")
		end
	end
end)

test("ambiguous creation keeps files through recovered close failure and fresh acceptance", function()
	for _, response in ipairs({ "throw", "invalid" }) do
		local env = {
			views = { ["session:a"] = view_with({}), ["session:b"] = view_with({}) },
			sessions = { { session_id = "session:a" }, { session_id = "session:b", label = "target" } },
		}
		local fake = install(env)
		local ctx = { session_id = "session:a", client_id = "client:app" }
		if response == "throw" then
			env.on_layer = function()
				error("response lost after creation")
			end
		else
			env.layer_response = {}
		end
		local ok, err = pcall(open, fake, "session_picker", ctx)
		expect(
			not ok and tostring(err):find(response == "throw" and "response lost" or "Invalid picker layer", 1, true),
			"original ambiguous response propagates"
		)
		local command = fake.layers[1].layout.block.options.command
		local rows = read_file(command[3])
		expect_equal(read_file(command[4]), "", "choice file preserved")
		env.on_layer, env.layer_response = nil, nil
		env.rpc_errors = { ["session.close_layer"] = "close denied" }
		ok = pcall(fake.actions.project_picker.run, ctx, {})
		expect(not ok, "cross-type retry must close recovered picker")
		expect_equal(#fake.layers, 1, "failed recovered close cannot create")
		expect_equal(read_file(command[3]), rows, "rows remain available after failed close")
		local selected = choose_label("target")(nil, rows).stdout
		write_file(command[4], selected)
		expect_equal(read_file(command[4]), selected, "choice remains writable and readable")
		require("project-picker").run(launch_invocation(fake, command))
		expect_equal(fake.queued[1].args.session_id, "session:b", "preserved choice accepted")
		expect_equal(#fake.fzf_runs, 0, "acceptance does not restart fzf")
		env.rpc_errors = {}
		env.on_close = function()
			expect_equal(read_file(command[3]), rows, "recovered rows survive until close")
			expect_equal(read_file(command[4]), selected, "recovered choice survives until close")
		end
		local retry = fake.actions.project_picker.run(ctx, {})
		expect(retry.layer_id ~= "layer:1", "recovered picker replaced rather than returned")
		expect_equal(#fake.layers, 2, "one replacement after recovered close")
		expect_equal(fake.closed[1].layer_id, "layer:1", "recovered layer closed")
		env.on_close = nil
		fake.actions.session_picker.run(ctx, {})
		local fresh = fake.layers[3].layout.block.options.command
		write_file(fresh[4], choose_label("target")(nil, read_file(fresh[3])).stdout)
		require("project-picker").run(launch_invocation(fake, fresh))
		expect_equal(fake.queued[2].args.session_id, "session:b", "fresh replacement choice accepted")
	end
end)

test("unknown creation ownership retains files until retry proves layer presence or absence", function()
	for _, layer_exists in ipairs({ false, true }) do
		for _, lookup_fails in ipairs({ false, true }) do
			local env = {
				views = { ["session:a"] = view_with({}) },
				sessions = { { session_id = "session:a" } },
				rpc_errors = {},
			}
			local fake = install(env)
			local ctx = { session_id = "session:a", client_id = "client:app" }
			env.on_layer = function()
				if not layer_exists then
					close_picker(fake, { layer_id = "layer:1" })
				end
				env.rpc_errors["session.view"] = "recovery view denied"
				if lookup_fails then
					env.rpc_errors["session.list"] = "recovery lookup denied"
				end
				error("creation outcome unknown")
			end
			local ok, err = pcall(open, fake, "project_picker", ctx)
			expect(not ok and tostring(err):find("creation outcome unknown", 1, true), "creation error preserved")
			local command = fake.layers[1].layout.block.options.command
			local rows = read_file(command[3])
			expect_equal(read_file(command[4]), "", "unresolved choice file retained")
			env.on_layer = nil
			ok = pcall(fake.actions.session_picker.run, ctx, {})
			expect(not ok, "retry requires successful ownership lookup")
			expect_equal(#fake.layers, 1, "unknown outcome never creates a duplicate")
			expect_equal(read_file(command[3]), rows, "unresolved rows survive another failed lookup")
			expect_equal(read_file(command[4]), "", "unresolved choice survives another failed lookup")
			env.rpc_errors = {}
			if layer_exists then
				env.rpc_errors["session.close_layer"] = "recovered close denied"
				ok = pcall(fake.actions.session_picker.run, ctx, {})
				expect(not ok, "recovered presence must close before cross-type replacement")
				expect_equal(#fake.layers, 1, "failed recovered close prevents creation")
				expect_equal(read_file(command[3]), rows, "failed recovered close retains rows")
				write_file(command[4], "choice still writable")
				expect_equal(read_file(command[4]), "choice still writable", "failed close retains choice")
				env.rpc_errors = {}
			end
			local retry = fake.actions.session_picker.run(ctx, {})
			expect(retry.layer_id ~= "layer:1", "confirmed presence or absence permits fresh picker")
			expect_equal(#fake.layers, 2, "one replacement after proof")
			expect_equal(#fake.closed, layer_exists and 1 or 0, "recovered live layer closed")
			expect_equal(
				fake.layers[2].layout.block.label,
				"rex.picker.sessions:client:app",
				"latest requested source wins"
			)
			if not layer_exists then
				for _, path in ipairs({ command[3], command[4] }) do
					local file = io.open(path, "rb")
					if file then
						file:close()
					end
					expect(not file, "confirmed absent layer's abandoned file removed")
				end
			end
		end
	end
end)

test("failed creation retries rediscover and release the busy slot", function()
	for _, thrown in ipairs({ false, true }) do
		local env = { views = { ["session:a"] = view_with({}) } }
		env[thrown and "layer_throw" or "layer_error"] = "creation denied"
		local fake = install(env)
		local ctx = { session_id = "session:a", client_id = "client:app" }
		local ok = pcall(open, fake, "project_picker", ctx)
		expect(not ok, "creation error propagated")
		env.layer_throw, env.layer_error = nil, nil
		local retry = fake.actions.project_picker.run(ctx, {})
		expect(retry.layer_id ~= nil, "retry succeeds")
		expect_equal(count(fake.calls, "session.attach_all"), 3, "failed creation verifies absence then rescans")
		expect_equal(#fake.views["session:a"].windows[1].layers, 1, "only successful layer exists")
	end
end)

test("reentrant discovery, creation, and close coalesce both picker types behind the app guard", function()
	for _, boundary in ipairs({
		"session.attach_all",
		"session.view",
		"creation",
		"session.close_layer",
	}) do
		local env = { views = { ["session:a"] = view_with({}) } }
		local fake = install(env)
		require("project-picker").setup({ roots = { tmp } })
		local ctx = { session_id = "session:a", client_id = "client:app" }
		local fired = false
		local function overlap()
			if fired then
				return
			end
			fired = true
			expect_equal(fake.actions.project_picker.run(ctx, {}), nil, "same source coalesces")
			expect_equal(fake.actions.session_picker.run(ctx, {}), nil, "other source also coalesces")
		end
		if boundary == "creation" then
			env.on_layer = overlap
		elseif boundary == "session.close_layer" then
			fake.actions.project_picker.run(ctx, {})
		end
		env.on_call = function(method)
			if method == boundary then
				overlap()
			end
		end
		local result = fake.actions.project_picker.run(ctx, {})
		expect(fired, "boundary exercised")
		expect(result and result.layer_id, "first opener returns IDs")
		expect_equal(#fake.layers, boundary == "session.close_layer" and 2 or 1, "only the first opener creates")
		expect_equal(#fake.views[ctx.session_id].windows[1].layers, 1, "one live picker total")
	end
end)

test("yielded discovery, creation, and close keep both types busy until completion", function()
	for _, boundary in ipairs({ "session.view", "creation", "session.close_layer" }) do
		local env = { views = { ["session:a"] = view_with({}) } }
		local fake = install(env)
		require("project-picker").setup({ roots = { tmp } })
		local ctx = { session_id = "session:a", client_id = "client:app" }
		if boundary == "session.close_layer" then
			fake.actions.project_picker.run(ctx, {})
		end
		local function pause()
			coroutine.yield("paused")
		end
		if boundary == "creation" then
			env.on_layer = pause
		else
			env.on_call = function(method)
				if method == boundary then
					pause()
				end
			end
		end
		local thread = coroutine.create(function()
			return fake.actions.project_picker.run(ctx, {})
		end)
		local ok, value = coroutine.resume(thread)
		expect(ok and value == "paused", tostring(value))
		expect_equal(fake.actions.project_picker.run(ctx, {}), nil, "overlap coalesced while suspended")
		expect_equal(fake.actions.session_picker.run(ctx, {}), nil, "cross-type overlap coalesced while suspended")
		env.on_call, env.on_layer = nil, nil
		ok, value = coroutine.resume(thread)
		expect(ok and value and value.layer_id, tostring(value))
		expect_equal(coroutine.status(thread), "dead", "open completed")
		expect_equal(#fake.layers, boundary == "session.close_layer" and 2 or 1, "one launch for suspended opener")
		local replacement = fake.actions.session_picker.run(ctx, {})
		expect(replacement.layer_id ~= value.layer_id, "shared slot released after yield")
		expect_equal(#fake.views[ctx.session_id].windows[1].layers, 1, "one live picker total")
	end
end)

test("overlapping client resolution converges on one picker for the resolved app", function()
	local env = { views = { ["session:a"] = view_with({}) } }
	local fake = install(env)
	require("project-picker").setup({ roots = { tmp } })
	local ctx = { session_id = "session:a", client_id = "client:app" }
	local threads = {}
	env.on_call = function(method)
		if method == "client.list" then
			coroutine.yield("resolving")
		end
	end
	for index = 1, 2 do
		threads[index] = coroutine.create(function()
			return fake.actions[index == 1 and "project_picker" or "session_picker"].run(ctx, {})
		end)
		local ok, value = coroutine.resume(threads[index])
		expect(ok and value == "resolving", tostring(value))
	end
	env.on_call = nil
	env.on_layer = function()
		coroutine.yield("creating")
	end
	local ok, first = coroutine.resume(threads[1])
	expect(ok and first == "creating", tostring(first))
	local second
	ok, second = coroutine.resume(threads[2])
	expect(ok and second == nil, "second resolved call coalesces before creation")
	env.on_layer = nil
	ok, first = coroutine.resume(threads[1])
	expect(ok and first and first.layer_id, tostring(first))
	second = fake.actions.project_picker.run(ctx, {})
	expect(second.layer_id ~= first.layer_id, "next invocation replaces completed instance")
	expect_equal(#fake.layers, 2, "coalesced overlap then fresh invocation")
	expect_equal(#fake.views[ctx.session_id].windows[1].layers, 1, "one live picker after overlapping lookup")
end)

test("a busy picker in one app does not block either picker type in another app", function()
	for _, action in ipairs({ "project_picker", "session_picker" }) do
		local env = {
			views = { ["session:a"] = view_with({}) },
			app_clients = { { client_id = "client:one" }, { client_id = "client:two" } },
		}
		local fake = install(env)
		require("project-picker").setup({ roots = { tmp } })
		env.on_layer = function()
			coroutine.yield("created")
		end
		local first = coroutine.create(function()
			return fake.actions.project_picker.run({ session_id = "session:a", client_id = "client:one" }, {})
		end)
		local ok, value = coroutine.resume(first)
		expect(ok and value == "created", tostring(value))
		env.on_layer = nil
		local other = fake.actions[action].run({ session_id = "session:a", client_id = "client:two" }, {})
		expect(other and other.layer_id, "other app opens without waiting")
		ok, value = coroutine.resume(first)
		expect(ok and value and value.layer_id, tostring(value))
		expect(value.layer_id ~= other.layer_id, "separate app instances")
		expect_equal(#fake.layers, 2, "one picker for each app")
		expect_equal(#fake.closed, 0, "other app never closes the pending picker")
	end
end)

test("Ctrl+t f opens the project picker and Ctrl+t d opens the session picker", function()
	local fake = install({ views = { ["session:a"] = view_with({}) } })
	assert(loadfile(rex_dir .. "/init.lua"))()
	expect_equal(fake.binds["ctrl+t>f"], "project_picker", "f binding")
	expect_equal(fake.binds["ctrl+t>d"], "session_picker", "d binding")
	for _, name in ipairs({ "project_picker", "session_picker" }) do
		expect_equal(fake.actions[name].args.client_id, "string?", name .. " takes an optional client_id")
	end
	fake.actions.project_picker.run({ session_id = "session:a", client_id = "client:app" }, {})
	local invocation = launch_invocation(fake, fake.layers[1].layout.block.options.command)
	local home = os.getenv("HOME")
	expect_equal(
		table.concat(invocation.roots, ","),
		home .. "/anyfin," .. home .. "/personal," .. home .. "/.dotfiles",
		"roots"
	)
end)

test("both pickers open the same centered card in the invoking block's window", function()
	local layers, invocations = {}, {}
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
		invocations[action] = launch_invocation(fake, fake.layers[1].layout.block.options.command)
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
	expect_equal(command[1], "/bin/sh", "nonlogin wrapper")
	expect_equal(command[2], rex_dir .. "/picker-launch.sh", "launch script")
	expect_equal(command[5], "client:app", "destination app")
	expect_equal(command[6], rex_dir .. "/picker-runner.lua", "accepted choice runner")
	expect_equal(command[8], FZF, "resolved fzf runs before the choice runner")
	expect_equal(invocations.project_picker.choice_file, command[4], "choice output")
end)

test("an explicit client_id targets that app when two apps are connected", function()
	local fake = install({
		app_clients = { { client_id = "client:one" }, { client_id = "client:two" } },
		views = { ["session:a"] = picker_view() },
		size = { desired = { size_report(400, 120, 1, "client:one"), size_report(200, 60, 1, "client:two") } },
	})
	open(fake, "session_picker", { session_id = "session:a", client_id = "client:cli" }, { client_id = "client:two" })
	local command = fake.layers[1].layout.block.options.command
	expect_equal(command[5], "client:two", "runner acts on the named app")
	local invocation = launch_invocation(fake, command)
	expect_equal(invocation.client_id, "client:two", "invocation client")
	expect_equal(invocation.source, "sessions", "invocation source")
	expect_equal(table.concat(fake.layers[1].bounds, ","), "0.25,0.25,0.5,0.5", "requested app's viewport")
	expect(fake.client_lists[1].session_id == nil, "apps are not filtered by session attachment")
end)

test("a key press targets the app that pressed it when two apps are connected", function()
	local fake = install({
		app_clients = { { client_id = "client:one" }, { client_id = "client:two" } },
		views = { ["session:a"] = view_with({}) },
	})
	open(fake, "project_picker", { session_id = "session:a", client_id = "client:one" })
	expect_equal(fake.layers[1].layout.block.options.command[5], "client:one", "invoking app")
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
	local fake = install({ views = { ["session:empty"] = { windows = {} } }, index_view = { entries = {} } })
	open(
		fake,
		"project_picker",
		{ session_id = "session:empty", client_id = "client:cli" },
		{ client_id = "client:app" }
	)
	expect_equal(#fake.windows, 1, "shell window created")
	expect_equal(fake.windows[1].layout.block.flavor, TERM, "normal shell")
	expect_equal(fake.layers[1].window_id, "window:new1", "picker opens in that window")
	expect_equal(table.concat(fake.layers[1].bounds, ","), "0.05,0.075,0.9,0.85", "immediate fallback bounds")
	expect(position(fake, "session.new_window") < position(fake, "session.new_layer"), "window first")
	invoke(fake, {})
	expect_equal(#fake.windows, 1, "cancel leaves the shell window usable")
	expect_equal(#fake.resizes + #fake.queued + #fake.created, 0, "cancel neither resizes nor selects")
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
			{ session_id = "session:untitled", label = "" },
			{ session_id = "session:tab", label = "a\tb" },
		},
	})
	invoke(fake, { source = "sessions" })
	local run = fake.fzf_runs[1]
	local rows = shown_rows(run.stdin)
	expect_equal(rows[2], "work  #11111111", "first duplicate")
	expect_equal(rows[3], "work  #22222222", "second duplicate")
	expect_equal(rows[4], "Untitled", "unnamed other session")
	expect_equal(rows[5], "a\\x09b", "escaped label")
	expect_equal(#rows, 5, "current session excluded")
	expect_equal(argument(run.argv, "--border-label"), " Sessions ", "title")
	expect_equal(argument(run.argv, "--prompt"), "session> ", "prompt")
	expect(argument(run.argv, "--header"):find("Ctrl-R", 1, true), "keyboard help")
	expect(not table.concat(run.argv, "\n"):find("load:", 1, true), "the session list is already fresh")
	expect_equal(#fake.queued + #fake.windows, 0, "cancel selects nothing")
	expect_equal(count(fake.calls, "session.view"), 0, "browsing does not touch other sessions")
end)

test("excluding the current session leaves unique labels and an empty state when alone", function()
	local fake = install({
		session_id = "session:here",
		sessions = {
			{ session_id = "session:here", label = "work" },
			{ session_id = "session:other", label = "work" },
		},
	})
	invoke(fake, { source = "sessions" })
	local rows = shown_rows(fake.fzf_runs[1].stdin)
	expect_equal(rows[2], "work", "hidden session does not disambiguate the visible label")
	expect_equal(#rows, 2, "only the other session is selectable")
	fake = install({ session_id = "session:here", sessions = { { session_id = "session:here", label = "work" } } })
	invoke(fake, { source = "sessions" })
	rows = shown_rows(fake.fzf_runs[1].stdin)
	expect_equal(#rows, 1, "no selectable sessions when alone")
	expect_equal(rows[1], "No other Rex sessions", "empty-state notice")
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
	local big = fitted_bounds({ columns = 200, rows = 60 })
	expect(near(big[3], 0.5) and near(big[4], 0.5), "scales to 100x30")
	expect(near(big[1], 0.25) and near(big[2], 0.25), "centered")
	local small = fitted_bounds({ columns = 50, rows = 15 })
	expect(near(small[3], 0.9) and near(small[4], 0.85), "capped")
	expect(near(small[1], 0.05) and near(small[2], 0.075), "capped and centered")
	expect_equal(table.concat(fitted_bounds(), ","), "0.05,0.075,0.9,0.85", "missing viewport uses centered caps")
end)

test("both pickers are created at final bounds before their runner starts", function()
	for _, source in ipairs({ "projects", "sessions" }) do
		local fake = install({
			views = { ["session:a"] = picker_view() },
			size = {
				columns = 80,
				rows = 24,
				owner = "client:other",
				desired = { size_report(300, 90, 1, "client:other"), size_report(200, 60, 1) },
			},
			index_view = { entries = {} },
		})
		open(fake, source == "projects" and "project_picker" or "session_picker", {
			session_id = "session:a",
			block_id = "block:host",
			client_id = "client:app",
		})
		expect_equal(table.concat(fake.layers[1].bounds, ","), "0.25,0.25,0.5,0.5", "final initial placement")
		expect(position(fake, "block.method") < position(fake, "session.new_layer"), "measurement before creation")
		local probes = count(fake.calls, "block.method")
		invoke(fake, { source = source })
		expect_equal(#fake.resizes, 0, "no post-open resize")
		expect_equal(count(fake.calls, "block.method"), probes, "runner does not probe geometry")
		expect_equal(fake.login_calls, 1, "no login shell in the runner")
	end
end)

test("a changed viewport affects the next open, never the running picker", function()
	local fake
	fake = install({
		views = { ["session:a"] = picker_view() },
		size = { desired = { size_report(200, 60, 1) } },
		index_view = { entries = {} },
		fzf = function()
			fake.size = { desired = { size_report(400, 120, 2) } }
			return { code = 130, stdout = "", stderr = "" }
		end,
	})
	require("project-picker").setup({ roots = { tmp } })
	local ctx = { session_id = "session:a", block_id = "block:host", client_id = "client:app" }
	local first = fake.actions.project_picker.run(ctx, {})
	invoke(fake, {})
	expect_equal(table.concat(fake.layers[1].bounds, ","), "0.25,0.25,0.5,0.5", "first bounds stay unchanged")
	close_picker(fake, first)
	fake.actions.project_picker.run(ctx, {})
	expect_equal(table.concat(fake.layers[2].bounds, ","), "0.375,0.375,0.25,0.25", "next open recomputes bounds")
	expect_equal(#fake.resizes, 0, "no resize")
	expect_equal(fake.login_calls, 1, "PATH captured once for both opens")
end)

test("both pickers reuse the login PATH and absolute fzf captured once at setup", function()
	local fake = install({
		views = { ["session:a"] = view_with({}) },
		index_view = { entries = {} },
	})
	local picker = require("project-picker")
	expect_equal(#fake.exec_runs, 0, "requiring the module does not start a shell")
	picker.setup({ roots = { tmp } })
	expect_equal(fake.login_calls, 1, "one capture for both registered actions")
	for _, name in ipairs({ "project_picker", "session_picker", "project_picker" }) do
		local result = fake.actions[name].run({ session_id = "session:a", client_id = "client:app" }, {})
		local options = fake.layers[#fake.layers].layout.block.options
		expect_equal(options.shell, "none", "no startup shell")
		expect_equal(options.login, false, "no macOS login wrapper")
		expect_equal(options.command[1], "/bin/sh", "explicit nonlogin wrapper")
		expect_equal(options.command[8], FZF, "direct resolved executable")
		expect_equal(launch_invocation(fake, options.command).fzf, FZF, "retry snapshot retains the executable")
		expect_equal(table.concat(options.path_prepend, ":"), "/opt/tools:/usr/bin:/bin", "noise-free login PATH")
		expect_equal(options.env, nil, "terminal options do not support env")
		close_picker(fake, result)
	end
	invoke(fake, {})
	expect_equal(fake.login_calls, 1, "no shell capture on keypress or run")
end)

test("failed or malformed login environment capture aborts setup", function()
	for _, result in ipairs({
		{ code = 1, stdout = "", stderr = "denied" },
		{ code = 0, stdout = "noise", stderr = "" },
		{ code = 0, stdout = "\0rex-picker-environment\0\0/opt/tools/fzf\0", stderr = "" },
		{ code = 0, stdout = "\0rex-picker-environment\0/bin\0\0", stderr = "" },
		{ code = 0, stdout = "\0rex-picker-environment\0/bin\0fzf\0", stderr = "" },
		{ code = 0, stdout = "\0rex-picker-environment\0/bin\0/opt/tools/fzf", stderr = "" },
	}) do
		local fake = install({ login_result = result })
		local ok, err = pcall(require("project-picker").setup, { roots = { tmp } })
		expect(not ok and tostring(err):find("login-shell", 1, true), "failed capture reports its boundary")
		expect_equal(#fake.actions, 0, "no actions registered")
	end
	local fake = install({ login_error = "spawn error" })
	local ok, err = pcall(require("project-picker").setup, { roots = { tmp } })
	expect(not ok and tostring(err):find("spawn error", 1, true), "exec nil/error contract")
	expect_equal(#fake.actions, 0, "no actions registered")
end)

test("the zsh login capture bypasses mise shims but preserves an earlier normal fzf", function()
	local directory = tmp .. "/login it's {a}"
	local normal, shims, bin = directory .. "/normal", directory .. "/shims", directory .. "/bin"
	local resolved, log = directory .. "/resolved fzf", directory .. "/mise-calls"
	sh('mkdir -p "$1" "$2" "$3"', normal, shims, bin)
	write_file(normal .. "/fzf", "#!/bin/sh\nexit 0\n")
	write_file(resolved, "#!/bin/sh\nexit 0\n")
	write_file(
		bin .. "/mise",
		"#!/bin/sh\nprintf '%s\\n' \"$*\" >> " .. quote(log) .. "\nprintf '%s\\n' " .. quote(resolved) .. "\n"
	)
	sh('chmod +x "$1" "$2" "$3"; ln -s "$3" "$4"', normal .. "/fzf", resolved, bin .. "/mise", shims .. "/fzf")
	for _, use_mise in ipairs({ false, true }) do
		write_file(log, "")
		local path = (use_mise and shims or normal .. ":" .. shims) .. ":" .. bin
		local fake = install({
			login_prefix = "export PATH=" .. quote(path) .. "; ",
			fzf_executable = use_mise and resolved or normal .. "/fzf",
			views = { ["session:a"] = view_with({}) },
		})
		require("project-picker").setup({ roots = { tmp } })
		for _, action in ipairs({ "project_picker", "session_picker" }) do
			fake.actions[action].run({ session_id = "session:a", client_id = "client:app" }, {})
			local options = fake.layers[#fake.layers].layout.block.options
			expect_equal(options.command[8], use_mise and resolved or normal .. "/fzf", "selected executable")
			expect_equal(table.concat(options.path_prepend, ":"), path, "captured PATH")
		end
		expect_equal(#fake.exec_runs, 1, "only setup starts a process")
		local invocation = launch_invocation(fake, fake.layers[1].layout.block.options.command)
		invocation.choice_file = nil
		invoke(fake, invocation)
		expect_equal(fake.fzf_runs[1].argv[1], use_mise and resolved or normal .. "/fzf", "retry executable")
		expect_equal(read_file(log), use_mise and "which fzf\n" or "", "mise only resolves the shim once")
	end
	for _, mode in ipairs({ "missing", "nonexecutable", "directory", "relative", "mise failure" }) do
		if mode == "nonexecutable" then
			sh('chmod -x "$1"', resolved)
		elseif mode == "directory" then
			sh('rm -f "$1"; mkdir "$1"', resolved)
		elseif mode == "relative" then
			write_file(bin .. "/mise", "#!/bin/sh\nprintf 'relative/fzf\\n'\n")
		elseif mode == "mise failure" then
			write_file(bin .. "/mise", "#!/bin/sh\nexit 1\n")
		end
		local path = mode == "missing" and bin or shims .. ":" .. bin
		local fake = install({ login_prefix = "export PATH=" .. quote(path) .. "; " })
		local ok, err = pcall(require("project-picker").setup, { roots = { tmp } })
		expect(not ok and tostring(err):find("fzf", 1, true), mode .. " reports failed fzf resolution")
		expect_equal(#fake.actions, 0, "invalid executable registers no actions")
	end
end)

test("split and zoomed hosts measure the owning window rather than the active window", function()
	for _, zoomed in ipairs({ false, true }) do
		local view = picker_view()
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
			views = { ["session:a"] = view },
			app_clients = { { client_id = "client:app" }, { client_id = "client:other" } },
			sizes = {
				["block:decoy"] = { desired = { size_report(900, 900, 1, zoomed and "client:app" or "client:other") } },
				["block:host"] = { desired = { size_report(zoomed and 200 or 100, zoomed and 60 or 30, 1) } },
			},
			index_view = { entries = {} },
		})
		open(fake, "project_picker", {
			session_id = "session:a",
			block_id = "block:host",
			client_id = "client:app",
		})
		expect_equal(fake.layers[1].window_id, "window:1", "invoking window, not active window")
		expect_equal(table.concat(fake.layers[1].bounds, ","), "0.25,0.25,0.5,0.5", "whole window measured")
		for _, entry in ipairs(fake.log) do
			if entry.method == "block.method" then
				expect_equal(entry.args.session_id, "session:a", "session ID comes from action context")
			end
		end
	end
end)

test("missing, invalid, foreign and vanished size reports use immediate stable fallback", function()
	for _, case in ipairs({
		{ size = { desired = {} } },
		{ size = { desired = { size_report(0, 60, 1), size_report(200, 0, 2), size_report(1.5, 60, 3) } } },
		{ size = { desired = { size_report(200, 60, 1, "client:other") } } },
		{ rpc_errors = { ["block.method"] = "request failed (status=404 code=not_found)" } },
	}) do
		case.views = { ["session:a"] = picker_view() }
		case.index_view = { entries = {} }
		local fake = install(case)
		open(fake, "project_picker", { session_id = "session:a", client_id = "client:app" })
		expect_equal(table.concat(fake.layers[1].bounds, ","), "0.05,0.075,0.9,0.85", "immediate capped fallback")
		expect_equal(count(fake.calls, "block.method"), 1, "one immediate report read, no retries")
		fake.size = { desired = { size_report(200, 60, 2) } }
		invoke(fake, {})
		expect_equal(#fake.resizes, 0, "late report cannot resize the picker")
	end
end)

test("placement RPC failures propagate before creating a picker", function()
	for _, method in ipairs({ "session.view", "block.method" }) do
		local fake = install({
			views = { ["session:a"] = picker_view() },
			size = { desired = { size_report(200, 60, 1) } },
			rpc_errors = { [method] = method .. " denied" },
			index_view = { entries = {} },
		})
		local ok, err = pcall(open, fake, "project_picker", { session_id = "session:a", client_id = "client:app" })
		expect(not ok and tostring(err):find(method .. " denied", 1, true), "RPC failure must not look successful")
		expect_equal(#fake.layers + #fake.fzf_runs, 0, "nothing opened")
	end
end)

test("nonterminal hosts and absent layout rectangles open without geometry waits", function()
	for _, browser in ipairs({ true, false }) do
		local view = picker_view()
		local host = view.windows[1].layers[1]
		if browser then
			host.blocks[1].flavor = "com.superlogical.browser"
		else
			host.layout = nil
		end
		local fake = install({ views = { ["session:a"] = view }, index_view = { entries = {} } })
		open(fake, "project_picker", { session_id = "session:a", client_id = "client:app" })
		expect_equal(table.concat(fake.layers[1].bounds, ","), "0.05,0.075,0.9,0.85", "fallback placement")
		expect_equal(count(fake.calls, "block.method"), 0, "unmeasurable host is not probed")
		invoke(fake, {})
		expect_equal(#fake.resizes, 0, "no resize after cancel")
	end
end)

test("blocking fzf execution failures and crashes are reported", function()
	local fake = install({ exec_error = "no such file", index_view = { entries = {} } })
	local ok, err = pcall(invoke, fake, {})
	expect(not ok and tostring(err):find("no such file", 1, true), tostring(err))

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
		expect_equal(argv[1], "fzf", "standalone runner defaults to PATH lookup")
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

test("cached project rows open without automatic discovery and keep manual rescan", function()
	local fake = install({
		index_view = { entries = { { path = tmp .. "/cached", label = "cached" } }, notice = "cached notice" },
		open = function()
			error("opening warm rows must not rescan")
		end,
	})
	invoke(fake, {})
	local run = fake.fzf_runs[1]
	expect_equal(shown_rows(run.stdin)[1], "cached notice", "cached notice preserved")
	expect_equal(shown_rows(run.stdin)[2], "cached", "cached row available immediately")
	expect(not table.concat(run.argv, "\n"):find("load:", 1, true), "warm cache has no automatic reload")
	expect(argument(run.argv, "--bind"):match("^ctrl%-r:reload%-sync:"), "Ctrl-R still rescans")
	expect_equal(#fake.exec_runs, 1, "only fzf runs on the warm browsing path")
	expect_equal(fake.cached_calls, 1, "one cached read")
end)

test("empty project rows start automatic initial discovery after fzf loads", function()
	local fake = install({
		index_view = { entries = {}, notice = "Discovering Git repositories..." },
		open = function()
			error("initial rows must be shown before discovery")
		end,
	})
	invoke(fake, {})
	local run = fake.fzf_runs[1]
	expect_equal(shown_rows(run.stdin)[1], "Discovering Git repositories...", "initial discovery notice")
	expect(argument(run.argv, "--bind"):match("^load:unbind%(load%)%+reload%-sync:"), "load triggers first discovery")
	expect_equal(#fake.exec_runs, 1, "initial rows do not wait for discovery")
	expect_equal(fake.login_calls, 0, "runner never captures a login PATH")
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

test("session reload rows exclude the invoking session rather than the script session", function()
	install({
		session_id = "session:one",
		sessions = {
			{ session_id = "session:here", label = "here" },
			{ session_id = "session:one", label = "one" },
		},
	})
	local written = {}
	io.write = function(text)
		written[#written + 1] = text
	end
	local ok, err = pcall(require("project-picker").rows, { source = "sessions", session_id = "session:here" })
	io.write = real_write
	assert(ok, err)
	local rows = shown_rows(table.concat(written))
	expect_equal(rows[2], "one", "other session row")
	expect_equal(#rows, 2, "refresh still excludes the invoking session")
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

test("opening actions prepare private fresh rows without starting processes", function()
	local env = {
		views = { ["session:a"] = picker_view() },
		index_view = { entries = { { path = tmp .. "/old", label = "old" } } },
	}
	local fake = install(env)
	local picker = require("project-picker")
	picker.setup({ roots = { tmp } })
	expect_equal(fake.cached_calls, 1, "setup primes the repository context")
	local baseline = #fake.exec_runs
	local ctx = { session_id = "session:a", client_id = "client:app" }
	local first_result = fake.actions.project_picker.run(ctx, {})
	local first = fake.layers[1].layout.block.options.command
	expect_equal(shown_rows(read_file(first[3]))[2], "old", "first cache contents")
	env.index_view = { entries = { { path = tmp .. "/new", label = "new" } } }
	close_picker(fake, first_result)
	fake.actions.project_picker.run(ctx, {})
	local second = fake.layers[2].layout.block.options.command
	expect_equal(shown_rows(read_file(second[3]))[2], "new", "cache read again on the next action")
	expect_equal(shown_rows(read_file(first[3]))[2], "old", "pending picker owns its snapshot")
	expect(first[3] ~= second[3] and first[4] ~= second[4], "successive pickers have separate files")
	expect_equal(fake.cached_calls, 3, "prime plus one read per opening")
	for _, command in ipairs({ first, second }) do
		expect_equal(read_file(command[4]), "", "choice output allocated empty")
		expect_equal(sh("stat -f '%Lp' \"$1\"", command[3]), "600", "private rows")
		expect_equal(sh("stat -f '%Lp' \"$1\"", command[4]), "600", "private choice")
		expect(not table.concat(command, "\n"):find("load:", 1, true), "warm rows have no automatic rescan")
	end
	fake.session_list = { { session_id = "session:first", label = "first" } }
	local session_result = fake.actions.session_picker.run(ctx, {})
	fake.session_list = { { session_id = "session:second", label = "second" } }
	close_picker(fake, session_result)
	fake.actions.session_picker.run(ctx, {})
	expect_equal(shown_rows(read_file(fake.layers[3].layout.block.options.command[3]))[2], "first", "first sessions")
	expect_equal(shown_rows(read_file(fake.layers[4].layout.block.options.command[3]))[2], "second", "fresh sessions")
	expect_equal(count(fake.calls, "session.list"), 2, "one current session list per opening")
	expect_equal(#fake.exec_runs, baseline, "no shell, discovery, Rex CLI, or fzf process on keypress")
	expect_equal(#fake.resizes, 0, "no resize")
end)

test("real repository context hashing happens at setup and never per opening", function()
	local fake = install({ views = { ["session:a"] = view_with({}) } })
	package.loaded["repository-index"] = assert(loadfile(rex_dir .. "/repository-index.lua"))()
	local picker = require("project-picker")
	picker.setup({ roots = { tmp .. "/context-prime-only" } })
	local hashes = 0
	for _, run in ipairs(fake.exec_runs) do
		if run.argv[1] == "/usr/bin/shasum" then
			hashes = hashes + 1
		end
	end
	expect_equal(hashes, 1, "one setup hash")
	local baseline = #fake.exec_runs
	for _ = 1, 3 do
		fake.actions.project_picker.run({ session_id = "session:a", client_id = "client:app" }, {})
	end
	expect_equal(#fake.exec_runs, baseline, "cached context avoids any opening process")
	local command = fake.layers[1].layout.block.options.command
	expect(argument(command, "--bind"):match("^load:unbind%(load%)%+reload%-sync:"), "cold cache discovers on load")
end)

test("opening session rows exclude the action context without script globals", function()
	for _, script_session in ipairs({ "", "session:other" }) do
		local fake = install({
			session_id = script_session ~= "" and script_session or nil,
			views = { ["session:here"] = view_with({}) },
			sessions = {
				{ session_id = "session:here", label = "here" },
				{ session_id = "session:other", label = "other" },
			},
		})
		open(fake, "session_picker", { session_id = "session:here", client_id = "client:app" })
		local rows = shown_rows(read_file(fake.layers[1].layout.block.options.command[3]))
		expect_equal(rows[2], "other", "script context does not hide another session")
		expect_equal(#rows, 2, "invoking session is excluded")
	end
end)

test("direct and retry fzf arguments and records agree for unusual roots and labels", function()
	local root = tmp .. "/it's {a}\ttab\nnewline"
	local label = 'it\'s {a} "b"\ttab\nnewline'
	local fake = install({
		views = { ["session:a"] = view_with({}) },
		index_view = { entries = { { path = root .. "/repo", label = label } } },
	})
	local picker = require("project-picker")
	picker.setup({ roots = { root } })
	fake.actions.project_picker.run({ session_id = "session:a", client_id = "client:app" }, {})
	local command = fake.layers[1].layout.block.options.command
	local invocation = launch_invocation(fake, command)
	invocation.choice_file = nil
	invoke(fake, invocation)
	local run = fake.fzf_runs[1]
	expect_equal(read_file(command[3]), run.stdin, "identical NUL records")
	local direct = {}
	for index = 8, #command do
		direct[#direct + 1] = command[index]
	end
	expect_equal(table.concat(direct, "\0"), table.concat(run.argv, "\0"), "one shared fzf argument protocol")
	expect_equal(launch_invocation(fake, command).roots[1], root, "exact root in the snapshot")
	expect_equal(shown_rows(run.stdin)[2], 'it\'s {a} "b"\\x09tab\\x0anewline', "safe shown label")
end)

test("failed preparation and layer creation remove only their own private files", function()
	for _, stage in ipairs({ "encode", "reload encode", "open", "write", "close", "tmpname", "layer", "throw" }) do
		local env = { views = { ["session:a"] = view_with({}) } }
		if stage == "layer" then
			env.layer_error = "layer denied"
		elseif stage == "throw" then
			env.layer_throw = "layer denied"
		end
		local fake = install(env)
		require("project-picker").setup({ roots = { tmp } })
		local sentinel = tmp .. "/unrelated"
		write_file(sentinel, "keep")
		local allocated, allocations, encodings = {}, 0, 0
		local real_tmpname, real_open, real_encode = os.tmpname, io.open, rex.json.encode
		os.tmpname = function()
			allocations = allocations + 1
			if stage == "tmpname" and allocations == 2 then
				error("tmpname denied")
			end
			local path = real_tmpname()
			allocated[#allocated + 1] = path
			return path
		end
		io.open = function(path, mode)
			if mode == "wb" and allocations == 2 then
				if stage == "open" then
					return nil, "open denied"
				elseif stage == "write" or stage == "close" then
					local file = assert(real_open(path, mode))
					return {
						write = function(_, text)
							if stage == "write" then
								return nil, "write denied"
							end
							return file:write(text)
						end,
						close = function()
							assert(file:close())
							return nil, "close denied"
						end,
					}
				end
			end
			return real_open(path, mode)
		end
		rex.json.encode = function(value)
			encodings = encodings + 1
			if stage == "encode" or (stage == "reload encode" and encodings == 2) then
				return nil, "encode denied"
			end
			return real_encode(value)
		end
		local ok, err = pcall(
			fake.actions.project_picker.run,
			{ session_id = "session:a", client_id = "client:app" },
			{}
		)
		os.tmpname, io.open, rex.json.encode = real_tmpname, real_open, real_encode
		expect(not ok and tostring(err):find("denied", 1, true), stage .. " propagates failure")
		expect_equal(#allocated, stage == "tmpname" and 1 or 2, stage .. " allocated files")
		for _, path in ipairs(allocated) do
			local file = io.open(path, "rb")
			if file then
				file:close()
			end
			expect(not file, stage .. " removes " .. path)
		end
		expect_equal(read_file(sentinel), "keep", "unrelated file survives " .. stage)
		expect_equal(#fake.layers, (stage == "layer" or stage == "throw") and 1 or 0, "no premature layer")
	end
end)

local function accepted_file(source, id, label, query)
	local env = {
		views = { ["session:host"] = view_with({}) },
		sessions = { { session_id = id, label = label } },
		index_view = { entries = { { path = id, label = label } } },
	}
	local fake = install(env)
	open(fake, source == "sessions" and "session_picker" or "project_picker", {
		session_id = "session:host",
		client_id = "client:app",
	})
	local command = fake.layers[1].layout.block.options.command
	local row = assert(read_file(command[3]):match("^[^%z]*%z([^%z]+)%z"), "one selectable row")
	write_file(command[4], (query or "") .. "\0" .. row .. "\0")
	return launch_invocation(fake, command)
end

test("accepted sessions select directly without fzf or loading either source", function()
	for _, empty in ipairs({ true, false }) do
		local invocation = accepted_file("sessions", "session:target", "target", "tar")
		local fake = install({
			views = { ["session:target"] = empty and {} or view_with({}) },
			fzf = function()
				error("accepted choice must not start fzf")
			end,
		})
		local real_open, reads = io.open, 0
		io.open = function(path, mode)
			if path == invocation.choice_file then
				reads = reads + 1
			end
			return real_open(path, mode)
		end
		local ok, err = pcall(invoke, fake, invocation)
		io.open = real_open
		assert(ok, err)
		expect_equal(reads, 1, "read accepted output once")
		expect_equal(fake.queued[1].args.session_id, "session:target", "exact chosen ID")
		expect_equal(#fake.windows, empty and 1 or 0, "only an empty destination gets a shell")
		expect_equal(#fake.exec_runs, 0, "no fzf or process before session selection")
		expect_equal(count(fake.calls, "session.list"), 0, "no source list")
		expect_equal(fake.cached_calls or 0, 0, "no cache read")
		expect(read_file(invocation.choice_file):find("tar\0", 1, true), "Lua leaves file ownership with the shell")
	end
end)

test("accepted projects preserve exact paths and reuse the matching window without fzf or cache", function()
	local label = "accepted it's {a}\tline\nnext"
	local repo = make_repo(label)
	for _, reuse in ipairs({ true, false }) do
		local invocation = accepted_file("projects", repo, label, "accepted")
		local fake = install({
			sessions = reuse and { { session_id = "session:existing", label = "existing" } } or {},
			views = {
				["session:existing"] = view_with(
					{ { kind = "tiled", blocks = { terminal("block:repo") } } },
					"window:repo"
				),
			},
			processes = { ["block:repo"] = repo },
		})
		invoke(fake, invocation)
		expect_equal(#fake.fzf_runs, 0, "no picker execution")
		expect_equal(fake.cached_calls or 0, 0, "no cache read")
		expect_equal(#fake.created, reuse and 0 or 1, "reuse or create once")
		if reuse then
			expect_equal(fake.queued[1].args.session_id, "session:existing", "existing session")
			expect_equal(fake.queued[1].args.window_id, "window:repo", "matching window")
			expect_equal(fake.focused[1].block_id, "block:repo", "matching block")
		else
			expect_equal(fake.created[1].label, label, "exact label")
			expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "exact repository")
		end
	end
end)

test("stale accepted choices retry with current rows, notice, and the original query", function()
	for _, source in ipairs({ "sessions", "projects" }) do
		local id = source == "sessions" and "session:vanished" or tmp .. "/vanished"
		local query = "it's {query}\ttext"
		local invocation = accepted_file(source, id, "vanished", query)
		local fake = install({
			sessions = { { session_id = "session:alive", label = "alive" } },
			index_view = { entries = { { path = tmp .. "/alive", label = "alive" } } },
		})
		invoke(fake, invocation)
		expect_equal(#fake.fzf_runs, 1, "only retry starts fzf")
		local run = fake.fzf_runs[1]
		expect_equal(run.argv[1], invocation.fzf, "retry uses the captured executable")
		expect_equal(run.argv[1], FZF, "no PATH or mise lookup on retry")
		expect_equal(argument(run.argv, "--query"), query, "query retained")
		local rows = shown_rows(run.stdin)
		expect(rows[1]:find("no longer", 1, true), "stale notice")
		expect_equal(rows[2], "alive", "current list loaded for retry")
		expect_equal(#fake.queued + #fake.created, 0, "nothing selected on retry cancel")
		expect(read_file(invocation.choice_file):find(query .. "\0", 1, true), "Lua does not delete choice file")
	end
end)

test("accepted files and blocking fzf reject the same malformed selection protocol", function()
	for _, output in ipairs({
		"",
		"query\0",
		"query\0status\ttext\t\0",
		"query\0zz\ttext\t74657874\0",
		"query\0" .. "73657373696f6e3a61\twrong\t74657874\0",
		"query\0" .. "73657373696f6e3a61\ttext\t74657874\0extra\0",
		"query\0" .. "73657373696f6e3a61\ttext\t74657874",
	}) do
		for _, pending in ipairs({ true, false }) do
			local path = tmp .. "/malformed-choice"
			write_file(path, output)
			local fake = install({
				fzf = function()
					return { code = 0, stdout = output, stderr = "" }
				end,
			})
			local invocation = { source = "sessions", choice_file = pending and path or nil }
			local ok, err = pcall(invoke, fake, invocation)
			expect(not ok and tostring(err):find("invalid selection", 1, true), "reject malformed output")
			expect_equal(#fake.queued + #fake.windows, 0, "nothing selected")
			expect_equal(read_file(path), output, "passed file never removed or rewritten")
		end
	end
end)

test("invalid or missing choice files fail before source loading", function()
	for _, path in ipairs({ false, {}, "", "bad\0path", tmp .. "/absent-choice" }) do
		local fake = install()
		local ok = pcall(invoke, fake, { source = "sessions", choice_file = path })
		expect(not ok, "invalid file boundary")
		expect_equal(#fake.exec_runs + #fake.calls, 0, "no source list or fzf")
	end
end)

test("launch wrapper runs fzf first, calls the matching Rex only on accept, and cleans up", function()
	local directory = tmp .. "/wrapper it's {a}\twith\nlines"
	sh('mkdir -p "$1"', directory)
	local fzf, rex = directory .. "/fzf", directory .. "/rex"
	write_file(
		fzf,
		[[#!/bin/sh
test "$FZF_DEFAULT_OPTS" = '' && test "$FZF_DEFAULT_OPTS_FILE" = '' || exit 90
printf 'fzf\000' >> "$PICKER_TEST_LOG"
printf '%s\000' "$@" >> "$PICKER_TEST_FZF_ARGS"
cat > "$PICKER_TEST_ROWS"
cat "$PICKER_TEST_OUTPUT"
test ! -e "$PICKER_TEST_REX_ARGS" || exit 91
exit "$PICKER_TEST_FZF_STATUS"
]]
	)
	write_file(
		rex,
		[[#!/bin/sh
test -f "$PICKER_TEST_INPUT" && test -f "$PICKER_TEST_CHOICE" || exit 92
IFS= read -r keyboard && test "$keyboard" = 'keyboard input' || exit 93
printf 'rex\000' >> "$PICKER_TEST_LOG"
printf '%s\000' "$@" > "$PICKER_TEST_REX_ARGS"
cat "$PICKER_TEST_CHOICE" > "$PICKER_TEST_SELECTED"
exit "$PICKER_TEST_REX_STATUS"
]]
	)
	sh('chmod +x "$1" "$2"', fzf, rex)
	for _, case in ipairs({
		{ fzf = 0, rex = 0, result = 0 },
		{ fzf = 0, rex = 7, result = 7 },
		{ fzf = 1, result = 0 },
		{ fzf = 130, result = 0 },
		{ fzf = 2, result = 2 },
		{ fzf = 127, result = 127 },
	}) do
		local input, choice = directory .. "/rows", directory .. "/choice"
		local log, fzf_args, rex_args = directory .. "/log", directory .. "/fzf-args", directory .. "/rex-args"
		local rows, output, selected = directory .. "/received", directory .. "/output", directory .. "/selected"
		os.remove(rex_args)
		write_file(log, "")
		write_file(fzf_args, "")
		write_file(input, "status\t\t\0id\ttext\tencoded\0")
		write_file(choice, "")
		write_file(output, "query\0id\ttext\tencoded\0")
		local sentinel = directory .. "/sentinel"
		write_file(sentinel, "keep")
		local client, runner, snapshot =
			"client:chosen", directory .. "/runner.lua", '{"source":"sessions","str":"it\'s {a}"}'
		local argv = {
			"/bin/sh",
			"-c",
			[[
export REX_BIN_DIR="$1" PICKER_TEST_LOG="$2" PICKER_TEST_FZF_ARGS="$3" PICKER_TEST_REX_ARGS="$4"
export PICKER_TEST_ROWS="$5" PICKER_TEST_OUTPUT="$6" PICKER_TEST_FZF_STATUS="$7" PICKER_TEST_REX_STATUS="$8"
export PICKER_TEST_INPUT="$9"
shift 9
export PICKER_TEST_CHOICE="$1" PICKER_TEST_SELECTED="$2"
export FZF_DEFAULT_OPTS='--bad-option' FZF_DEFAULT_OPTS_FILE='/bad/file'
shift 2
exec /bin/sh "$@" <<'PICKER_STDIN'
keyboard input
PICKER_STDIN
]],
			"wrapper-test",
			directory,
			log,
			fzf_args,
			rex_args,
			rows,
			output,
			tostring(case.fzf),
			tostring(case.rex or 0),
			input,
			choice,
			selected,
			rex_dir .. "/picker-launch.sh",
			input,
			choice,
			client,
			runner,
			snapshot,
			fzf,
			"--query",
			"it's {a}\ttab\nline",
		}
		local result = real_exec(argv)
		expect_equal(result.code, case.result, "wrapper exit status for fzf " .. case.fzf)
		expect_equal(read_file(rows), "status\t\t\0id\ttext\tencoded\0", "fzf receives file bytes")
		expect_equal(read_file(fzf_args), "--query\0it's {a}\ttab\nline\0", "fzf receives exact argv")
		expect_equal(read_file(log), case.fzf == 0 and "fzf\0rex\0" or "fzf\0", "Rex starts only after accept")
		if case.fzf == 0 then
			expect_equal(
				read_file(rex_args),
				"--autostart=false\0-C\0" .. client .. "\0do\0" .. runner .. "\0--args\0" .. snapshot .. "\0",
				"matching Rex invocation"
			)
			expect_equal(read_file(selected), read_file(output), "accepted output survives until Rex reads it")
		end
		for _, path in ipairs({ input, choice }) do
			local file = io.open(path, "rb")
			if file then
				file:close()
			end
			expect(not file, "shell owns cleanup on every exit")
		end
		expect_equal(read_file(sentinel), "keep", "cleanup touches only the two owned files")
	end
end)

test("launch wrapper cleans up after redirection failure", function()
	local input, choice = tmp .. "/absent-rows", tmp .. "/error-choice"
	write_file(choice, "")
	local result = real_exec({
		"/bin/sh",
		rex_dir .. "/picker-launch.sh",
		input,
		choice,
		"client:app",
		"/unused-runner",
		"{}",
		"/usr/bin/true",
	})
	expect(result.code ~= 0, "redirection failure propagates")
	local file = io.open(choice, "rb")
	if file then
		file:close()
	end
	expect(not file, "cleanup after redirection failure")
end)

for _, schedule in ipairs({ "blocked", "publication" }) do
	test("signalling only the wrapper reaps fzf or Rex during " .. schedule .. " before cleanup", function()
		local directory = tmp .. "/" .. schedule .. "-wrapper"
		sh('mkdir -p "$1"', directory)
		local launcher = rex_dir .. "/picker-launch.sh"
		if schedule == "publication" then
			local instrumented, points = read_file(launcher):gsub("([ \t]*)child=%$!\n", function(indent)
				return indent
					.. [[PICKER_TEST_LAUNCH_COUNT=$((${PICKER_TEST_LAUNCH_COUNT:-0} + 1))
if test "$PICKER_TEST_LAUNCH_COUNT" = "$PICKER_TEST_PAUSE_LAUNCH"; then
  printf '%s\n' "$!" > "$PICKER_TEST_PAUSED"
  kill -STOP "$$"
fi
]]
					.. indent
					.. "child=$!\n"
			end)
			expect(points > 0, "instrument a real fork-to-publication boundary")
			launcher = directory .. "/picker-launch.sh"
			write_file(launcher, instrumented)
		end
		local blocker = directory .. "/rex"
		write_file(
			blocker,
			[[#!/bin/sh
printf '%s\n' "$$" > "$PICKER_TEST_CHILD_PID"
exec /bin/sleep 30
]]
		)
		sh('chmod +x "$1"', blocker)
		for _, stage in ipairs({ "fzf", "rex" }) do
			for _, signal in ipairs({ "TERM", "HUP" }) do
				local input, choice = directory .. "/rows", directory .. "/choice"
				local pid_file, sentinel = directory .. "/child-pid", directory .. "/sentinel"
				local paused = directory .. "/paused"
				os.remove(pid_file)
				os.remove(paused)
				write_file(input, "rows")
				write_file(choice, "")
				write_file(sentinel, "keep")
				local result = real_exec({
					"/bin/sh",
					"-c",
					[[
export REX_BIN_DIR="$1" PICKER_TEST_CHILD_PID="$2"
signal=$3
export PICKER_TEST_PAUSE_LAUNCH="$4" PICKER_TEST_PAUSED="$5"
shift 5
/bin/sh "$@" </dev/null &
wrapper=$!
attempt=0
ready=0
while test "$attempt" -lt 200; do
  if test -s "$PICKER_TEST_CHILD_PID"; then
    if test "$PICKER_TEST_PAUSE_LAUNCH" = 0; then
      ready=1
      break
    elif test -s "$PICKER_TEST_PAUSED"; then
      case $(ps -o state= -p "$wrapper") in
      *T*) ready=1; break ;;
      esac
    fi
  fi
  sleep 0.01
  attempt=$((attempt + 1))
done
child=$(cat "$PICKER_TEST_CHILD_PID")
if test "$ready" != 1; then
  kill -KILL "$wrapper" ${child:+"$child"} 2>/dev/null
  wait "$wrapper"
  exit 90
fi
if test "$PICKER_TEST_PAUSE_LAUNCH" != 0; then
  test "$(cat "$PICKER_TEST_PAUSED")" = "$child" || exit 93
fi
kill -0 "$child" || exit 90
kill -"$signal" "$wrapper" || exit 91
if test "$PICKER_TEST_PAUSE_LAUNCH" != 0; then
  kill -CONT "$wrapper" || exit 92
fi
attempt=0
while kill -0 "$wrapper" 2>/dev/null && test "$attempt" -lt 200; do
  sleep 0.01
  attempt=$((attempt + 1))
done
timed_out=0
if kill -0 "$wrapper" 2>/dev/null; then
  timed_out=1
  kill -KILL "$child" "$wrapper" 2>/dev/null
fi
wait "$wrapper"
status=$?
child_alive=0
if kill -0 "$child" 2>/dev/null; then
  child_alive=1
  kill -KILL "$child" 2>/dev/null
fi
printf '%s %s %s\n' "$status" "$timed_out" "$child_alive"
]],
					"signal-test",
					directory,
					pid_file,
					signal,
					schedule == "publication" and (stage == "fzf" and "1" or "2") or "0",
					paused,
					launcher,
					input,
					choice,
					"client:app",
					"/unused-runner",
					"{}",
					stage == "fzf" and blocker or "/usr/bin/true",
				})
				expect_equal(result.code, 0, stage .. " signal test completed")
				expect_equal(result.stdout, (signal == "TERM" and "143" or "129") .. " 0 0\n", stage .. " " .. signal)
				for _, path in ipairs({ input, choice }) do
					local file = io.open(path, "rb")
					if file then
						file:close()
					end
					expect(not file, stage .. " signal removes owned file")
				end
				expect_equal(read_file(sentinel), "keep", "signal cleanup leaves unrelated files")
			end
		end
	end)
end

local failures = 0
for _, case in ipairs(tests) do
	local ok, err = pcall(case.fn)
	io.write = real_write
	for _, path in ipairs(owned_files) do
		os.remove(path)
	end
	owned_files = {}
	print((ok and "ok   " or "FAIL ") .. case.name .. (ok and "" or "\n     " .. tostring(err)))
	if not ok then
		failures = failures + 1
	end
end
os.execute("rm -rf " .. quote(tmp))
os.exit(failures == 0 and 0 or 1)
