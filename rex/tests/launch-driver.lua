local actions, prefix = {}, ""
local register = rex.action
rex.action = function(action)
	actions[prefix .. "/" .. action.name] = action
end
for _, variant in ipairs(rex.args.variants) do
	prefix = variant[1]
	local directory = assert(variant[2]:match("^(.*/)"))
	package.path = directory .. "?.lua;" .. package.path
	package.loaded["project-picker"] = nil
	assert(loadfile(variant[2]))()
end
rex.action = register
io.write("READY\n")
io.flush()
for line in io.lines() do
	local request = assert(rex.json.decode(line))
	local action = assert(actions[request.variant .. "/" .. request.action])
	local ok, result = pcall(action.run, {
		session_id = rex.session_id,
		client_id = rex.args.client_id,
		origin = "key",
	}, { client_id = rex.args.client_id })
	io.write(assert(rex.json.encode({ ok = ok, result = result })) .. "\n")
	io.flush()
end
