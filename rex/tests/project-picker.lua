local script = debug.getinfo(1, "S").source:gsub("^@", "")
if script:sub(1, 1) ~= "/" then
	script = (os.getenv("PWD") or ".") .. "/" .. script
end
local rex_dir = script:gsub("/tests/[^/]*$", "")
package.path = rex_dir .. "/?.lua;" .. package.path

local TERM = "com.superlogical.terminal.shell"

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

local function install(env)
	env = env or {}
	local fake = {
		calls = {},
		actions = {},
		binds = {},
		queued = {},
		created = {},
		windows = {},
		prompts = {},
		exec_runs = {},
	}
	local handlers = {
		["session.attach_all"] = function(args)
			assert(args.event_scope == "session", "no block event subscription")
			fake.subscribed = true
			return { sessions = env.sessions or {} }
		end,
		["session.view"] = function(args)
			assert(fake.subscribed, "session.view needs session.attach_all first")
			return assert((env.views or {})[args.session_id], "unexpected session.view " .. args.session_id)
		end,
		["session.create"] = function(args)
			fake.created[#fake.created + 1] = args
			return { session_id = "session:new" }
		end,
		["session.new_window"] = function(args)
			fake.windows[#fake.windows + 1] = args
			return { window_id = "window:new" }
		end,
	}
	rawset(_G, "rex", {
		call = function(method, args)
			fake.calls[#fake.calls + 1] = method
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

local tmp = sh('cd "$(mktemp -d)" && pwd -P')
local root_count = 0
local function new_root()
	root_count = root_count + 1
	local path = tmp .. "/root" .. root_count
	sh('mkdir -p "$1"', path)
	return path
end

local function make_repo(root, name)
	local path = name == "" and root or (root .. "/" .. name)
	sh('mkdir -p "$1" && git init -q "$1"', path)
	return path
end

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function open(fake, roots)
	require("project-picker").setup({ roots = roots })
	return fake.actions.project_picker.run({ session_id = "session:a", client_id = "client:app" }, {})
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
	expect_equal(#fake.exec_runs, 0, "loading the config starts no process")
end)

test("the prompt is titled, lists repositories by path, and cancelling does nothing", function()
	local root = new_root()
	local zebra, apple = make_repo(root, "zebra"), make_repo(root, "apple")
	local fake = install()
	open(fake, { root })
	local spec = fake.prompts[1]
	expect_equal(spec.title, "Open Project Session", "title")
	expect_equal(spec.placeholder, "Filter projects", "placeholder")
	expect_equal(titles(spec), "apple|zebra", "items")
	expect_equal(spec.items[1].id, apple, "repository ID is its path")
	expect_equal(spec.items[2].id, zebra, "repository ID is its path")
	expect_equal(#fake.prompts, 1, "one prompt")
	expect_equal(#fake.queued + #fake.created, 0, "nothing selected")
	expect_equal(#fake.calls, 0, "no session lookup on cancel")
	expect_equal(#fake.exec_runs, 1, "one process lists the repositories")
end)

test("a root that starts with a tilde is searched under the home directory", function()
	local fake = install()
	open(fake, { "~/no-such-picker-root", "/absolute/root" })
	local argv = fake.exec_runs[1]
	expect_equal(argv[#argv - 1], os.getenv("HOME") .. "/no-such-picker-root", "tilde root")
	expect_equal(argv[#argv], "/absolute/root", "absolute root")
end)

test("the scan finds a root, its children and grandchildren, and nothing hidden or deeper", function()
	local root = new_root()
	make_repo(root, "")
	make_repo(root, "child")
	make_repo(root, "group/grandchild")
	make_repo(root, "group/deep/too-deep")
	make_repo(root, ".hidden/secret")
	make_repo(root, "child/.cache/vendored")
	sh('mkdir -p "$1/plain" "$1/linked" && printf "gitdir: elsewhere\n" > "$1/linked/.git"', root)
	local fake = install()
	open(fake, { root })
	local found = {}
	for position, item in ipairs(fake.prompts[1].items) do
		found[position] = item.id:sub(#root + 1)
	end
	expect_equal(table.concat(found, "|"), "|/child|/group/grandchild|/linked", "repositories")
end)

test("every open scans again, and missing or repeated roots are harmless", function()
	local root = new_root()
	make_repo(root, "first")
	local fake = install()
	open(fake, { root, tmp .. "/no-such-root", root })
	expect_equal(titles(fake.prompts[1]), "first", "one row per repository")
	make_repo(root, "second")
	fake.actions.project_picker.run({ session_id = "session:a" }, {})
	expect_equal(titles(fake.prompts[2]), "first|second", "a new repository shows on the next open")
end)

test("no repositories is explained in the prompt", function()
	local fake = install()
	open(fake, { new_root() })
	expect_equal(#fake.prompts[1].items, 0, "no rows")
	expect_equal(fake.prompts[1].placeholder, "No Git repositories found under the configured roots", "empty")
end)

test("a project without a session gets a new one in its directory", function()
	local root = new_root()
	local repo = make_repo(root, "fresh")
	local fake = install({
		sessions = {
			{ session_id = "session:a", label = "fresh-2" },
			{ session_id = "session:b", label = "FRESH" },
			{ session_id = "session:c" },
		},
		pick = choose("fresh"),
	})
	open(fake, { root })
	expect_equal(#fake.created, 1, "created sessions")
	expect_equal(fake.created[1].label, "fresh", "label")
	expect_equal(fake.created[1].initial_windows[1].layout.block.flavor, TERM, "terminal")
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "cwd")
	expect_equal(#fake.queued, 1, "one queued action")
	expect_equal(fake.queued[1].action, "session.select", "queued action")
	expect_equal(fake.queued[1].args.session_id, "session:new", "selected session")
	expect_equal(#fake.windows, 0, "no extra window")
end)

test("the session that has the project's label is selected again", function()
	local root = new_root()
	make_repo(root, "again")
	local fake = install({
		sessions = {
			{ session_id = "session:other", label = "other" },
			{ session_id = "session:again", label = "again" },
		},
		views = { ["session:again"] = { windows = { { window_id = "window:1" } } } },
		pick = choose("again"),
	})
	open(fake, { root })
	expect_equal(#fake.created, 0, "created sessions")
	expect_equal(#fake.windows, 0, "its windows stay as they are")
	expect_equal(fake.queued[1].args.session_id, "session:again", "selected session")
end)

test("a project session that lost every window gets a terminal in the project", function()
	local root = new_root()
	local repo = make_repo(root, "hollow")
	local fake = install({
		sessions = { { session_id = "session:hollow", label = "hollow" } },
		views = { ["session:hollow"] = { windows = {} } },
		pick = choose("hollow"),
	})
	open(fake, { root })
	expect_equal(#fake.created, 0, "created sessions")
	expect_equal(#fake.windows, 1, "new windows")
	expect_equal(fake.windows[1].session_id, "session:hollow", "window in the project session")
	expect_equal(fake.windows[1].layout.block.options.cwd, repo, "cwd")
	expect_equal(fake.queued[1].args.session_id, "session:hollow", "selected session")
end)

test("unsafe directory names keep their exact path and label", function()
	local root = new_root()
	local name = 'it\'s {a} "b"\ttab\nnewline'
	local repo = make_repo(root, name)
	local fake = install({ pick = choose(name) })
	open(fake, { root })
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, repo, "exact path")
	expect_equal(fake.created[1].label, name, "exact label")
end)

test("equal repository names are told apart by their parent directory", function()
	local root = new_root()
	make_repo(root, "one/api")
	local second = make_repo(root, "two/api")
	make_repo(root, "two/web")
	local fake = install({
		sessions = { { session_id = "session:first", label = "one/api" } },
		pick = choose("two/api"),
	})
	open(fake, { root })
	expect_equal(titles(fake.prompts[1]), "one/api|two/api|web", "items")
	expect_equal(fake.created[1].label, "two/api", "session label")
	expect_equal(fake.created[1].initial_windows[1].layout.block.options.cwd, second, "cwd")
end)

test("an unanswered prompt ends quietly and an unavailable one fails with its reason", function()
	local root = new_root()
	make_repo(root, "x")
	for _, reason in ipairs({ "cancelled", "timeout", "busy" }) do
		local fake = install({
			pick = function()
				return nil, reason
			end,
		})
		open(fake, { root })
		expect_equal(#fake.prompts, 1, reason .. " prompts once")
	end
	for reason, detail in pairs({ unsupported = false, no_client = false, failed = "the app closed" }) do
		local fake = install({
			pick = function()
				return nil, reason, detail or nil
			end,
		})
		local ok, err = pcall(open, fake, { root })
		expect(not ok, reason .. " fails the action")
		expect(tostring(err):find(reason, 1, true), reason .. " is reported")
		expect(not detail or tostring(err):find(detail, 1, true), "detail is reported")
	end
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
