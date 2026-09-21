local M = {}

local function row(kind, name, status, highlight, action, icon, detail)
	return {
		text = table.concat(
			vim.tbl_filter(function(value)
				return value and value ~= ""
			end, { kind, name, status, detail }),
			"  "
		),
		kind = kind,
		name = name,
		status = status,
		highlight = highlight,
		action = action,
		icon = icon or "›",
		detail = detail,
	}
end

local function select(items, title, hint)
	local function move(offset)
		return function(picker, finder_item)
			local item = finder_item and finder_item.item
			if not item or not item.move_action then
				return
			end
			item.move_action(offset)
		end
	end
	return require("snacks").picker.select(items, {
		prompt = title,
		format_item = function(item, chunks)
			if not chunks then
				return item.text
			end
			return {
				{ item.icon .. "  ", item.highlight },
				{ string.format("%-9s", item.kind), "Comment" },
				{ string.format("%-25s", item.name), "Title" },
				{ "  " .. item.status, item.highlight },
				{ item.detail and ("  · " .. item.detail) or "", "Comment" },
			}
		end,
		snacks = {
			layout = { preset = "select", layout = { width = 0.9, max_width = 160, border = "rounded" } },
			actions = {
				confirm = function(_, finder_item)
					local item = finder_item and finder_item.item
					if item and item.action then
						item.action()
					end
				end,
				project_tools_up = move(-1),
				project_tools_down = move(1),
			},
			win = {
				input = {
					footer = hint,
					footer_pos = "center",
					keys = {
						["<M-k>"] = { "project_tools_up", mode = { "n", "i" } },
						["<M-j>"] = { "project_tools_down", mode = { "n", "i" } },
					},
				},
				list = {
					keys = {
						["<M-k>"] = "project_tools_up",
						["<M-j>"] = "project_tools_down",
					},
				},
			},
		},
	}, function(item)
		if item and item.action then
			item.action()
		end
	end)
end

local function tool_row(kind, item, refresh)
	local active = item.enabled or item.running
	local highlight = item.available == false and "DiagnosticWarn" or (active and "DiagnosticOk" or "Comment")
	local result = row(kind, item.name, item.status, highlight, function()
		item.toggle()
		refresh()
	end, item.enabled and "●" or "○", item.detail)
	if item.move then
		result.move_action = function(offset)
			item.move(offset)
			refresh()
		end
	end
	return result
end

function M.open(bufnr, scope, show_missing)
	local tools = require("config.project-tools")
	local current_scope, current_show_missing = scope, show_missing
	local items = {}
	local picker
	local build
	local function refresh(next_scope, missing)
		if next_scope ~= nil then
			current_scope = next_scope
		end
		if missing ~= nil then
			current_show_missing = missing
		end
		if picker and not picker.closed then
			build()
			picker:find({ refresh = true })
		else
			-- Also keeps the picker easy to exercise through a minimal vim.ui.select mock.
			tools.pick(bufnr, current_scope, current_show_missing)
		end
	end

	build = function()
		for index = #items, 1, -1 do
			table.remove(items, index)
		end
		local view = tools.inspect(bufnr, current_scope)
		current_scope = view.scope
		local project_name = view.project and vim.fs.basename(view.project) or "outside Git"
		local coverage = view.coverage
		items[#items + 1] = row(
			"HEALTH",
			"Coverage",
			coverage.headline,
			coverage.level == "ok" and "DiagnosticOk" or "DiagnosticWarn",
			nil,
			coverage.level == "ok" and "✓" or "!",
			coverage.advice
		)
		if view.project then
			local next_scope = view.scope == "project" and "global" or "project"
			items[#items + 1] = row(
				"SCOPE",
				"Editing",
				view.scope == "project" and ("project · " .. project_name) or "global defaults",
				"DiagnosticInfo",
				function()
					refresh(next_scope)
				end,
				"↔",
				"Enter: edit " .. next_scope
			)
		else
			items[#items + 1] = row(
				"SCOPE",
				"Editing",
				"global defaults",
				"DiagnosticInfo",
				nil,
				"·",
				"files outside Git inherit global settings"
			)
		end

		for _, item in ipairs(view.settings) do
			items[#items + 1] = tool_row("SETTING", item, refresh)
		end

		local hidden = 0
		for _, group in ipairs({
			{ "LSP", view.lsp },
			{ "FORMAT", view.formatters },
			{ "LINT", view.linters },
		}) do
			local kind, candidates = unpack(group)
			for _, item in ipairs(candidates) do
				if item.enabled or item.running or item.available or current_show_missing then
					items[#items + 1] = tool_row(kind, item, refresh)
				else
					hidden = hidden + 1
				end
			end
		end

		if hidden > 0 or current_show_missing then
			items[#items + 1] = row(
				"VIEW",
				current_show_missing and "Hide unavailable tools" or "Show unavailable tools",
				hidden > 0 and tostring(hidden) .. " hidden" or "all shown",
				"Comment",
				function()
					refresh(nil, not current_show_missing)
				end,
				"…"
			)
		end

		items[#items + 1] = row(
			"RESET",
			view.scope == "project" and "Clear project overrides" or "Reset global defaults",
			"inherit defaults",
			"Comment",
			function()
				view.reset()
				refresh()
			end,
			"↺"
		)
		return project_name, view.ft
	end

	local project_name, ft = build()
	picker = select(
		items,
		"Project tools · " .. project_name .. " / " .. (ft ~= "" and ft or "no filetype"),
		" Enter: toggle/action  ·  Alt-j/k: reorder formatter  ·  /: filter  ·  Esc: close "
	)
end

return M
