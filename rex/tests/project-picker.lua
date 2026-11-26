local script = debug.getinfo(1, "S").source:gsub("^@", "")
if script:sub(1, 1) ~= "/" then
	script = (os.getenv("PWD") or ".") .. "/" .. script
end
local rex_dir = script:gsub("/tests/[^/]*$", "")
package.path = rex_dir .. "/?.lua;" .. package.path

local TERM = "com.superlogical.terminal.shell"
local RESCAN = "Rescan repositories"

local function quote(text)
	return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function real_exec(argv)
	local words = {}
	for index, arg in ipairs(argv) do
		words[index] = quote(arg)
	end
	local pipe = io.popen(table.concat(words, " ") .. ' </dev/null 2>/dev/null; echo "__exit:$?"')
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
		focused = {},
		prompts = {},
		exec_runs = {},
		cached_calls = 0,
		open_calls = 0,
		session_list = env.sessions or {},
		views = env.views or {},
		processes = env.processes or {},
	}
	local handlers = {
		["session.attach_all"] = function(args)
			assert(args.event_scope == "session", "no block event subscription")
			fake.subscribed = true
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
		["session.focus_block"] = function(args)
			fake.focused[#fake.focused + 1] = args
			return { revision = 1 }
		end,
	}
	rawset(_G, "rex", {
		call = function(method, args)
			fake.calls[#fake.calls + 1] = method
			fake.log[#fake.log + 1] = method
			local handler = assert(handlers[method], "unexpected rex.call " .. method)
			return handler(args)
		end,
		exec = function(argv)
			fake.exec_runs[#fake.exec_runs + 1] = argv
			return real_exec(argv)
		end,
		layout = {
			block = function(spec)
				return { block = spec }
			end,
		},
		client = {
			queue = function(action, args)
				fake.log[#fake.log + 1] = "queue:" .. action
				fake.queued[#fake.queued + 1] = { action = action, args = args }
			end,
		},
		ui = {
			pick = function(spec)
				fake.prompts[#fake.prompts + 1] = spec
				if env.pick then
					return env.pick(spec, #fake.prompts)
				end
				return nil, "cancelled"
			end,
		},
		action = function(spec)
			fake.actions[spec.name] = spec
		end,
		bind = function(key, action)
			fake.binds[key] = action
		end,
	})
	package.loaded["project-picker"] = nil
	package.loaded["repository-index"] = {
		cached = function()
			fake.cached_calls = fake.cached_calls + 1
			return env.views_sequence and env.views_sequence[fake.cached_calls] or env.index_view or { entries = {} }
		end,
		open = function(roots, fresh)
			fake.open_calls = fake.open_calls + 1
			assert(fresh, "the picker only asks for a fresh list")
			return assert(env.open, "unexpected repository discovery")(roots, fresh)
		end,
	}
	return fake
end

-- Answers each prompt in turn with the item shown under that title; nil cancels.
local function choose(...)
	local titles = { ... }
	return function(spec, prompt)
		local wanted = titles[prompt]
		if wanted == nil then
			return nil, "cancelled"
		end
		for _, item in ipairs(spec.items) do
			if item.title == wanted then
				return item.id
			end
		end
		error("no item shown as " .. wanted)
	end
end

local function titles(spec)
	local shown = {}
	for position, item in ipairs(spec.items) do
		shown[position] = item.title
	end
	return table.concat(shown, "|")
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
		if entry == method then
			return index
		end
	end
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

local function open(fake, ctx)
	require("project-picker").setup({ roots = { tmp } })
	return fake.actions.project_picker.run(ctx or { session_id = "session:a", client_id = "client:app" }, {})
end

test("Ctrl+t f opens the project picker and Ctrl+t d opens the built-in session switcher", function()
	local fake = install()
	assert(loadfile(rex_dir .. "/init.lua"))()
	expect_equal(fake.binds["ctrl+t>f"], "project_picker", "project picker key")
	expect_equal(fake.binds["ctrl+t>d"], "session.switch", "session switcher key")
	expect(fake.actions.project_picker, "project picker action")
	expect(not fake.actions.session_picker, "no custom session picker")
	expect_equal(fake.binds["ctrl+t>1"], "client.tab.goto", "prefixed tab key")
	expect(not fake.binds["cmd+1"], "cmd+1 stays the Rex default")
end)

test("the prompt is titled, lists repositories then rescan, and cancelling does nothing", function()
	local repo = make_repo("cancel")
	local fake = install({ index_view = { entries = { { path = repo, label = "cancel" } } } })
	open(fake)
	local spec = fake.prompts[1]
	expect_equal(spec.title, "Open Project Session", "title")
	expect_equal(spec.placeholder, "Filter projects", "placeholder")
	expect_equal(titles(spec), "cancel|" .. RESCAN, "items")
	expect_equal(spec.items[1].id, repo, "repository ID is its path")
	expect_equal(#fake.prompts, 1, "one prompt")
	expect_equal(#fake.queued + #fake.created, 0, "nothing selected")
	expect_equal(#fake.calls, 0, "no session scan on cancel")
end)

test("a warm cache opens without discovery and shows its notice", function()
	local fake = install({
		index_view = { entries = { { path = tmp .. "/cached", label = "cached" } }, notice = "cached notice" },
	})
	open(fake)
	expect_equal(fake.prompts[1].placeholder, "cached notice", "cached notice")
	expect_equal(titles(fake.prompts[1]), "cached|" .. RESCAN, "cached row")
	expect_equal(fake.open_calls, 0, "no discovery")
	expect_equal(#fake.exec_runs, 0, "no process on the warm path")
end)

test("an empty cache discovers repositories before prompting", function()
	local fake = install({
		index_view = { entries = {}, notice = "Discovering Git repositories..." },
		open = function()
			return { entries = { { path = tmp .. "/found", label = "found" } } }
		end,
	})
	open(fake)
	expect_equal(fake.open_calls, 1, "one discovery")
	expect_equal(titles(fake.prompts[1]), "found|" .. RESCAN, "discovered row")
	expect_equal(fake.prompts[1].placeholder, "Filter projects", "discovery notice cleared")
end)

test("no repositories and failed discovery are both explained in the prompt", function()
	local fake = install({
		open = function()
			return { entries = {} }
		end,
	})
	open(fake)
	expect_equal(fake.prompts[1].placeholder, "No Git repositories found under the configured roots", "empty")
	fake = install({
		open = function()
			return nil, "boom"
		end,
	})
	open(fake)
	expect_equal(fake.prompts[1].placeholder, "Refresh failed. boom", "failure")
	expect_equal(titles(fake.prompts[1]), RESCAN, "rescan stays available")
end)

test("rescan rediscovers and prompts again, keeping the cached list on failure", function()
	local attempts = 0
	local fake = install({
		index_view = { entries = { { path = tmp .. "/old", label = "old" } } },
		open = function()
			attempts = attempts + 1
			if attempts == 1 then
				return { entries = { { path = tmp .. "/new", label = "new" } } }
			end
			return nil, "boom"
		end,
		pick = choose(RESCAN, RESCAN),
	})
	open(fake)
	expect_equal(#fake.prompts, 3, "prompts")
	expect_equal(titles(fake.prompts[2]), "new|" .. RESCAN, "rescanned rows")
	expect_equal(fake.prompts[2].placeholder, "Filter projects", "no notice after a good rescan")
	expect_equal(titles(fake.prompts[3]), "new|" .. RESCAN, "previous rows kept")
	expect_equal(fake.prompts[3].placeholder, "Refresh failed. boom", "failure notice")
	expect_equal(#fake.queued + #fake.created, 0, "nothing selected")
end)

test("a repository without an existing session gets a new one", function()
	local repo = make_repo("fresh")
	local fake = install({
		sessions = { { session_id = "session:a", label = "a" } },
		views = { ["session:a"] = view_with({ { kind = "tiled", blocks = { terminal("block:a") } } }) },
		processes = { ["block:a"] = tmp },
		index_view = { entries = { { path = repo, label = "fresh" } } },
		pick = choose("fresh"),
	})
	open(fake)
	expect_equal(#fake.prompts, 1, "one prompt")
	expect_equal(#fake.created, 1, "created sessions")
	expect_equal(fake.created[1].label, "fresh", "label")
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "cwd")
	expect_equal(fake.queued[1].action, "session.select", "queued action")
	expect_equal(fake.queued[1].args.session_id, "session:new", "selected session")
end)

test("an existing session is reused from session.view snapshots without joining each session", function()
	local repo = make_repo("reuse")
	local fake = install({
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
			["block:other"] = tmp,
			["block:hit"] = repo .. "/nested/..",
		},
		index_view = { entries = { { path = repo, label = "reuse" } } },
		pick = choose("reuse"),
	})
	sh('mkdir -p "$1/nested"', repo)
	open(fake)
	expect_equal(#fake.created, 0, "created sessions")
	expect_equal(fake.queued[1].args.session_id, "session:hit", "reused session")
	expect_equal(fake.queued[1].args.window_id, "window:hit", "reused window")
	expect_equal(fake.focused[1].block_id, "block:hit", "reused terminal focused")
	expect_equal(count(fake.calls, "session.attach"), 0, "session.attach calls")
	expect_equal(count(fake.calls, "session.view"), 4, "one view per session")
end)

test("the invoking session is searched first and its own terminal counts as reuse", function()
	local repo = make_repo("current")
	local fake = install({
		sessions = {
			{ session_id = "session:other", label = "other" },
			{ session_id = "session:mine", label = "mine" },
		},
		views = {
			["session:other"] = view_with({ { kind = "tiled", blocks = { terminal("block:other") } } }),
			["session:mine"] = view_with({ { kind = "tiled", blocks = { terminal("block:mine") } } }, "window:mine"),
		},
		processes = { ["block:other"] = repo, ["block:mine"] = repo },
		index_view = { entries = { { path = repo, label = "current" } } },
		pick = choose("current"),
	})
	open(fake, { session_id = "session:mine", block_id = "block:mine", client_id = "client:app" })
	expect_equal(#fake.created, 0, "created sessions")
	expect_equal(fake.focused[1].block_id, "block:mine", "invoking terminal reused")
	expect_equal(fake.queued[1].args.session_id, "session:mine", "invoking session selected")
	expect_equal(count(fake.calls, "session.view"), 1, "search stops at the invoking session")
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
		pick = choose("inactive"),
	})
	open(fake)
	expect_equal(fake.queued[1].args.window_id, "window:repo", "selected window")
	expect_equal(fake.focused[1].session_id, "session:work", "focus in that session")
	expect_equal(fake.focused[1].block_id, "block:repo", "focused block")
	expect(position(fake, "session.focus_block") < position(fake, "queue:session.select"), "focus before select")
end)

test("only floating or remote blocks in a repository do not count as reuse", function()
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
		pick = choose("decoy-only"),
	})
	open(fake)
	expect_equal(#fake.created, 1, "created sessions")
end)

test("a stale selection prompts again with the current list and a notice", function()
	local missing = tmp .. "/never-created"
	local repo = make_repo("alive")
	local fake = install({
		views_sequence = {
			{ entries = { { path = missing, label = "never-created" } } },
			{ entries = { { path = missing, label = "never-created" } } },
			{ entries = { { path = repo, label = "alive" } } },
		},
		pick = choose("never-created"),
	})
	open(fake)
	expect_equal(#fake.prompts, 2, "prompts")
	expect(fake.prompts[2].placeholder:find("no longer available", 1, true), "notice")
	expect_equal(titles(fake.prompts[2]), "alive|" .. RESCAN, "current entries")
	expect_equal(#fake.created + #fake.queued, 0, "nothing selected")
end)

test("unsafe directory names keep their exact path and label", function()
	local name = 'it\'s {a} "b"\ttab\nnewline'
	local repo = make_repo(name)
	local fake = install({
		index_view = { entries = { { path = repo, label = name } } },
		pick = choose(name),
	})
	open(fake)
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "exact path")
	expect_equal(fake.created[1].label, name, "exact label")
end)

test("equal repository names are told apart by their parent directory", function()
	local first, second = make_repo("one/api"), make_repo("two/api")
	local fake = install({
		index_view = { entries = { { path = first, label = "api" }, { path = second, label = "api" } } },
		pick = choose("two/api"),
	})
	open(fake)
	expect_equal(titles(fake.prompts[1]), "one/api|two/api|" .. RESCAN, "items")
	expect_equal(fake.created[1].label, "two/api", "session label")
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, second, "cwd")
end)

test("an unanswered prompt ends quietly and an unavailable one fails with its reason", function()
	for _, reason in ipairs({ "cancelled", "timeout", "busy" }) do
		local fake = install({
			index_view = { entries = { { path = tmp .. "/x", label = "x" } } },
			pick = function()
				return nil, reason
			end,
		})
		open(fake)
		expect_equal(#fake.prompts, 1, reason .. " prompts once")
	end
	for reason, detail in pairs({ unsupported = false, no_client = false, failed = "the app closed" }) do
		local fake = install({
			index_view = { entries = { { path = tmp .. "/x", label = "x" } } },
			pick = function()
				return nil, reason, detail or nil
			end,
		})
		local ok, err = pcall(open, fake)
		expect(not ok, reason .. " fails the action")
		expect(tostring(err):find(reason, 1, true), reason .. " is reported")
		expect(not detail or tostring(err):find(detail, 1, true), "detail is reported")
	end
end)

test("the real repository cache is keyed once at setup", function()
	local fake = install()
	package.loaded["repository-index"] = assert(loadfile(rex_dir .. "/repository-index.lua"))()
	local roots = { tmp .. "/context-prime-only" }
	require("project-picker").setup({ roots = roots })
	local function hashes()
		local total = 0
		for _, argv in ipairs(fake.exec_runs) do
			if argv[1] == "/usr/bin/shasum" then
				total = total + 1
			end
		end
		return total
	end
	expect_equal(hashes(), 1, "one setup hash")
	require("repository-index").cached(roots)
	expect_equal(hashes(), 1, "later reads reuse the key")
end)

local failures = 0
for _, case in ipairs(tests) do
	local ok, err = pcall(case.fn)
	print((ok and "ok   " or "FAIL ") .. case.name .. (ok and "" or "\n     " .. tostring(err)))
	if not ok then
		failures = failures + 1
	end
end
os.execute("rm -rf " .. quote(tmp))
os.exit(failures == 0 and 0 or 1)
