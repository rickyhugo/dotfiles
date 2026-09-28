local M = {}

local function sorted_keys(value)
	local keys = vim.tbl_keys(value)
	table.sort(keys)
	return keys
end

local function report_executable(label, command)
	if type(command) ~= "string" then
		return vim.health.info(label .. " (command resolved when it starts)")
	end
	local path = vim.fn.exepath(command)
	if path ~= "" then
		vim.health.ok(label .. " → " .. path)
	else
		vim.health.error(label .. ": " .. command .. " not found on $PATH", "Add it to mise.local.toml")
	end
end

function M.report(project, source)
	for _, name in ipairs(project.lsp_names) do
		local config = vim.lsp.config[name]
		if not config then
			vim.health.error("lsp " .. name .. ": unknown LSP config")
		else
			local running = #vim.tbl_filter(function(client)
				return client.root_dir ~= nil and vim.startswith(client.root_dir .. "/", project.root .. "/")
			end, vim.lsp.get_clients({ name = name }))
			local cmd = type(config.cmd) == "table" and config.cmd[1] or nil
			report_executable("lsp " .. name .. (running > 0 and " [running]" or ""), cmd)
		end
	end

	local conform_ok, conform = pcall(require, "conform")
	for _, ft in ipairs(sorted_keys(project.format)) do
		for _, name in ipairs(project.format[ft]) do
			local label = "format " .. ft .. " " .. name
			local info = conform_ok and conform.get_formatter_info(name, source) or nil
			if not info then
				vim.health.warn(label .. ": conform is not loaded")
			elseif info.available then
				local path = info.command and vim.fn.exepath(info.command)
				vim.health.ok(label .. (info.command and (" → " .. (path ~= "" and path or info.command)) or ""))
			else
				vim.health.error(label .. ": " .. (info.available_msg or "unavailable"), "Add it to mise.local.toml")
			end
		end
	end

	local lint_ok, lint = pcall(require, "lint")
	for _, ft in ipairs(sorted_keys(project.lint)) do
		for _, name in ipairs(project.lint[ft]) do
			local label = "lint " .. ft .. " " .. name
			local linter = lint_ok and lint.linters[name]
			if not linter then
				vim.health.error(label .. ": unknown linter")
			else
				local ok, command = pcall(vim.api.nvim_buf_call, source, function()
					linter = type(linter) == "function" and linter() or linter
					return type(linter.cmd) == "function" and linter.cmd() or linter.cmd
				end)
				report_executable(label, ok and command or nil)
			end
		end
	end
end

function M.check()
	local tools = require("project-tools")
	-- Report the project of the buffer :checkhealth was opened from, plus any others loaded.
	local alternate = vim.fn.bufnr("#")
	local source = alternate > 0 and alternate or vim.api.nvim_get_current_buf()
	tools.get(source)
	local global = tools.global()
	vim.health.start("project-tools: global " .. vim.fn.fnamemodify(global.path, ":~"))
	if global.error then
		vim.health.error(global.error, "Fix " .. global.path .. " then save it")
	elseif not global.config then
		vim.health.info("No global file; create one with :ProjectTools global")
	else
		-- The global base, as buffers outside any project get it.
		M.report(tools.outside(), source)
	end
	local projects = tools.loaded()
	if not next(projects) then
		vim.health.info("No " .. tools.file .. " found for any open buffer. Create one with :ProjectTools edit")
		return
	end
	for _, root in ipairs(sorted_keys(projects)) do
		local project = projects[root]
		vim.health.start("project-tools: " .. vim.fn.fnamemodify(root, ":~"))
		if not vim.uv.fs_stat(root .. "/" .. tools.mise_file) then
			vim.health.warn("no " .. tools.mise_file .. "; tools come from whatever $PATH has")
		end
		if project.error then
			vim.health.error(project.error, "Fix " .. project.path .. " then save it; the global base still applies")
		else
			vim.health.info("Includes the global base")
			M.report(project, source)
		end
	end
end

return M
