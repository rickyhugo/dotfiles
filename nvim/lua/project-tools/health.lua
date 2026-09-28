local M = {}

local function report_command(tools, project, label, command)
	if not command then
		return vim.health.error(label .. ": unknown")
	end
	local path, err, providers = tools.resolve(project, command)
	if not path then
		return vim.health.error(label .. ": " .. err)
	end
	local message = label .. " → " .. path .. " (" .. providers[1] .. ")"
	if #providers > 1 then
		vim.health.warn(message, "Also provided by " .. table.concat(providers, ", ", 2) .. "; add `bin` to narrow")
	else
		vim.health.ok(message)
	end
end

local function sorted_keys(value)
	local keys = vim.tbl_keys(value)
	table.sort(keys)
	return keys
end

function M.check()
	local tools = require("project-tools")
	-- Report the project of the buffer :checkhealth was opened from, plus any others loaded.
	local alternate = vim.fn.bufnr("#")
	local source = alternate > 0 and alternate or vim.api.nvim_get_current_buf()
	tools.get(source)
	local projects = tools.loaded()
	if not next(projects) then
		vim.health.start("project-tools")
		vim.health.info("No " .. tools.file .. " found for any open buffer. Create one with :ProjectTools edit")
		return
	end
	for _, root in ipairs(sorted_keys(projects)) do
		local project = projects[root]
		vim.health.start("project-tools: " .. vim.fn.fnamemodify(root, ":~"))
		if project.error then
			vim.health.error(project.error, "Fix " .. project.path .. " then save it")
		else
			M.report(tools, project, source)
		end
	end
end

function M.report(tools, project, source)
	local root = project.root

	for name, tool in vim.spairs(project.tools) do
		local label = name .. " (" .. tool.provider .. (tool.version and (" " .. tool.version) or "") .. ")"
		if tool.status == "ok" then
			vim.health.ok(label .. ": " .. table.concat(sorted_keys(tool.bins), ", "))
		elseif tool.status == "not installed" then
			vim.health.error(label .. ": " .. tool.status, "Run :ProjectTools install")
		else
			vim.health.error(label .. ": " .. tool.status)
		end
	end

	for _, name in ipairs(project.lsp_names) do
		local running = #vim.tbl_filter(function(client)
			return client.root_dir ~= nil and vim.startswith(client.root_dir .. "/", root .. "/")
		end, vim.lsp.get_clients({ name = name }))
		report_command(
			tools,
			project,
			"lsp " .. name .. (running > 0 and " [running]" or ""),
			tools.lsp_command(name, root)
		)
	end

	for _, ft in ipairs(sorted_keys(project.format)) do
		for _, name in ipairs(project.format[ft]) do
			local command = tools.formatter_command(name, source)
			if command == false then
				vim.health.ok("format " .. ft .. " " .. name .. " (built into conform)")
			else
				report_command(tools, project, "format " .. ft .. " " .. name, command)
			end
		end
	end

	for _, ft in ipairs(sorted_keys(project.lint)) do
		for _, name in ipairs(project.lint[ft]) do
			report_command(tools, project, "lint " .. ft .. " " .. name, tools.linter_command(name, source))
		end
	end
end

return M
