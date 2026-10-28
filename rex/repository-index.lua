local M = {}
local module_source = debug.getinfo(1, "S").source:gsub("^@", "")
local policy = "visible-git-markers-v1"
local inflight, contexts = {}, {}
local refresh_script

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

local function hex(text)
	return (text:gsub(".", function(char)
		return string.format("%02x", char:byte())
	end))
end

local function unhex(text)
	assert(type(text) == "string" and #text % 2 == 0 and not text:find("[^0-9a-f]"), "Invalid path encoding")
	return (text:gsub("..", function(pair)
		return string.char(tonumber(pair, 16))
	end))
end

local function list(value)
	assert(type(value) == "table", "Invalid cache list")
	local count = 0
	for key in pairs(value) do
		assert(type(key) == "number" and key >= 1 and key % 1 == 0, "Invalid cache list key")
		count = count + 1
	end
	assert(count == #value, "Invalid cache list length")
	return value
end

local function path(value)
	assert(type(value) == "string" and value:sub(1, 1) == "/" and not value:find("%z"), "Invalid repository path")
	return value
end

local function context(roots)
	local identity, encoded = { policy }, {}
	for _, root in ipairs(roots) do
		path(root)
		encoded[#encoded + 1] = hex(root)
		identity[#identity + 1] = #root .. ":" .. root
	end
	identity = table.concat(identity, "\0")
	if contexts[identity] then
		return contexts[identity]
	end
	local hashed = exec({ "/usr/bin/shasum", "-a", "256" }, { stdin = identity })
	assert(hashed.code == 0, failure(hashed, "Cannot key repository cache"))
	local key = hashed.stdout:match("^([0-9a-f]+)%s")
	assert(key and #key == 64, "Invalid repository cache key")
	local base = os.getenv("XDG_CACHE_HOME")
	if not base or base:sub(1, 1) ~= "/" then
		base = assert(os.getenv("HOME"), "HOME is required for repository cache") .. "/Library/Caches"
	end
	local directory = base:gsub("/$", "") .. "/rex/project-picker/v1"
	local ctx = {
		identity = hex(identity),
		roots = roots,
		roots_hex = encoded,
		key = key,
		directory = directory,
		file = directory .. "/" .. key .. ".json",
	}
	contexts[identity] = ctx
	return ctx
end

local function visible(repository, roots)
	for _, root in ipairs(roots) do
		local prefix = root:gsub("/$", "") .. "/"
		if repository == root then
			return true
		elseif root ~= "" and repository:sub(1, #prefix) == prefix then
			local relative = repository:sub(#prefix + 1)
			if relative ~= "" and not ("/" .. relative):find("/%.") then
				return true
			end
		end
	end
	return false
end

local function validate(state, ctx)
	assert(type(state) == "table" and state.schema == 1 and state.policy == policy, "Incompatible repository cache")
	assert(state.identity == ctx.identity, "Wrong repository cache roots")
	local configured = list(state.configured_roots_hex)
	assert(#configured == #ctx.roots_hex, "Wrong repository cache roots")
	for index, root in ipairs(configured) do
		assert(root == ctx.roots_hex[index], "Wrong repository cache roots")
	end
	local attempt = state.attempt
	assert(type(attempt) == "table" and type(attempt.id) == "string" and attempt.id ~= "", "Invalid cache attempt")
	assert(type(attempt.finished_at) == "number" and attempt.finished_at >= 0, "Invalid cache attempt time")
	assert(attempt.status == "ok" or attempt.status == "error", "Invalid cache attempt status")
	if attempt.status == "error" then
		assert(type(attempt.error) == "string" and attempt.error ~= "", "Invalid cache attempt error")
	end
	if state.snapshot then
		local snapshot = state.snapshot
		assert(type(snapshot) == "table" and snapshot.complete == true, "Incomplete repository cache")
		assert(type(snapshot.completed_at) == "number" and snapshot.completed_at >= 0, "Invalid cache snapshot time")
		local resolved = {}
		for _, root in ipairs(list(snapshot.resolved_roots_hex)) do
			root = unhex(root)
			resolved[#resolved + 1] = root == "" and "" or path(root)
		end
		assert(#resolved == #ctx.roots, "Invalid resolved repository roots")
		local previous
		for _, encoded in ipairs(list(snapshot.paths_hex)) do
			local repository = path(unhex(encoded))
			assert(not previous or previous < repository, "Unsorted repository cache")
			assert(visible(repository, resolved), "Repository outside visible roots")
			previous = repository
		end
	end
	assert(attempt.status ~= "ok" or state.snapshot, "Successful cache attempt has no snapshot")
	return state
end

local function load(ctx)
	local file = io.open(ctx.file, "rb")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	local ok, state = pcall(function()
		return validate(assert(rex.json.decode(text)), ctx)
	end)
	if ok then
		return state
	end
	return nil, "Repository cache is invalid; discovering a complete list"
end

local function view(state, provenance, notice)
	local snapshot, entries = state.snapshot, {}
	for _, encoded in ipairs(snapshot.paths_hex) do
		local repository = unhex(encoded)
		entries[#entries + 1] = {
			id = encoded,
			path = repository,
			label = repository:match("[^/]+$") or "/",
			detail = repository,
		}
	end
	return { entries = entries, provenance = provenance, completed_at = snapshot.completed_at, notice = notice }
end

local function physical_directory(directory)
	local result = exec({
		"/bin/sh",
		"-c",
		'[ ! -d "$1" ] || { cd "$1" && pwd -P; }',
		"rex-picker",
		directory,
	})
	assert(result.code == 0, failure(result, "Cannot read picker directory " .. directory))
	return (result.stdout:gsub("\n$", ""))
end

local function repositories(roots)
	local entries, seen, scanned, resolved = {}, {}, {}, {}
	for _, configured_root in ipairs(roots) do
		local root = physical_directory(configured_root)
		resolved[#resolved + 1] = hex(root)
		if root ~= "" and not scanned[root] then
			scanned[root] = true
			local result = exec({
				"rg",
				"--no-config",
				"--files",
				"--hidden",
				"--no-ignore",
				"--null",
				-- Marker globs must come later to retain .git/HEAD.
				"-g",
				"!**/.*/**",
				"-g",
				"**/.git/HEAD",
				"-g",
				"**/.git",
				".",
			}, { cwd = root })
			assert(result.code == 0 or result.code == 1, failure(result, "Repository discovery failed under " .. root))
			for marker in result.stdout:gmatch("([^%z]+)%z") do
				local relative = marker:gsub("^%./", "")
				if relative == ".git/HEAD" or relative == ".git" then
					relative = ""
				else
					relative = relative:gsub("/%.git/HEAD$", ""):gsub("/%.git$", "")
				end
				local repository = root
				if relative ~= "" then
					repository = root:gsub("/$", "") .. "/" .. relative
				end
				if not ("/" .. relative):find("/%.") and not seen[repository] then
					seen[repository] = true
					entries[#entries + 1] = repository
				end
			end
		end
	end
	table.sort(entries)
	local paths = {}
	for _, repository in ipairs(entries) do
		paths[#paths + 1] = hex(repository)
	end
	return { complete = true, completed_at = os.time(), resolved_roots_hex = resolved, paths_hex = paths }
end

local function publish(ctx, state)
	local temporary = exec({ "/usr/bin/mktemp", ctx.directory .. "/." .. ctx.key .. ".XXXXXXXX" })
	assert(temporary.code == 0, failure(temporary, "Cannot allocate repository cache write"))
	local name = temporary.stdout:gsub("\n$", "")
	state.attempt.id = hex(name)
	local ok, err = pcall(function()
		local text, encode_err = rex.json.encode(state)
		assert(text, encode_err)
		local file, open_err = io.open(name, "wb")
		assert(file, open_err)
		local written, write_err = file:write(text)
		local closed, close_err = file:close()
		assert(written, write_err)
		assert(closed, close_err)
		assert(os.rename(name, ctx.file))
	end)
	if not ok then
		os.remove(name)
		error(err, 0)
	end
end

-- The adapter runs under lockf -k. The persistent lock inode must never be removed.
function M.refresh(job)
	assert(
		type(job) == "table" and job.schema == 1 and type(job.baseline) == "string",
		"Invalid repository refresh job"
	)
	local roots = {}
	for _, encoded in ipairs(list(job.roots_hex)) do
		roots[#roots + 1] = path(unhex(encoded))
	end
	local ctx = context(roots)
	assert(job.key == ctx.key and job.identity == ctx.identity, "Wrong repository refresh identity")
	local old = load(ctx)
	if old and old.attempt.id ~= job.baseline then
		return { attempt_id = old.attempt.id }
	end
	local ok, snapshot = pcall(repositories, roots)
	local state = {
		schema = 1,
		policy = policy,
		identity = ctx.identity,
		configured_roots_hex = ctx.roots_hex,
		snapshot = ok and snapshot or (old and old.snapshot),
		attempt = {
			status = ok and "ok" or "error",
			finished_at = os.time(),
			error = not ok and tostring(snapshot) or nil,
		},
	}
	publish(ctx, state)
	return { attempt_id = state.attempt.id }
end

local function start(ctx, state)
	if not refresh_script then
		local directory = assert(module_source:match("^(.*/)"), "Cannot locate repository refresh adapter")
		if directory:sub(1, 1) ~= "/" then
			directory = physical_directory(directory)
		end
		refresh_script = directory:gsub("/$", "") .. "/repository-refresh.lua"
	end
	local job, encode_err = rex.json.encode({
		schema = 1,
		roots_hex = ctx.roots_hex,
		key = ctx.key,
		identity = ctx.identity,
		baseline = state and state.attempt.id or "",
	})
	assert(job, encode_err)
	local handle, err = rex.exec.start({
		"/bin/sh",
		"-c",
		'umask 077; mkdir -p "$1" && shift && exec "$@"',
		"rex-repository-refresh",
		ctx.directory,
		"/usr/bin/lockf",
		"-k",
		ctx.directory .. "/" .. ctx.key .. ".lock",
		"rex",
		"--autostart=false",
		"do",
		refresh_script,
		"--json",
		"--args",
		job,
	}, {
		detach = true,
		stdout = false,
		stderr = false,
		env = { REX_SESSION = false, REX_BLOCK = false, REX_CLIENT = false },
		timeout = 180,
	})
	assert(handle, err)
	local attempt = { handle = handle, baseline = state and state.attempt.id or "" }
	inflight[ctx.identity] = attempt
	return attempt
end

function M.cached(roots)
	local state, notice = load(context(roots))
	if state and state.snapshot then
		return view(state, "cached", state.attempt.status == "error" and state.attempt.error or nil)
	end
	return { entries = {}, notice = notice or "Discovering Git repositories..." }
end

function M.open(roots, fresh)
	local ok, opened = pcall(function()
		local ctx = context(roots)
		local state = load(ctx)
		local attempt = inflight[ctx.identity]
		if not attempt or not attempt.handle:running() then
			local started, value = pcall(start, ctx, state)
			if not started then
				if state and state.snapshot and not fresh then
					return view(state, "cached", "Refresh could not start: " .. tostring(value))
				end
				error(value, 0)
			end
			attempt = value
		end
		if state and state.snapshot and not fresh then
			return view(state, "cached", state.attempt.status == "error" and state.attempt.error or nil)
		end
		local completed, err = attempt.handle:wait(180)
		inflight[ctx.identity] = nil
		assert(completed, err)
		assert(completed.code == 0, failure(completed, "Repository refresh failed"))
		state = load(ctx)
		assert(state and state.attempt.id ~= attempt.baseline, "Repository refresh did not publish a completed attempt")
		assert(state.attempt.status == "ok", state.attempt.error)
		return view(state, "discovered")
	end)
	if ok then
		return opened
	end
	return nil, tostring(opened)
end

return M
